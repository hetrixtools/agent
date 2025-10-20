# HetrixTools Linux Server Monitoring Agent

Documentation available here: https://docs.hetrixtools.com/category/server-monitor/

### Changelog

#### Version 2.3.4:
- Improved Software RAID detection
- Fixed timeout wrong value

#### Version 2.3.3:
- Implemented automatic ports detection if no ports specified in `hetrixtools.cfg`
- Improved CPU temperature collection method
- Improved disk metrics collection method
- Fixed an issue with Outgoing Pings validation

#### Version 2.3.2:
- Add support for HP Smart Array RAID controllers
- Fixed an issue where, in some cases, CPU temperature wasn't being read properly

#### Version 2.3.1:
- Improved `mdadm` RAID reading
- Improved auto network detection
- Improved install script to use `systemd`
- Fixed `lsblk` compatibility with older operating systems (issue [#79](https://github.com/hetrixtools/agent/issues/79))

#### Version 2.3.0:
- Added support for Outgoing Pings
- Added support for `zpool` pools IO read/write metrics
- Fallback service-status check via `service` command
- Improved NVMe disks info reading
- Improved disk IO read/write metrics
- Improved OS reading (issue [#66](https://github.com/hetrixtools/agent/issues/66))
- Branch-existence verification in the update script
- Fixed an issue where in some cases `sensors` would yield repeated errors (non-impacting)
- Fixed an issue where sometimes smart log would yield some errors (non-impacting)

#### Version 2.2.11:
- Fixed an issue where, in some cases, `zpool` metrics weren't being registered properly

#### Version 2.2.10:
- Fixed an issue where, in some cases, the CPU temperature collection would interrupt the metrics collection loop

#### Version 2.2.9:
- Fixed an issue where, in some cases, NVMe disk Serial and Model were not detected properly

#### Version 2.2.8:
- Fixed an issue with incorrect MegaRAID disk detection

#### Version 2.2.7:
- Fixed an issue related to `mdadm` introduced in `2.2.1`

#### Version 2.2.6:
- Switched back to the old DEBUG mode method, as it was more efficient
- Fixed an incompatibility with older kernels introduced in `2.2.5`
- Fixed cases where Software RAID isn't picked up properly

#### Version 2.2.5:
- `zpool` now records disk usage even for unmounted pools
- Fixed some rare cases where base64 would break on multiple lines

#### Version 2.2.4:
- `CPUModel` should now pick up more CPU model names
- Fixed an issue where `CPUCores` and `CPUThreads` would not handle multi-line data properly
- Changed how the agent handles killing of its own old/frozen processes, if any are found
- Increased DEBUG mode clearing time
- Improved DEBUG mode

#### Version 2.2.3:
- Fixed an issue where SMART test was not properly performed on NVMe disks
- Improved DEBUG mode

#### Version 2.2.2:
- Improved DEBUG mode
- Fixed an issue where agent would kill its own processes too eagerly, causing data sending issues

#### Version 2.2.1:
- Fixed an issue where, in some cases, the agent would query `mdadm` for devices not using `mdadm`
- Changed `LC_NUMERIC` locale

#### Version 2.2.0:
- Introducing DEBUG mode
- Minor fixes and tweaks

#### Version 2.1.0:
- Introducing ZFS pool health monitoring
- Added `CollectEveryXSeconds` to agent config

#### Version 2.0.12:
- Fixed an issue with the new service monitoring method introduced in version 2.0.11

#### Version 2.0.11:
- Improved service monitoring
- Fixed an issue where the metrics collection loop wouldn't break properly

#### Version 2.0.10: 
- Fixed `division by zero` error for servers without swap
- Replace `ifconfig` with `ip` command for IP address extraction (thanks to @Ry3nlNaToR)

#### Version 2.0.9: 
- Fixed a bug where in some cases RAID would not be detected properly

#### Version 2.0.8: 
- Added support for Custom Variables: https://docs.hetrixtools.com/server-agent-custom-variables/ 
- Fixed `needs-restarting` for CloudLinux 8 https://github.com/hetrixtools/agent/commit/7e87b191bab90f682d2f55cc0f2650b5f4f7e0c7 (thanks to @JLHC)

#### Version 2.0.7:  
- Improved CPU temperature reading by adding support for two third-party software `lm-sensors` and `ipmitool`

#### Version 2.0.6:
- Improved the `servicestatus` function

#### Version 2.0.5:
- Improved the `servicestatus` function

#### Version 2.0.4:
- Fixed a bug where data was not properly being formatted in some cases when monitoring running processes

#### Version 2.0.3:
- Initial v2 release

#### Version 1.x:
https://github.com/hetrixtools/agent/tree/1.6.x

