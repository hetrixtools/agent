#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Update Script
#	version 1.5.7
#	Copyright 2015 - 2019 @  HetrixTools
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

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Old Agent Path
AGENT="/etc/hetrixtools/hetrixtools_agent.sh"

# Check if user specified version to update to
if [ -z "$1" ]
then
	VERS="master"
else
	VERS=$1
fi

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "ERROR: Please run the install script as root."
  exit
fi
echo "... done."

# Check if system has crontab and wget
echo "Checking for crontab and wget..."
command -v crontab >/dev/null 2>&1 || { echo "ERROR: Crontab is required to run this agent." >&2; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
echo "... done."

# Look for the old agent
echo "Looking for the old agent..."
if [ -f "$AGENT" ]
then
	echo "... done."
else
	echo "ERROR: No old agent found. Nothing to update." >&2; exit 1;
fi

# Extract data from the old agent
echo "Extracting configs from the old agent..."
# SID (Server ID)
SID=$(grep 'SID="' $AGENT | awk -F'"' '{ print $2 }')
# Check Services
CheckServices=$(grep 'CheckServices="' $AGENT | awk -F'"' '{ print $2 }')
# Check Software RAID Health
CheckSoftRAID=$(grep 'CheckSoftRAID=' $AGENT | awk -F'=' '{ print $2 }')
# Check Drive Health
CheckDriveHealth=$(grep 'CheckDriveHealth=' $AGENT | awk -F'=' '{ print $2 }')
# RunningProcesses
RunningProcesses=$(grep 'RunningProcesses=' $AGENT | awk -F'=' '{ print $2 }')
if [ -z "$RunningProcesses" ]
then
	RunningProcesses=0
fi
echo "... done."

# Fetching new agent
echo "Fetching the new agent..."
wget -t 1 -T 30 -qO $AGENT --no-check-certificate https://raw.github.com/hetrixtools/agent/$VERS/hetrixtools_agent.sh
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SIDPLACEHOLDER/$SID/" $AGENT
echo "... done."

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ ! -z "$CheckServices" ]
then
	echo "Services found, inserting them into the agent config..."
	sed -i "s/CheckServices=\"\"/CheckServices=\"$CheckServices\"/" $AGENT
fi
echo "... done."

# Check if Software RAID should be monitored
echo "Checking if software RAID should be monitored..."
if [ "$CheckSoftRAID" -eq "1" ]
then
	echo "Enabling software RAID monitoring in the agent config..."
	sed -i "s/CheckSoftRAID=0/CheckSoftRAID=1/" $AGENT
fi
echo "... done."

# Check if Drive Health should be monitored
echo "Checking if Drive Health should be monitored..."
if [ "$CheckDriveHealth" -eq "1" ]
then
	echo "Enabling Drive Health monitoring in the agent config..."
	sed -i "s/CheckDriveHealth=0/CheckDriveHealth=1/" $AGENT
fi
echo "... done."

# Check if 'View running processes' should be enabled
echo "Checking if 'View running processes' should be enabled..."
if [ "$RunningProcesses" -eq "1" ]
then
	echo "Enabling 'View running processes' in the agent config..."
	sed -i "s/RunningProcesses=0/RunningProcesses=1/" $AGENT
fi
echo "... done."

# Killing any running hetrixtools agents
echo "Making sure no hetrixtools agent scripts are currently running..."
ps aux | grep -ie hetrixtools_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Assign permissions
echo "Assigning permissions for the hetrixtools user..."
if id -u hetrixtools >/dev/null 2>&1
then
	chown -R hetrixtools:hetrixtools /etc/hetrixtools
	chmod -R 700 /etc/hetrixtools
fi

# Cleaning up install file
echo "Cleaning up the update file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# All done
echo "HetrixTools agent update completed. It can take up to two (2) minutes for new data to be collected."
