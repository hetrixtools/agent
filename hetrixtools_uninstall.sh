#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Uninstall Script
#	version 1.01
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

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "Please run the install script as root."
  exit
fi
echo "... done."

# Fetch Server Unique ID
SID=$1

# Make sure SID is not empty
echo "Checking Server ID (SID)..."
if [ -z "$SID" ]
	then echo "Please run the uninstaller with the 32 character code (SID) after it."
	exit
fi
echo "... done."

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

# Checking if hetrixtools user exists
echo "Checking if hetrixtool user exists..."
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

# Cleaning up uninstall file
echo "Cleaning up the installation file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."

# Let HetrixTools platform know uninstall has been completed
echo "Letting HetrixTools platform know the uninstallation has been completed..."
POST="v=uninstall&s=$SID"
wget -t 1 -T 30 -qO- --post-data "$POST" https://hetrixtools.com/s.php &> /dev/null
echo "... done."

# All done
echo "HetrixTools agent uninstallation completed."
