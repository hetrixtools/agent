# HetrixTools Linux Server Monitoring Agent

Documentation available here: https://docs.hetrixtools.com/category/server-monitor/


-= ChangeLog =-

Version 2.0.10: 
- Fixed `division by zero` error for servers without swap.
- Replace `ifconfig` with `ip` command for IP address extraction. (thanks to @Ry3nlNaToR)

Version 2.0.9: 
- Fixed a bug where in some cases RAID would not be detected properly.

Version 2.0.8: 
- Added support for Custom Variables: https://docs.hetrixtools.com/server-agent-custom-variables/ 
- Fixed `needs-restarting` for CloudLinux 8 https://github.com/hetrixtools/agent/commit/7e87b191bab90f682d2f55cc0f2650b5f4f7e0c7 (thanks to @JLHC)

Version 2.0.7:  
- Improved CPU temperature reading by adding support for two third-party software `lm-sensors` and `ipmitool`.

Version 2.0.6:
- Improved the `servicestatus` function.

Version 2.0.5:
- Improved the `servicestatus` function.

Version 2.0.4:
- fixed a bug where data was not properly being formatted in some cases when monitoring running processes

Version 2.0.3:
- initial v2 release

Pre v2 changelog:  
https://github.com/hetrixtools/agent/tree/1.6.x
