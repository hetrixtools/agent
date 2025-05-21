#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Update Script
#	Copyright 2015 - 2025 @  HetrixTools
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

# Old Config Path
CONFIG="/etc/hetrixtools/hetrixtools.cfg"

# Check if user specified branch to update to
if [ -z "$1" ]
then
	BRANCH="master"
else
	BRANCH=$1
fi

# Check if the selected branch exists
if wget --spider -q https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
then
	echo "Updating to $BRANCH branch..."
else
	echo "ERROR: Branch $BRANCH does not exist." >&2
	exit 1
fi
# Check if update script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "ERROR: Please run the update script as root."
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

# Look for the old config
echo "Looking for the old config file..."
if [ -f "$CONFIG" ]
then
	echo "... done."
	echo "Upgrading from v2..."
	EXTRACT=$CONFIG
else
	echo "... done."
	echo "Upgrading from v1..."
	EXTRACT=$AGENT
fi

# Extract data from the old agent
echo "Extracting configs from the old agent..."
# SID (Server ID)
SID=$(grep 'SID="' $EXTRACT | awk -F'"' '{ print $2 }')
# Network Interfaces
NetworkInterfaces=$(grep 'NetworkInterfaces="' $EXTRACT | awk -F'"' '{ print $2 }')
# Check Services
CheckServices=$(grep 'CheckServices="' $EXTRACT | awk -F'"' '{ print $2 }')
# Check Software RAID Health
CheckSoftRAID=$(grep 'CheckSoftRAID=' $EXTRACT | awk -F'=' '{ print $2 }')
# Check Drive Health
CheckDriveHealth=$(grep 'CheckDriveHealth=' $EXTRACT | awk -F'=' '{ print $2 }')
# RunningProcesses
RunningProcesses=$(grep 'RunningProcesses=' $EXTRACT | awk -F'=' '{ print $2 }')
if [ -z "$RunningProcesses" ]
then
	RunningProcesses=0
fi
echo "... done."
# Port Connections
ConnectionPorts=$(grep 'ConnectionPorts="' $EXTRACT | awk -F'"' '{ print $2 }')
if [ -f "$CONFIG" ]
then
	# Custom Variables
	CustomVars=$(grep 'CustomVars="' $EXTRACT | awk -F'"' '{ print $2 }')
	# Secured Connection
	SecuredConnection=$(grep 'SecuredConnection=' $EXTRACT | awk -F'=' '{ print $2 }')
	# CollectEveryXSeconds
	CollectEveryXSeconds=$(grep 'CollectEveryXSeconds=' $EXTRACT | awk -F'=' '{ print $2 }')
	# OutgoingPings
	OutgoingPings=$(grep 'OutgoingPings="' $EXTRACT | awk -F'"' '{ print $2 }')
	# OutgoingPingsCount
	OutgoingPingsCount=$(grep 'OutgoingPingsCount=' $EXTRACT | awk -F'=' '{ print $2 }')
fi

# Fetching the new agent
echo "Fetching the new agent..."
wget -t 1 -T 30 -qO $AGENT https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
echo "... done."

# Fetching the new config file
echo "Fetching the new config file..."
wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools.cfg https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools.cfg
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SID=\"\"/SID=\"$SID\"/" /etc/hetrixtools/hetrixtools.cfg
echo "... done."

# Check if any network interfaces are specified
echo "Checking if any network interfaces are specified..."
if [ ! -z "$NetworkInterfaces" ]
then
	echo "Network interfaces found, inserting them into the agent config..."
	sed -i "s/NetworkInterfaces=\"\"/NetworkInterfaces=\"$NetworkInterfaces\"/" /etc/hetrixtools/hetrixtools.cfg
fi

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ ! -z "$CheckServices" ]
then
	echo "Services found, inserting them into the agent config..."
	sed -i "s/CheckServices=\"\"/CheckServices=\"$CheckServices\"/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if Software RAID should be monitored
echo "Checking if software RAID should be monitored..."
if [ "$CheckSoftRAID" -eq "1" ]
then
	echo "Enabling software RAID monitoring in the agent config..."
	sed -i "s/CheckSoftRAID=0/CheckSoftRAID=1/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if Drive Health should be monitored
echo "Checking if Drive Health should be monitored..."
if [ "$CheckDriveHealth" -eq "1" ]
then
	echo "Enabling Drive Health monitoring in the agent config..."
	sed -i "s/CheckDriveHealth=0/CheckDriveHealth=1/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if 'View running processes' should be enabled
echo "Checking if 'View running processes' should be enabled..."
if [ "$RunningProcesses" -eq "1" ]
then
	echo "Enabling 'View running processes' in the agent config..."
	sed -i "s/RunningProcesses=0/RunningProcesses=1/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if any ports to monitor number of connections on
echo "Checking if any ports to monitor number of connections on..."
if [ ! -z "$ConnectionPorts" ]
then
	echo "Ports found, inserting them into the agent config..."
	sed -i "s/ConnectionPorts=\"\"/ConnectionPorts=\"$ConnectionPorts\"/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if any custom variables are specified
echo "Checking if any custom variables are specified..."
if [ ! -z "$CustomVars" ]
then
    echo "Custom variables found, inserting them into the agent config..."
    sed -i "s/CustomVars=\"custom_variables.json\"/CustomVars=\"$CustomVars\"/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if secured connection is enabled
echo "Checking if secured connection is enabled..."
if [ ! -z "$SecuredConnection" ]
then
    echo "Inserting secured connection in the agent config..."
    sed -i "s/SecuredConnection=1/SecuredConnection=$SecuredConnection/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check CollectEveryXSeconds
echo "Checking CollectEveryXSeconds..."
if [ ! -z "$CollectEveryXSeconds" ]
then
	echo "Inserting CollectEveryXSeconds in the agent config..."
	sed -i "s/CollectEveryXSeconds=3/CollectEveryXSeconds=$CollectEveryXSeconds/" /etc/hetrixtools/hetrixtools.cfg
fi

# Check OutgoingPings
echo "Checking OutgoingPings..."
if [ ! -z "$OutgoingPings" ]
then
	echo "Inserting OutgoingPings in the agent config..."
	sed -i "s/OutgoingPings=\"\"/OutgoingPings=\"$OutgoingPings\"/" /etc/hetrixtools/hetrixtools.cfg
fi

# Check OutgoingPingsCount
echo "Checking OutgoingPingsCount..."
if [ ! -z "$OutgoingPingsCount" ]
then
	echo "Inserting OutgoingPingsCount in the agent config..."
	sed -i "s/OutgoingPingsCount=20/OutgoingPingsCount=$OutgoingPingsCount/" /etc/hetrixtools/hetrixtools.cfg
fi

# Killing any running hetrixtools agents
echo "Making sure no hetrixtools agent scripts are currently running..."
ps aux | grep -ie hetrixtools_agent.sh | awk '{print $2}' | xargs -r kill -9
echo "... done."

# Assign permissions
echo "Assigning permissions for the hetrixtools user..."
if id -u hetrixtools >/dev/null 2>&1
then
	chown -R hetrixtools:hetrixtools /etc/hetrixtools
	chmod -R 700 /etc/hetrixtools
fi

# Cleaning up update file
echo "Cleaning up the update file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# All done
echo "HetrixTools agent update completed. It can take up to two (2) minutes for new data to be collected."

