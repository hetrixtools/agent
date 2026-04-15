#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_BIN="${1:-$ROOT_DIR/hetrixtools_agent}"

if ! command -v nim >/dev/null 2>&1; then
  echo "ERROR: nim is not installed." >&2
  exit 1
fi

# The Nim agent requires SSL for HTTPS posting and zlib for in-memory gzip.
if ! echo 'int main(void){return 0;}' | gcc -x c - -lz -o /tmp/hetrixtools_zlib_check >/dev/null 2>&1; then
  echo "ERROR: host zlib link check failed." >&2
  echo "Install package: zlib1g-dev" >&2
  exit 1
fi
rm -f /tmp/hetrixtools_zlib_check

nim c -d:release -d:ssl --opt:speed --mm:orc -o:"$OUT_BIN" "$ROOT_DIR/hetrixtools_agent.nim"
echo "Built: $OUT_BIN"
