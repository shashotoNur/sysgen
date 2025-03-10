#!/bin/bash

# Function to establish an internet connection
setup_internet_connection() {
    log_info "Setting up Internet Connection"

    #Check if networkmanager is available.
    if ! command_exists nmcli; then
        log_error "nmcli is not installed. Please install NetworkManager."
        return 1
    fi

    local wifi_ssid=$(extract_config_value "WiFi SSID")
    local wifi_password=$(extract_config_value "WiFi Password")

    log_debug "Connecting to WiFi: SSID=$wifi_ssid"

    sudo systemctl enable --now NetworkManager.service || {
        log_error "Failed to enable and start NetworkManager service."
        return 1
    }

    nmcli device wifi connect "$wifi_ssid" password "$wifi_password" || {
        log_error "Failed to connect to WiFi: $wifi_ssid."
        return 1
    }

    log_success "Internet connection established."
}

# --- Network Configuration ---
configure_network() {
    log_info "Configuring network..."
    sudo pacman -S --needed --noconfirm resolvconf nm-connection-editor networkmanager-openvpn || {
        log_error "Failed to install network packages."
        return 1
    }

    sudo systemctl enable systemd-resolved.service
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    sudo systemctl enable --now wpa_supplicant.service

    log_success "Network configured successfully."
}

check_internet() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connection."
        return 1
    fi
    log_success "Internet connection is available."
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
