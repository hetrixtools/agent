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

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run the update script as root."
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemd is required for the Nim daemon agent."
  exit 1
fi
if ! command -v nim >/dev/null 2>&1; then
  echo "ERROR: Nim compiler (nim) is required on the target server to build updates." >&2
  exit 1
fi

BRANCH="${1:-master}"
if ! github_wget --spider -q "https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.nim"; then
  echo "ERROR: Branch $BRANCH does not contain Nim agent sources." >&2
  exit 1
fi

if [ ! -f /etc/hetrixtools/hetrixtools.cfg ]; then
  echo "ERROR: Missing /etc/hetrixtools/hetrixtools.cfg."
  exit 1
fi

mkdir -p /etc/hetrixtools

github_wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools_agent.nim "https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.nim"
github_wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools_update.sh "https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_update.sh"
github_wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools_uninstall.sh "https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_uninstall.sh"

chmod 700 /etc/hetrixtools/hetrixtools_update.sh /etc/hetrixtools/hetrixtools_uninstall.sh

nim c -d:release --opt:speed --mm:orc -o:/etc/hetrixtools/hetrixtools_agent /etc/hetrixtools/hetrixtools_agent.nim
chmod 700 /etc/hetrixtools/hetrixtools_agent

SERVICE_USER=$(systemctl cat hetrixtools_agent.service 2>/dev/null | awk -F= '/^User=/ {print $2; exit}')
if [ -z "$SERVICE_USER" ]; then
  SERVICE_USER=$(stat -c '%U' /etc/hetrixtools/hetrixtools.cfg 2>/dev/null || echo root)
fi
if [ "$SERVICE_USER" != "root" ] && [ "$SERVICE_USER" != "hetrixtools" ]; then
  SERVICE_USER="root"
fi
if [ "$SERVICE_USER" = "hetrixtools" ] && ! id -u hetrixtools >/dev/null 2>&1; then
  SERVICE_USER="root"
fi

if [ "$SERVICE_USER" = "hetrixtools" ]; then
  chown -R hetrixtools:hetrixtools /etc/hetrixtools
else
  chown -R root:root /etc/hetrixtools
fi

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

echo "HetrixTools Nim daemon agent update completed."
