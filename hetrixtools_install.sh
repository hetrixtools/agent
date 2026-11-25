#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Install Script
#	Copyright 2015 - 2026 @  HetrixTools
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
umask 077

# Prefer IPv4 when fetching from GitHub, fallback to IPv6 if needed
github_wget() {
	local url=${!#}
	if ! wget -4 "$@"; then
		echo "IPv4 request failed for $url, retrying with IPv6..."
		if ! wget -6 "$@"; then
			echo "ERROR: Unable to fetch $url via IPv4 or IPv6." >&2
			return 1
		fi
	fi
	return 0
}

trim_config_value() {
	local value=$1

	value="${value#"${value%%[!$' \t\r\n']*}"}"
	value="${value%"${value##*[!$' \t\r\n']}"}"
	printf '%s' "$value"
}

normalize_connection_ports() {
	local raw_ports=$1
	local normalized_ports=""
	local port
	local port_number
	local ports_array

	IFS=',' read -r -a ports_array <<< "$raw_ports"
	for port in "${ports_array[@]}"
	do
		port=$(trim_config_value "$port")
		if [[ "$port" =~ ^[0-9]{1,5}$ ]]
		then
			port_number=$((10#$port))
			if [ "$port_number" -ge 1 ] && [ "$port_number" -le 65535 ]
			then
				if [ -n "$normalized_ports" ]
				then
					normalized_ports="$normalized_ports,"
				fi
				normalized_ports="$normalized_ports$port_number"
			fi
		fi
	done

	printf '%s' "$normalized_ports"
}

normalize_service_names() {
	local raw_services=$1
	local normalized_services=""
	local service_name
	local services_array

	IFS=',' read -r -a services_array <<< "$raw_services"
	for service_name in "${services_array[@]}"
	do
		service_name=$(trim_config_value "$service_name")
		if [[ "$service_name" =~ ^[A-Za-z0-9_.@:+-]+$ ]]
		then
			if [ -n "$normalized_services" ]
			then
				normalized_services="$normalized_services,"
			fi
			normalized_services="$normalized_services$service_name"
		fi
	done

	printf '%s' "$normalized_services"
}

# Branch
BRANCH="master"

# Check if first argument is branch or SID
if [ -n "$1" ] && [ ${#1} -ne 32 ]
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

apply_agent_permissions() {
	local run_user=$1

	if [ "$run_user" = "root" ]
	then
		chown -R root:root /etc/hetrixtools || return 1
	else
		chown -R hetrixtools:hetrixtools /etc/hetrixtools || return 1
	fi

	chmod 700 /etc/hetrixtools || return 1
	chmod 700 /etc/hetrixtools/hetrixtools_agent.sh || return 1
	chmod 600 /etc/hetrixtools/hetrixtools.cfg || return 1
}

create_agent_user() {
	if useradd hetrixtools -r -K SYS_UID_MAX=989 -K SYS_GID_MAX=989 -d /etc/hetrixtools -s /bin/false 2>/dev/null
	then
		return 0
	fi
	echo "Could not allocate a UID below 990, falling back to the system default range..."
	useradd hetrixtools -r -d /etc/hetrixtools -s /bin/false || return 1
}

# Fetch Server Unique ID
SID=$1

# Make sure SID is not empty
echo "Checking Server ID (SID)..."
if [ -z "$SID" ]
then
	echo "ERROR: Server ID (SID) parameter missing." >&2
	exit 1
fi
echo "... done."

# Check if user has selected to run agent as 'root' or as 'hetrixtools' user
if [ -z "$2" ]
then
	echo "ERROR: Second parameter missing, it must be 0 for 'hetrixtools' or 1 for 'root'." >&2
	exit 1
fi
case "$2" in
	1)
		RUN_USER=root
		;;
	0)
		RUN_USER=hetrixtools
		;;
	*)
		echo "ERROR: Second parameter must be 0 for 'hetrixtools' or 1 for 'root'." >&2
		exit 1
		;;
esac

# Check if the selected branch exists
if github_wget --spider -q https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
then
	echo "Installing from $BRANCH branch..."
else
	echo "ERROR: Branch $BRANCH does not exist." >&2
	exit 1
fi

# Check for wget and cron/systemd availability
echo "Checking system utilities..."
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
USE_CRON=0
USE_SYSTEMD=0
SYSTEMCTL_AVAILABLE=0
EXISTING_CRON=0
CRON_ACTIVE=0
if command -v systemctl >/dev/null 2>&1; then
	if [ -d /run/systemd/system ] || systemctl list-units >/dev/null 2>&1; then
		SYSTEMCTL_AVAILABLE=1
	fi
fi
if command -v crontab >/dev/null 2>&1; then
	if crontab -u root -l 2>/dev/null | grep -q 'hetrixtools_agent.sh'; then
		EXISTING_CRON=1
	elif id -u hetrixtools >/dev/null 2>&1 && crontab -u hetrixtools -l 2>/dev/null | grep -q 'hetrixtools_agent.sh'; then
		EXISTING_CRON=1
	fi
	CRON_ACTIVE=$EXISTING_CRON
	if command -v pgrep >/dev/null 2>&1 && [ "$CRON_ACTIVE" -ne 1 ]; then
		for cron_process in cron crond cronie systemd-cron fcron busybox-cron busybox-crond; do
			if pgrep -x "$cron_process" >/dev/null 2>&1 || pgrep -f "$cron_process" >/dev/null 2>&1; then
				CRON_ACTIVE=1
				break
			fi
		done
	fi
	if [ "$CRON_ACTIVE" -ne 1 ] && [ "$SYSTEMCTL_AVAILABLE" -eq 1 ]; then
		for cron_service in cron crond cronie systemd-cron fcron busybox-cron busybox-crond; do
			if systemctl is-active --quiet "$cron_service"; then
				CRON_ACTIVE=1
				break
			fi
		done
		if [ "$CRON_ACTIVE" -ne 1 ]; then
			if systemctl list-units --type=service --state=active 2>/dev/null | grep -Ei '\bcron(ie)?\b' >/dev/null 2>&1; then
				CRON_ACTIVE=1
			fi
		fi
	fi
	if [ "$CRON_ACTIVE" -ne 1 ] && [ "$SYSTEMCTL_AVAILABLE" -ne 1 ]; then
		CRON_ACTIVE=1
	fi
	if [ "$CRON_ACTIVE" -eq 1 ]; then
		USE_CRON=1
	fi
fi
if [ "$USE_CRON" -ne 1 ] && [ "$SYSTEMCTL_AVAILABLE" -eq 1 ] && command -v systemd-run >/dev/null 2>&1; then
	USE_SYSTEMD=1
fi
if [ "$USE_CRON" -ne 1 ] && [ "$USE_SYSTEMD" -ne 1 ]; then
	echo "ERROR: Neither cron nor systemd with systemd-run is available to schedule the agent." >&2
	exit 1
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
if ! github_wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools_agent.sh https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
then
	echo "ERROR: Failed to download the agent script from GitHub." >&2
	exit 1
fi
echo "... done."

# Fetching the config file
echo "Fetching the config file..."
if ! github_wget -t 1 -T 30 -qO /etc/hetrixtools/hetrixtools.cfg https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools.cfg
then
	echo "ERROR: Failed to download the agent configuration from GitHub." >&2
	exit 1
fi
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SID=\"\"/SID=\"$SID\"/" /etc/hetrixtools/hetrixtools.cfg
echo "... done."

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ "$3" != "0" ]
then
	InstallCheckServices=$(normalize_service_names "$3")
	if [ -n "$InstallCheckServices" ]
	then
		echo "Services found, inserting them into the agent config..."
		sed -i "s/CheckServices=\"\"/CheckServices=\"$InstallCheckServices\"/" /etc/hetrixtools/hetrixtools.cfg
	fi
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

# Check if reboot required should be checked
echo "Checking if reboot required should be checked..."
if [ "$8" = "0" ]
then
	echo "Disabling reboot required check in the agent config..."
	sed -i "s/CheckReboot=1/CheckReboot=0/" /etc/hetrixtools/hetrixtools.cfg
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
	InstallConnectionPorts=$(normalize_connection_ports "$7")
	if [ -n "$InstallConnectionPorts" ]
	then
		echo "Ports found, inserting them into the agent config..."
		sed -i "s/ConnectionPorts=\"\"/ConnectionPorts=\"$InstallConnectionPorts\"/" /etc/hetrixtools/hetrixtools.cfg
	fi
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
	echo "Deleting hetrixtools user..."
	userdel -f hetrixtools || exit 1
	echo "Creating the new hetrixtools user..."
	create_agent_user || exit 1
else
	echo "The hetrixtools user doesn't exist, creating it now..."
	create_agent_user || exit 1
fi
echo "Assigning permissions for the selected runtime user..."
if ! apply_agent_permissions "$RUN_USER"
then
	echo "ERROR: Failed to assign permissions for the agent files." >&2
	exit 1
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
if [ "$SYSTEMCTL_AVAILABLE" -eq 1 ]; then
	systemctl stop hetrixtools_agent.timer >/dev/null 2>&1
	systemctl disable hetrixtools_agent.timer >/dev/null 2>&1
	systemctl stop hetrixtools_agent.service >/dev/null 2>&1
	systemctl disable hetrixtools_agent.service >/dev/null 2>&1
	systemctl daemon-reload >/dev/null 2>&1
fi
rm -f /etc/systemd/system/hetrixtools_agent.timer >/dev/null 2>&1
rm -f /etc/systemd/system/hetrixtools_agent.service >/dev/null 2>&1
rm -f /etc/hetrixtools/hetrixtools_systemd_launcher.sh >/dev/null 2>&1
rm -f /usr/local/sbin/hetrixtools_systemd_launcher.sh >/dev/null 2>&1

# Setup the new systemd or cronjob timer to run the agent every minute
if [ "$USE_CRON" -eq 1 ]
then
	# Default is running the agent as 'hetrixtools' user, unless chosen otherwise by the client when fetching the installation code from the hetrixtools website.
	if [ "$RUN_USER" = "root" ]
	then
		echo "Setting up the new cronjob as 'root' user..."
		crontab -u root -l 2>/dev/null | { cat; echo "* * * * * bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1"; } | crontab -u root - >/dev/null 2>&1
	else
		echo "Setting up the new cronjob as 'hetrixtools' user..."
		crontab -u hetrixtools -l 2>/dev/null | { cat; echo "* * * * * bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1"; } | crontab -u hetrixtools - >/dev/null 2>&1
	fi
elif [ "$USE_SYSTEMD" -eq 1 ]
then
	echo "Setting up systemd timer..."
	SERVICE_USER=$RUN_USER
	cat > /usr/local/sbin/hetrixtools_systemd_launcher.sh <<-'EOF'
#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ServiceUser=$1
if [ "$ServiceUser" != "root" ] && [ "$ServiceUser" != "hetrixtools" ]
then
	ServiceUser=root
fi

if ! command -v systemd-run >/dev/null 2>&1
then
	echo "ERROR: systemd-run is required for systemd timer scheduling." >&2
	exit 1
fi

RunID=$(date +%s)-$$
UnitName="hetrixtools_agent_${RunID}"
AgentCommand='exec /bin/bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1'

if [ "$ServiceUser" = "root" ]
then
	systemd-run --quiet --collect --unit="$UnitName" /bin/bash -c "$AgentCommand"
else
	systemd-run --quiet --collect --unit="$UnitName" --property="User=$ServiceUser" /bin/bash -c "$AgentCommand"
fi
EOF
	chown root:root /usr/local/sbin/hetrixtools_systemd_launcher.sh >/dev/null 2>&1
	chmod 700 /usr/local/sbin/hetrixtools_systemd_launcher.sh
	cat > /etc/systemd/system/hetrixtools_agent.service <<-EOF
[Unit]
Description=HetrixTools Agent Launcher

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/sbin/hetrixtools_systemd_launcher.sh $SERVICE_USER
EOF
	cat > /etc/systemd/system/hetrixtools_agent.timer <<-EOF
[Unit]
Description=Runs HetrixTools agent every minute

[Timer]
OnBootSec=1min
OnCalendar=*-*-* *:*:00 UTC
OnCalendar=*-*-* *:*:00
OnUnitActiveSec=1min
AccuracySec=1s
RandomizedDelaySec=0
Persistent=true
Unit=hetrixtools_agent.service

[Install]
WantedBy=timers.target
EOF
	chmod 644 /etc/systemd/system/hetrixtools_agent.service /etc/systemd/system/hetrixtools_agent.timer
	systemctl daemon-reload >/dev/null 2>&1
	systemctl enable --now hetrixtools_agent.timer >/dev/null 2>&1
	systemctl restart hetrixtools_agent.timer >/dev/null 2>&1
else
	echo "ERROR: Unable to configure scheduling for the agent." >&2
	exit 1
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
if [ "$RUN_USER" = "root" ]
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
