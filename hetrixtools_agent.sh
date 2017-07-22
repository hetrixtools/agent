#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent
#	version 1.04
#	Copyright 2016 @  HetrixTools
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
VERSION="1.04"

# SID (Server ID - automatically assigned on installation, do not change this)
# DO NOT share this ID with anyone
SID="SIDPLACEHOLDER"

# How frequently should the data be collected (in seconds) [recommended: 3-5, min: 2, max: 15]
CollectEveryXSeconds=3

# Runtime, in seconds (do not modify this, unless instructed to do so)
Runtime=60

# Partition to get disk usage for
# * you can modify this value, if you wish to track the disk usage of any other partition on the server
DiskPartition="/"

# Network Interface
# * our agent will try to find your public network interface during installation
# * however, you can manually specify a network interface name below, in order to gather usage statistics from that particular one instead
NetworkInterface="ETHPLACEHOLDER"

################################################
## CAUTION: Do not edit any of the code below ##
################################################

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
# Get CPU model
CPUModel=$(cat /proc/cpuinfo | grep 'model name' | uniq | awk -F": " '{ print $2 }')
CPUModel=$(echo -ne "$CPUModel" | base64)
# Get CPU speed (MHz)
CPUSpeed=$(cat /proc/cpuinfo | grep 'cpu MHz' | uniq | awk -F": " '{ print $2 }')
# Get number of cores
CPUCores=$(cat /proc/cpuinfo | grep processor | wc -l)
# Calculate average CPU Usage
CPU=$(echo | awk "{ print $tCPU / $X }")
# Get system memory (RAM)
RAMSize=$(cat /proc/meminfo | grep MemTotal | awk -F":" '{ print $2 }' | xargs)
RAMSize=$(echo "$RAMSize" | awk -F" " '{ print $1 }')
# Calculate average RAM Usage
RAM=$(echo | awk "{ print $tRAM / $X }")
# Get disk size
DISKSize=$(df -h "$DiskPartition" | awk '{print $2}' | tail -n 1)
# Get disk usage
DISK=$(df -h "$DiskPartition" | awk '{print $(NF-1)}' | tail -n 1 | sed 's/\%//g')
# Calculate Network Usage (bytes)
RX=$(echo | awk "{ print $tRX / $X }")
RX=$(echo "$RX" | awk {'printf "%18.0f",$1'} | xargs)
TX=$(echo | awk "{ print $tTX / $X }")
TX=$(echo "$TX" | awk {'printf "%18.0f",$1'} | xargs)

# Bundle collected data
DATA="$OS|$CPUModel|$CPUSpeed|$CPUCores|$CPU|$RAMSize|$RAM|$DISKSize|$DISK|$RX|$TX"
# Post string
POST="v=$VERSION&s=$SID&d=$DATA"

# Logging entire post string (for debugging)
echo $POST > /etc/hetrixtools/hetrixtools_agent.log

# Post collected data
wget -t 1 -T 30 -qO- --post-data "$POST" --no-check-certificate https://hetrixtools.com/s.php &> /dev/null
