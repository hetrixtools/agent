#!/usr/bin/env python3
"""
End-to-end test for the OutgoingPings / oping payload feature.

Covers:
  - ICMP ping (to 127.0.0.1 loopback) — runs concurrently with stats collection
  - TCP port ping (to an ephemeral localhost listener started by this test)

The test builds the Nim agent, configures OutgoingPings with both an ICMP and a
TCP entry, runs the agent once, decodes the payload and asserts the oping field
contains valid results with 0% packet loss for both reachable targets.
"""

import base64
import gzip
import json
import os
import shutil
import socket
import subprocess
import tempfile
import threading
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
NIM_SOURCE = os.path.join(ROOT, "hetrixtools_agent.nim")
CFG_TEMPLATE = os.path.join(ROOT, "hetrixtools.cfg")


# ── Helpers ──────────────────────────────────────────────────────────────────

def decode_payload(log_path):
    raw = open(log_path, "r", encoding="utf-8").read().strip()
    assert raw.startswith("j="), f"invalid payload format in {log_path}"
    encoded = raw[2:]
    gz_bytes = base64.b64decode(urllib.parse.unquote_plus(encoded))
    payload = gzip.decompress(gz_bytes).decode("utf-8")
    return json.loads(payload)


def build_nim(tmpdir):
    nim = shutil.which("nim")
    if not nim:
        raise RuntimeError("nim compiler not found — skipping oping test")
    out_bin = os.path.join(tmpdir, "hetrixtools_agent_oping")
    subprocess.check_call(
        [nim, "c", "-d:release", "--opt:speed", "-o:" + out_bin, NIM_SOURCE],
        cwd=ROOT,
    )
    return out_bin


def find_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]


def parse_oping(oping_b64):
    """Decode base64 oping field into a list of result dicts."""
    raw = base64.b64decode(oping_b64).decode("utf-8")
    results = []
    for entry in raw.split(";"):
        entry = entry.strip()
        if not entry:
            continue
        parts = entry.split(",")
        assert len(parts) == 4, f"unexpected oping entry format: {entry!r}"
        results.append({
            "name":   parts[0],
            "target": parts[1],
            "loss":   int(parts[2]),
            "rtt":    int(parts[3]),
        })
    return results


# ── TCP listener ─────────────────────────────────────────────────────────────

class TcpListener:
    """Minimal TCP server that accepts and immediately closes connections."""

    def __init__(self, port):
        self.port = port
        self._sock = None
        self._thread = None
        self._stop = threading.Event()

    def start(self):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind(("127.0.0.1", self.port))
        self._sock.listen(32)
        self._sock.settimeout(1.0)
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    def _serve(self):
        while not self._stop.is_set():
            try:
                conn, _ = self._sock.accept()
                conn.close()
            except socket.timeout:
                continue
            except OSError:
                break

    def stop(self):
        self._stop.set()
        if self._sock:
            try:
                self._sock.close()
            except OSError:
                pass
        if self._thread:
            self._thread.join(timeout=3)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    tcp_port = find_free_port()
    listener = TcpListener(tcp_port)
    listener.start()

    try:
        with tempfile.TemporaryDirectory() as tmp:
            nim_bin = build_nim(tmp)

            work_dir = os.path.join(tmp, "run")
            os.makedirs(work_dir)

            cfg = open(CFG_TEMPLATE, "r", encoding="utf-8").read()
            cfg = cfg.replace('SID=""', 'SID="0123456789abcdef0123456789abcdef"')
            # Speed up stats collection (2-second interval, ~60s total)
            cfg = cfg.replace("CollectEveryXSeconds=3", "CollectEveryXSeconds=2")
            # ICMP entry (2 fields) + TCP entry (3 fields, port = tcp_port)
            cfg = cfg.replace(
                'OutgoingPings=""',
                f'OutgoingPings="loopback,127.0.0.1|tcptest,127.0.0.1,{tcp_port}"',
            )
            # Low sample count → 2 TCP probes, 1 gap × 5 s = ~5 s overhead
            cfg = cfg.replace("OutgoingPingsCount=20", "OutgoingPingsCount=10")

            cfg_path = os.path.join(work_dir, "hetrixtools.cfg")
            log_path = os.path.join(work_dir, "hetrixtools_agent.log")
            open(cfg_path, "w", encoding="utf-8").write(cfg)

            subprocess.check_call(
                [
                    nim_bin,
                    "--once",
                    "--no-post",
                    f"--config={cfg_path}",
                    f"--log={log_path}",
                ],
                cwd=work_dir,
            )

            payload = decode_payload(log_path)

            # ── oping field must be present and non-empty ──────────────────
            oping_b64 = payload.get("oping", "")
            assert oping_b64, "oping field is missing or empty in the agent payload"

            results = parse_oping(oping_b64)
            assert len(results) == 2, (
                f"expected 2 oping results (1 ICMP + 1 TCP), got {len(results)}: {results}"
            )

            # ── ICMP result ────────────────────────────────────────────────
            icmp = next((r for r in results if r["name"] == "loopback"), None)
            assert icmp is not None, f"'loopback' ICMP entry missing from oping: {results}"
            assert icmp["target"] == "127.0.0.1", (
                f"unexpected ICMP target: {icmp['target']!r}"
            )
            assert icmp["loss"] == 0, (
                f"loopback ICMP ping reported {icmp['loss']}% packet loss (expected 0%)"
            )
            assert icmp["rtt"] >= 0, f"loopback ICMP RTT is negative: {icmp['rtt']}"

            # ── TCP result ─────────────────────────────────────────────────
            tcp = next((r for r in results if r["name"] == "tcptest"), None)
            assert tcp is not None, f"'tcptest' TCP entry missing from oping: {results}"
            assert tcp["target"] == f"127.0.0.1_{tcp_port}", (
                f"unexpected TCP target: {tcp['target']!r}"
            )
            assert tcp["loss"] == 0, (
                f"localhost TCP ping reported {tcp['loss']}% packet loss (expected 0%)"
            )
            assert tcp["rtt"] >= 0, f"localhost TCP RTT is negative: {tcp['rtt']}"

            print(f"PASS: ICMP loopback — loss={icmp['loss']}% rtt={icmp['rtt']}ms")
            print(f"PASS: TCP 127.0.0.1:{tcp_port} — loss={tcp['loss']}% rtt={tcp['rtt']}ms")

    finally:
        listener.stop()


if __name__ == "__main__":
    main()
