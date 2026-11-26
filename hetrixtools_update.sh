#!/bin/bash
#
#
#	HetrixTools Server Monitoring Agent - Update Script
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

normalize_collect_interval() {
	local collect_interval

	collect_interval=$(printf '%s' "$1" | tr -d '[:space:]')
	if ! [[ "$collect_interval" =~ ^[0-9]{1,2}$ ]] || [ "$collect_interval" -lt 1 ] || [ "$collect_interval" -gt 60 ]
	then
		collect_interval=3
	fi

	printf '%s' "$collect_interval"
}

normalize_secured_connection() {
	local secured_connection

	secured_connection=$(printf '%s' "$1" | tr -d '[:space:]')
	if ! [[ "$secured_connection" =~ ^[01]$ ]]
	then
		secured_connection=1
	fi

	printf '%s' "$secured_connection"
}

# Detect whether the currently installed agent is configured to run as
# 'root' or as the 'hetrixtools' user, using the existing cron/systemd setup.
# As a last resort (non-standard schedulers we can't read, e.g. /etc/cron.d,
# /etc/crontab, relocated systemd units), fall back to the owner of the
# /etc/hetrixtools directory, which the install/update scripts always chown
# to the user the agent runs as.
detect_agent_run_user() {
	local detected_user=""
	local systemd_unit=""
	local dir_owner=""

	if command -v crontab >/dev/null 2>&1; then
		if crontab -u root -l 2>/dev/null | grep -q 'hetrixtools_agent.sh'; then
			detected_user=root
		elif id -u hetrixtools >/dev/null 2>&1 && crontab -u hetrixtools -l 2>/dev/null | grep -q 'hetrixtools_agent.sh'; then
			detected_user=hetrixtools
		fi
	fi

	if [ -z "$detected_user" ]; then
		for systemd_unit in \
			/etc/systemd/system/hetrixtools_agent.service \
			/lib/systemd/system/hetrixtools_agent.service \
			/usr/lib/systemd/system/hetrixtools_agent.service
		do
			if [ -f "$systemd_unit" ]; then
				detected_user=$(awk -F= '/^User=/{print $2; exit}' "$systemd_unit" 2>/dev/null)
				if [ -z "$detected_user" ]; then
					detected_user=$(awk '/hetrixtools_systemd_launcher\.sh/ {print $NF; exit}' "$systemd_unit" 2>/dev/null)
				fi
				break
			fi
		done
	fi

	if [ "$detected_user" != "root" ] && [ "$detected_user" != "hetrixtools" ]; then
		dir_owner=$(stat -c '%U' /etc/hetrixtools 2>/dev/null || stat -f '%Su' /etc/hetrixtools 2>/dev/null)
		if [ "$dir_owner" = "root" ] || [ "$dir_owner" = "hetrixtools" ]; then
			detected_user=$dir_owner
		else
			detected_user=unknown
		fi
	fi

	echo "$detected_user"
}

# Old Agent Path
AGENT="/etc/hetrixtools/hetrixtools_agent.sh"

# Old Config Path
CONFIG="/etc/hetrixtools/hetrixtools.cfg"

BRANCH="master"
BRANCH_SET=0
FORCE_UPDATE=0

# Parse arguments
for ARG in "$@"
do
	case "$ARG" in
		-force|--force)
			FORCE_UPDATE=1
			;;
		-h|--help)
			echo "Usage: $0 [-force|--force] [branch]"
			exit 0
			;;
		-*)
			echo "ERROR: Unknown option: $ARG" >&2
			echo "Usage: $0 [-force|--force] [branch]" >&2
			exit 1
			;;
		*)
			if [ "$BRANCH_SET" -eq 1 ]
			then
				echo "ERROR: Multiple branches specified." >&2
				echo "Usage: $0 [-force|--force] [branch]" >&2
				exit 1
			fi
			BRANCH=$ARG
			BRANCH_SET=1
			;;
	esac
done

extract_agent_version() {
	sed -n "s/^[[:space:]]*Version[[:space:]]*=[[:space:]]*['\"]\\{0,1\\}\\([^'\"[:space:]#]*\\).*/\\1/p" "$1" 2>/dev/null | head -n 1
}

cleanup_update_tmp_dir() {
	if [ -n "$UPDATE_TMP_DIR" ] && [ -d "$UPDATE_TMP_DIR" ]
	then
		rm -rf "$UPDATE_TMP_DIR"
	fi
	if [ -n "$STAGED_AGENT" ] && [ -f "$STAGED_AGENT" ]
	then
		rm -f "$STAGED_AGENT"
	fi
	if [ -n "$STAGED_CONFIG" ] && [ -f "$STAGED_CONFIG" ]
	then
		rm -f "$STAGED_CONFIG"
	fi
	if [ -n "$STAGED_CONFIG" ] && [ -f "$STAGED_CONFIG.tmp" ]
	then
		rm -f "$STAGED_CONFIG.tmp"
	fi
}

copy_file_metadata() {
	local reference_file=$1
	local target_file=$2
	local file_owner=""
	local file_mode=""

	if [ ! -e "$reference_file" ]
	then
		return 0
	fi

	if ! chown --reference="$reference_file" "$target_file" >/dev/null 2>&1
	then
		file_owner=$(stat -c '%u:%g' "$reference_file" 2>/dev/null)
		if [ -n "$file_owner" ]
		then
			chown "$file_owner" "$target_file" >/dev/null 2>&1 || return 1
		fi
	fi

	if ! chmod --reference="$reference_file" "$target_file" >/dev/null 2>&1
	then
		file_mode=$(stat -c '%a' "$reference_file" 2>/dev/null)
		if [ -n "$file_mode" ]
		then
			chmod "$file_mode" "$target_file" >/dev/null 2>&1 || return 1
		fi
	fi
}

apply_agent_file_permissions() {
	local run_user=$1
	local target_file=$2
	local file_mode=$3

	if [ -z "$file_mode" ]
	then
		file_mode=700
	fi

	if [ "$run_user" = "root" ] || ! id -u hetrixtools >/dev/null 2>&1
	then
		chown root:root "$target_file" >/dev/null 2>&1 || return 1
	else
		chown hetrixtools:hetrixtools "$target_file" >/dev/null 2>&1 || return 1
	fi
	chmod "$file_mode" "$target_file" >/dev/null 2>&1 || return 1
}

custom_vars_file_path() {
	local custom_vars=""
	local base_dir=""
	local custom_vars_path=""
	local real_dir=""
	local real_file=""

	custom_vars=$(extract_config_value 'CustomVars' "$CONFIG" 2>/dev/null)
	if [ -z "$custom_vars" ]
	then
		return 1
	fi

	case "$custom_vars" in
		''|/*)
			return 1
			;;
	esac

	base_dir=$(cd -P -- /etc/hetrixtools 2>/dev/null && pwd) || return 1
	custom_vars_path="$base_dir/$custom_vars"

	if [ -L "$custom_vars_path" ] || [ ! -f "$custom_vars_path" ]
	then
		return 1
	fi

	real_dir=$(cd -P -- "$(dirname -- "$custom_vars_path")" 2>/dev/null && pwd) || return 1
	real_file="$real_dir/$(basename -- "$custom_vars_path")"
	case "$real_file" in
		"$base_dir"/*)
			printf '%s\n' "$real_file"
			;;
		*)
			return 1
			;;
	esac
}

apply_custom_vars_permissions() {
	local run_user=$1
	local custom_vars_path=""

	if [ "$run_user" != "hetrixtools" ] || ! id -u hetrixtools >/dev/null 2>&1
	then
		return 0
	fi

	custom_vars_path=$(custom_vars_file_path) || return 0
	chown hetrixtools:hetrixtools "$custom_vars_path" >/dev/null 2>&1 || return 1
	chmod 600 "$custom_vars_path" >/dev/null 2>&1 || return 1
}

apply_agent_permissions() {
	local run_user=$1

	if [ "$run_user" = "root" ] || ! id -u hetrixtools >/dev/null 2>&1
	then
		chown -R root:root /etc/hetrixtools >/dev/null 2>&1 || return 1
	else
		chown -R hetrixtools:hetrixtools /etc/hetrixtools >/dev/null 2>&1 || return 1
	fi
	chmod 700 /etc/hetrixtools >/dev/null 2>&1 || return 1
	apply_agent_file_permissions "$run_user" "$AGENT" 700 || return 1
	apply_agent_file_permissions "$run_user" "$CONFIG" 600 || return 1
	apply_custom_vars_permissions "$run_user" || return 1
}

prepare_staged_file() {
	local source_file=$1
	local target_file=$2
	local staged_file=$3
	local file_mode=700

	if [ "$target_file" = "$CONFIG" ]
	then
		file_mode=600
	fi

	if ! cp "$source_file" "$staged_file"
	then
		return 1
	fi

	if [ -n "$AGENT_RUNTIME_USER" ]
	then
		apply_agent_file_permissions "$AGENT_RUNTIME_USER" "$staged_file" "$file_mode" || return 1
	elif id -u hetrixtools >/dev/null 2>&1
	then
		apply_agent_file_permissions hetrixtools "$staged_file" "$file_mode" || return 1
	elif [ -e "$target_file" ]
	then
		copy_file_metadata "$target_file" "$staged_file" || true
	fi

	return 0
}

extract_config_value() {
	local key=$1
	local file=$2

	awk -v key="$key" '
		function trim(value) {
			gsub(/^[ \t\r]+|[ \t\r]+$/, "", value)
			return value
		}
		function strip_comment(value,    output, char, previous_char, in_single, in_double, i) {
			output = ""
			previous_char = ""
			in_single = 0
			in_double = 0
			for (i = 1; i <= length(value); i++) {
				char = substr(value, i, 1)
				if (char == "'\''" && in_double == 0) {
					in_single = !in_single
				} else if (char == "\"" && in_single == 0) {
					in_double = !in_double
				} else if (char == "#" && in_single == 0 && in_double == 0) {
					if (previous_char == "" || previous_char ~ /[ \t\r]/) {
						break
					}
				}
				output = output char
				previous_char = char
			}
			return output
		}
		$0 ~ "^[ \t\r]*" key "[ \t\r]*=" {
			sub("^[ \t\r]*" key "[ \t\r]*=[ \t\r]*", "")
			$0 = trim(strip_comment($0))
			if (($0 ~ /^".*"$/) || ($0 ~ /^'\''.*'\''$/)) {
				$0 = substr($0, 2, length($0) - 2)
			}
			print
			exit
		}
	' "$file" | tr -d '\r'
}

extract_config_line() {
	local key=$1
	local file=$2

	awk -v key="$key" '
		{
			sub(/\r$/, "")
			position = index($0, "=")
			if (position == 0) {
				next
			}
			name = substr($0, 1, position - 1)
			gsub(/^[ \t\r]+|[ \t\r]+$/, "", name)
			if (name == key) {
				value = substr($0, position + 1)
				sub(/^[ \t]+/, "", value)
				line = key "=" value
			}
		}
		END {
			if (line != "") {
				print line
			}
		}
	' "$file"
}

replace_config_line() {
	local file=$1
	local old_line=$2
	local new_line=$3
	local tmp_file="$file.tmp"

	if awk -v old_line="$old_line" -v new_line="$new_line" '
		$0 == old_line { print new_line; next }
		{ print }
	' "$file" > "$tmp_file"
	then
		if [ -e "$file" ]
		then
			copy_file_metadata "$file" "$tmp_file" || true
		fi
		if ! mv "$tmp_file" "$file"
		then
			echo "ERROR: Failed to update the staged agent configuration." >&2
			rm -f "$tmp_file"
			exit 1
		fi
	else
		echo "ERROR: Failed to update the staged agent configuration." >&2
		rm -f "$tmp_file"
		exit 1
	fi
}

preserve_config_line() {
	local file=$1
	local key=$2
	local line=$3
	local tmp_file="$file.tmp"

	if PRESERVED_LINE="$line" awk -v key="$key" '
		index($0, key "=") == 1 { print ENVIRON["PRESERVED_LINE"]; next }
		{ print }
	' "$file" > "$tmp_file"
	then
		if [ -e "$file" ]
		then
			copy_file_metadata "$file" "$tmp_file" || true
		fi
		mv "$tmp_file" "$file"
	else
		rm -f "$tmp_file"
		echo "WARNING: Failed to preserve $key during update." >&2
	fi
}

# Check for wget
echo "Checking wget..."
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
echo "... done."

echo "Using $BRANCH branch..."
# Check if update script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
	then echo "ERROR: Please run the update script as root."
	exit 1
fi
echo "... done."

# Look for the old agent
echo "Looking for the old agent..."
if [ -f "$AGENT" ]
then
	echo "... done."
else
	echo "ERROR: No old agent found. Nothing to update." >&2; exit 1;
fi

UPDATE_TMP_DIR=$(mktemp -d /tmp/hetrixtools_update.XXXXXX 2>/dev/null || mktemp -d)
if [ -z "$UPDATE_TMP_DIR" ] || [ ! -d "$UPDATE_TMP_DIR" ]
then
	echo "ERROR: Unable to create a temporary update directory." >&2
	exit 1
fi
trap cleanup_update_tmp_dir EXIT
NEW_AGENT="$UPDATE_TMP_DIR/hetrixtools_agent.sh"
NEW_CONFIG="$UPDATE_TMP_DIR/hetrixtools.cfg"
STAGED_AGENT="$AGENT.update.$$"
STAGED_CONFIG="$CONFIG.update.$$"

# Fetching the available agent to check its version
echo "Checking available agent version..."
if ! github_wget -t 1 -T 30 -qO "$NEW_AGENT" https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools_agent.sh
then
	echo "ERROR: Failed to download the agent script from GitHub for branch/tag $BRANCH." >&2
	exit 1
fi
CURRENT_VERSION=$(extract_agent_version "$AGENT")
AVAILABLE_VERSION=$(extract_agent_version "$NEW_AGENT")
DISPLAY_CURRENT_VERSION=$CURRENT_VERSION
DISPLAY_AVAILABLE_VERSION=$AVAILABLE_VERSION
if [ -z "$DISPLAY_CURRENT_VERSION" ]
then
	DISPLAY_CURRENT_VERSION="unknown"
fi
if [ -z "$DISPLAY_AVAILABLE_VERSION" ]
then
	DISPLAY_AVAILABLE_VERSION="unknown"
fi
echo "Installed agent version: $DISPLAY_CURRENT_VERSION"
echo "Available agent version: $DISPLAY_AVAILABLE_VERSION"
if [ -z "$CURRENT_VERSION" ]
then
	echo "WARNING: Unable to determine the installed agent version; proceeding with update." >&2
fi
if [ -z "$AVAILABLE_VERSION" ]
then
	echo "WARNING: Unable to determine the available agent version; proceeding with update." >&2
fi
if [ -n "$CURRENT_VERSION" ] && [ -n "$AVAILABLE_VERSION" ] && [ "$CURRENT_VERSION" = "$AVAILABLE_VERSION" ]
then
	if [ "$FORCE_UPDATE" -eq 1 ]
	then
		echo "Force update requested; reinstalling the current version."
	else
		echo "HetrixTools agent is already at latest version ($CURRENT_VERSION). Use -force option to reinstall the current version."
		exit 0
	fi
else
	echo "Version differs or could not be determined; updating the agent."
fi
echo "... done."

# Check for required system utilities (either cron or systemd)
echo "Checking system utilities..."
USE_CRON=0
USE_SYSTEMD=0
SYSTEMCTL_AVAILABLE=0
CRON_ACTIVE=0
if command -v systemctl >/dev/null 2>&1; then
	if [ -d /run/systemd/system ] || systemctl list-units >/dev/null 2>&1; then
		SYSTEMCTL_AVAILABLE=1
	fi
fi
if command -v crontab >/dev/null 2>&1; then
	if command -v pgrep >/dev/null 2>&1; then
		for cron_process in cron crond cronie systemd-cron fcron busybox-cron busybox-crond; do
			if pgrep -x "$cron_process" >/dev/null 2>&1 || pgrep -f '^([^ ]*/)?(busybox +)?'"$cron_process"'( |$)' >/dev/null 2>&1; then
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

# Detect the current runtime user before recreating cron/systemd entries later.
echo "Detecting the current agent runtime user..."
AGENT_RUNTIME_USER=$(detect_agent_run_user)
if [ "$AGENT_RUNTIME_USER" != "root" ] && [ "$AGENT_RUNTIME_USER" != "hetrixtools" ]
then
	echo "ERROR: Unable to detect whether the current agent runs as 'root' or 'hetrixtools'." >&2
	echo "Please re-run the agent install code provided by the HetrixTools platform." >&2
	exit 1
fi
echo "... done."

# Extract data from the old agent
echo "Extracting configs from the old agent..."
# SID (Server ID)
SID=$(extract_config_value 'SID' "$EXTRACT")
if [ -z "$SID" ]
then
	echo "ERROR: Unable to read the Server ID (SID) from the current agent, nothing was changed." >&2
	echo "Please re-run the agent install code provided by the HetrixTools platform." >&2
	exit 1
fi
# Network Interfaces
NetworkInterfaces=$(extract_config_value 'NetworkInterfaces' "$EXTRACT")
# Ignored Network Interfaces
IgnoredNICsLine=$(extract_config_line 'IgnoredNICs' "$EXTRACT")
# Ignore Bridge Interfaces
IgnoreBridgeInterfaces=$(extract_config_value 'IgnoreBridgeInterfaces' "$EXTRACT" | tr -d '[:space:]')
if [ "$IgnoreBridgeInterfaces" != "1" ]
then
	IgnoreBridgeInterfaces=0
fi
# Ignored Disks
IgnoredDisksLine=$(extract_config_line 'IgnoredDisks' "$EXTRACT")
# Check Services
CheckServices=$(normalize_service_names "$(extract_config_value 'CheckServices' "$EXTRACT")")
# Check Software RAID Health
CheckSoftRAID=$(extract_config_value 'CheckSoftRAID' "$EXTRACT" | tr -d '[:space:]')
if [ "$CheckSoftRAID" != "1" ]
then
	CheckSoftRAID=0
fi
# Check Drive Health
CheckDriveHealth=$(extract_config_value 'CheckDriveHealth' "$EXTRACT" | tr -d '[:space:]')
if [ "$CheckDriveHealth" != "1" ]
then
	CheckDriveHealth=0
fi
# Check Reboot Required
CheckReboot=$(extract_config_value 'CheckReboot' "$EXTRACT" | tr -d '[:space:]')
if [ "$CheckReboot" != "0" ]
then
	CheckReboot=1
fi
# RunningProcesses
RunningProcesses=$(extract_config_value 'RunningProcesses' "$EXTRACT" | tr -d '[:space:]')
if [ "$RunningProcesses" != "1" ]
then
	RunningProcesses=0
fi
echo "... done."
# Port Connections
ConnectionPorts=$(normalize_connection_ports "$(extract_config_value 'ConnectionPorts' "$EXTRACT")")
if [ -f "$CONFIG" ]
then
	# Custom Variables
	CustomVars=$(extract_config_value 'CustomVars' "$EXTRACT")
	# Secured Connection
	SecuredConnection=$(normalize_secured_connection "$(extract_config_value 'SecuredConnection' "$EXTRACT")")
	# CollectEveryXSeconds
	CollectEveryXSeconds=$(normalize_collect_interval "$(extract_config_value 'CollectEveryXSeconds' "$EXTRACT")")
	# OutgoingPings
	OutgoingPings=$(extract_config_value 'OutgoingPings' "$EXTRACT")
	# OutgoingPingsCount
	OutgoingPingsCount=$(extract_config_value 'OutgoingPingsCount' "$EXTRACT")
fi

# Fetching the new config file
echo "Fetching the new config file..."
if ! github_wget -t 1 -T 30 -qO "$NEW_CONFIG" https://raw.githubusercontent.com/hetrixtools/agent/$BRANCH/hetrixtools.cfg
then
	echo "ERROR: Failed to download the agent configuration from GitHub." >&2
	exit 1
fi
echo "... done."

# Preparing the new agent and config file
echo "Preparing the new agent and config file..."
if ! prepare_staged_file "$NEW_AGENT" "$AGENT" "$STAGED_AGENT"
then
	echo "ERROR: Failed to prepare the new agent script." >&2
	exit 1
fi
if ! prepare_staged_file "$NEW_CONFIG" "$CONFIG" "$STAGED_CONFIG"
then
	echo "ERROR: Failed to prepare the new agent configuration." >&2
	exit 1
fi
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
replace_config_line "$STAGED_CONFIG" 'SID=""' "SID=\"$SID\""
echo "... done."

# Check if any network interfaces are specified
echo "Checking if any network interfaces are specified..."
if [ ! -z "$NetworkInterfaces" ]
then
	echo "Network interfaces found, inserting them into the agent config..."
	replace_config_line "$STAGED_CONFIG" 'NetworkInterfaces=""' "NetworkInterfaces=\"$NetworkInterfaces\""
fi
echo "... done."

# Check if any disks should be ignored
echo "Checking if any disks should be ignored..."
if [ -n "$IgnoredDisksLine" ]
then
	echo "Ignored disks found, inserting them into the agent config..."
	preserve_config_line "$STAGED_CONFIG" 'IgnoredDisks' "$IgnoredDisksLine"
fi
echo "... done."

# Check if any network interfaces should be ignored
echo "Checking if any network interfaces should be ignored..."
if [ -n "$IgnoredNICsLine" ]
then
	echo "Ignored network interfaces found, inserting them into the agent config..."
	preserve_config_line "$STAGED_CONFIG" 'IgnoredNICs' "$IgnoredNICsLine"
fi
if [ "$IgnoreBridgeInterfaces" = "1" ]
then
	echo "Enabling ignoring of bridge interfaces in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'IgnoreBridgeInterfaces=0' 'IgnoreBridgeInterfaces=1'
fi
echo "... done."

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ ! -z "$CheckServices" ]
then
	echo "Services found, inserting them into the agent config..."
	replace_config_line "$STAGED_CONFIG" 'CheckServices=""' "CheckServices=\"$CheckServices\""
fi
echo "... done."

# Check if Software RAID should be monitored
echo "Checking if software RAID should be monitored..."
if [ "$CheckSoftRAID" = "1" ]
then
	echo "Enabling software RAID monitoring in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'CheckSoftRAID=0' 'CheckSoftRAID=1'
fi
echo "... done."

# Check if Drive Health should be monitored
echo "Checking if Drive Health should be monitored..."
if [ "$CheckDriveHealth" = "1" ]
then
	echo "Enabling Drive Health monitoring in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'CheckDriveHealth=0' 'CheckDriveHealth=1'
fi
echo "... done."

# Check if reboot required should be checked
echo "Checking if reboot required should be checked..."
if [ "$CheckReboot" = "0" ]
then
	echo "Disabling reboot required check in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'CheckReboot=1' 'CheckReboot=0'
fi
echo "... done."

# Check if 'View running processes' should be enabled
echo "Checking if 'View running processes' should be enabled..."
if [ "$RunningProcesses" = "1" ]
then
	echo "Enabling 'View running processes' in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'RunningProcesses=0' 'RunningProcesses=1'
fi
echo "... done."

# Check if any ports to monitor number of connections on
echo "Checking if any ports to monitor number of connections on..."
if [ ! -z "$ConnectionPorts" ]
then
	echo "Ports found, inserting them into the agent config..."
	replace_config_line "$STAGED_CONFIG" 'ConnectionPorts=""' "ConnectionPorts=\"$ConnectionPorts\""
fi
echo "... done."

# Check if any custom variables are specified
echo "Checking if any custom variables are specified..."
if [ ! -z "$CustomVars" ]
then
	echo "Custom variables found, inserting them into the agent config..."
	replace_config_line "$STAGED_CONFIG" 'CustomVars="custom_variables.json"' "CustomVars=\"$CustomVars\""
fi
echo "... done."

# Check if secured connection is enabled
echo "Checking if secured connection is enabled..."
if [ ! -z "$SecuredConnection" ]
then
	echo "Inserting secured connection in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'SecuredConnection=1' "SecuredConnection=$SecuredConnection"
fi
echo "... done."

# Check CollectEveryXSeconds
echo "Checking CollectEveryXSeconds..."
if [ ! -z "$CollectEveryXSeconds" ]
then
	echo "Inserting CollectEveryXSeconds in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'CollectEveryXSeconds=3' "CollectEveryXSeconds=$CollectEveryXSeconds"
fi

# Check OutgoingPings
echo "Checking OutgoingPings..."
if [ ! -z "$OutgoingPings" ]
then
	echo "Inserting OutgoingPings in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'OutgoingPings=""' "OutgoingPings=\"$OutgoingPings\""
fi

# Check OutgoingPingsCount
echo "Checking OutgoingPingsCount..."
if [ ! -z "$OutgoingPingsCount" ]
then
	echo "Inserting OutgoingPingsCount in the agent config..."
	replace_config_line "$STAGED_CONFIG" 'OutgoingPingsCount=20' "OutgoingPingsCount=$OutgoingPingsCount"
fi

# Atomically install the staged agent and config file
echo "Installing the new agent and config file..."
if ! mv "$STAGED_CONFIG" "$CONFIG"
then
	echo "ERROR: Failed to install the new agent configuration." >&2
	exit 1
fi
if ! mv "$STAGED_AGENT" "$AGENT"
then
	echo "ERROR: Failed to install the new agent script." >&2
	exit 1
fi
echo "... done."
rm -f /etc/hetrixtools/hetrixtools_reboot_check.cache >/dev/null 2>&1

# Refresh scheduler configuration (prefer cron when available)
if [ "$USE_CRON" -eq 1 ]
then
	echo "Ensuring cron schedule is configured..."
	CRON_TARGET_USER=""
	if crontab -u root -l 2>/dev/null | grep -q 'hetrixtools_agent.sh'; then
		CRON_TARGET_USER=root
	elif id -u hetrixtools >/dev/null 2>&1 && crontab -u hetrixtools -l 2>/dev/null | grep -q 'hetrixtools_agent.sh'; then
		CRON_TARGET_USER=hetrixtools
	fi
	if [ -z "$CRON_TARGET_USER" ]; then
		CRON_TARGET_USER=$AGENT_RUNTIME_USER
	fi
	if [ "$CRON_TARGET_USER" = "hetrixtools" ] && ! id -u hetrixtools >/dev/null 2>&1; then
		CRON_TARGET_USER=root
	fi
	crontab -u root -l 2>/dev/null | grep -v 'hetrixtools_agent.sh' | crontab -u root - >/dev/null 2>&1
	if id -u hetrixtools >/dev/null 2>&1; then
		crontab -u hetrixtools -l 2>/dev/null | grep -v 'hetrixtools_agent.sh' | crontab -u hetrixtools - >/dev/null 2>&1
	fi
	if [ "$CRON_TARGET_USER" = "root" ]; then
		crontab -u root -l 2>/dev/null | { cat; echo "* * * * * bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1"; } | crontab -u root - >/dev/null 2>&1
	else
		crontab -u hetrixtools -l 2>/dev/null | { cat; echo "* * * * * bash /etc/hetrixtools/hetrixtools_agent.sh >> /etc/hetrixtools/hetrixtools_cron.log 2>&1"; } | crontab -u hetrixtools - >/dev/null 2>&1
	fi
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
	echo "... done."
elif [ "$USE_SYSTEMD" -eq 1 ]
then
	echo "Ensuring systemd service and timer schedule..."
	SERVICE_USER=$AGENT_RUNTIME_USER
	if [ "$SERVICE_USER" = "hetrixtools" ] && ! id -u hetrixtools >/dev/null 2>&1; then
		SERVICE_USER=root
	fi
	if command -v crontab >/dev/null 2>&1; then
		crontab -u root -l 2>/dev/null | grep -v 'hetrixtools_agent.sh' | crontab -u root - >/dev/null 2>&1
		if id -u hetrixtools >/dev/null 2>&1; then
			crontab -u hetrixtools -l 2>/dev/null | grep -v 'hetrixtools_agent.sh' | crontab -u hetrixtools - >/dev/null 2>&1
		fi
	fi
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
	echo "... done."
fi

# Killing any running hetrixtools agents
echo "Making sure no hetrixtools agent scripts are currently running..."
ps aux | grep -ie hetrixtools_agent.sh | awk '{print $2}' | xargs -r kill -9
echo "... done."

# Assign permissions
echo "Assigning permissions for the selected runtime user..."
if ! apply_agent_permissions "$AGENT_RUNTIME_USER"
then
	echo "ERROR: Failed to assign permissions for the agent files." >&2
	exit 1
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
