#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent
#	version 1.5.3
#	Copyright 2018 @  HetrixTools
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

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Agent Version (do not change)
VERSION="1.5.3"

# SID (Server ID - automatically assigned on installation, do not change this)
# DO NOT share this ID with anyone
SID="SIDPLACEHOLDER"

# How frequently should the data be collected (do not modify this, unless instructed to do so)
CollectEveryXSeconds=3

# Runtime, in seconds (do not modify this, unless instructed to do so)
Runtime=60

# Network Interface
# * our agent will try to find your public network interface during installation
# * however, you can manually specify a network interface name below, in order to gather usage statistics from that particular one instead
NetworkInterface="ETHPLACEHOLDER"

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

################################################
## CAUTION: Do not edit any of the code below ##
################################################

# Check service status function
function servicestatus() {
	# Check if we have systemctl
	if command -v "systemctl" > /dev/null 2>&1
	then
		if $(systemctl is-active --quiet $1)
		then
			echo "$(echo -ne "$1" | base64),1"
		else
			echo "$(echo -ne "$1" | base64),0"
		fi
	else
		if (( $(ps -ef | grep -v grep | grep $1 | wc -l) > 0 ))
		then
			echo "$(echo -ne "$1" | base64),1"
		else
			echo "$(echo -ne "$1" | base64),0"
		fi
	fi
}

# Kill any lingering agent processes (there shouldn't be any, the agent should finish its job within ~50 seconds, 
# so when a new cycle starts there shouldn't be any lingering agents around, but just in case, so they won't stack)
HTProcesses=$(ps -eo user=|sort|uniq -c | grep hetrixtools | awk -F " " '{print $1}')
if [ -z "$HTProcesses" ]
then
	HTProcesses=0
fi
if [ "$HTProcesses" -gt 300 ]
then
	ps aux | grep -ie hetrixtools_agent.sh | awk '{print $2}' | xargs kill -9
fi

# Calculate how many times per minute should the data be collected (based on the `CollectEveryXSeconds` setting)
RunTimes=$(($Runtime/$CollectEveryXSeconds))

# Get starting minute
M=$(echo `date +%M` | sed 's/^0*//')
if [ -z "$M" ]
then
	M=0
	# Clear the hetrixtools_cron.log every hour
	rm -f /etc/hetrixtools/hetrixtools_cron.log
fi

# Get the initial network usage
T=$(cat /proc/net/dev | grep "$NetworkInterface:" | awk '{print $2"|"$10}')
START=$(date +%s)
aRX=$(echo $T | awk -F "|" '{print $1}')
aTX=$(echo $T | awk -F "|" '{print $2}')

# Collect data loop
for X in $(seq $RunTimes)
do
	# Get vmstat info
	VMSTAT=$(vmstat $CollectEveryXSeconds 2 | tail -1 )
	# Get CPU Load
	CPU=$(echo $[100-$( echo "$VMSTAT" | awk '{print $15}')])
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
	T=$(cat /proc/net/dev | grep "$NetworkInterface:" | awk '{print $2"|"$10}')
	END=$(date +%s)
	TIMEDIFF=$(echo | awk "{ print $END - $START }")
	START=$(date +%s)
	# Received Traffic
	RX=$(echo | awk "{ print $(echo $T | awk -F "|" '{print $1}') - $aRX }")
	RX=$(echo | awk "{ print $RX / $TIMEDIFF }")
	RX=$(echo "$RX" | awk {'printf "%18.0f",$1'} | xargs)
	aRX=$(echo $T | awk -F "|" '{print $1}')
	tRX=$(echo | awk "{ print $tRX + $RX }")
	tRX=$(echo "$tRX" | awk {'printf "%18.0f",$1'} | xargs)
	# Transferred Traffic
	TX=$(echo | awk "{ print $(echo $T | awk -F "|" '{print $2}') - $aTX }")
	TX=$(echo | awk "{ print $TX / $TIMEDIFF }")
	TX=$(echo "$TX" | awk {'printf "%18.0f",$1'} | xargs)
	aTX=$(echo $T | awk -F "|" '{print $2}')
	tTX=$(echo | awk "{ print $tTX + $TX }")
	tTX=$(echo "$tTX" | awk {'printf "%18.0f",$1'} | xargs)
	# Check if minute changed, so we can end the loop
	MM=$(echo `date +%M` | sed 's/^0*//')
	if [ -z "$MM" ]
	then
		MM=0
	fi
	if [ "$MM" -gt "$M" ] 
	then
		break
	fi
done

# Get Operating System
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
	OS=`cat /etc/redhat-release`
# If all else fails, get Kernel name
else
	OS="$(uname -s) $(uname -r)"
fi
OS=$(echo -ne "$OS" | base64)
# Get the server uptime
Uptime=$(cat /proc/uptime | awk '{ print $1 }')
# Get CPU model
CPUModel=$(cat /proc/cpuinfo | grep 'model name' | uniq | awk -F": " '{ print $2 }')
CPUModel=$(echo -ne "$CPUModel" | base64)
# Get CPU speed (MHz)
CPUSpeed=$(cat /proc/cpuinfo | grep 'cpu MHz' | uniq | awk -F": " '{ print $2 }')
# Get number of cores
CPUCores=$(cat /proc/cpuinfo | grep processor | wc -l)
# Calculate average CPU Usage
CPU=$(echo | awk "{ print $tCPU / $X }")
# Calculate IO Wait
IOW=$(echo | awk "{ print $tIOW / $X }")
# Get system memory (RAM)
RAMSize=$(cat /proc/meminfo | grep ^MemTotal: | awk '{print $2}')
# Calculate RAM Usage
RAM=$(echo | awk "{ print $tRAM / $X }")
# Get the Swap Size
SwapSize=$(cat /proc/meminfo | grep ^SwapTotal: | awk '{print $2}')
# Calculate Swap Usage
SwapFree=$(cat /proc/meminfo | grep ^SwapFree: | awk '{print $2}')
Swap=$(echo | awk "{ print 100 - (($SwapFree / $SwapSize) * 100) }")
# Get all disks usage
DISKs=$(echo -ne $(df -PB1 | awk '$1 ~ /\// {print}' | awk '{ print $(NF)","$2","$3","$4";" }') | base64)
# Calculate Network Usage (bytes)
RX=$(echo | awk "{ print $tRX / $X }")
RX=$(echo "$RX" | awk {'printf "%18.0f",$1'} | xargs)
TX=$(echo | awk "{ print $tTX / $X }")
TX=$(echo "$TX" | awk {'printf "%18.0f",$1'} | xargs)
# Check Services (if any are set to be checked)
if [ ! -z "$CheckServices" ]
then
	IFS=',' read -r -a CheckServicesArray <<< "$CheckServices"
	for i in "${CheckServicesArray[@]}"
	do
		ServiceStatusString="$ServiceStatusString"$(servicestatus "$i")";"
	done
fi
# Check Software RAID
RAID=""
if [ "$CheckSoftRAID" -gt 0 ]
then
	for i in $(df -PB1 | awk '$1 ~ /\// {print}' | awk '{ print $1 }')
	do
		mdadm=$(mdadm -D $i)
		if [ ! -z "$mdadm" ]
		then
			mnt=$(df -PB1 | grep $i | awk '{ print $(NF) }')
			RAID="$RAID|$mnt;$i;$mdadm;"
		fi
	done
fi
RAID=$(echo -ne "$RAID" | base64)
#Check Drive Health
DH=""
if [ "$CheckDriveHealth" -gt 0 ]
then
	if [ -x "$(command -v smartctl)" ] #Using S.M.A.R.T. (for regular HDD/SSD)
	then
		for i in $(lsblk -l | grep 'disk' | awk '{ print $1 }')
		do
			DHealth=$(smartctl -A /dev/$i)
			if grep -q 'Attribute' <<< $DHealth
			then
				DHealth=$(smartctl -H /dev/$i)"\n$DHealth"
				DH="$DH|1\n$i\n$DHealth\n"
			fi
		done
	fi
	if [ -x "$(command -v nvme)" ] #Using nvme-cli (for NVMe)
	then
		for i in $(lsblk -l | grep 'disk' | awk '{ print $1 }')
		do
			DHealth=$(nvme smart-log /dev/$i)
			if grep -q 'NVME' <<< $DHealth
			then
				DH="$DH|2\n$i\n$DHealth\n"
			fi
		done
	fi
fi
DH=$(echo -ne "$DH" | base64)

# Bundle collected data
DATA="$OS|$Uptime|$CPUModel|$CPUSpeed|$CPUCores|$CPU|$IOW|$RAMSize|$RAM|$SwapSize|$Swap|$DISKs|$RX|$TX|$ServiceStatusString|$RAID|$DH"
# Post string
POST="v=$VERSION&s=$SID&d=$DATA"

# Logging entire post string (for debugging)
echo $POST > /etc/hetrixtools/hetrixtools_agent.log

# Post collected data
wget -t 1 -T 30 -qO- --post-data "$POST" --no-check-certificate https://sm.hetrixtools.com/ &> /dev/null
