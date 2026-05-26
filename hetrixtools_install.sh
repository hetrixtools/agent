#!/bin/bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

GITHUB_OWNER="dictcp"
GITHUB_REPO="hetrixtools-agent"
RELEASE_TAG="v0.0.6"

github_wget() {
  local url=${!#}
  if ! wget -4 "$@"; then
    echo "IPv4 request failed for $url, retrying with IPv6..."
    if ! wget -6 "$@"; then
      echo "ERROR: Unable to fetch $url via IPv4 or IPv6." >&2
      return 1
    fi
  fi
  return 0
}

github_raw_url() {
  local branch=$1
  local file=$2
  echo "https://raw.githubusercontent.com/$GITHUB_OWNER/$GITHUB_REPO/$branch/$file"
}

github_release_url() {
  local arch=$1
  echo "https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/download/$RELEASE_TAG/hetrixtools_agent_linux_${arch}.tar.gz"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv8l|armv7l|armv7|armhf)
      echo "armv7"
      ;;
    riscv64)
      echo "riscv64"
      ;;
    *)
      echo "ERROR: Unsupported architecture: $(uname -m). Supported: amd64, arm64, armv7, riscv64." >&2
      return 1
      ;;
  esac
}

install_prebuilt_agent() {
  local arch=$1
  local url
  local extracted_bin
  local tmpdir

  url=$(github_release_url "$arch")
  extracted_bin="hetrixtools_agent_linux_${arch}"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  github_wget -t 1 -T 30 -qO "$tmpdir/hetrixtools_agent.tar.gz" "$url"
  tar -xzf "$tmpdir/hetrixtools_agent.tar.gz" -C "$tmpdir"

  if [ ! -f "$tmpdir/$extracted_bin" ]; then
    echo "ERROR: Release archive did not contain $extracted_bin." >&2
    return 1
  fi

  install -m 700 "$tmpdir/$extracted_bin" /etc/hetrixtools/hetrixtools_agent
}

BRANCH="master"
if [ "${1:-}" != "" ] && [ ${#1} -ne 32 ]; then
  BRANCH="$1"
  shift
fi

SID="${1:-}"
RUN_AS_ROOT="${2:-0}"
CHECK_SERVICES="${3:-0}"
CHECK_SOFT_RAID="${4:-0}"
CHECK_DRIVE_HEALTH="${5:-0}"
RUNNING_PROCESSES="${6:-0}"
CONNECTION_PORTS="${7:-0}"

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run the install script as root."
  exit 1
fi
if [ -z "$SID" ] || [ ${#SID} -ne 32 ]; then
  echo "ERROR: Missing or invalid SID."
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemd is required for the Nim daemon agent."
  exit 1
fi
if ! command -v wget >/dev/null 2>&1; then
  echo "ERROR: wget is required."
  exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
  echo "ERROR: tar is required."
  exit 1
fi

if ! github_wget --spider -q "$(github_raw_url "$BRANCH" hetrixtools.cfg)"; then
  echo "ERROR: Branch $BRANCH does not contain installer assets." >&2
  exit 1
fi

rm -rf /etc/hetrixtools
mkdir -p /etc/hetrixtools

for f in hetrixtools.cfg hetrixtools_update.sh hetrixtools_uninstall.sh; do
  github_wget -t 1 -T 30 -qO "/etc/hetrixtools/$f" "$(github_raw_url "$BRANCH" "$f")"
done

chmod 700 /etc/hetrixtools
chmod 600 /etc/hetrixtools/hetrixtools.cfg
chmod 700 /etc/hetrixtools/hetrixtools_update.sh /etc/hetrixtools/hetrixtools_uninstall.sh

sed -i "s/SID=\"\"/SID=\"$SID\"/" /etc/hetrixtools/hetrixtools.cfg
if [ "$CHECK_SERVICES" != "0" ]; then
  sed -i "s/CheckServices=\"\"/CheckServices=\"$CHECK_SERVICES\"/" /etc/hetrixtools/hetrixtools.cfg
fi
if [ "$CHECK_SOFT_RAID" = "1" ]; then
  sed -i "s/CheckSoftRAID=0/CheckSoftRAID=1/" /etc/hetrixtools/hetrixtools.cfg
fi
if [ "$CHECK_DRIVE_HEALTH" = "1" ]; then
  sed -i "s/CheckDriveHealth=0/CheckDriveHealth=1/" /etc/hetrixtools/hetrixtools.cfg
fi
if [ "$RUNNING_PROCESSES" = "1" ]; then
  sed -i "s/RunningProcesses=0/RunningProcesses=1/" /etc/hetrixtools/hetrixtools.cfg
fi
if [ "$CONNECTION_PORTS" != "0" ]; then
  sed -i "s/ConnectionPorts=\"\"/ConnectionPorts=\"$CONNECTION_PORTS\"/" /etc/hetrixtools/hetrixtools.cfg
fi

if ! id -u hetrixtools >/dev/null 2>&1; then
  useradd hetrixtools -r -d /etc/hetrixtools -s /bin/false
fi

SERVICE_USER="hetrixtools"
if [ "$RUN_AS_ROOT" = "1" ]; then
  SERVICE_USER="root"
fi

AGENT_ARCH=$(detect_arch)
install_prebuilt_agent "$AGENT_ARCH"

if [ "$SERVICE_USER" = "hetrixtools" ]; then
  chown -R hetrixtools:hetrixtools /etc/hetrixtools
else
  chown -R root:root /etc/hetrixtools
fi

# cleanup legacy schedules
if command -v crontab >/dev/null 2>&1; then
  crontab -u root -l 2>/dev/null | grep -v 'hetrixtools_agent' | crontab -u root - >/dev/null 2>&1 || true
  if id -u hetrixtools >/dev/null 2>&1; then
    crontab -u hetrixtools -l 2>/dev/null | grep -v 'hetrixtools_agent' | crontab -u hetrixtools - >/dev/null 2>&1 || true
  fi
fi
systemctl stop hetrixtools_agent.timer >/dev/null 2>&1 || true
systemctl disable hetrixtools_agent.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/hetrixtools_agent.timer

cat > /etc/systemd/system/hetrixtools_agent.service <<SERVICE
[Unit]
Description=HetrixTools Nim Agent (daemon)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=/etc/hetrixtools
ExecStart=/etc/hetrixtools/hetrixtools_agent --config=/etc/hetrixtools/hetrixtools.cfg --log-shm
Restart=always
RestartSec=5s
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now hetrixtools_agent.service
systemctl restart hetrixtools_agent.service

wget -t 1 -T 30 -qO- --post-data "v=install&s=$SID" https://sm.hetrixtools.net/ >/dev/null 2>&1 || true

echo "HetrixTools Nim daemon agent installation completed."
