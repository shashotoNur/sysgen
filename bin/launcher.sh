#!/bin/bash

###############################################################################
# Script Name: launcher.sh
# Description: Connects to the internet, clones sysgen repository and launches
#              installation phase
# Author: Shashoto Nur

# Version: 1.1
# License: MIT
###############################################################################

# --- Configuration ---
set -euo pipefail # Exit on error, unset variable, or pipeline failure

# --- Logging Functions ---

log_info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1" >&2; }
log_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; }
log_success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1" >&2; }

# Read configuration from install.conf
read_config() {
    declare -A config_values
    local file="install.conf"

    while IFS= read -r line; do
        key="${line%%: *}"
        value="${line#*: }"
        config_values["$key"]="$value"
    done < "$file"

    declare -p config_values
}

# Function to connect to a Wi-Fi network using iwctl
connect_to_wifi() {
    local ssid="$1"
    local password="$2"

    if [[ -z "$ssid" || -z "$password" ]]; then
        log_error "Error: SSID and password must be provided."
        return 1
    fi

    log_info "Attempting to connect to Wi-Fi: $ssid"

    # Check for wlan0. Modify if interface is different.
    if ! ip link show wlan0 &>/dev/null; then
        log_error "Error: wlan0 interface not found."
        return 1
    fi

    # Check if already connected,
    if iwctl station wlan0 show | grep -q "Connected to:"; then
        log_info "Already connected to a network"
        iwctl station wlan0 disconnect
        sleep 5
        log_info "Disconnected from current network"
    fi

    # Connect to the Wi-Fi network
    iwctl --passphrase "$password" station wlan0 connect "$ssid"
    if [[ $? -ne 0 ]]; then
        log_error "Error: Failed to connect to Wi-Fi network: $ssid"
        return 1
    fi

    log_success "Successfully connected to Wi-Fi network: $ssid"
    return 0
}

check_internet() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connection."
        return 1
    fi
    log_success "Internet connection is available."
}

launcher() {
    # Load configuration
    config_values=$(read_config "install.conf")
    eval "$config_values"

    # Connect and check internet connection
    connect_to_wifi "${config_values["WiFi SSID"]}" "${config_values["WiFi Password"]}" || return 1
    check_internet || return 1

    git clone https://github.com/shashotoNur/sysgen.git
    cp install.conf sync_dirs.lst sysgen
    cd sysgen
    sudo bash main.sh install
}

launcher
