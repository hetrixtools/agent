# HetrixTools Linux Server Monitoring Agent

Documentation available here: <https://docs.hetrixtools.com/category/server-monitor/>

## Nim Daemon Rewrite (WIP)

- `hetrixtools_agent.nim` is a compiled Nim implementation of the Linux agent.
- It runs as a long-running daemon process (systemd service), replacing cron/timer one-shot execution.
- Installer/update scripts keep the existing argument compatibility while deploying the Nim daemon service.
- Build locally with:

```bash
./scripts/build_nim_agent.sh
```

- Build all Linux targets (`amd64` + `arm64` + `armv7`) in one command:

```bash
./scripts/build_multiarch.sh
```

- Run one-shot payload generation for testing:

```bash
./hetrixtools_agent --once --no-post --config=./hetrixtools.cfg --log=./hetrixtools_agent.log
```

- Show CLI help:

```bash
./hetrixtools_agent --help
```

- CLI options:
  - `-h`, `--help`: show usage and exit
  - `--once`: run one collection cycle and exit
  - `--no-post`: generate payload locally without posting to HetrixTools
  - `--config=PATH` or `--config PATH`: set config file path (default: `/etc/hetrixtools/hetrixtools.cfg`)
  - `--log=PATH` or `--log PATH`: set output payload log path (default: `/etc/hetrixtools/hetrixtools_agent.log`)
  - unknown options now fail with a clear error message and usage output

- Required commands/dependencies:
  - Runtime commands used by the Nim agent:
    - `uname`, `whoami`, `df`, `lscpu`, `lsblk`, `ip`
    - `awk`, `grep`, `sort`, `wc`, `cut`, `paste` (used in command pipelines)
  - Runtime libraries:
    - OpenSSL (for HTTPS posting, build uses `-d:ssl`)
    - zlib (for in-memory gzip payload compression)
  - Build requirements:
    - `nim`, `gcc`
    - for multi-arch build:
      - `aarch64-linux-gnu-gcc` (or `aarch64-linux-musl-gcc`) with `arm64` zlib/ssl libs
      - `arm-linux-gnueabihf-gcc` (or `arm-linux-musleabihf-gcc`) with `armhf` zlib/ssl libs
  - Test/debug helpers (optional):
    - `python3` (parity tests and dummy ingest server)
    - `curl` (manual post checks to dummy ingest server)
- Parity test (core metrics):

```bash
python3 tests/parity_test.py
```

- Fields not implemented yet in the Nim agent payload (currently sent as empty values):
  - `raid` (software/hardware RAID details)
  - `zp` (ZFS pool health/details)
  - `dh` (drive health / SMART details)
  - `conn` (configured port connection counts)
  - `temp` (temperature metrics)
  - `serv` (service status checks)
  - `oping` (outgoing ping checks)
  - `rps1`, `rps2` (HTTP request-per-second checks)

### Changelog
