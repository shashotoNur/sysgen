#!/bin/bash

# Function to unmount the USB drive
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

mount_partitions() {
    local storage_mount="/mnt/storage"
    local multiboot_mount="/mnt/multiboot"

    mkdir -p "$storage_mount" "$multiboot_mount"
    log_info "Mounting partitions..."
    mount "${1}3" "$storage_mount"
    mount "${1}1" "$multiboot_mount"

    log_success "Partitions mounted."
}

# ---  Btrfs Subvolume Creation ---
create_btrfs_subvolumes() {
    local root_mount="/mnt"
    local home_mount="$root_mount/home"

    log_info "Creating Btrfs subvolumes..."
    mkdir -p "$root_mount" "$home_mount" || {
        log_error "Failed to create mount points"
        return 1
    }

    mount "/dev/mapper/cryptroot" "$root_mount" || {
        log_error "Failed to mount root partition"
        return 1
    }
    mount "/dev/mapper/crypthome" "$home_mount" || {
        log_error "Failed to mount home partition"
        return 1
    }

    btrfs subvolume create "$root_mount/@"
    btrfs subvolume create "$home_mount/@home" || {
        log_error "Failed to create Btrfs subvolumes"
        return 1
    }

    umount "$home_mount" && umount "$root_mount" || {
        log_error "Failed to unmount partitions"
        return 1
    }

    log_success "Btrfs subvolumes created successfully."
}

# --- Mount Functions ---
mount_partitions() {
    local root_mount="/mnt"
    local home_mount="$root_mount/home"
    local boot_mount="$root_mount/boot/efi"

    log_info "Mounting partitions..."
    mkdir -p "$home_mount" "$boot_mount" || {
        log_error "Failed to create mount points"
        return 1
    }

    mount -o compress=zstd,subvol=@ "/dev/mapper/cryptroot" "$root_mount" || {
        log_error "Failed to mount root partition"
        return 1
    }
    mount -o compress=zstd,subvol=@home "/dev/mapper/crypthome" "$home_mount" || {
        log_error "Failed to mount home partition"
        return 1
    }
    mount "${CONFIG_VALUES["Drive"]}1" "$boot_mount" || {
        log_error "Failed to mount boot partition"
        return 1
    }

    log_success "Partitions mounted successfully."
}

# Function to mount the USB drive
mount_usb_drive() {
    log_info "Mounting USB Drive"
    local usb_device=$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')
    local multiboot_mount="/mnt/multiboot"
    local storage_mount="/mnt/storage"

    log_debug "Detected USB device: $usb_device"

    if [[ -z "$usb_device" ]]; then
        log_error "No USB Device found"
        return 1
    fi

    sudo mkdir -p "$multiboot_mount"
    sudo mkdir -p "$storage_mount"

    sudo mount "${usb_device}1" "$multiboot_mount" || {
        log_error "Failed to mount ${usb_device}1 to $multiboot_mount."
        return 1
    }

    sudo mount "${usb_device}3" "$storage_mount" || {
        log_error "Failed to mount ${usb_device}3 to $storage_mount."
        return 1
    }

    log_success "USB drive mounted successfully."
    echo "$usb_device" "$multiboot_mount" "$storage_mount"
}
