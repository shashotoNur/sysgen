#!/bin/bash

###############################################################################
# Script Name: install.sh
# Description: Automates the installation of a custom Arch Linux system to a
#              specified drive, including partitioning, encryption, base system
#              installation, and setup postinstallation script.
# Author: Shashoto Nur

# Version: 1.1
# License: MIT
###############################################################################

install() {
    check_uefi || return 1

    # Load configuration
    config_values=$(read_config "install.conf")
    eval "$config_values"

    # Handle LUKS and Root passwords
    if [[ -v config_values["Password"] ]]; then
        PASSWORD=${config_values["Password"]}
        config_values["LUKS Password"]=$PASSWORD
        config_values["Root Password"]=$PASSWORD
    fi

    # connect_to_wifi "${config_values["WiFi SSID"]}" "${config_values["WiFi Password"]}" || return 1
    check_internet || return 1

    if [[ "${config_values["Drive"]}" == "/dev/" || -z "${config_values["Drive"]}" ]]; then
        config_values["Drive"]=$(select_drive) || return 1
    fi

    log_info "Wiping ${config_values["Drive"]}..."
    exit
    wipefs --all --force "${config_values["Drive"]}" || log_error "Failed to wipe drive" && return 1
    log_success "Drive wiped successfully."

    partition_disk "${config_values["Drive"]}" "${config_values[@]}" || return 1
    format_partitions "$config_values["Drive"]" "$config_values["Swap Partition"]" || return 1

    encrypt_partition "${config_values["Drive"]}2" "${config_values["LUKS Password"]}" "cryptroot" || return 1
    encrypt_partition "${config_values["Drive"]}4" "${config_values["LUKS Password"]}" "crypthome" || return 1

    create_btrfs_subvolumes || return 1
    mount_partitions "${config_values["Drive"]}" || return 1

    update_mirrors || return 1
    install_base_system || return 1

    generate_fstab || return 1
    local usb_device=$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')
    manage_keyfiles "${config_values["LUKS Password"]}" "$config_values["Drive"]4" "$config_values["Drive"]2" "$usb_device" || return 1

    configure_system "${config_values["Root Password"]}" "${config_values["Username"]}" "${config_values["Hostname"]}" || return 1
    install_grub "$config_values["Drive"]" || return 1
    ensure_auto_login "${config_values["Username"]}" || return 1
    execute_post_install
    backup_config || return 1

    log_success "Installation completed successfully."
    reboot
}
