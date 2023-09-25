# HetrixTools Linux Server Monitoring Agent

Documentation available here: https://docs.hetrixtools.com/category/server-monitor/


-= ChangeLog =-

Version 1.6.3:
- moving to 1.6.x branch
- minor changes

Version 1.6.2:
- improved the `timeout` command for `needs-restarting` which would still hang in rare cases (thanks to @BetTD)

Version 1.6.1:
- Added `timeout` to some calls to prevent them from freezing the agent script entirely in certain rare cases
- Improved metrics posting with retries when the initial try fails
- Improved disk detection for disk usage metrics (certain disks were not being detected before)

Version 1.6.0:
- Bash code improvements ( thanks to https://www.shellcheck.net/ ).
- Fixed warning messages for servers without swap.

Version 1.5.9:
- Added disk IO data collection.
- Added disk inodes data collection.
- Added ability to track the number of network connections on specific ports.

Version 1.5.8:
- Improved compression to reduce data payload size

Version 1.5.7:
- Drive Health can now query the Drive stats (via S.M.A.R.T.) even when drives are behind hardware RAID

Version 1.5.6:
- Added user warning if the server requires reboot
- Added SMART self-test for NVMe disks

Version 1.5.5:
- Support for multiple network interfaces
- Read kernel version

Version 1.5.4:
- View running processes

Version 1.5.3:
- Software RAID Monitor
- Drive Health Monitor

Version 1.5.2:
- System Uptime
- IO Wait
- Swap Usage
- Multiple Disks Support (up to 10 disks)
- Service Monitor (up to 10 services)

---

### Unofficial forks:
- SmartOS/Solaris: https://github.com/sunfoxcz/hetrixtools-agent-smartos/tree/smartos
- OpenBSD: https://github.com/sholwe/hetrixtools-agent-openbsd
