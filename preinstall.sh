#!/bin/bash

###############################################################################
# Script Name: preinstall.sh
# Description: Prepares a USB drive for system installation, including ISO
#              creation, Ventoy setup, data backup, and configuration.
# Author: Shashoto Nur
# Date: [Current Date]
# Version: 1.1
# License: MIT
###############################################################################

# --- Configuration ---
set -euo pipefail # Exit on error, unset variable, or pipeline failure

# --- Logging Functions ---

log_info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1" >&2; }
log_warning() { printf "\033[1;33m[WARNING]\033[0m %s\n" "$1" >&2; }
log_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; }
log_success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1" >&2; }
log_debug() { printf "\e[90mDEBUG:\e[0m %s\n" "$1" >&2; }

# --- Functions ---

check_command_availability() {
    local commands=("$@")
    log_info "Checking command availability: ${commands[@]}"
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "'$cmd' is not installed. Please install it and try again."
            return 1
        fi
    done
    log_success "All required commands are available."
    return 0
}

select_usb_device() {
    USB_DEVICE=$(lsblk -dno NAME,MODEL,SIZE | grep '^sd' | fzf --prompt="Select USB device: " --height=10 --reverse | awk '{print "/dev/" $1}')
    if [[ -z "$USB_DEVICE" ]]; then
        log_error "No USB device selected. Exiting."
        exit 1
    fi
    # log_info "Selected USB device: $USB_DEVICE"
    echo "$USB_DEVICE"
}

confirm_data_wipe() {
    local device="$1"
    log_warning "WARNING: This will completely erase all data on $device!"
    read -rp "Are you sure you want to continue? (y/N): " confirm
    if [[ "$confirm" != "y" ]]; then
        log_info "Aborted by user."
        exit 1
    fi
    log_info "User confirmed data wipe."
}

backup_user_data() {
    local user="$1"
    local data_dir="./backup/data"
    local selected_file="./fzf_selected"
    local size_file="./fzf_total"
    log_info "Starting data backup process..."

    mkdir -p "$data_dir"
    >"$selected_file"
    >"$size_file"

    log_info "Prompting for files and directories to backup..."
    SELECTED_ITEMS=$(
        find /home/"$user" -mindepth 1 -maxdepth 5 | fzf --multi --preview 'du -sh {}' \
            --bind "tab:execute-silent(
            grep -Fxq {} "$selected_file" && sed -i '\|^{}$|d' "$selected_file" || echo {} >> "$selected_file";
            xargs -d '\n' du -ch 2>/dev/null < "$selected_file" | grep total$ | sed 's/total\s*/<-Total size /' > "$size_file"
        )+toggle" \
            --preview 'cat ./fzf_total'
    )

    rm "$selected_file" "$size_file"

    if [[ -z "$SELECTED_ITEMS" ]]; then
        log_info "No files or directories selected for backup."
    else
        log_info "Copying selected files to backup directory..."
        mkdir -p "$data_dir"
        cp -r --parents $(printf '%s\n' "${SELECTED_ITEMS[@]}") "$data_dir"

        log_info "Total size of selected items: \"$(du -sh $data_dir)\""
        log_success "Backup complete!"
    fi
}

get_installation_configuration() {
    log_info "\nGetting installation configuration..."
    bash utils/getconfig.sh
    log_success "Installation configuration retrieved."
}

extract_value() {
    grep -E "^$1:" "$config_file" | awk -F': ' '{print $2}'
}

get_mega_sync_directories() {
    local user="$1"
    log_info "Prompting for MEGA sync directories (if any)..."
    read -rp "Do you want to select directories to backup your MEGA sync data? (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        log_info "Select the directories you want to sync on MEGA."
        find /home/"$user" -type d -print0 | fzf --read0 --print0 --multi >sync_dirs.lst
        log_success "MEGA sync directories selected."
    else
        log_info "MEGA sync backup selection skipped."
    fi
}

unmount_usb_partitions() {
    local usb_device="$1"
    log_info "Checking for mounted partitions on $usb_device..."
    local mounted_partitions=$(mount | grep "^$usb_device" | awk '{print $1}')

    if [[ -n "$mounted_partitions" ]]; then
        log_info "Unmounting partitions on $usb_device..."
        for partition in $mounted_partitions; do
            sudo umount -l "$partition" || sudo umount -f "$partition"
            log_info "Unmounted: $partition"
        done
        log_success "All partitions unmounted from $usb_device."
    else
        log_info "$usb_device is not mounted."
    fi
}

wipe_usb_filesystems() {
    local usb_device="$1"
    log_info "Wiping existing filesystems on $usb_device..."
    wipefs --all "$usb_device"
    log_success "Filesystems wiped from $usb_device."
}

calculate_partition_sizes() {
    local usb_device="$1"
    log_info "Calculating partition sizes for $usb_device..."
    local total_size_gb=$(lsblk -b -n -o SIZE "$usb_device" | awk '{print $1/1024/1024/1024}')
    local total_size_mb=$(lsblk -b -n -o SIZE "$usb_device" | awk '{print $1/1024/1024}')
    local total_size_gb_int=${total_size_gb%.*} # Remove decimals
    log_info "Detected USB Size: ${total_size_gb_int}GB"

    while true; do
        read -rp "Enter storage partition size (in GB, max: ${total_size_gb_int}): " storage_size_gb
        if [[ "$storage_size_gb" =~ ^[0-9]+$ ]] && [[ "$storage_size_gb" -gt 0 ]] && [[ "$storage_size_gb" -lt "$total_size_gb_int" ]]; then
            break
        else
            log_error "Invalid input. Please enter a valid number between 1 and ${total_size_gb_int}."
        fi
    done

    local storage_size_mb=$((storage_size_gb * 1024))
    local multiboot_size_mb=$((total_size_mb - storage_size_mb))

    log_info "Storage Partition: ${storage_size_gb}GB (${storage_size_mb}MB)"
    log_info "Multiboot Partition: $((total_size_gb_int - storage_size_gb))GB (${multiboot_size_mb}MB)"
    echo "$storage_size_mb $multiboot_size_mb"
}

backup_configurations() {
    local user=$1
    log_info "Backing up configurations..."
    mkdir -p ./backup/code
    sudo -u "$user" code --list-extensions >./backup/code/ext.lst
    sudo cp "/home/$user/.config/Code - OSS/User/settings.json" ./backup/code/
    log_info "VS Code configurations backed up."

    mkdir -p ./backup/dolphin
    cp /home/$user/.local/share/kxmlgui5/dolphin/dolphinui.rc ./backup/dolphin
    cp /home/$user/.config/dolphinrc ./backup/dolphin/
    log_info "Dolphin configurations backed up."

    mkdir -p ./backup/zsh/
    cp /home/$user/.zshrc ./backup/zsh/
    log_info "Zsh configurations backed up."

    mkdir -p ./backup/timeshift
    cp /etc/timeshift/timeshift.json ./backup/timeshift/
    log_info "Timeshift configurations backed up."

    mkdir -p ./backup/sysgen
    cp -r ./*.sh ./*.conf ./*.lst ./utils/ ./backup/sysgen/
    log_info "Sysgen scripts and configurations backed up."

    log_success "All configurations backed up."
}

setup_tmux_session() {
    local data_dir="./backup/data"
    local script_dir="sysgen"

    # Start a new tmux session for parallel jobs
    session_name="sysgen"
    log_info "Starting a new tmux session: $session_name..."
    tmux new-session -d -s "$session_name"

    # Pane 1: Build a modified version of the Arch ISO
    tmux send-keys -t "$session_name" "echo 'Cloning ArchISO and building.'; sudo bash utils/buildiso.sh . && exit" C-m

    # Pane 2: Install Ventoy on multiboot partition
    tmux split-window -h -t "$session_name"
    tmux send-keys -t "$session_name" "echo 'Setting up Ventoy on $1...'; yes | sudo ventoy -L MULTIBOOT -r $2 -I $1 && exit" C-m

    # Pane 3: Export GPG keys
    if [[ -n "$3" ]]; then
        tmux split-window -v -t "$session_name"
        tmux send-keys -t "$session_name" "echo 'Exporting GPG keys...'; gpg --export-secret-keys --pinentry-mode loopback --passphrase '$3' > private.asc && gpg --export --armor > public.asc && exit" C-m
    fi

    log_success "Tmux session '$session_name' created and configured."

    # Attach to the tmux session and wait for user to close panes
    log_info "Attaching to tmux session..."
    tmux attach-session -t "$session_name"
}

create_partitions() {
    log_info "Creating storage partition..."
    parted -s "$1" mkpart primary btrfs "${2}MiB" 100%

    if [[ -z "${1}3" ]]; then
        log_error "Could not detect the storage partition."
        exit 1
    fi
    log_success "Storage partition created"

}

format_storage_partition() {
    log_info "Formatting ${1}3 as Btrfs (STORAGE)..."
    mkfs.btrfs -f -L STORAGE "${1}3"
    log_success "Storage partition formatted as btrfs."
}

mount_partitions() {
    local storage_mount="/mnt/storage"
    local multiboot_mount="/mnt/multiboot"

    mkdir -p "$storage_mount" "$multiboot_mount"
    log_info "Mounting partitions..."
    mount "${1}3" "$storage_mount"
    mount "${1}1" "$multiboot_mount"

    log_success "Partitions mounted."
}

copy_files_to_usb() {
    local storage_mount="/mnt/storage"
    local multiboot_mount="/mnt/multiboot"

    log_info "Copying the arch iso to the USB drive..."
    cp iso/sysgen_archlinux.iso "$multiboot_mount"

    log_info "Copying backup to the USB drive..."
    cp -r backup "$storage_mount"

    log_success "Files copied to the USB device."
}

clean_up() {
    log_info "Cleaning up temporary files..."
    sudo rm -rf archiso iso work out backup sysgen ./*.lst ./*.conf
    log_success "Temporary files cleaned up."
}

configure_ventoy() {
    log_info "Configuring Ventoy..."
    local multiboot_mount="/mnt/multiboot"

    # Create Ventoy config directory if it doesn't exist
    mkdir -p "$multiboot_mount/ventoy"

    echo '{
        "control": [
            { "VTOY_MENU_TIMEOUT": "0" },
            { "VTOY_SECONDARY_TIMEOUT": "0" }
        ]
    }' | sudo tee "$multiboot_mount/ventoy/ventoy.json"
    log_info "Ventoy is configured to boot the first ISO in normal mode automatically!"

    log_success "Ventoy configured."
}

check_local_installation() {
    local storage_mount="/mnt/storage"
    local multiboot_mount="/mnt/multiboot"

    log_info "Checking for local installation..."
    if [[ "${1}" == "y" ]]; then
        # Get the boot number for EFI USB Device
        local usb_boot_num=$(efibootmgr | awk '/EFI USB Device/ {gsub("[^0-9]", "", $1); print $1}')

        # Check if a USB boot entry was found
        if [[ -z "$usb_boot_num" ]]; then
            log_error "No EFI USB Device found in efibootmgr output. You would have to manually boot into the USB Device."
            log_success "Preinstallation script completed."
            systemctl reboot --firmware-setup
        fi

        log_info "Found EFI USB Device with Boot Number: $usb_boot_num"

        # Set the USB device as the next boot option
        sudo efibootmgr --bootnext "$usb_boot_num"
        log_success "Preinstallation script completed."
        systemctl reboot
    else
        # Unmount the partitions
        log_info "Unmounting the storage and multiboot partitions..."
        sudo umount "$storage_mount" || sudo umount -f "$storage_mount"
        sudo umount "$multiboot_mount" || sudo umount -f "$multiboot_mount"

        log_success "You may unplug the USB drive and proceed with the installation..."
    fi
}

################################################################################################
# Main Preinstallation Function
################################################################################################

preinstall() {
    local user="$1"
    # Check command availability
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
    mount_partitions "$usb_device"
    copy_files_to_usb
    clean_up
    configure_ventoy

    check_local_installation "${config_values["Local Installation"]}"
    log_success "Preinstallation script completed."
}
################################################################################################
# --- Main Script Execution ---

preinstall "$1"
