#!/bin/bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

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

if ! github_wget --spider -q "https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.nim"; then
  echo "ERROR: Branch $BRANCH does not contain Nim agent sources." >&2
  exit 1
fi

rm -rf /etc/hetrixtools
mkdir -p /etc/hetrixtools

for f in hetrixtools.cfg hetrixtools_agent.nim hetrixtools_update.sh hetrixtools_uninstall.sh; do
  github_wget -t 1 -T 30 -qO "/etc/hetrixtools/$f" "https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/$f"
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

if ! command -v nim >/dev/null 2>&1; then
  echo "ERROR: Nim compiler (nim) is required on the target server to build the agent." >&2
  echo "Install Nim and re-run this installer." >&2
  exit 1
fi

nim c -d:release --opt:speed --mm:orc -o:/etc/hetrixtools/hetrixtools_agent /etc/hetrixtools/hetrixtools_agent.nim
chmod 700 /etc/hetrixtools/hetrixtools_agent

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
ExecStart=/etc/hetrixtools/hetrixtools_agent --config=/etc/hetrixtools/hetrixtools.cfg --log=/etc/hetrixtools/hetrixtools_agent.log
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
