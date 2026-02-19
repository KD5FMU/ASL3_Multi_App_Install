#!/bin/bash
# This script assists with the new install of AllStarLink version 3.
# It installs SkywarnPlus, AllScan Dashboard, DVSwitch Server, and Supermon 7.4+.
#
# Copyright (C) 2024 Freddie Mac - KD5FMU
# Copyright (C) 2024 Allan - OCW3AW
# Copyright (C) 2024-2025 Jory A. Pratt - W5GLE
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

# Configuration
CONF_FILE="/etc/asterisk/rpt.conf"
LOG_FILE="/var/log/m_app_install.log"
TEMP_DIR="/root/m_app_install"
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
   
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) [ "$VERBOSE" = true ] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
   
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
error_exit() {
    log ERROR "$1"
    exit 1
}

# Check if root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root or with sudo"
fi

# ────────────────────────────────────────────────────────────────
# Ensure web server & PHP basics are present (needed by Supermon, DVSwitch, AllScan)
# ────────────────────────────────────────────────────────────────
log INFO "Checking for Apache2 + PHP prerequisites..."

ensure_web_prereqs() {
    local pkgs=("apache2" "php" "libapache2-mod-php")
    local to_install=()

    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            to_install+=("$pkg")
        fi
    done

    if [ ${#to_install[@]} -gt 0 ]; then
        log INFO "Installing missing web server / PHP packages: ${to_install[*]}"
        apt update || error_exit "apt update failed before installing web prerequisites"
        apt install -y "${to_install[@]}" || error_exit "Failed to install apache2 + PHP packages"
        
        systemctl enable apache2  >/dev/null 2>&1
        systemctl start  apache2  >/dev/null 2>&1 || log WARN "Failed to start apache2 service"
        log INFO "Apache2 + PHP installed and service started"
    else
        log INFO "Apache2 and PHP appear to be already installed"
    fi
}

ensure_web_prereqs

# Create temp directory and log file
mkdir -p "$TEMP_DIR"
touch "$LOG_FILE"
log INFO "Starting M-Apps installation script"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get Debian codename
get_debian_codename() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_CODENAME"
    elif [ -f /etc/debian_version ]; then
        local debian_version=$(cat /etc/debian_version)
        case "$debian_version" in
            12*) echo "bookworm" ;;
            13*) echo "trixie"   ;;
            *)   echo "unknown"  ;;
        esac
    else
        echo "unknown"
    fi
}

# Function to ensure pip3 is installed
ensure_pip3() {
    if ! command_exists pip3; then
        log INFO "Installing python3-pip"
        apt install -y python3-pip || error_exit "Failed to install python3-pip"
    fi
}

# Function to install Python package via pip if not already installed
install_pip_package() {
    local package=$1
    local module_name=${2:-$package}
   
    if ! python3 -c "import $module_name" 2>/dev/null; then
        log INFO "Installing $package via pip3"
        pip3 install --break-system-packages "$package" || error_exit "Failed to install $package via pip3"
    else
        log INFO "$module_name is already installed"
    fi
}

# Function to safely download files
safe_download() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
   
    while [ $retry_count -lt $max_retries ]; do
        if wget --no-verbose --timeout=30 --tries=3 -O "$output" "$url"; then
            log DEBUG "Successfully downloaded $url"
            return 0
        else
            retry_count=$((retry_count + 1))
            log WARN "Download failed for $url (attempt $retry_count/$max_retries)"
            [ $retry_count -lt $max_retries ] && sleep 2
        fi
    done
   
    error_exit "Failed to download $url after $max_retries attempts"
}

# Function to backup configuration file
backup_config() {
    local backup_suffix="$1"
    if [ -f "$CONF_FILE" ]; then
        cp "$CONF_FILE" "${CONF_FILE}.bak-${backup_suffix}"
        log INFO "Configuration backed up to ${CONF_FILE}.bak-${backup_suffix}"
    else
        log WARN "Configuration file $CONF_FILE not found"
    fi
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]
Options:
  -a Install allscan
  -s Install supermon
  -w Install skywarnplus
  -d Install dvswitch
  -v Verbose output
  -t Dry run (test mode)
  -h Display this help message
You can combine options to install multiple software (e.g., $0 -a -s -w).
EOF
}

# ────────────────────────────────────────────────────────────────
# Install functions (apache/php deps removed – handled globally)
# ────────────────────────────────────────────────────────────────

install_allscan() {
    log INFO "Installing AllScan..."
   
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would install AllScan"
        return 0
    fi
   
    # Remaining deps (unzip usually needed)
    if ! dpkg -l unzip >/dev/null 2>&1; then
        apt install -y unzip || error_exit "Failed to install unzip"
    fi
   
    cd "$TEMP_DIR" || error_exit "Failed to change to temp directory"
   
    local installer="AllScanInstallUpdate.php"
    safe_download "https://raw.githubusercontent.com/davidgsd/AllScan/main/AllScanInstallUpdate.php" "$installer"
    chmod 755 "$installer"
   
    log INFO "Running AllScan installer..."
    if ./"$installer"; then
        log INFO "AllScan installation completed successfully"
    else
        error_exit "AllScan installation failed"
    fi
   
    rm -f "$installer"
}

install_supermon() {
    log INFO "Installing Supermon..."
   
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would install Supermon"
        return 0
    fi
   
    # Remaining deps
    if ! dpkg -l libcgi-session-perl bc >/dev/null 2>&1; then
        apt install -y libcgi-session-perl bc || error_exit "Failed to install Supermon remaining deps"
    fi
   
    cd "$TEMP_DIR" || error_exit "Failed to change to temp directory"
   
    safe_download "http://2577.asnode.org:43856/supermonASL_fresh_install" "supermonASL_fresh_install"
    chmod +x supermonASL_fresh_install
   
    log INFO "Running Supermon fresh install..."
    ./supermonASL_fresh_install || error_exit "Supermon fresh installation failed"
   
    safe_download "http://2577.asnode.org:43856/supermonASL_latest_update" "supermonASL_latest_update"
    chmod +x supermonASL_latest_update
   
    log INFO "Running Supermon latest update..."
    ./supermonASL_latest_update || error_exit "Supermon update failed"
   
    rm -f supermonASL_fresh_install supermonASL_latest_update
   
    backup_config "supermon"
   
    if [ -f "$CONF_FILE" ]; then
        if ! grep -q "SMUPDATE=" "$CONF_FILE"; then
            sed -i '/\[functions\]/a SMUPDATE=cmd,/usr/local/sbin/supermonASL_latest_update' "$CONF_FILE"
            log INFO "Added SMUPDATE function to configuration"
        fi
    fi
   
    log INFO "Setting up Supermon cron job..."
    local cron_comment="# Supermon 7.4 updater crontab entry"
    local cron_job="0 3 * * * /var/www/html/supermon/astdb.php cron"
   
    if ! crontab -l 2>/dev/null | grep -q "astdb.php cron"; then
        ( crontab -l 2>/dev/null; echo "$cron_comment"; echo "$cron_job" ) | crontab -
        log INFO "Cron job added"
    else
        log INFO "Cron job already exists"
    fi
   
    log INFO "Supermon installation completed"
}

install_skywarnplus() {
    log INFO "Installing SkywarnPlus..."
   
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would install SkywarnPlus"
        return 0
    fi
   
    local deps=("unzip" "python3" "python3-pip" "ffmpeg" "python3-ruamel.yaml" "python3-requests" "python3-dateutil")
    for dep in "${deps[@]}"; do
        if ! dpkg -l "$dep" >/dev/null 2>&1; then
            log INFO "Installing dependency: $dep"
            apt install -y "$dep" || error_exit "Failed to install $dep"
        fi
    done
   
    local debian_codename=$(get_debian_codename)
    if [ "$debian_codename" = "trixie" ]; then
        log INFO "Debian Trixie detected - using pip for pydub"
        ensure_pip3
        install_pip_package "pydub" "pydub"
        install_pip_package "audioop-lts" "audioop"
    else
        if ! dpkg -l python3-pydub >/dev/null 2>&1; then
            log INFO "Trying to install python3-pydub via apt"
            if ! apt install -y python3-pydub 2>/dev/null; then
                log WARN "python3-pydub not in apt → falling back to pip"
                ensure_pip3
                install_pip_package "pydub" "pydub"
            fi
        fi
    fi
   
    cd "$TEMP_DIR" || error_exit "Failed to change to temp directory"
   
    local installer="swp-install"
    safe_download "https://raw.githubusercontent.com/Mason10198/SkywarnPlus/main/swp-install" "$installer"
    chmod +x "$installer"
   
    log INFO "Downloading Trixie compatibility patch..."
    local patch_file="swp-install-trixie.patch"
    safe_download "https://raw.githubusercontent.com/KD5FMU/ASL3_Multi_App_Install/refs/heads/main/swp-install-trixie.patch" "$patch_file"
   
    if ! command_exists patch; then
        apt install -y patch || error_exit "Failed to install patch"
    fi
   
    log INFO "Applying patch (if needed)..."
    patch "$installer" "$patch_file" 2>/dev/null || log WARN "Patch already applied or failed – continuing"
    rm -f "$patch_file"
   
    log INFO "Running SkywarnPlus installer..."
    ./"$installer" || error_exit "SkywarnPlus installation failed"
   
    rm -f "$installer"
   
    backup_config "skywarn"
   
    if [ -f "$CONF_FILE" ]; then
        if ! grep -q "SkywarnPlus/SkyControl.py" "$CONF_FILE"; then
            sed -i '/\[functions\]/a \
831 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py enable toggle ; Toggles SkywarnPlus\
832 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py sayalert toggle ; Toggles SayAlert\
833 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py sayallclear toggle ; Toggles SayAllClear\
834 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py tailmessage toggle ; Toggles TailMessage\
835 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py courtesytone toggle ; Toggles CourtesyTone\
836 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py alertscript toggle ; Toggles AlertScript\
837 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py idchange toggle ; Toggles IDChange\
838 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py changect normal ; Forces CT to "normal" mode\
839 = cmd,/usr/local/bin/SkywarnPlus/SkyControl.py changeid normal ; Forces ID to "normal" mode\
841 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 1 ; SkyDescribe the 1st alert\
842 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 2 ; SkyDescribe the 2nd alert\
843 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 3 ; SkyDescribe the 3rd alert\
844 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 4 ; SkyDescribe the 4th alert\
845 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 5 ; SkyDescribe the 5th alert\
846 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 6 ; SkyDescribe the 6th alert\
847 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 7 ; SkyDescribe the 7th alert\
848 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 8 ; SkyDescribe the 8th alert\
849 = cmd,/usr/local/bin/SkywarnPlus/SkyDescribe.py 9 ; SkyDescribe the 9th alert' "$CONF_FILE"
            log INFO "Added SkywarnPlus functions"
        fi
       
        sed -i '/tailmessagetime=/s/^#//; s/tailmessagetime=.*/tailmessagetime=600000/' "$CONF_FILE"
        sed -i '/tailsquashedtime=/s/^#//; s/tailsquashedtime=.*/tailsquashedtime=30000/' "$CONF_FILE"
       
        if ! grep -q "tailmessagelist.*SkywarnPlus" "$CONF_FILE"; then
            awk '/tailsquashedtime=30000/ { print "tailmessagelist = /tmp/SkywarnPlus/wx-tail"; } { print }' "$CONF_FILE" > "${CONF_FILE}.tmp" && mv "${CONF_FILE}.tmp" "$CONF_FILE"
            log INFO "Added tailmessagelist"
        fi
    fi
   
    log INFO "SkywarnPlus installation completed"
}

install_dvswitch() {
    log INFO "Installing DVSwitch Server..."
   
    if [ "$DRY_RUN" = true ]; then
        log INFO "[DRY RUN] Would install DVSwitch Server"
        return 0
    fi
   
    cd "$TEMP_DIR" || error_exit "Failed to change to temp directory"
   
    safe_download "dvswitch.org/bookworm" "bookworm"
    chmod +x bookworm
   
    log INFO "Running DVSwitch bookworm installer..."
    ./bookworm || error_exit "DVSwitch bookworm script failed"
   
    rm -f bookworm
   
    apt update
    apt install -y dvswitch-server || error_exit "Failed to install dvswitch-server package"
   
    local config_file="/usr/share/dvswitch/include/config.php"
    if [ -f "$config_file" ]; then
        sed -i 's/31001/34001/' "$config_file" && \
            log INFO "Changed USRP port to 34001" || \
            log WARN "Could not update USRP port in config.php"
    else
        log WARN "DVSwitch config.php not found"
    fi
   
    log INFO "DVSwitch Server installation completed"
}

# ────────────────────────────────────────────────────────────────
# Parse arguments
# ────────────────────────────────────────────────────────────────

while getopts "aswdhtv" opt; do
    case $opt in
        a) install_allscan_flag=true ;;
        s) install_supermon_flag=true ;;
        w) install_skywarnplus_flag=true ;;
        d) install_dvswitch_flag=true ;;
        t) DRY_RUN=true; log INFO "Dry run mode enabled" ;;
        v) VERBOSE=true; log INFO "Verbose mode enabled" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [ "$OPTIND" -eq 1 ]; then
    usage
    exit 1
fi

if [ ! -f "$CONF_FILE" ]; then
    log WARN "rpt.conf not found – some steps may behave differently"
fi

# Execute selected installations
[ "$install_allscan_flag"    ] && install_allscan
[ "$install_supermon_flag"   ] && install_supermon
[ "$install_skywarnplus_flag"] && install_skywarnplus
[ "$install_dvswitch_flag"   ] && install_dvswitch

# Cleanup
if [ "$DRY_RUN" = false ]; then
    rm -rf "$TEMP_DIR"
    log INFO "Installation finished. Log: $LOG_FILE"
else
    log INFO "Dry run complete – no changes applied"
fi

exit 0