#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist}"

NIM_SOURCE="$ROOT_DIR/hetrixtools_agent.nim"
mkdir -p "$OUT_DIR"

if ! command -v nim >/dev/null 2>&1; then
  echo "ERROR: nim is not installed." >&2
  exit 1
fi

if ! echo 'int main(void){return 0;}' | gcc -x c - -lz -o /tmp/hetrixtools_zlib_check >/dev/null 2>&1; then
  echo "ERROR: host zlib link check failed." >&2
  echo "Install package: zlib1g-dev" >&2
  exit 1
fi
rm -f /tmp/hetrixtools_zlib_check

echo "[1/2] Building linux/amd64..."
nim c -d:release -d:ssl --opt:speed --mm:orc \
  --os:linux --cpu:amd64 \
  --cc:gcc --gcc.exe:gcc \
  -o:"$OUT_DIR/hetrixtools_agent_linux_amd64" \
  "$NIM_SOURCE"

if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
  ARM64_CC="aarch64-linux-gnu-gcc"
elif command -v aarch64-linux-musl-gcc >/dev/null 2>&1; then
  ARM64_CC="aarch64-linux-musl-gcc"
else
  echo "ERROR: ARM64 cross compiler not found." >&2
  echo "Install one of: aarch64-linux-gnu-gcc or aarch64-linux-musl-gcc" >&2
  exit 1
fi

if ! echo 'int main(void){return 0;}' | "$ARM64_CC" -x c - -lz -o /tmp/hetrixtools_zlib_check_arm64 >/dev/null 2>&1; then
  echo "ERROR: ARM64 zlib not found for $ARM64_CC." >&2
  echo "Install package: zlib1g-dev-arm64-cross (or provide arm64 sysroot with libz)." >&2
  exit 1
fi
rm -f /tmp/hetrixtools_zlib_check_arm64

echo "[2/2] Building linux/arm64 using $ARM64_CC..."
nim c -d:release -d:ssl --opt:speed --mm:orc \
  --os:linux --cpu:arm64 \
  --cc:gcc --gcc.exe:"$ARM64_CC" \
  -o:"$OUT_DIR/hetrixtools_agent_linux_arm64" \
  "$NIM_SOURCE"

echo "Done."
echo "Artifacts:"
echo "  $OUT_DIR/hetrixtools_agent_linux_amd64"
echo "  $OUT_DIR/hetrixtools_agent_linux_arm64"
