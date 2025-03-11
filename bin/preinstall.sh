#!/bin/bash

###############################################################################
# Script Name: preinstall.sh
# Description: Prepares a USB drive for system installation, including ISO
#              creation, Ventoy setup, data backup, and configuration.
# Author: Shashoto Nur

# Version: 1.1
# License: MIT
###############################################################################

preinstall() {
    # --- Source files ---
    while IFS= read -r -d '' script; do
        source "$script"
    done < <(find lib/ -type f -name "*.sh" -print0)

    local user="$1"
    check_command_availability ventoy tmux mkarchiso fzf mkfs.vfat mkfs.btrfs

    # Setup required variables
    local script_dir="sysgen"
    local data_dir="./backup/data"
    local config_file="install.conf"
    local gpg_passphrase=""
    local storage_size_mb=""
    local multiboot_size_mb=""
    local storage_mount="/mnt/storage"
    local multiboot_mount="/mnt/multiboot"
    local config_values

    # Get initial user input and data
    log_info "Listing available USB devices..."
    local usb_device=$(select_usb_device)
    confirm_data_wipe "$usb_device"

    log_info "Prompting for GPG key export passphrase..."
    read -rsp "Enter passphrase for GPG key export: " gpg_passphrase

    backup_user_data "$user"
    get_installation_configuration

    declare -A config_values
    for key in "Local Installation"; do
        config_values["$key"]=$(extract_value "$key")
    done

    get_mega_sync_directories "$user"
    unmount_usb_partitions "$usb_device"
    wipe_usb_filesystems "$usb_device"

    local partition_sizes="$(calculate_partition_sizes "$usb_device")"
    storage_size_mb=$(echo "$partition_sizes" | awk '{print $1}')
    multiboot_size_mb=$(echo "$partition_sizes" | awk '{print $2}')

    backup_configurations "$user"
    setup_tmux_session "$usb_device" "$storage_size_mb" "$gpg_passphrase"
    create_partitions "$usb_device" "$multiboot_size_mb"
    format_storage_partition "$usb_device"
    mount_usb_partitions "$usb_device"
    copy_files_to_usb
    clean_up
    configure_ventoy

    check_local_installation "${config_values["Local Installation"]}"
    log_success "Preinstallation script completed."
}
