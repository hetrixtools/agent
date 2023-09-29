#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Install Script
#	version 2.0.0
#	Copyright 2015 - 2023 @  HetrixTools
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
SID_length=32
SID_valid='^[0-9a-f]{'$SID_length'}$'
user=hetrixtools
dir=/etc/hetrixtools
agent=hetrixtools_agent.sh
agent_url=https://raw.githubusercontent.com/hetrixtools/agent/master/$agent
agent_path=$dir/$agent
fatal_help=1

help_show () {
	cat <<-EOHELP
		Usage: $0 [ -RrdP ] [ -s SERVICES ] [ -p PORTS ] SID

		Options:
		   -R   Agent should run as root instead of dedicated user ($user).
		   -r   Software RAID (mdadm) should be monitored.
		   -d   Drive health should be monitored.
		   -P   Running processes should display in the HetrixTools dashboard.
		   -s SERVICE1,SERVICE2,...
		        A comma-separated list of up to 10 systemd service names to monitor.
		   -p PORT1,PORT2,...
		        A comma-separated list of up to 10 port numbers to monitor connections.
		   -h   This help.
		EOHELP
}
fatal () {
	echo
	echo "ERROR: $*" >&2
	if (( fatal_help )); then
		echo >&2
		help_show >&2
	fi
	exit 1
}

# Defaults
help=0
root=0
services=
raid=0
drive=0
processes=0
ports=
while getopts ':hRs:rdPp:' opt; do
	case $opt in
		h)
			help=1
			;;
		R)
			root=1
			;;
		s)
			services="$OPTARG"
			;;
		r)
			raid=1
			;;
		d)
			drive=1
			;;
		P)
			processes=1
			;;
		p)
			ports="$OPTARG"
			;;
		:)
			# missing argument
			case $OPTARG in
				s)
					fatal -$OPTARG option requires a comma-separated list of services as its argument.
					;;
				p)
					fatal -$OPTARG option requires a comma-separated list of port numbers as its argument.
					;;
				*)
					# An option in the getopts string above has a colon after it, so expects an argument.
					# The argument's contents needs to be documented or maybe it's not meant to have the colon.
					fatal Script error in option -$OPTARG.
					;;
			esac
			;;
		*)
			fatal Unknown option "-$OPTARG".
			;;
	esac
done
shift $(( OPTIND - 1 ))

if (( help )); then
	help_show
	exit
fi

# Check if install script is run by root
echo -n Checking root privileges...
if (( EUID )); then
	: #fatal Please run the install script as root.
fi
echo ' yes.'

# Make sure SID is not empty
echo -n 'Checking server ID (SID)...'
if ! (( $# )); then
	fatal SID missing.
else
	SID="${1@L}" # lowercase it
	shift
	if ! [[ "$SID" =~ $SID_valid ]]; then
		fatal "Invalid SID, expected $SID_length hexadecimal characters: $SID"
	fi
fi
echo ' ok.'

if (( $# )); then
	fatal "Unexpected arguments after options & SID: $@"
fi

fatal_help=0

# Check if system has crontab and wget
echo -n Checking for crontab and wget...
command -v crontab &> /dev/null || fatal crontab is required to run this agent.
command -v wget &> /dev/null || fatal wget is required to run this agent.
echo ' yes.'

# Remove old agent (if exists)
echo -n "Checking if there's any hetrixtools agent already installed..."
if [ -d $dir ]; then
	echo -n ' yes, deleting it...'
	rm -rf $dir || fatal Could not remove old agent.
	echo ' done.'
else
	echo ' no.'
fi

# Creating agent folder
echo -n Creating the hetrixtools agent folder...
mkdir -p $dir || fatal Could not create folder.
echo ' done.'

# Fetching new agent
#
echo -n Fetching the new agent...
wget -t 1 -T 30 -qO $agent_path $agent_url || fatal Could not fetch agent.
echo ' done.'

# Inserting Server ID (SID) into the agent config
echo -n "Inserting SID '$SID' into agent config..."
sed -i "s/SIDPLACEHOLDER/$SID/" $agent_path || fatal Could not insert SID.
echo ' done.'

# Check if any services are to be monitored
echo -n Checking if any services should be monitored...
if [[ "$services" ]]; then
	echo ' yes.'
	echo -n "Inserting services to monitor '$services' into the agent config..."
	sed -Ei 's/(CheckServices=")(")/\1'"$services"'\2/' $agent_path || fatal Could not insert services.
	echo ' done.'
else
	echo ' no.'
fi

# Check if software RAID should be monitored
echo -n Checking if software RAID should be monitored...
if (( raid )); then
	echo ' yes.'
	echo -n Enabling software RAID monitoring in the agent config...
	sed -Ei 's/(CheckSoftRAID=)0/\11/' $agent_path || fatal Could not enable RAID monitoring.
	echo ' done.'
else
	echo ' no.'
fi

# Check if Drive Health should be monitored
echo -n Checking if drive health should be monitored...
if (( drive )); then
	echo ' yes.'
	echo -n Enabling drive health monitoring in the agent config...
	sed -Ei 's/(CheckDriveHealth=)0/\11/' $agent_path || fatal Could not enable drive health monitoring.
	echo ' done.'
else
	echo ' no.'
fi

# Check if 'View running processes' should be enabled
echo -n Checking if viewing of running processes should be enabled...
if (( processes )); then
	echo ' yes.'
	echo -n Enabling viewing of running processes in the agent config...
	sed -Ei 's/(RunningProcesses=)0/\11/' $agent_path || fatal Could not enable viewing processes.
	echo ' done.'
else
	echo ' no.'
fi

# Check if any ports to monitor number of connections on
echo -n Checking if any ports to monitor number of connections on...
if [[ "$ports" ]]; then
	echo ' yes.'
	echo -n "Inserting ports to monitor '$ports' into the agent config..."
	sed -Ei 's/(ConnectionPorts=")(")/\1'"$ports"'\2/' $agent_path || fatal Could not insert ports.
	echo ' done.'
else
	echo ' no.'
fi

cron_users=()
# Checking if hetrixtools user exists
echo -n Checking if hetrixtools user already exists...
if id -u $user &> /dev/null; then
	cron_users+=($user)
	user_exists=1
	echo ' yes.'
else
	user_exists=0
	echo ' no.'
fi
cron_users+=(root)

# Removing old cronjob (if exists)
echo -n Removing old hetrixtools cronjob, if exists...
for cron_user in ${cron_users[@]}; do
	crontab -u $cron_user -l 2> /dev/null | grep -vF $agent | crontab -u $cron_user - &> /dev/null
done
echo ' done.'

# Killing any running hetrixtools agents
echo -n Making sure no hetrixtools agent scripts are currently running...
pkill -9 -f $agent_path # can't differentiate failure from no processes
echo ' done.'

# Removing old hetrixtools user
if (( user_exists )); then
	echo -n The hetrixtools user already exists, killing its processes...
	pkill -9 -u $user # can't differentiate failure from no processes
	echo ' done.'
	echo -n Deleting hetrixtools user...
	userdel $user || fatal Could not delete user.
	echo ' done.'
fi

# Create new hetrixtools user only if needed
if ! (( root )); then
	if (( user_exists )); then
		echo -n Recreating the hetrixtools user...
	else
		echo -n "The hetrixtools user doesn't exist, creating it now..."
	fi
	useradd $user -r -d $dir -s /bin/false || fatal Could not add user.
	echo ' done.'
	echo -n Assigning permissions for the hetrixtools user...
	chown -R $user: $dir && chmod -R 700 $dir || fatal Could not set permissions.
	echo ' done.'
fi

# Setup the new cronjob to run the agent either as 'root' or as 'hetrixtools' user, depending on client's installation choice.
# Default is running the agent as 'hetrixtools' user, unless chosen otherwise by the client when fetching the installation code from the hetrixtools website.
if (( root )); then
	cron_user=root
	sudo=
else
	cron_user=$user
	sudo="sudo -u $user"
fi
echo -n "Setting up the new cronjob as '$cron_user' user..."
crontab -u $cron_user -l 2> /dev/null \
	| { cat; echo "*	*	*	*	*	bash $agent_path >> $dir/hetrixtools_cron.log 2>&1"; } \
	| crontab -u $cron_user - &> /dev/null
echo ' done.'

# Let HetrixTools platform know install has been completed
echo -n Letting HetrixTools platform know the installation has been completed...
if wget -t 1 -T 30 -qO- --post-data "v=install&s=$SID" https://sm.hetrixtools.net/ &> /dev/null; then
	echo ' done.'
else
	echo ' failed.'
fi

# Start the agent
echo -n "Starting the agent under the '$cron_user' user..."
$sudo bash /etc/hetrixtools/hetrixtools_agent.sh &> /dev/null &
echo ' done.'

# Cleaning up install file
if [[ -f "$0" ]]; then
	echo -n Cleaning up the installation file...
	if rm -f "$0"; then
		echo ' done.'
	else
		echo ' failed.'
	fi
fi

# All done
echo HetrixTools agent installation completed.
