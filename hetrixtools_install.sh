#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Install Script
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

# Branch
BRANCH="master"

# Check if first argument is branch or SID
if [ ${#1} -ne 32 ]
then
	BRANCH=$1
	shift
fi

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
	then echo "ERROR: Please run the install script as root."
	exit 1
fi
echo "... done."

# Check if the selected branch exists
if wget --spider -q https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
then
	echo "Installing from $BRANCH branch..."
else
	echo "ERROR: Branch $BRANCH does not exist." >&2
	exit 1
fi

# Fetch Server Unique ID
SID=$1

# Make sure SID is not empty
echo "Checking Server ID (SID)..."
if [ -z "$SID" ]
	then echo "ERROR: First parameter missing."
	exit
fi
echo "... done."

# Check if user has selected to run agent as 'root' or as 'hetrixtools' user
if [ -z "$2" ]
	then echo "ERROR: Second parameter missing."
	exit
fi

# Check for wget and systemd/cron availability
echo "Checking system utilities..."
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
USE_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1; then
	if [ -d /run/systemd/system ]; then
		USE_SYSTEMD=1
	else
		if systemctl list-units >/dev/null 2>&1; then
			USE_SYSTEMD=1
		fi
	fi
fi
if [ "$USE_SYSTEMD" -ne 1 ]; then
	command -v crontab >/dev/null 2>&1 || { echo "ERROR: Crontab is required to run this agent when systemd is unavailable." >&2; exit 1; }
fi
echo "... done."

# Remove old agent (if exists)
echo "Checking if there's any old hetrixtools agent already installed..."
if [ -d /etc/hetrixtools ]
then
	echo "Old hetrixtools agent found, deleting it..."
	rm -rf /etc/hetrixtools
else
	echo "No old hetrixtools agent found..."
fi
echo "... done."

# Creating agent folder
echo "Creating the hetrixtools agent folder..."
mkdir -p /etc/hetrixtools
echo "... done."

# Fetching the agent
echo "Fetching the agent..."
wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools_agent.sh https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
echo "... done."

# Fetching the config file
echo "Fetching the config file..."
wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools.cfg https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools.cfg
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SID=\"\"/SID=\"$SID\"/" /etc/hetrixtools/hetrixtools.cfg
echo "... done."

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ "$3" != "0" ]
then
	echo "Services found, inserting them into the agent config..."
	sed -i "s/CheckServices=\"\"/CheckServices=\"$3\"/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if software RAID should be monitored
echo "Checking if software RAID should be monitored..."
if [ "$4" -eq "1" ]
then
	echo "Enabling software RAID monitoring in the agent config..."
	sed -i "s/CheckSoftRAID=0/CheckSoftRAID=1/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if Drive Health should be monitored
echo "Checking if Drive Health should be monitored..."
if [ "$5" -eq "1" ]
then
	echo "Enabling Drive Health monitoring in the agent config..."
	sed -i "s/CheckDriveHealth=0/CheckDriveHealth=1/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if 'View running processes' should be enabled
echo "Checking if 'View running processes' should be enabled..."
if [ "$6" -eq "1" ]
then
	echo "Enabling 'View running processes' in the agent config..."
	sed -i "s/RunningProcesses=0/RunningProcesses=1/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Check if any ports to monitor number of connections on
echo "Checking if any ports to monitor number of connections on..."
if [ "$7" != "0" ]
then
	echo "Ports found, inserting them into the agent config..."
	sed -i "s/ConnectionPorts=\"\"/ConnectionPorts=\"$7\"/" /etc/hetrixtools/hetrixtools.cfg
fi
echo "... done."

# Killing any running hetrixtools agents
echo "Making sure no hetrixtools agent scripts are currently running..."
ps aux | grep -ie hetrixtools_agent.sh | awk '{print $2}' | xargs -r kill -9
echo "... done."

# Checking if hetrixtools user exists
echo "Checking if hetrixtools user already exists..."
if id -u hetrixtools >/dev/null 2>&1
then
	echo "The hetrixtools user already exists, killing its processes..."
	pkill -9 -u `id -u hetrixtools`
	echo "Deleting hetrixtools user..."
	userdel hetrixtools
	echo "Creating the new hetrixtools user..."
	useradd hetrixtools -r -d /etc/hetrixtools -s /bin/false
	echo "Assigning permissions for the hetrixtools user..."
	chown -R hetrixtools:hetrixtools /etc/hetrixtools
	chmod -R 700 /etc/hetrixtools
else
	echo "The hetrixtools user doesn't exist, creating it now..."
	useradd hetrixtools -r -d /etc/hetrixtools -s /bin/false
	echo "Assigning permissions for the hetrixtools user..."
	chown -R hetrixtools:hetrixtools /etc/hetrixtools
	chmod -R 700 /etc/hetrixtools
fi
echo "... done."

# Removing old cronjob (if exists)
echo "Removing any old hetrixtools cronjob, if exists..."
if command -v crontab >/dev/null 2>&1
then
	crontab -u root -l 2>/dev/null | grep -v 'hetrixtools_agent.sh'  | crontab -u root - >/dev/null 2>&1
	crontab -u hetrixtools -l 2>/dev/null | grep -v 'hetrixtools_agent.sh'  | crontab -u hetrixtools - >/dev/null 2>&1
fi
echo "... done."

# Removing old systemd service/timer (if exists)
if [ "$USE_SYSTEMD" -eq 1 ]; then
	systemctl stop hetrixtools_agent.timer >/dev/null 2>&1
	systemctl disable hetrixtools_agent.timer >/dev/null 2>&1
	systemctl stop hetrixtools_agent.service >/dev/null 2>&1
	systemctl disable hetrixtools_agent.service >/dev/null 2>&1
	systemctl daemon-reload >/dev/null 2>&1
fi
rm -f /etc/systemd/system/hetrixtools_agent.timer >/dev/null 2>&1
rm -f /etc/systemd/system/hetrixtools_agent.service >/dev/null 2>&1

# Setup the new systemd or cronjob timer to run the agent every minute
if [ "$USE_SYSTEMD" -eq 1 ]
then
	echo "Setting up systemd timer..."
		if [ "$2" -eq "1" ]
		then
		SERVICE_USER=root
		else
		SERVICE_USER=hetrixtools
		fi
	cat > /etc/systemd/system/hetrixtools_agent.service <<EOF
[Unit]
Description=HetrixTools Agent

[Service]
Type=oneshot
User=$SERVICE_USER
ExecStart=/bin/bash /etc/hetrixtools/hetrixtools_agent.sh
EOF
	cat > /etc/systemd/system/hetrixtools_agent.timer <<EOF
[Unit]
Description=Runs HetrixTools agent every minute

[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
	systemctl daemon-reload >/dev/null 2>&1
	systemctl enable --now hetrixtools_agent.timer >/dev/null 2>&1
else
	# Default is running the agent as 'hetrixtools' user, unless chosen otherwise by the client when fetching the installation code from the hetrixtools website.
	if [ "$2" -eq "1" ]
	then
		echo "Setting up the new cronjob as 'root' user..."
		crontab -u root -l 2>/dev/null | { cat; echo "* * * * * bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1"; } | crontab -u root - >/dev/null 2>&1
	else
		echo "Setting up the new cronjob as 'hetrixtools' user..."
		crontab -u hetrixtools -l 2>/dev/null | { cat; echo "* * * * * bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1"; } | crontab -u hetrixtools - >/dev/null 2>&1
	fi
fi
echo "... done."

# Cleaning up install file
echo "Cleaning up the installation file..."
if [ -f $0 ]
then
	rm -f $0
fi
echo "... done."

# Let HetrixTools platform know install has been completed
echo "Letting HetrixTools platform know the installation has been completed..."
POST="v=install&s=$SID"
wget -t 1 -T 30 -qO- --post-data "$POST" https://sm.hetrixtools.net/ &> /dev/null
echo "... done."

# Start the agent
if [ "$2" -eq "1" ]
then
	echo "Starting the agent under the 'root' user..."
	bash /etc/hetrixtools/hetrixtools_agent.sh > /dev/null 2>&1 &
else
	echo "Starting the agent under the 'hetrixtools' user..."
	sudo -u hetrixtools bash /etc/hetrixtools/hetrixtools_agent.sh > /dev/null 2>&1 &
fi
echo "... done."

# All done
echo "HetrixTools agent installation completed."
