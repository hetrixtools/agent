#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist}"

NIM_SOURCE="$ROOT_DIR/hetrixtools_agent.nim"
mkdir -p "$OUT_DIR"

find_cross_compiler() {
  local var_name=$1
  shift
  local candidate

  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf -v "$var_name" '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

require_zlib_link() {
  local cc=$1
  local tmp_bin=$2
  local label=$3
  local package_hint=$4

  if ! echo 'int main(void){return 0;}' | "$cc" -x c - -lz -o "$tmp_bin" >/dev/null 2>&1; then
    echo "ERROR: $label zlib not found for $cc." >&2
    echo "Install package: $package_hint (or provide a matching sysroot with libz)." >&2
    exit 1
  fi

  rm -f "$tmp_bin"
}

if ! command -v nim >/dev/null 2>&1; then
  echo "ERROR: nim is not installed." >&2
  exit 1
fi

require_zlib_link gcc /tmp/hetrixtools_zlib_check "host" "zlib1g-dev"

echo "[1/4] Building linux/amd64..."
nim c -d:release -d:ssl --opt:speed --mm:orc \
  --os:linux --cpu:amd64 \
  --cc:gcc --gcc.exe:gcc \
  -o:"$OUT_DIR/hetrixtools_agent_linux_amd64" \
  "$NIM_SOURCE"

if ! find_cross_compiler ARM64_CC aarch64-linux-gnu-gcc aarch64-linux-musl-gcc; then
  echo "ERROR: ARM64 cross compiler not found." >&2
  echo "Install one of: aarch64-linux-gnu-gcc or aarch64-linux-musl-gcc" >&2
  exit 1
fi

require_zlib_link "$ARM64_CC" /tmp/hetrixtools_zlib_check_arm64 "ARM64" "libz-dev:arm64"

echo "[2/4] Building linux/arm64 using $ARM64_CC..."
nim c -d:release -d:ssl --opt:speed --mm:orc \
  --os:linux --cpu:arm64 \
  --cc:gcc --gcc.exe:"$ARM64_CC" \
  -o:"$OUT_DIR/hetrixtools_agent_linux_arm64" \
  "$NIM_SOURCE"

if ! find_cross_compiler ARMV7_CC arm-linux-gnueabihf-gcc arm-linux-musleabihf-gcc; then
  echo "ERROR: ARMv7 cross compiler not found." >&2
  echo "Install one of: arm-linux-gnueabihf-gcc or arm-linux-musleabihf-gcc" >&2
  exit 1
fi

require_zlib_link "$ARMV7_CC" /tmp/hetrixtools_zlib_check_armv7 "ARMv7" "libz-dev:armhf"

echo "[3/4] Building linux/armv7 using $ARMV7_CC..."
nim c -d:release -d:ssl --opt:speed --mm:orc \
  --os:linux --cpu:arm \
  --cc:gcc --gcc.exe:"$ARMV7_CC" \
  -o:"$OUT_DIR/hetrixtools_agent_linux_armv7" \
  "$NIM_SOURCE"

if ! find_cross_compiler RISCV64_CC riscv64-linux-gnu-gcc riscv64-linux-musl-gcc; then
  echo "ERROR: RISC-V 64 cross compiler not found." >&2
  echo "Install one of: riscv64-linux-gnu-gcc or riscv64-linux-musl-gcc" >&2
  exit 1
fi

require_zlib_link "$RISCV64_CC" /tmp/hetrixtools_zlib_check_riscv64 "RISC-V 64" "libz-dev:riscv64"

echo "[4/4] Building linux/riscv64 using $RISCV64_CC..."
nim c -d:release -d:ssl --opt:speed --mm:orc \
  --os:linux --cpu:riscv64 \
  --cc:gcc --gcc.exe:"$RISCV64_CC" \
  -o:"$OUT_DIR/hetrixtools_agent_linux_riscv64" \
  "$NIM_SOURCE"

echo "Done."
echo "Artifacts:"
echo "  $OUT_DIR/hetrixtools_agent_linux_amd64"
echo "  $OUT_DIR/hetrixtools_agent_linux_arm64"
echo "  $OUT_DIR/hetrixtools_agent_linux_armv7"
echo "  $OUT_DIR/hetrixtools_agent_linux_riscv64"
