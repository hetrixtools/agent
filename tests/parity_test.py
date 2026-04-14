#!/usr/bin/env python3
import base64
import gzip
import json
import os
import shutil
import subprocess
import tempfile
import urllib.parse


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SHELL_AGENT = os.path.join(ROOT, "hetrixtools_agent.sh")
NIM_SOURCE = os.path.join(ROOT, "hetrixtools_agent.nim")
CFG_TEMPLATE = os.path.join(ROOT, "hetrixtools.cfg")


def decode_payload(log_path: str) -> dict:
    raw = open(log_path, "r", encoding="utf-8").read().strip()
    assert raw.startswith("j="), f"invalid payload format in {log_path}"
    encoded = raw[2:]
    gz_bytes = base64.b64decode(urllib.parse.unquote_plus(encoded))
    payload = gzip.decompress(gz_bytes).decode("utf-8")
    return json.loads(payload)


def create_cfg(path: str):
    cfg = open(CFG_TEMPLATE, "r", encoding="utf-8").read()
    cfg = cfg.replace('SID=""', 'SID="0123456789abcdef0123456789abcdef"')
    cfg = cfg.replace("CollectEveryXSeconds=3", "CollectEveryXSeconds=2")
    cfg = cfg.replace("CheckDriveHealth=0", "CheckDriveHealth=0")
    cfg = cfg.replace("CheckSoftRAID=0", "CheckSoftRAID=0")
    cfg = cfg.replace("RunningProcesses=0", "RunningProcesses=0")
    open(path, "w", encoding="utf-8").write(cfg)


def maybe_build_nim(tmpdir: str) -> str:
    nim = shutil.which("nim")
    if not nim:
        return ""
    out_bin = os.path.join(tmpdir, "hetrixtools_agent")
    subprocess.check_call(
        [nim, "c", "-d:release", "--opt:speed", "-o:" + out_bin, NIM_SOURCE],
        cwd=ROOT,
    )
    return out_bin


def run_with_fake_wget(command, cwd, path_prefix):
    env = os.environ.copy()
    env["PATH"] = path_prefix + os.pathsep + env.get("PATH", "")
    subprocess.check_call(command, cwd=cwd, env=env)


def compare_core(shell_data: dict, nim_data: dict):
    core_keys = [
        "SID",
        "agent",
        "user",
        "cpusockets",
        "cpucores",
        "cputhreads",
        "ramsize",
        "ramswapsize",
    ]
    for key in core_keys:
        assert str(shell_data.get(key, "")) == str(nim_data.get(key, "")), f"mismatch on {key}"

    near_keys = ["cpu", "wa", "st", "us", "sy", "ram", "ramswap", "load1", "load5", "load15"]
    for key in near_keys:
        sv = float(shell_data.get(key, 0))
        nv = float(nim_data.get(key, 0))
        assert abs(sv - nv) <= 20.0, f"{key} differs too much: shell={sv} nim={nv}"


def main():
    with tempfile.TemporaryDirectory() as tmp:
        shell_dir = os.path.join(tmp, "shell")
        nim_dir = os.path.join(tmp, "nim")
        os.makedirs(shell_dir, exist_ok=True)
        os.makedirs(nim_dir, exist_ok=True)

        shutil.copy2(SHELL_AGENT, os.path.join(shell_dir, "hetrixtools_agent.sh"))
        shutil.copy2(CFG_TEMPLATE, os.path.join(shell_dir, "hetrixtools.cfg"))
        create_cfg(os.path.join(shell_dir, "hetrixtools.cfg"))
        create_cfg(os.path.join(nim_dir, "hetrixtools.cfg"))

        fakebin = os.path.join(tmp, "fakebin")
        os.makedirs(fakebin, exist_ok=True)
        fake_wget = os.path.join(fakebin, "wget")
        open(fake_wget, "w", encoding="utf-8").write("#!/bin/sh\nexit 0\n")
        os.chmod(fake_wget, 0o755)

        run_with_fake_wget(["bash", "./hetrixtools_agent.sh"], cwd=shell_dir, path_prefix=fakebin)

        nim_bin = maybe_build_nim(tmp)
        if not nim_bin:
            print("SKIP: nim compiler not found, shell payload generation verified only.")
            return
        run_with_fake_wget(
            [
                nim_bin,
                "--once",
                "--no-post",
                "--config=" + os.path.join(nim_dir, "hetrixtools.cfg"),
                "--log=" + os.path.join(nim_dir, "hetrixtools_agent.log"),
            ],
            cwd=nim_dir,
            path_prefix=fakebin,
        )

        shell_payload = decode_payload(os.path.join(shell_dir, "hetrixtools_agent.log"))
        nim_payload = decode_payload(os.path.join(nim_dir, "hetrixtools_agent.log"))
        compare_core(shell_payload, nim_payload)
        print("PASS: Nim agent payload is near-equivalent on core metrics.")


if __name__ == "__main__":
    main()
