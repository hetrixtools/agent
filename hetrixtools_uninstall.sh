#!/bin/bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run the uninstall script as root."
  exit 1
fi

SID="${1:-}"

systemctl stop hetrixtools_agent.service >/dev/null 2>&1 || true
systemctl disable hetrixtools_agent.service >/dev/null 2>&1 || true
systemctl stop hetrixtools_agent.timer >/dev/null 2>&1 || true
systemctl disable hetrixtools_agent.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/hetrixtools_agent.service /etc/systemd/system/hetrixtools_agent.timer
systemctl daemon-reload >/dev/null 2>&1 || true

if command -v crontab >/dev/null 2>&1; then
  crontab -u root -l 2>/dev/null | grep -v 'hetrixtools_agent' | crontab -u root - >/dev/null 2>&1 || true
  if id -u hetrixtools >/dev/null 2>&1; then
    crontab -u hetrixtools -l 2>/dev/null | grep -v 'hetrixtools_agent' | crontab -u hetrixtools - >/dev/null 2>&1 || true
  fi
fi

rm -rf /etc/hetrixtools

if id -u hetrixtools >/dev/null 2>&1; then
  pkill -9 -u "$(id -u hetrixtools)" >/dev/null 2>&1 || true
  userdel hetrixtools >/dev/null 2>&1 || true
fi

if [ -n "$SID" ]; then
  wget -t 1 -T 30 -qO- --post-data "v=uninstall&s=$SID" https://sm.hetrixtools.net/ >/dev/null 2>&1 || true
fi

echo "HetrixTools Nim daemon agent uninstallation completed."
