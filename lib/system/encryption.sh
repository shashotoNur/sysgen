#!/bin/bash

# --- Encryption Functions ---
encrypt_partition() {
    local partition="$1"
    local password="$2"
    local mapper_name="$3"

    log_info "Encrypting partition $partition with LUKS..."
    echo -n "$password" | cryptsetup luksFormat "$partition" || {
        log_error "Failed to encrypt partition $partition"
        return 1
    }
    echo -n "$password" | cryptsetup open "$partition" "$mapper_name" || {
        log_error "Failed to open encrypted partition $partition"
        return 1
    }
    log_success "Partition $partition encrypted successfully."
}

# ---  Keyfile Management ---
manage_keyfiles() {
    local usb_device=$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')
    local usb_mount="/mnt/usbkey"
    local key_file="luks-root.key"
    local keyfile_path="$usb_mount/$key_file"
    local luks_device="${1}2"
    local luks_password="$2"

    mkdir -p "$usb_mount"

    mount "$usb_device"3 "$usb_mount" || {
        log_error "Failed to mount USB drive"
        return 1
    }

    #Generate a secure keyfile on USB.
    log_info "Creating keyfile on USB..."
    dd if=/dev/urandom of="$keyfile_path" bs=512 count=4
    chmod 600 "$keyfile_path" || {
        log_error "Failed to create keyfile"
        return 1
    }

    # Add keyfile to root LUKS partition
    log_info "Adding keyfile to LUKS..."
    echo -n "$luks_password" | cryptsetup luksAddKey "$luks_device" "$keyfile_path" || {
        log_error "Failed to add keyfile to LUKS"
        return 1
    }

    umount "$usb_mount" || {
        log_error "Failed to unmount USB drive"
        return 1
    }
    log_success "Keyfile management completed successfully."
}

# Function to remove the cryptkey parameter and delete the LUKS key slot
remove_cryptkey_and_delete_slot() {
    log_info "Removing cryptkey boot parameter and deleting LUKS key slot."

    local drive=$(extract_config_value "Drive")

    sudo sed -i 's/ cryptkey=UUID=[^ ]*\( \|"\)/\1/g' /etc/default/grub || {
        log_error "Failed to remove cryptkey parameter from GRUB configuration."
        return 1
    }

    local second_slot=1
    sudo cryptsetup luksKillSlot "${drive}2" "$second_slot" || {
        log_error "Failed to delete LUKS key slot."
        return 1
    }

    log_success "Cryptkey parameter removed and LUKS key slot deleted successfully."
}
