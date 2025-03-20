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
