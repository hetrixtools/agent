#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_BIN="${1:-$ROOT_DIR/hetrixtools_agent}"

if ! command -v nim >/dev/null 2>&1; then
  echo "ERROR: nim is not installed." >&2
  exit 1
fi

nim c -d:release --opt:speed --mm:orc -o:"$OUT_BIN" "$ROOT_DIR/hetrixtools_agent.nim"
echo "Built: $OUT_BIN"
