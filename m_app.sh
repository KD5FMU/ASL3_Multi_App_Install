#!/bin/sh

# This script assists with the new install of AllStarLink version 3.
# It installs SkywarnPlus, AllScan Dashboard, DVSwitch Server, and Supermon 7.4+.
#
# Copyright (C) 2024 Freddie Mac - KD5FMU 
# Copyright (C) 2024 Allan - OCW3AW
# Copyright (C) 2024 Jory A. Pratt - W5GLE
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# Check if root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root or with sudo"
    exit 1
fi

CONF_FILE="/etc/asterisk/rpt.conf"

# Function to display usage
usage() {
	cat << EOF
Usage: $0 [OPTIONS]

Options:
  -a    Install allscan
  -s    Install supermon
  -w    Install skywarnplus
  -d    Install dvswitch
  -h    Display this help message

You can combine options to install multiple software (e.g., $0 -a -s).
EOF
}

# Functions to install each software package
install_allscan() {
	echo "Installing allscan..."
	# First make sure required deps are installed
	apt install php unzip -y
	cd || exit
	wget 'https://raw.githubusercontent.com/davidgsd/AllScan/main/AllScanInstallUpdate.php'
	chmod 755 AllScanInstallUpdate.php
	./AllScanInstallUpdate.php
	rm -f AllScanInstallUpdate.php
	echo "Allscan installation complete."
}

install_supermon() {
	echo "Installing supermon..."
	# Install deps before we fetch script and run
	apt -y install apache2 php libapache2-mod-php libcgi-session-perl bc
	cd || exit
	wget "http://2577.asnode.org:43856/supermonASL_fresh_install" -O supermonASL_fresh_install
	chmod +x supermonASL_fresh_install
	./supermonASL_fresh_install
	echo "Supermon 7.4+ fresh installation complete."
	
	echo "Installing Upgradeable Supermon 7.4..."
	wget "http://2577.asnode.org:43856/supermonASL_latest_update" -O supermonASL_latest_update
	chmod +x supermonASL_latest_update
	./supermonASL_latest_update
	rm -f supermonASL_fresh_install supermonASL_latest_update

	cp "$CONF_FILE" "${CONF_FILE}.bak-supermon"
	sed -i '/\[functions\]/a SMUPDATE=cmd,/usr/local/sbin/supermonASL_latest_update \n' "$CONF_FILE"

	echo "Setting up cron job..."
	DISABLE_MAIL="MAILTO=\"\""
	CRON_COMMENT="# Supermon 7.4 updater crontab entry"
	CRON_JOB="0 3 * * * /var/www/html/supermon/astdb.php cron"
	( crontab -l 2>/dev/null; echo "$DISABLE_MAIL"; echo "$CRON_COMMENT"; echo "$CRON_JOB" ) | crontab -
	echo "Cron job set."

	echo "Upgradeable Supermon 7.4 install complete."
}

install_skywarnplus() {
	echo "Installing skywarnplus..."
	# Install deps before we install skywarn via script
	apt install -y unzip python3 python3-pip ffmpeg python3-ruamel.yaml python3-requests python3-dateutil python3-pydub
	cd || exit
	bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mason10198/SkywarnPlus/main/swp-install)"

	cp "$CONF_FILE" "${CONF_FILE}.bak-skywarn"
	sed -i '/\[functions\]/a \
831 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py enable toggle ; Toggles SkywarnPlus \
832 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py sayalert toggle ; Toggles SayAlert \
833 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py sayallclear toggle ; Toggles SayAllClear \
834 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py tailmessage toggle ; Toggles TailMessage \
835 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py courtesytone toggle ; Toggles CourtesyTone \
836 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py alertscript toggle ; Toggles AlertScript \
837 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py idchange toggle ; Toggles IDChange \
838 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py changect normal ; Forces CT to "normal" mode \
839 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py changeid normal ; Forces ID to "normal" mode \
841 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 1 ; SkyDescribe the 1st alert \
842 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 2 ; SkyDescribe the 2nd alert \
843 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 3 ; SkyDescribe the 3rd alert \
844 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 4 ; SkyDescribe the 4th alert \
845 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 5 ; SkyDescribe the 5th alert \
846 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 6 ; SkyDescribe the 6th alert \
847 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 7 ; SkyDescribe the 7th alert \
848 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 8 ; SkyDescribe the 8th alert \
849 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 9 ; SkyDescribe the 9th alert \n' "$CONF_FILE"

	sed -i '/tailmessagetime=/s/^#//; s/tailmessagetime=.*/tailmessagetime=600000/' "$CONF_FILE"
	sed -i '/tailsquashedtime=/s/^#//; s/tailsquashedtime=.*/tailsquashedtime=30000/' "$CONF_FILE"
	awk '/tailsquashedtime=30000/ { print "tailmessagelist = /tmp/SkywarnPlus/wx-tail"; } { print }' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv "${CONF_FILE}.tmp" "$CONF_FILE"
	
	echo "Skywarnplus installation complete."
}

install_dvswitch() {
	echo "Installing dvswitch..."
	# Install deps before we install dvswitch
	apt install -y php-cgi libapache2-mod-php8.2
	cd || exit
	wget dvswitch.org/bookworm
	chmod +x bookworm
	./bookworm
	rm bookworm
	apt update
	apt install -y dvswitch-server

	# Allow Apache2 to access /tmp
	cp /lib/systemd/system/apache2.service /etc/systemd/system/
	sed -i 's/true/false/g' /etc/systemd/system/apache2.service
	systemctl restart apache2
	systemctl daemon-reload

	echo "Dvswitch Server installation complete."
}

# Parse command-line arguments
while getopts "aswdh" opt; do
	case $opt in
		a)
			install_allscan_flag=true
		;;
		s)
			install_supermon_flag=true
		;;
		w)
			install_skywarnplus_flag=true
		;;
		d)
			install_dvswitch_flag=true
		;;
		h)
			usage
			exit 0
		;;
		*)
			usage
			exit 1
		;;
	esac
done

# If no options are provided, show usage and exit
if [ "$OPTIND" -eq 1 ]; then
	usage
	exit 1
fi

# Perform the installations based on flags
[ "$install_allscan_flag" ] && install_allscan
[ "$install_supermon_flag" ] && install_supermon
[ "$install_skywarnplus_flag" ] && install_skywarnplus
[ "$install_dvswitch_flag" ] && install_dvswitch
