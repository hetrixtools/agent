#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Uninstall Script
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

# Check if uninstall script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "ERROR: Please run the uninstall script as root."
  exit
fi
echo "... done."

# Fetch Server Unique ID
SID=$1

# Remove old agent (if exists)
echo "Checking if hetrixtools agent folder exists..."
if [ -d /etc/hetrixtools ]
then
	echo "Old hetrixtools agent found, deleting it..."
	rm -rf /etc/hetrixtools
else
	echo "No old hetrixtools agent folder found..."
fi
echo "... done."

# Killing any running hetrixtools agents
echo "Killing any hetrixtools agent scripts that may be currently running..."
ps aux | grep -ie hetrixtools_agent.sh | awk '{print $2}' | xargs -r kill -9
echo "... done."

# Checking if hetrixtools user exists
echo "Checking if hetrixtools user exists..."
if id -u hetrixtools >/dev/null 2>&1
then
	echo "The hetrixtools user exists, killing its processes..."
	pkill -9 -u `id -u hetrixtools`
	echo "Deleting hetrixtools user..."
	userdel hetrixtools
else
	echo "The hetrixtools user doesn't exist..."
fi
echo "... done."

# Removing cronjob (if exists)
echo "Removing any hetrixtools cronjob, if exists..."
crontab -u root -l | grep -v 'hetrixtools_agent.sh'  | crontab -u root - >/dev/null 2>&1
crontab -u hetrixtools -l | grep -v 'hetrixtools_agent.sh'  | crontab -u hetrixtools - >/dev/null 2>&1
echo "... done."

# Cleaning up uninstall file
echo "Cleaning up the uninstall file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# Let HetrixTools platform know uninstall has been completed
echo "Letting HetrixTools platform know the uninstallation has been completed..."
POST="v=uninstall&s=$SID"
wget -t 1 -T 30 -qO- --post-data "$POST" https://sm.hetrixtools.net/ &> /dev/null
echo "... done."

# All done
echo "HetrixTools agent uninstallation completed."

