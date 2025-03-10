#!/bin/bash

select_usb_device() {
    USB_DEVICE=$(lsblk -dno NAME,MODEL,SIZE | grep '^sd' | fzf --prompt="Select USB device: " --height=10 --reverse | awk '{print "/dev/" $1}')
    if [[ -z "$USB_DEVICE" ]]; then
        log_error "No USB device selected. Exiting."
        exit 1
    fi
    # log_info "Selected USB device: $USB_DEVICE"
    echo "$USB_DEVICE"
}

wipe_usb_filesystems() {
    local usb_device="$1"
    log_info "Wiping existing filesystems on $usb_device..."
    wipefs --all "$usb_device"
    log_success "Filesystems wiped from $usb_device."
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

# --- Ventoy Configuration ---
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

# --- Backup Configuration ---
backup_config() {
    local storage_mount="/mnt/storage"
    local usb_device=$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')
    mkdir -p "$storage_mount"

    mount "$usb_device"3 "$storage_mount" || {
        log_error "Failed to mount storage partition"
        return 1
    }

    cp "$CONFIG_FILE" "$storage_mount/backup/sysgen/" || {
        log_error "Failed to backup config file"
        return 1
    }

    umount "$storage_mount" || {
        log_error "Failed to unmount storage partition"
        return 1
    }

    log_success "Config file backed up successfully."
}

# Function to copy backup files to disk
copy_backup_files() {
    log_info "Copying backup files to disk."
    local storage_mount="$3"
    local multiboot_mount="$2"

    if [[ -z "$multiboot_mount" || -z "$storage_mount" ]]; then
        log_error "Either the multiboot or storage mount variable is empty."
        return 1
    fi

    cp -r "$storage_mount/backup/"* ~/Backups/ || {
        log_error "Failed to copy backup files from storage to ~/Backups/."
        return 1
    }
    cp -r "$multiboot_mount/"* ~/Backups/ISOs || {
        log_error "Failed to copy backup files from multiboot to ~/Backups/ISOs."
        return 1
    }

    log_success "Backup files copied to disk successfully."
}

# Function to wipe the USB drive
wipe_usb_drive() {
    log_info "Securely wiping the USB drive."
    local usb_device="$1"
    sudo dd if=/dev/zero of="${usb_device}" bs=4M status=progress || {
        log_error "Failed to wipe USB drive with dd."
        return 1
    }
}
