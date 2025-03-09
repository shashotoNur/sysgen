#!/bin/bash

# --- Base System Installation ---
install_base_system() {
    log_info "Installing base system..."
    pacstrap "/mnt" base base-devel linux linux-headers linux-lts linux-lts-headers linux-firmware nano vim networkmanager iw wpa_supplicant dialog zsh || {
        log_error "Failed to install base system"
        return 1
    }
    log_success "Base system installed successfully."
}

generate_fstab() {
    log_info "Generating fstab..."
    genfstab -U /mnt >>/mnt/etc/fstab || {
        log_error "Failed to generate fstab"
        return 1
    }
    log_success "fstab generated successfully."
}

# --- User Password Setup ---
set_user_password() {
    local username="$1"
    local root_password="$2"
    log_info "Setting user password..."
    echo "$username:$root_password" | sudo chpasswd || {
        log_error "Failed to set user password."
        return 1
    }
    log_success "User password set."
}
