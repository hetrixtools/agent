# HetrixTools Linux Server Monitoring Agent

Documentation available here: https://docs.hetrixtools.com/category/server-monitor/


-= ChangeLog =-

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
