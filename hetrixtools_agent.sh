#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent
#	Copyright 2015 - 2024 @  HetrixTools
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
#		END OF DISCLAIMER OF WARRANTY

# Set PATH/Locale
export LC_NUMERIC="C"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ScriptPath=$(dirname "${BASH_SOURCE[0]}")

# Agent Version (do not change)
Version="2.2.8"

# Load configuration file
if [ -f "$ScriptPath"/hetrixtools.cfg ]
then
	. "$ScriptPath"/hetrixtools.cfg
else
	exit 1
fi

# Script start time
ScriptStartTime=$(date +[%Y-%m-%d\ %T)

# Service status function
function servicestatus() {
	# Check first via ps
	if (( $(ps -ef | grep -E "[\/ ]$1([^\/]|$)" | grep -v "grep" | wc -l) > 0 ))
	then # Up
		echo "1"
	else # Down, try with systemctl (if available)
		if command -v "systemctl" > /dev/null 2>&1
		then # Use systemctl
			if systemctl is-active --quiet "$1"
			then # Up
				echo "1"
			else # Down
				echo "0"
			fi
		else # No systemctl
			echo "0"
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

# Clear debug.log every day at midnight
if [ -z "$(date +%H | sed 's/^0*//')" ] && [ -z "$(date +%M | sed 's/^0*//')" ] && [ -f "$ScriptPath"/debug.log ]
then
	rm -f "$ScriptPath"/debug.log
	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Cleared debug.log" >> "$ScriptPath"/debug.log; fi
fi

# Start timers
START=$(date +%s)
tTIMEDIFF=0

# Get current minute
M=$(date +%M | sed 's/^0*//')
if [ -z "$M" ]
then
	# If minute is empty, set it to 0
	M=0

	# Clear hetrixtools_cron.log every hour
	if [ -f "$ScriptPath"/hetrixtools_cron.log ]
	then
		rm -f "$ScriptPath"/hetrixtools_cron.log
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Cleared hetrixtools_cron.log" >> "$ScriptPath"/debug.log; fi
	fi
fi

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Starting HetrixTools Agent v$Version" >> "$ScriptPath"/debug.log; fi

# Kill any lingering agent processes
HTProcesses=$(pgrep -f hetrixtools_agent.sh | wc -l)
if [ -z "$HTProcesses" ]
then
	HTProcesses=0
fi
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Found $HTProcesses agent processes\n$(ps aux | grep 'hetrixtools_agent.sh')" >> "$ScriptPath"/debug.log; fi

if [ "$HTProcesses" -ge 50 ]
then
	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Killing $HTProcesses lingering agent processes" >> "$ScriptPath"/debug.log; fi
	pgrep -f hetrixtools_agent.sh | xargs kill -9
fi
if [ "$HTProcesses" -ge 10 ]
then
	for PID in $(pgrep -f hetrixtools_agent.sh)
	do
		PID_TIME=$(ps -p "$PID" -oetime= | tr '-' ':' | awk -F: '{total=0; m=1;} {for (i=0; i < NF; i++) {total += $(NF-i)*m; m *= i >= 2 ? 24 : 60 }} {print total}')
		if [ -n "$PID_TIME" ] && [ "$PID_TIME" -ge 90 ]
		then
			if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Killing PID $PID, running for $PID_TIME seconds" >> "$ScriptPath"/debug.log; fi
			kill -9 "$PID"
		fi
	done
fi

# Network interfaces
if [ -n "$NetworkInterfaces" ]
then
	# Use the network interfaces specified in Settings
	IFS=',' read -r -a NetworkInterfacesArray <<< "$NetworkInterfaces"
else
	# Automatically detect the network interfaces
	NetworkInterfacesArray=()
	while IFS='' read -r line; do NetworkInterfacesArray+=("$line"); done < <(ip a | grep BROADCAST | grep 'state UP' | awk '{print $2}' | awk -F ":" '{print $1}' | awk -F "@" '{print $1}')
fi
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Interfaces: ${NetworkInterfacesArray[*]}" >> "$ScriptPath"/debug.log; fi

# Initial network usage
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
	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Interface $NIC RX: ${aRX[$NIC]} TX: ${aTX[$NIC]}" >> "$ScriptPath"/debug.log; fi
done

# Port connections
if [ -n "$ConnectionPorts" ]
then
	IFS=',' read -r -a ConnectionPortsArray <<< "$ConnectionPorts"
	declare -A Connections
	netstat=$(ss -ntu | awk '{print $5}')
	for cPort in "${ConnectionPortsArray[@]}"
	do
		Connections[$cPort]=$(echo "$netstat" | grep -c ":$cPort$")
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Port $cPort Connections: ${Connections[$cPort]}" >> "$ScriptPath"/debug.log; fi
	done
fi

# Temperature
declare -A TempArray
declare -A TempArrayCnt

# Check Services
if [ -n "$CheckServices" ]
then
	declare -A SRVCSR
	IFS=',' read -r -a CheckServicesArray <<< "$CheckServices"
	for i in "${CheckServicesArray[@]}"
	do
		SRVCSR[$i]=$(( ${SRVCSR[$i]} + $(servicestatus "$i") ))
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Service $i status: ${SRVCSR[$i]}" >> "$ScriptPath"/debug.log; fi
	done
fi

# Disks IOPS
declare -A vDISKs
for i in $(timeout 3 df | awk '$1 ~ /\// {print}' | awk '{print $(NF)}')
do
	vDISKs[$i]=$(lsblk -l | grep -w "$i" | awk '{print $1}')
	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Disk $i: ${vDISKs[$i]}" >> "$ScriptPath"/debug.log; fi
done
declare -A IOPSRead
declare -A IOPSWrite
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
	IOPSRead[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}')
	IOPSWrite[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}')
	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Disk $i IOPS Read: ${IOPSRead[$i]} Write: ${IOPSWrite[$i]}" >> "$ScriptPath"/debug.log; fi
done

# Calculate how many how many data sample loops
RunTimes=$(echo | awk "{print 60 / $CollectEveryXSeconds}")
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Collecting data for $RunTimes loops" >> "$ScriptPath"/debug.log; fi

# Collect data loop
for X in $(seq "$RunTimes")
do
	# Get vmstat
	VMSTAT=$(vmstat "$CollectEveryXSeconds" 2 | tail -1)
	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) $VMSTAT" >> "$ScriptPath"/debug.log; fi
	
	# CPU usage
	CPU=$(echo "$VMSTAT" | awk '{print 100 - $15}')
	tCPU=$(echo | awk "{print $tCPU + $CPU}")
	
	# CPU IO wait
	CPUwa=$(echo "$VMSTAT" | awk '{print $16}')
	tCPUwa=$(echo | awk "{print $tCPUwa + $CPUwa}")
	
	# CPU steal time
	CPUst=$(echo "$VMSTAT" | awk '{print $17}')
	tCPUst=$(echo | awk "{print $tCPUst + $CPUst}")

	# CPU user time
	CPUus=$(echo "$VMSTAT" | awk '{print $13}')
	tCPUus=$(echo | awk "{print $tCPUus + $CPUus}")
	
	# CPU system time
	CPUsy=$(echo "$VMSTAT" | awk '{print $14}')
	tCPUsy=$(echo | awk "{print $tCPUsy + $CPUsy}")
	
	# CPU clock
	CPUSpeed=$(grep 'cpu MHz' /proc/cpuinfo | awk -F": " '{print $2}' | awk '{printf "%18.0f",$1}' | xargs | sed -e 's/ /+/g')
	if [ -z "$CPUSpeed" ]
	then
		CPUSpeed=0
	fi
	tCPUSpeed=$(echo | awk "{print $tCPUSpeed + $CPUSpeed}")

	# CPU Load
	loadavg=$(cat /proc/loadavg)
	loadavg1=$(echo "$loadavg" | awk '{print $1}')
	tloadavg1=$(echo | awk "{print $tloadavg1 + $loadavg1}")
	loadavg5=$(echo "$loadavg" | awk '{print $2}')
	tloadavg5=$(echo | awk "{print $tloadavg5 + $loadavg5}")
	loadavg15=$(echo "$loadavg" | awk '{print $3}')
	tloadavg15=$(echo | awk "{print $tloadavg15 + $loadavg15}")

	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) CPU: $CPU IO wait: $CPUwa Steal time: $CPUst User time: $CPUus System time: $CPUsy Load: $loadavg1 $loadavg5 $loadavg15" >> "$ScriptPath"/debug.log; fi
	
	# RAM usage
	aRAM=$(echo "$VMSTAT" | awk '{print $4 + $5 + $6}')
	bRAM=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
	RAM=$(echo | awk "{print $aRAM * 100 / $bRAM}")
	RAM=$(echo | awk "{print 100 - $RAM}")
	tRAM=$(echo | awk "{print $tRAM + $RAM}")

	# RAM swap usage
	aRAMSwap=$(echo "$VMSTAT" | awk '{print $3}')
	cRAM=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')
	if [ "$cRAM" -gt 0 ]
	then
		RAMSwap=$(echo | awk "{print $aRAMSwap * 100 / $cRAM}")
	else
		RAMSwap=0
	fi
	tRAMSwap=$(echo | awk "{print $tRAMSwap + $RAMSwap}")
	
	# RAM buffers usage
	aRAMBuff=$(echo "$VMSTAT" | awk '{print $5}')
	RAMBuff=$(echo | awk "{print $aRAMBuff * 100 / $bRAM}")
	tRAMBuff=$(echo | awk "{print $tRAMBuff + $RAMBuff}")
	
	# RAM cache usage
	aRAMCache=$(echo "$VMSTAT" | awk '{print $6}')
	RAMCache=$(echo | awk "{print $aRAMCache * 100 / $bRAM}")
	tRAMCache=$(echo | awk "{print $tRAMCache + $RAMCache}")

	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) RAM: $RAM Swap: $RAMSwap Buffers: $RAMBuff Cache: $RAMCache" >> "$ScriptPath"/debug.log; fi
	
	# Network usage
	T=$(cat /proc/net/dev)
	END=$(date +%s)
	TIMEDIFF=$(echo | awk "{print $END - $START}")
	tTIMEDIFF=$(echo | awk "{print $tTIMEDIFF + $TIMEDIFF}")
	START=$(date +%s)
	
	# Loop through network interfaces
	for NIC in "${NetworkInterfacesArray[@]}"
	do
		# Received Traffic
		RX=$(echo | awk "{print $(echo "$T" | grep -w "$NIC:" | awk '{print $2}') - ${aRX[$NIC]}}")
		RX=$(echo | awk "{print $RX / $TIMEDIFF}")
		RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
		aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
		tRX[$NIC]=$(echo | awk "{print ${tRX[$NIC]} + $RX}")
		tRX[$NIC]=$(echo "${tRX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
		# Transferred Traffic
		TX=$(echo | awk "{print $(echo "$T" | grep -w "$NIC:" | awk '{print $10}') - ${aTX[$NIC]}}")
		TX=$(echo | awk "{print $TX / $TIMEDIFF}")
		TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
		aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
		tTX[$NIC]=$(echo | awk "{print ${tTX[$NIC]} + $TX}")
		tTX[$NIC]=$(echo "${tTX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
	done

	if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Traffic: ${tRX[*]} ${tTX[*]}" >> "$ScriptPath"/debug.log; fi
	
	# Port connections
	if [ -n "$ConnectionPorts" ]
	then
		netstat=$(ss -ntu | awk '{print $5}')
		for cPort in "${ConnectionPortsArray[@]}"
		do
			Connections[$cPort]=$(echo | awk "{print ${Connections[$cPort]} + $(echo "$netstat" | grep -c ":$cPort$")}")
		done
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Port Connections: ${Connections[*]}" >> "$ScriptPath"/debug.log; fi
	fi

	# Temperature
	if [ "$(find /sys/class/thermal/thermal_zone*/type 2> /dev/null | wc -l)" -gt 0 ]
	then
		TempArrayIndex=()
		TempArrayVal=()
		while IFS='' read -r line; do TempArrayIndex+=("$line"); done < <(cat /sys/class/thermal/thermal_zone*/type)
		while IFS='' read -r line; do TempArrayVal+=("$line"); done < <(cat /sys/class/thermal/thermal_zone*/temp)
		TempNameCnt=0
		for TempName in "${TempArrayIndex[@]}"
		do
				TempArray[$TempName]=$((${TempArray[$TempName]} + ${TempArrayVal[$TempNameCnt]}))
				TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
				TempNameCnt=$((TempNameCnt + 1))
		done
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Temperature thermal_zone: ${TempArray[*]}" >> "$ScriptPath"/debug.log; fi
	else
		if command -v "sensors" > /dev/null 2>&1
		then
			SensorsArray=()
			while IFS='' read -r line; do SensorsArray+=("$line"); done < <(sensors -A)
			for i in "${SensorsArray[@]}"
			do
				if [ -n "$i" ]
				then
					if [[ "$i" != *":"* ]] && [[ "$i" != *"="* ]]
					then
						SensorsCat="$i"
					else
						if [[ "$i" == *":"* ]] && [[ "$i" == *"°C"* ]]
						then
							TempName="$SensorsCat|"$(echo "$i" | awk -F"°C" '{print $1}' | awk -F":" '{print $1}' | sed 's/ /_/g' | xargs)
							TempVal=$(echo "$i" | awk -F"°C" '{print $1}' | awk -F":" '{print $2}' | sed 's/ //g' | awk '{printf "%18.3f",$1}' | sed -e 's/\.//g' | xargs)
							TempArray[$TempName]=$((${TempArray[$TempName]} + TempVal))
							TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
						fi
					fi
				fi
			done
			if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Temperature sensors: ${TempArray[*]}" >> "$ScriptPath"/debug.log; fi
		else
			if command -v "ipmitool" > /dev/null 2>&1
			then
				IPMIArray=()
				while IFS='' read -r line; do IPMIArray+=("$line"); done < <(timeout -s 9 3 ipmitool sdr type Temperature)
				for i in "${IPMIArray[@]}"
				do
					if [ -n "$i" ]
					then
						if [[ "$i" == *"degrees"* ]]
						then
							TempName=$(echo "$i" | awk -F"|" '{print $1}' | xargs | sed 's/ /_/g')
							TempVal=$(echo "$i" | awk -F"|" '{print $NF}' | awk -F"degrees" '{print $1}' | sed 's/ //g' | awk '{printf "%18.3f",$1}' | sed -e 's/\.//g' | xargs)
							TempArray[$TempName]=$((${TempArray[$TempName]} + TempVal))
							TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
						fi
					fi
				done
				if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Temperature ipmitool: ${TempArray[*]}" >> "$ScriptPath"/debug.log; fi
			fi
		fi
	fi
	
	# Check if minute changed, so we can end the loop
	MM=$(date +%M | sed 's/^0*//')
	if [ -z "$MM" ]
	then
		MM=0
	fi
	if [ "$MM" -ne "$M" ] 
	then
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Minute changed, ending loop" >> "$ScriptPath"/debug.log; fi
		break
	fi
done

# Get user running the agent
User=$(whoami)

# Check if system requires reboot
RequiresReboot=0
if [ -f  /var/run/reboot-required ]
then
	RequiresReboot=1
fi

# Operating System
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

 	# Check if system is CloudLinux release 8 (CL8 will only output "This system is receiving updates from CloudLinux Network server.")
  	if [[ "$OS" != "CloudLinux release 8."* ]]
	then
		# Check if system requires reboot (Only supported in CentOS/RHEL 7 and later, with yum-utils installed)
		if timeout -s 9 5 needs-restarting -r | grep -q 'Reboot is required'
		then
			RequiresReboot=1
		fi
  	fi
# If all else fails
else
	OS="$(uname -s)"
fi
OS=$(echo -ne "$OS" | base64 | tr -d '\n\r\t ')

# Kernel
Kernel=$(uname -r | base64 | tr -d '\n\r\t ')

# Hostname
Hostname=$(uname -n | base64 | tr -d '\n\r\t ')

# Server uptime
Uptime=$(awk '{print $1}' < /proc/uptime | awk '{printf "%18.0f",$1}' | xargs)

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) User: $User OS: $OS Kernel: $Kernel Hostname: $Hostname Uptime: $Uptime" >> "$ScriptPath"/debug.log; fi

# lscpu
lscpu=$(lscpu)

# CPU model
CPUModel=$(grep -m1 -E 'model name|cpu model' /proc/cpuinfo | awk -F": " '{print $NF}' | xargs)
if [ -z "$CPUModel" ]
then
	CPUModel=$(echo "$lscpu" | grep "^Model name:" | awk -F": " '{print $NF}' | xargs)
fi
CPUModel=$(echo -ne "$CPUModel" | base64 | tr -d '\n\r\t ')

# CPU sockets
CPUSockets=$(grep -i "physical id" /proc/cpuinfo | sort -u | wc -l)

# CPU cores
CPUCores=$(echo "$lscpu" | grep "^CPU(s):" | awk '{print $(NF)}' | xargs)

# CPU threads
CPUThreads=$(echo "$lscpu" | grep "^Thread(s) per core:" | awk '{print $(NF)}' | xargs)

# CPU clock speed
if [ -z "$tCPUSpeed" ] || [ "$tCPUSpeed" -eq 0 ]
then
	CPUSpeed=$(echo "$lscpu" | grep "^CPU max MHz" | awk '{print $NF}' | awk '{printf "%18.0f",$1}' | xargs)
else
	CPUSpeed=$(echo | awk "{print $tCPUSpeed / $CPUCores / $X}" | awk '{printf "%18.0f",$1}' | xargs)
fi

# Average CPU usage
CPU=$(echo | awk "{print $tCPU / $X}")

# Average CPU IO wait
CPUwa=$(echo | awk "{print $tCPUwa / $X}")

# Average CPU steal time
CPUst=$(echo | awk "{print $tCPUst / $X}")

# Average CPU user time
CPUus=$(echo | awk "{print $tCPUus / $X}")

# Average CPU system time
CPUsy=$(echo | awk "{print $tCPUsy / $X}")

# CPU Load
loadavg1=$(echo | awk "{print $tloadavg1 / $X}")
loadavg5=$(echo | awk "{print $tloadavg5 / $X}")
loadavg15=$(echo | awk "{print $tloadavg15 / $X}")

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) CPU Model: $CPUModel Sockets: $CPUSockets Cores: $CPUCores Threads: $CPUThreads Speed: $CPUSpeed CPU: $CPU IO wait: $CPUwa Steal time: $CPUst User time: $CPUus System time: $CPUsy Load: $loadavg1 $loadavg5 $loadavg15" >> "$ScriptPath"/debug.log; fi

# RAM size
RAMSize=$(grep ^MemTotal: /proc/meminfo | awk '{print $2}')

# RAM Usage
RAM=$(echo | awk "{print $tRAM / $X}")

# RAM swap size
RAMSwapSize=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')

# RAM swap usage
if [ "$RAMSwapSize" -gt 0 ]
then
	RAMSwap=$(echo | awk "{print $tRAMSwap / $X}")
else
	RAMSwap=0
fi

# RAM buffers usage
RAMBuff=$(echo | awk "{print $tRAMBuff / $X}")

# RAM cache usage
RAMCache=$(echo | awk "{print $tRAMCache / $X}")

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) RAM Size: $RAMSize Usage: $RAM Swap Size: $RAMSwapSize Usage: $RAMSwap Buffers: $RAMBuff Cache: $RAMCache" >> "$ScriptPath"/debug.log; fi

# Disks inodes
INODEs=$(echo -ne "$(timeout 3 df -Ti | sed 1d | grep -v -E 'tmpfs' | awk '{print $(NF)","$3","$4","$5";"}')" | tr -d '\n\r\t ' | base64 | tr -d '\n\r\t ')

# Disks IOPS
IOPS=""
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
	IOPSRead[$i]=$(echo | awk "{print $(echo | awk "{print $(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}') - ${IOPSRead[$i]}}" 2> /dev/null) * 512 / $tTIMEDIFF}" 2> /dev/null)
	IOPSRead[$i]=$(echo "${IOPSRead[$i]}" | awk '{printf "%18.0f",$1}' | xargs)
	IOPSWrite[$i]=$(echo | awk "{print $(echo | awk "{print $(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}') - ${IOPSWrite[$i]}}" 2> /dev/null) * 512 / $tTIMEDIFF}" 2> /dev/null)
	IOPSWrite[$i]=$(echo "${IOPSWrite[$i]}" | awk '{printf "%18.0f",$1}' | xargs)
	IOPS="$IOPS$i,${IOPSRead[$i]},${IOPSWrite[$i]};"
done
IOPS=$(echo -ne "$IOPS" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) lsblk: $(lsblk -l | base64 | tr -d '\n\r\t ') Disks: $DISKs Inodes: $INODEs IOPS: $IOPS" >> "$ScriptPath"/debug.log; fi

# Total network usage and IP addresses
RX=0
TX=0
NICS=""
IPv4=""
IPv6=""
for NIC in "${NetworkInterfacesArray[@]}"
do
	# Individual NIC network usage
	RX=$(echo | awk "{print ${tRX[$NIC]} / $X}")
	RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
	TX=$(echo | awk "{print ${tTX[$NIC]} / $X}")
	TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
	NICS="$NICS$NIC,$RX,$TX;"
	# Individual NIC IP addresses
	IPv4="$IPv4$NIC,$(ip -4 addr show "$NIC" | grep -oP 'inet \K[\d.]+' | xargs | sed 's/ /,/g');"
	IPv6="$IPv6$NIC,$(ip -6 addr show "$NIC" | grep -w "global" | grep -oP 'inet6 \K[0-9a-fA-F:]+' | xargs | sed 's/ /,/g');"
done
NICS=$(echo -ne "$NICS" | base64 | tr -d '\n\r\t ')
IPv4=$(echo -ne "$IPv4" | base64 | tr -d '\n\r\t ')
IPv6=$(echo -ne "$IPv6" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Interfaces: $NICS IPv4: $IPv4 IPv6: $IPv6" >> "$ScriptPath"/debug.log; fi

# Port connections
CONN=""
if [ -n "$ConnectionPorts" ]
then
	for cPort in "${ConnectionPortsArray[@]}"
	do
		CON=$(echo | awk "{print ${Connections[$cPort]} / $X}")
		CON=$(echo "$CON" | awk '{printf "%18.0f",$1}' | xargs)
		CONN="$CONN$cPort,$CON;"
	done
fi
CONN=$(echo -ne "$CONN" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Port Connections: $CONN" >> "$ScriptPath"/debug.log; fi

# Temperature
TEMP=""
if [ -n "$TempName" ]
then
	for TempName in "${!TempArray[@]}"
	do
		TMP=$(echo | awk "{print ${TempArray[$TempName]} / ${TempArrayCnt[$TempName]}}")
		TMP=$(echo "$TMP" | awk '{printf "%18.0f",$1}' | xargs)
		TEMP="$TEMP$TempName,$TMP;"
	done
fi
TEMP=$(echo -ne "$TEMP" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Temperature: $TEMP" >> "$ScriptPath"/debug.log; fi

# Check Services
SRVCS=""
if [ -n "$CheckServices" ]
then
	for i in "${CheckServicesArray[@]}"
	do
		SRVCSR[$i]=$(( ${SRVCSR[$i]} + $(servicestatus "$i") ))
		if [ "${SRVCSR[$i]}" -eq "0" ]
		then
			SRVCS="$SRVCS$i,0;"
		else
			SRVCS="$SRVCS$i,1;"
		fi
	done
fi
SRVCS=$(echo -ne "$SRVCS" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Services: $SRVCS" >> "$ScriptPath"/debug.log; fi

# Check Software RAID
RAID=""
ZP=""
dfPB1=$(timeout 3 df -PB1 2>/dev/null)
mdstat=$(cat /proc/mdstat 2>/dev/null)
declare -A zpooldiskusage
if [ "$CheckSoftRAID" -gt 0 ]
then
	for i in $(echo -ne "$dfPB1" | awk '$1 ~ /\// {print}' | awk '{print $1}')
	do
		mdadm=$(mdadm -D "$i" 2>/dev/null)
		# DEBUG
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) mdadm -D $i:\n$mdadm" >> "$ScriptPath"/debug.log; fi
		if [ -n "$mdadm" ]
		then
			mnt=$(echo -ne "$dfPB1" | grep "$i " | awk '{print $(NF)}')
			RAID="$RAID$mnt,$i,$mdadm;"
		fi
	done
	if [ -x "$(command -v zpool)" ]
	then
		zpoolsoverall=$(zpool status 2>/dev/null)
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) zpool status:\n$zpoolsoverall" >> "$ScriptPath"/debug.log; fi
		if ! grep -q "no pools available" <<< "$zpoolsoverall"
		then
			zpools=()
			while IFS= read -r line; do zpools+=("$line"); done < <(echo -ne "$zpoolsoverall"  2>/dev/null | grep "pool: " | awk '{print $2}')
			for i in "${zpools[@]}"
			do
				zpoolstatus=$(zpool status "$i" 2>/dev/null)
				zpoolstatus=$(echo -ne "$zpoolstatus" | base64 | tr -d '\n\r\t ')
				mnt=$(echo -ne "$dfPB1" | grep "$i " | awk '{print $(NF)}')
				ZP="$ZP$mnt,$i,$zpoolstatus;"
				zpooldiskusage[$mnt]=$(zfs get -H -o value -p used,avail "$i" | xargs | awk '{printf "%.0f %.0f %.0f", $1+$2, $1, $2}')
			done
		fi
	fi
fi
RAID=$(echo -ne "$RAID" | base64 | tr -d '\n\r\t ')
ZP=$(echo -ne "$ZP" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) RAID: $RAID ZP: $ZP" >> "$ScriptPath"/debug.log; fi

# Disks usage
DISKs=""
IFS=$'\n' read -d '' -r -a DISKsArray < <(timeout 3 df -TPB1 | sed 1d | grep -v -E 'tmpfs' | awk '{print $(NF)","$2","$3","$4","$5";"}')
for i in "${DISKsArray[@]}"; do
    IFS=',' read -r mount_point filesystem_type total_size used_size available_size <<< "$i"
	if [ -n "${zpooldiskusage[$mount_point]}" ]
	then
		IFS=' ' read -r zpool_total zpool_allocated zpool_free <<< "${zpooldiskusage[$mount_point]}"
		total_size=$zpool_total
		used_size=$zpool_allocated
		available_size=$zpool_free
	fi
	DISKs="$DISKs$mount_point,$filesystem_type,$total_size,$used_size,$available_size;"
done
DISKs=$(echo -ne "$DISKs" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) DISKs: $DISKs" >> "$ScriptPath"/debug.log; fi

# Check Drive Health
DH=""
if [ "$CheckDriveHealth" -gt 0 ]
then
	if [ -x "$(command -v smartctl)" ] #Using S.M.A.R.T. (for regular HDD/SSD)
	then
		for i in $(lsblk -lp | grep ' disk' | awk '{print $1}')
		do
			DHealth=$(smartctl -A "$i")
			if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) smartctl -A $i:\n$DHealth" >> "$ScriptPath"/debug.log; fi
			if grep -q 'Attribute' <<< "$DHealth"
			then
				DHealth=$(smartctl -H "$i")"\n$DHealth"
				DHealth=$(echo -ne "$DHealth" | base64 | tr -d '\n\r\t ')
				DInfo="$(smartctl -i "$i")"
				DModel="$(echo "$DInfo" | grep -i "Device Model:" | awk -F ':' '{print $2}' | xargs)"
				DSerial="$(echo "$DInfo" | grep -i "Serial Number:" | awk -F ':' '{print $2}' | xargs)"
				i=${i##*/}
				DH="$DH""1,$i,$DHealth,$DModel,$DSerial;"
			else # If initial read has failed, see if drives are behind hardware raid
				MegaRaid=()
				while IFS='' read -r line; do MegaRaid+=("$line"); done < <(smartctl --scan | grep megaraid | awk '{print $(3)}')
				if [ ${#MegaRaid[@]} -gt 0 ]
				then
					MegaRaidN=0
					for MegaRaidID in "${MegaRaid[@]}"
					do
						DHealth=$(smartctl -A -d "$MegaRaidID" "$i")
						if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) smartctl -A -d $MegaRaidID $i:\n$DHealth" >> "$ScriptPath"/debug.log; fi
						if grep -q 'Attribute' <<< "$DHealth"
						then
							MegaRaidN=$((MegaRaidN + 1))
							DHealth=$(smartctl -H -d "$MegaRaidID" "$i")"\n$DHealth"
							DHealth=$(echo -ne "$DHealth" | base64 | tr -d '\n\r\t ')
							DInfo="$(smartctl -i -d "$MegaRaidID" "$i")"
							DModel="$(echo "$DInfo" | grep -i "Device Model:" | awk -F ':' '{print $2}' | xargs)"
							DSerial="$(echo "$DInfo" | grep -i "Serial Number:" | awk -F ':' '{print $2}' | xargs)"
							ii=${i##*/}
							DH="$DH""1,${ii}[$MegaRaidN],$DHealth,$DModel,$DSerial;"
						fi
					done
					break
				fi
			fi
		done
	fi
	if [ -x "$(command -v nvme)" ] #Using nvme-cli (for NVMe)
	then
		NVMeList="$(nvme list)"
		if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) NVMe List:\n$NVMeList" >> "$ScriptPath"/debug.log; fi
		for i in $(lsblk -lp | grep ' disk' | awk '{print $1}')
		do
			DHealth=$(nvme smart-log "$i")
			if grep -q 'NVME' <<< "$DHealth"
			then
				if [ -x "$(command -v smartctl)" ]
				then
					ii=${i##*/}
					DHealth=$(smartctl -H /dev/"${ii%??}")"\n$DHealth"
				fi
				DHealth=$(echo -ne "$DHealth" | base64 | tr -d '\n\r\t ')
				DModel="$(echo "$NVMeList" | grep "$i" | sed -E 's/[ ]{2,}/|/g' | awk -F '|' '{print $3}')"
				DSerial="$(echo "$NVMeList" | grep "$i" | awk '{print $2}')"
				i=${i##*/}
				DH="$DH""2,$i,$DHealth,$DModel,$DSerial;"
			fi
		done
	fi
fi
DH=$(echo -ne "$DH" | base64 | tr -d '\n\r\t ')

if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) DH: $DH" >> "$ScriptPath"/debug.log; fi

# Custom Variables
CV=""
if [ -n "$CustomVars" ]
then
	if [ -s "$ScriptPath"/"$CustomVars" ]
	then
		CV=$(< "$ScriptPath"/"$CustomVars" base64 | tr -d '\n\r\t ')
	fi
fi

# Running Processes
RPS1=""
RPS2=""
if [ "$RunningProcesses" -gt 0 ]
then
	if [ -f "$ScriptPath"/running_proc.txt ]
	then
		# Get initial 'running processes' snapshot, saved from last run
		RPS1=$(cat "$ScriptPath"/running_proc.txt)
	fi
	# Get the current 'running processes' snapshot
	RPS2=$(ps -Ao pid,ppid,uid,user:20,pcpu,pmem,cputime,etime,comm,cmd --no-headers)
	RPS2=$(echo -ne "$RPS2" | base64 -w 0 | sed 's/ //g')
	# Save the current snapshot for next run
	echo "$RPS2" > "$ScriptPath"/running_proc.txt
fi
# Secured Connection
if [ "$SecuredConnection" -gt 0 ]
then
	SecuredConnection=""
else
	SecuredConnection="--no-check-certificate"
fi

# Current time/date
Time=$(date +%Y-%m-%d\ %T\ %Z | base64 | tr -d '\n\r\t ')

# Prepare data
json='{"version":"'"$Version"'","SID":"'"$SID"'","agent":"0","user":"'"$User"'","os":"'"$OS"'","kernel":"'"$Kernel"'","hostname":"'"$Hostname"'","time":"'"$Time"'","reqreboot":"'"$RequiresReboot"'","uptime":"'"$Uptime"'","cpumodel":"'"$CPUModel"'","cpusockets":"'"$CPUSockets"'","cpucores":"'"$CPUCores"'","cputhreads":"'"$CPUThreads"'","cpuspeed":"'"$CPUSpeed"'","cpu":"'"$CPU"'","wa":"'"$CPUwa"'","st":"'"$CPUst"'","us":"'"$CPUus"'","sy":"'"$CPUsy"'","load1":"'"$loadavg1"'","load5":"'"$loadavg5"'","load15":"'"$loadavg15"'","ramsize":"'"$RAMSize"'","ram":"'"$RAM"'","ramswapsize":"'"$RAMSwapSize"'","ramswap":"'"$RAMSwap"'","rambuff":"'"$RAMBuff"'","ramcache":"'"$RAMCache"'","disks":"'"$DISKs"'","inodes":"'"$INODEs"'","iops":"'"$IOPS"'","raid":"'"$RAID"'","zp":"'"$ZP"'","dh":"'"$DH"'","nics":"'"$NICS"'","ipv4":"'"$IPv4"'","ipv6":"'"$IPv6"'","conn":"'"$CONN"'","temp":"'"$TEMP"'","serv":"'"$SRVCS"'","cust":"'"$CV"'","rps1":"'"$RPS1"'","rps2":"'"$RPS2"'"}'

# Compress payload
jsoncomp=$(echo -ne "$json" | gzip -cf | base64 -w 0 | sed 's/ //g' | sed 's/\//%2F/g' | sed 's/+/%2B/g')

# Save data to file
echo "j=$jsoncomp" > "$ScriptPath"/hetrixtools_agent.log

if [ "$DEBUG" -eq 1 ]
then
	echo -e "$ScriptStartTime-$(date +%T]) JSON:\n$json" >> "$ScriptPath"/debug.log
	# Post data
	echo -e "$ScriptStartTime-$(date +%T]) Posting data" >> "$ScriptPath"/debug.log
	wget -v --debug --retry-connrefused --waitretry=1 -t 3 -T 15 -O- --post-file="$ScriptPath/hetrixtools_agent.log" $SecuredConnection https://sm.hetrixtools.net/v2/ &>> "$ScriptPath"/debug.log 
	echo -e "$ScriptStartTime-$(date +%T]) Data posted" >> "$ScriptPath"/debug.log
else
	# Post data
	wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --post-file="$ScriptPath/hetrixtools_agent.log" $SecuredConnection https://sm.hetrixtools.net/v2/ &> /dev/null
fi
