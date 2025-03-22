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

# Function to manage keyfiles for automatic unlocking of root and home partitions
manage_keyfiles() {
    local root_password="$1"
    local home_partition="$2"
    local root_partition="$3"
    local usb_device="$4"
    local usb_mount="/mnt/usbkey"
    local key_file="luks-root.key"
    local keyfile_path="$usb_mount/$key_file"

    # --- Home Partition Keyfile Setup ---

    log_info "Creating key file for home partition..."
    dd if=/dev/urandom of="/mnt/root/home.key" bs=512 count=4 || {
        log_error "Failed to create key file for home partition."
        return 1
    }
    chmod 600 "/mnt/root/home.key" || {
        log_error "Failed to set permissions on home key file."
        return 1
    }

    log_info "Adding key file to home partition..."
    echo -n "$root_password" | cryptsetup luksAddKey "$home_partition" "/mnt/root/home.key" || {
        log_error "Failed to add key file to home partition."
        return 1
    }

    log_info "Configuring home partition to be unlocked by initramfs using the key file..."
    echo "crypthome  UUID=$(blkid -s UUID -o value "$home_partition")  /root/home.key  luks" >>/mnt/etc/crypttab || {
        log_error "Failed to add entry to crypttab for home partition."
        return 1
    }

    log_info "Adding key file to initramfs..."
    sed -i '/^FILES=/ s/)/ \/root\/home.key)/' /mnt/etc/mkinitcpio.conf || {
        log_error "Failed to add key file to initramfs configuration."
        return 1
    }

    log_info "Updating mkinitcpio hooks..."
    sed -i '/^HOOKS=/ s/\bfilesystems\b/plymouth encrypt btrfs/' /mnt/etc/mkinitcpio.conf || {
        log_error "Failed to update mkinitcpio hooks."
        return 1
    }
    mkinitcpio -P || {
        log_error "Failed to regenerate initramfs."
        return 1
    }

    # --- Root Partition Keyfile Setup ---

    log_info "Configuring autoboot via passkey for root decryption..."

    # Check if USB device is provided
    if [[ -z "$usb_device" ]]; then
        log_error "Error: USB device not provided."
        return 1
    fi

    # Check for existing partitions on the USB.
    if ! lsblk -o NAME,TYPE,RM | grep -q "$usb_device"; then
        log_error "Error: USB device partition not found. Please check the provided USB device name"
        return 1
    fi

    local usb_device_partition="${usb_device}3"
    # Check if there is 3rd partition on the device
    if ! lsblk -o NAME,TYPE,RM | grep -q "$usb_device_partition"; then
        log_error "Error: USB device partition not found. Please check the provided USB device name"
        return 1
    fi

    # Create a mount point for the USB if it doesn't exist
    mkdir -p "$usb_mount" || {
        log_error "Failed to create USB mount point."
        return 1
    }

    # Mount the USB drive
    log_info "Mounting USB drive..."
    mount "$usb_device_partition" "$usb_mount" || {
        log_error "Failed to mount USB drive."
        return 1
    }

    # Generate a secure keyfile on USB.
    log_info "Creating keyfile on USB..."
    dd if=/dev/urandom of="$keyfile_path" bs=512 count=4 || {
        log_error "Failed to create keyfile on USB."
        umount "$usb_mount"
        return 1
    }
    chmod 600 "$keyfile_path" || {
        log_error "Failed to set permissions on keyfile on USB."
        umount "$usb_mount"
        return 1
    }

    # Add keyfile to root LUKS partition
    log_info "Adding keyfile to LUKS..."
    echo -n "$root_password" | cryptsetup luksAddKey "$root_partition" "$keyfile_path" || {
        log_error "Failed to add keyfile to LUKS on root partition."
        umount "$usb_mount"
        return 1
    }

    # Unmount the USB drive
    log_info "Unmounting USB drive..."
    umount "$usb_mount" || {
        log_error "Failed to unmount USB drive."
        return 1
    }

    log_success "Keyfile management completed successfully."
    return 0
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
