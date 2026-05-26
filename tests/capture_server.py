#!/usr/bin/env python3
"""
HetrixTools dummy capture endpoint — local visualisation helper.

Listens on http://0.0.0.0:18080  (override with PORT env var).
Accepts POST /v2/  with a form field  j=<url-encoded gzip+base64 JSON>,
decodes it, and pretty-prints every incoming report to stdout.

Usage
-----
1. Start this server:
     python3 tests/capture_server.py

2. In a second terminal, point the agent at it:
     HETRIXTOOLS_POST_URL=http://127.0.0.1:18080/v2/ \\
       ./hetrixtools_agent_linux_arm64 --once --config=hetrixtools.cfg

The server stays up and accepts repeated POSTs (Ctrl-C to stop).
"""

import base64
import gzip
import json
import os
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

PORT = int(os.environ.get("PORT", 18080))

SHOW_KEYS = [
    ("version", "Version"),
    ("SID",     "SID"),
    ("hostname", "Hostname"),
    ("os",      "OS"),
    ("uptime",  "Uptime (s)"),
    ("cpu",     "CPU %"),
    ("wa",      "IOwait %"),
    ("ram",     "RAM %"),
    ("load1",   "Load 1m"),
    ("load5",   "Load 5m"),
    ("load15",  "Load 15m"),
]

SEP = "-" * 72


def decode_b64(val: str) -> str:
    try:
        return base64.b64decode(val).decode("utf-8", errors="replace")
    except Exception:
        return val


def decode_payload(raw_body: str) -> dict:
    data = parse_qs(raw_body, keep_blank_values=True, strict_parsing=False)
    encoded = data.get("j", [""])[0]
    gz_bytes = base64.b64decode(encoded)
    payload = gzip.decompress(gz_bytes).decode("utf-8")
    return json.loads(payload)


def render_oping(oping_b64: str) -> str:
    if not oping_b64:
        return "  (none)"
    raw = decode_b64(oping_b64)
    lines = []
    for entry in raw.rstrip(";").split(";"):
        if not entry.strip():
            continue
        parts = entry.split(",")
        if len(parts) == 4:
            name, target, loss, rtt_us = parts
            try:
                rtt_ms = int(rtt_us) / 1000
            except ValueError:
                rtt_ms = 0.0
            lines.append(
                f"  {name:<20} {target:<45} loss={loss:>3}%  rtt={rtt_ms:.3f} ms"
            )
        else:
            lines.append(f"  (malformed) {entry}")
    return "\n".join(lines) if lines else "  (empty)"


def render_report(data: dict) -> str:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    out = ["", SEP, f"  CAPTURE  {ts}", SEP]

    for key, label in SHOW_KEYS:
        val = data.get(key, "")
        if key in ("hostname", "os"):
            val = decode_b64(val)
        out.append(f"  {label:<14} {val}")

    out.append("\n  Outgoing Pings:")
    out.append(render_oping(data.get("oping", "")))

    nics_raw = decode_b64(data.get("nics", ""))
    if nics_raw:
        out.append("\n  NICs (rx B/s, tx B/s):")
        for entry in nics_raw.rstrip(";").split(";"):
            if entry.strip():
                out.append(f"    {entry}")

    out.append(SEP)
    return "\n".join(out)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        try:
            data = decode_payload(raw)
            print(render_report(data), flush=True)
            body = b'{"ok":true}\n'
            self.send_response(200)
        except Exception as exc:
            print(f"[ERROR] Failed to decode payload: {exc}", file=sys.stderr, flush=True)
            body = b'{"error":"decode failed"}\n'
            self.send_response(400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # noqa: A003
        pass  # suppress per-request access log noise


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Listening on http://0.0.0.0:{PORT}/v2/  (Ctrl-C to stop)")
    print(f"")
    print(f"Point the agent at it:")
    print(f"  HETRIXTOOLS_POST_URL=http://127.0.0.1:{PORT}/v2/ \\")
    print(f"    ./hetrixtools_agent_linux_arm64 --once --config=hetrixtools.cfg")
    print(f"")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
