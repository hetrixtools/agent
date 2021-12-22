#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent
#	version 1.5.9
#	Copyright 2015 - 2021 @  HetrixTools
#	For support, please open a ticket on our website https://hetrixtools.com
#
#
#		DISCLAIMER OF WARRANTY
#
#	The Software is provided "AS IS" and "WITH ALL FAULTS," without warranty of any kind, 
#	including without limitation the warranties of merchantability, fitness for a particular purpose and non-infringement. 
#	HetrixTools makes no warranty that the Software is free of defects or is suitable for any particular purpose. 
#	In no event shall HetrixTools be responsible for loss or damages arising from the installation or use of the Software, 
#	including but not limited to any indirect, punitive, special, incidental or consequential damages of any character including, 
#	without limitation, damages for loss of goodwill, work stoppage, computer failure or malfunction, or any and all other commercial damages or losses. 
#	The entire risk as to the quality and performance of the Software is borne by you, the user.
#
#

##############
## Settings ##
##############

# Set PATH/Locale
export LC_NUMERIC="en_US.UTF-8"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ScriptPath=$(dirname "${BASH_SOURCE[0]}")

# Agent Version (do not change)
VERSION="1.5.9"

# SID (Server ID - automatically assigned on installation, do not change this)
# DO NOT share this ID with anyone
SID="SIDPLACEHOLDER"

# How frequently should the data be collected (do not modify this, unless instructed to do so)
CollectEveryXSeconds=3

# Runtime, in seconds (do not modify this, unless instructed to do so)
Runtime=60

# Network Interfaces
# * if you leave this setting empty our agent will detect and monitor all of your active network interfaces
# * if you wish to monitor just one interface, fill its name down below (ie: "eth1")
# * if you wish to monitor just some specific interfaces, fill their names below separated by comma (ie: "eth0,eth1,eth2")
NetworkInterfaces=""

# Check Services
# * separate service names by comma (,) with a maximum of 10 services to be monitored (ie: "ssh,mysql,apache2,nginx")
# * NOTE: this will only check if the service is running, not its functionality
CheckServices=""

# Check Software RAID Health
# * checks the status/health of any software RAID (mdadm) setup on the server
# * agent must be run as 'root' or privileged user to fetch the RAID status
# * 0 - OFF (default) | 1 - ON
CheckSoftRAID=0

# Check Drive Health
# * checks the health of any found drives on the system
# * requirements: 'S.M.A.R.T.' for HDD/SSD or 'nvme-cli' for NVMe
# * (these do not get installed by our agent, you must install them separately)
# * agent must be run as 'root' or privileged user to use this function
# * 0 - OFF (default) | 1 - ON
CheckDriveHealth=0

# View Running Processes
# * whether or not to record the server's running processes and display them in your HetrixTools dashboard
# * 0 - OFF (default) | 1 - ON
RunningProcesses=0

# Port Connections
# * track network connections to specific ports
# * supports up to 10 different ports, separated by comma (ie: "80,443,3306")
ConnectionPorts=""

# Config Override file
# Create a file called "hetrixtools_agent.conf" in the script directory instead of modifying the above variables
# to allow easy git pulls / updates
if [ -f "$ScriptPath/hetrixtools_agent.conf" ]; then
	source "$ScriptPath/hetrixtools_agent.conf"
fi

################################################
## CAUTION: Do not edit any of the code below ##
################################################

function servicestatus() {
	# Check first via ps
	if (( $(pgrep -ifc "$1") > 0 ))
	then
		# Up
		echo "$(echo -ne "$1" | base64),1"
	else
		# Down, try with systemctl (if available)
		if command -v "systemctl" > /dev/null 2>&1
		then
			if systemctl is-active --quiet "$1"
			then
				# Up
				echo "$(echo -ne "$1" | base64),1"
			else
				# Down
				echo "$(echo -ne "$1" | base64),0"
			fi
		else
			# No systemctl, declare it down
			echo "$(echo -ne "$1" | base64),0"
		fi
	fi
}

# Function used to prepare base64 str for url encoding
function base64prep() {
	str=$1
	str="${str//+/%2B}"
	str="${str//\//%2F}"
	echo "$str"
}

# Kill any lingering agent processes
HTProcesses=$(pgrep -ifc "hetrixtools_agent.sh")
if [ -z "$HTProcesses" ]
then
	HTProcesses=0
fi
if [ "$HTProcesses" -gt 15 ]
then
	pgrep -if "hetrixtools_agent.sh" | xargs kill -9
fi
for PID in $(pgrep -if "hetrixtools_agent.sh")
do
	PID_TIME=$(ps -p "$PID" -oetime= | tr '-' ':' | awk -F: '{ total=0; m=1; } { for (i=0; i < NF; i++) {total += $(NF-i)*m; m *= i >= 2 ? 24 : 60 }} {print total}')
	if [ -n "$PID_TIME" ] && [ "$PID_TIME" -ge 120 ]
	then
		kill -9 "$PID"
	fi
done

# Calculate how many times per minute should the data be collected (based on the `CollectEveryXSeconds` setting)
RunTimes=$((Runtime / CollectEveryXSeconds))

# Start timers
START=$(date +%s)
tTIMEDIFF=0
M=$(date +%M | sed 's/^0*//')
if [ -z "$M" ]
then
	M=0
	# Clear the hetrixtools_cron.log every hour
	rm -f "$ScriptPath"/hetrixtools_cron.log
fi

# Network interfaces
if [ -n "$NetworkInterfaces" ]
then
	# Use the network interfaces specified in Settings
	IFS=',' read -r -a NetworkInterfacesArray <<< "$NetworkInterfaces"
else
	# Automatically detect the network interfaces
    mapfile -t NetworkInterfacesArray < <(ip a | grep BROADCAST | grep 'state UP' | awk '{print $2}' | awk -F ":" '{print $1}' | awk -F "@" '{print $1}')
fi
# Get the initial network usage
T=$(cat /proc/net/dev)
declare -A aRX
declare -A aTX
declare -A tRX
declare -A tTX
# Loop through network interfaces
for NIC in "${NetworkInterfacesArray[@]}"
do
	aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
	aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
done

# Port connections
if [ -n "$ConnectionPorts" ]
then
	IFS=',' read -r -a ConnectionPortsArray <<< "$ConnectionPorts"
	declare -A Connections
	netstat=$(netstat -ntu | awk '{print $4}')
	for cPort in "${ConnectionPortsArray[@]}"
	do
		Connections[$cPort]=$(echo "$netstat" | grep -c ":$cPort$")
	done
fi

# Disks IOPS
declare -A vDISKs
for i in $(df | awk '$1 ~ /\// {print}' | awk '{ print $(NF) }')
do
	vDISKs[$i]=$(lsblk -l | grep -w "$i" | awk '{ print $1 }')
done
declare -A IOPSRead
declare -A IOPSWrite
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
	IOPSRead[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}')
	IOPSWrite[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}')
done

# Collect data loop
for X in $(seq $RunTimes)
do
	# Get vmstat info
	VMSTAT=$(vmstat $CollectEveryXSeconds 2 | tail -1 )
	# Get CPU Load
	CPU=$((100 - $( echo "$VMSTAT" | awk '{print $15}')))
	tCPU=$(echo | awk "{ print $tCPU + $CPU }")
	# Get IO Wait
	IOW=$( echo "$VMSTAT" | awk '{print $16}')
	tIOW=$(echo | awk "{ print $tIOW + $IOW }")
	# Get RAM Usage
	aRAM=$( echo "$VMSTAT" | awk '{print $4 + $5 + $6}')
	bRAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
	RAM=$(echo | awk "{ print $aRAM*100/$bRAM }")
	RAM=$(echo | awk "{ print 100 - $RAM }")
	tRAM=$(echo | awk "{ print $tRAM + $RAM }")
	# Get Network Usage
	T=$(cat /proc/net/dev)
	END=$(date +%s)
	TIMEDIFF=$(echo | awk "{ print $END - $START }")
	tTIMEDIFF=$(echo | awk "{ print $tTIMEDIFF + $TIMEDIFF }")
	START=$(date +%s)
	# Loop through network interfaces
	for NIC in "${NetworkInterfacesArray[@]}"
	do
		# Received Traffic
		RX=$(echo | awk "{ print $(echo "$T" | grep -w "$NIC:" | awk '{print $2}') - ${aRX[$NIC]} }")
		RX=$(echo | awk "{ print $RX / $TIMEDIFF }")
		RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
		aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
		tRX[$NIC]=$(echo | awk "{ print ${tRX[$NIC]} + $RX }")
		tRX[$NIC]=$(echo "${tRX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
		# Transferred Traffic
		TX=$(echo | awk "{ print $(echo "$T" | grep -w "$NIC:" | awk '{print $10}') - ${aTX[$NIC]} }")
		TX=$(echo | awk "{ print $TX / $TIMEDIFF }")
		TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
		aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
		tTX[$NIC]=$(echo | awk "{ print ${tTX[$NIC]} + $TX }")
		tTX[$NIC]=$(echo "${tTX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
	done
	# Port connections
	if [ -n "$ConnectionPorts" ]
	then
		netstat=$(netstat -ntu | awk '{print $4}')
		for cPort in "${ConnectionPortsArray[@]}"
		do
			Connections[$cPort]=$(echo | awk "{ print ${Connections[$cPort]} + $(echo "$netstat" | grep -c ":$cPort$") }")
		done
	fi
	# Check if minute changed, so we can end the loop
	MM=$(date +%M | sed 's/^0*//')
	if [ -z "$MM" ]
	then
		MM=0
	fi
	if [ "$MM" -gt "$M" ] 
	then
		break
	fi
done

# Disks IOPS
IOPS=""
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
	IOPSRead[$i]=$(echo | awk "{ print $(echo | awk "{ print $(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}') - ${IOPSRead[$i]} }") * 512 / $tTIMEDIFF}")
	IOPSRead[$i]=$(echo "${IOPSRead[$i]}" | awk '{printf "%18.0f",$1}' | xargs)
	IOPSWrite[$i]=$(echo | awk "{ print $(echo | awk "{ print $(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}') - ${IOPSWrite[$i]} }") * 512 / $tTIMEDIFF}")
	IOPSWrite[$i]=$(echo "${IOPSWrite[$i]}" | awk '{printf "%18.0f",$1}' | xargs)
	IOPS="${IOPS}|${i};${IOPSRead[$i]};${IOPSWrite[$i]}"
done
IOPS=$(echo -ne "$IOPS" | gzip -cf | base64)
IOPS=$(base64prep "$IOPS")

# Check if system requires reboot
RequiresReboot=0
if [ -f  /var/run/reboot-required ]
then
	RequiresReboot=1
fi
# Get Operating System and Kernel
# Check via lsb_release if possible
if command -v "lsb_release" > /dev/null 2>&1
then
	OS=$(lsb_release -s -d)
# Check if it's Debian
elif [ -f /etc/debian_version ]
then
	OS="Debian $(cat /etc/debian_version)"
# Check if it's CentOS/Fedora
elif [ -f /etc/redhat-release ]
then
	OS=$(cat /etc/redhat-release)
	# Check if system requires reboot (Only supported in CentOS/RHEL 7 and later, with yum-utils installed)
	if needs-restarting -r | grep -q 'Reboot is required'
	then
		RequiresReboot=1
	fi
# If all else fails, get Kernel name
else
	OS="$(uname -s) $(uname -r)"
fi
OS=$(echo -ne "$OS|$(uname -r)|$RequiresReboot" | base64)
# Get the server uptime
Uptime=$(awk '{ print $1 }' /proc/uptime)
# Get CPU model
CPUModel=$(grep -m1 'model name' /proc/cpuinfo | awk -F": " '{ print $2 }')
CPUModel=$(echo -ne "$CPUModel" | base64)
# Get CPU speed (MHz)
CPUSpeed=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F": " '{ print $2 }')
CPUSpeed=$(echo -ne "$CPUSpeed" | base64)
# Get number of cores
CPUCores=$(grep -c processor /proc/cpuinfo)
# Calculate average CPU Usage
CPU=$(echo | awk "{ print $tCPU / $X }")
# Calculate IO Wait
IOW=$(echo | awk "{ print $tIOW / $X }")
# Get system memory (RAM)
RAMSize=$(grep ^MemTotal: /proc/meminfo | awk '{print $2}')
# Calculate RAM Usage
RAM=$(echo | awk "{ print $tRAM / $X }")
# Get the Swap Size
SwapSize=$(grep ^SwapTotal: /proc/meminfo | awk '{print $2}')
# Calculate Swap Usage
SwapFree=$(grep ^SwapFree: /proc/meminfo | awk '{print $2}')
Swap=$(echo | awk "{ print 100 - (($SwapFree / $SwapSize) * 100) }")
# Get all disks usage
DISKs=$(echo -ne "$(df -PB1 | awk '$1 ~ /\// {print}' | awk '{ print $(NF)","$2","$3","$4";" }')" | gzip -cf | base64)
DISKs=$(base64prep "$DISKs")
# Get all disks inodes
DISKi=$(echo -ne "$(df -i | awk '$1 ~ /\// {print}' | awk '{ print $(NF)","$2","$3","$4";" }')" | gzip -cf | base64)
DISKi=$(base64prep "$DISKi")
# Calculate Total Network Usage (bytes)
RX=0
TX=0
NICS=""
for NIC in "${NetworkInterfacesArray[@]}"
do
	# Calculate individual NIC usage
	RX=$(echo | awk "{ print ${tRX[$NIC]} / $X }")
	RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
	TX=$(echo | awk "{ print ${tTX[$NIC]} / $X }")
	TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
	NICS="${NICS}|${NIC};${RX};${TX};"
done
NICS=$(echo -ne "$NICS" | gzip -cf | base64)
NICS=$(base64prep "$NICS")
# Port connections
CONN=""
if [ -n "$ConnectionPorts" ]
then
	for cPort in "${ConnectionPortsArray[@]}"
	do
		CON=$(echo | awk "{ print ${Connections[$cPort]} / $X }")
		CON=$(echo "$CON" | awk '{printf "%18.0f",$1}' | xargs)
		CONN="${CONN}|${cPort};${CON}"
	done
fi
CONN=$(echo -ne "$CONN" | base64)
CONN=$(base64prep "$CONN")
# Check Services (if any are set to be checked)
ServiceStatusString=""
if [ -n "$CheckServices" ]
then
	IFS=',' read -r -a CheckServicesArray <<< "$CheckServices"
	for i in "${CheckServicesArray[@]}"
	do
		ServiceStatusString="${ServiceStatusString}$(servicestatus "$i");"
	done
fi
# Check Software RAID
RAID=""
if [ "$CheckSoftRAID" -gt 0 ]
then
	for i in $(df -PB1 | awk '$1 ~ /\// {print}' | awk '{ print $1 }')
	do
		mdadm=$(mdadm -D "$i")
		if [ -n "$mdadm" ]
		then
			mnt=$(df -PB1 | grep "$i" | awk '{ print $(NF) }')
			RAID="$RAID|$mnt;$i;$mdadm;"
		fi
	done
fi
RAID=$(echo -ne "$RAID" | gzip -cf | base64)
RAID=$(base64prep "$RAID")
# Check Drive Health
DH=""
if [ "$CheckDriveHealth" -gt 0 ]
then
	if [ -x "$(command -v smartctl)" ] #Using S.M.A.R.T. (for regular HDD/SSD)
	then
		for i in $(lsblk -l | grep 'disk' | awk '{ print $1 }')
		do
			DHealth=$(smartctl -A /dev/"$i")
			if grep -q 'Attribute' <<< "$DHealth"
			then
				DHealth=$(smartctl -H /dev/"$i")"\n$DHealth"
				DH="$DH|1\n$i\n$DHealth\n"
			else # If initial read has failed, see if drives are behind hardware raid
				mapfile -t MegaRaid < <(smartctl --scan | grep megaraid | awk '{ print $(3) }')
				if [ ${#MegaRaid[@]} -gt 0 ]
				then
					MegaRaidN=0
					for MegaRaidID in "${MegaRaid[@]}"
					do
						DHealth=$(smartctl -A -d "$MegaRaidID" /dev/"$i")
						if grep -q 'Attribute' <<< "$DHealth"
						then
							MegaRaidN=$((MegaRaidN + 1))
							DHealth=$(smartctl -H -d "$MegaRaidID" /dev/"$i")"\n$DHealth"
							DH="$DH|1\n${i}[$MegaRaidN]\n$DHealth\n"
						fi
					done
					break
				fi
			fi
		done
	fi
	if [ -x "$(command -v nvme)" ] #Using nvme-cli (for NVMe)
	then
		for i in $(lsblk -l | grep 'disk' | awk '{ print $1 }')
		do
			DHealth=$(nvme smart-log /dev/"$i")
			if grep -q 'NVME' <<< "$DHealth"
			then
				if [ -x "$(command -v smartctl)" ]
				then
					DHealth=$(smartctl -H /dev/"${i%??}")"\n$DHealth"
				fi
				DH="$DH|2\n$i\n$DHealth\n"
			fi
		done
	fi
fi
DH=$(echo -ne "$DH" | gzip -cf | base64)
DH=$(base64prep "$DH")
# Running Processes
RPS1=""
RPS2=""
if [ "$RunningProcesses" -gt 0 ]
then
	# Get initial 'running processes' snapshot, saved from last run
	RPS1=$(cat "$ScriptPath"/running_proc.txt)
	# Get the current 'running processes' snapshot
	RPS2=$(ps -Ao pid,ppid,uid,user:20,pcpu,pmem,cputime,etime,comm,cmd --no-headers)
	RPS2=$(echo -ne "$RPS2" | gzip -cf | base64)
	RPS2=$(base64prep "$RPS2")
	# Save the current snapshot for next run
	echo "$RPS2" > "$ScriptPath"/running_proc.txt
fi

# Prepare data
DATA="$OS|$Uptime|$CPUModel|$CPUSpeed|$CPUCores|$CPU|$IOW|$RAMSize|$RAM|$SwapSize|$Swap|$DISKs|$NICS|$ServiceStatusString|$RAID|$DH|$RPS1|$RPS2|$IOPS|$CONN|$DISKi"
POST="v=$VERSION&s=$SID&d=$DATA"
# Save data to file
echo "$POST" > "$ScriptPath"/hetrixtools_agent.log

# Post data
wget -t 1 -T 30 -qO- --post-file="$ScriptPath/hetrixtools_agent.log" --no-check-certificate https://sm.hetrixtools.net/ &> /dev/null
