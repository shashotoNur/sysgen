#!/bin/bash

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

# --- Partitioning and Formatting ---
partition_disk() {
    local drive="$1"
    local config_values="$2"

    # Check if drive is specified and exists.
    if [[ -z "$drive" || ! -b "$drive" ]]; then
        log_error "Invalid or missing drive specified: $drive"
        return 1
    fi

    # Create GPT partition table
    log_info "Creating GPT partition table on $drive..."
    parted -s "$drive" mklabel gpt || log_error "Failed to create GPT partition table" && return 1

    local partition_num=1
    local start_sector=1

    # Function to create a single partition
    create_partition() {
        local drive="$1"
        local part_num="$2"
        local fs_type="$3"
        local size_bytes="$4"
        local flags="$5"

        local start_sector=$((start_sector))
        local end_sector=$((start_sector + size_bytes - 1))

        log_info "Creating partition $part_num ($fs_type) on $drive ($start_sector - $end_sector)"

        parted -s "$drive" mkpart primary "$fs_type" "$start_sector" "$end_sector" || {
            log_error "Failed to create partition $part_num"
            return 1
        }
        if [[ -n "$flags" ]]; then
            log_debug "Setting flags: $flags"
            parted -s "$drive" set "$part_num" "$flags" on || {
                log_error "Failed to set flags on partition $part_num"
                return 1
            }
        fi
        start_sector=$((start_sector + size_bytes))

        log_success "Partition $part_num created successfully."
    }

    #Partitions sizes from config
    local boot_size_bytes=$(unit_to_bytes "${config_values["Boot Partition"]}")
    local root_size_bytes=$(unit_to_bytes "${config_values["Root Partition"]}")
    local swap_size_bytes=$(unit_to_bytes "${config_values["Swap Partition"]}")
    local home_size_bytes=$(unit_to_bytes "${config_values["Home Partition"]}")

    # Create Partitions
    create_partition "$drive" "$partition_num" fat32 "$boot_size_bytes" esp || return 1
    partition_num=$((partition_num + 1))
    create_partition "$drive" "$partition_num" btrfs "$root_size_bytes" || return 1
    partition_num=$((partition_num + 1))

    if ((swap_size_bytes > 0)); then
        create_partition "$drive" "$partition_num" linux-swap "$swap_size_bytes" || return 1
        partition_num=$((partition_num + 1))
    fi
    create_partition "$drive" "$partition_num" btrfs "$home_size_bytes" || return 1

    log_success "Partitions created successfully."
}

# Function to format partitions
format_partitions() {
    local drive="${CONFIG_VALUES["Drive"]}"
    local boot_part="$drive"1
    local root_part="$drive"2
    local swap_part="$drive"3
    local home_part="$drive"4

    #Format Partitions
    log_info "Formatting partitions..."
    mkfs.fat -F32 "$boot_part" -n BOOT || log_error "Failed to format boot partition" && return 1
    mkfs.btrfs -f "$root_part" -L ROOT || log_error "Failed to format root partition" && return 1
    mkfs.btrfs -f "$home_part" -L HOME || log_error "Failed to format home partition" && return 1

    if [[ "${CONFIG_VALUES["Swap Partition"]}" != "0" ]]; then
        mkswap "$swap_part" -L SWAP || log_error "Failed to format swap partition" && return 1
        swapon "$swap_part" || log_error "Failed to activate swap partition" && return 1
    fi

    log_success "Partitions formatted successfully."
}
