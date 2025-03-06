#!/bin/bash

###############################################################################
# Script Name: install.sh
# Description: Automates the installation of a custom Arch Linux system to a
#              specified drive, including partitioning, encryption, base system
#              installation, and setup postinstallation script.
# Author: Shashoto Nur
# Date: [Current Date]
# Version: 1.1
# License: MIT
###############################################################################

# --- Configuration ---
set -euo pipefail # Exit on error, unset variable, or pipeline failure

# --- Global Variables ---
CONFIG_FILE="install.conf"
SCRIPT_DIR="$(dirname "$0")" # Get the directory of the script

# --- Logging Functions ---
log_info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1" >&2; }
log_warning() { printf "\033[1;33m[WARNING]\033[0m %s\n" "$1" >&2; }
log_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; }
log_success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1" >&2; }
log_debug() { printf "\e[90mDEBUG:\e[0m %s\n" "$1" >&2; }

# --- Utility Functions ---

# Read configuration from install.conf
read_config() {
    local key
    declare -A config_values

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file '$CONFIG_FILE' not found. Run utils/getconfig.sh"
        return 1
    fi

    while IFS='=' read -r key value; do
        config_values["$key"]="$value"
    done < <(sed '/^#/d;s/^[[:blank:]]*//;s/[[:blank:]]*$//' "$CONFIG_FILE") #remove comments and trim whitespace

    return 0
}

# Function to handle device selection using fzf
select_drive() {
    local drive_selection

    log_info "No drive specified. Selecting a drive using fzf..."
    drive_selection=$(lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme|/dev/mmcblk" | fzf --prompt="Select a drive: " --height=10 --border --reverse | awk '{print $1}')

    if [[ -z "$drive_selection" ]]; then
        log_error "No drive selected. Exiting."
        return 1
    fi

    log_success "Selected drive: $drive_selection"
    echo "$drive_selection"
}

# Function to convert size units to bytes
unit_to_bytes() {
    local size="$1"
    local unit="${size##*[0-9]}"
    local value="${size%[a-zA-Z]*}"

    case "${unit,,}" in
    mib) echo $((value * 1024 * 1024)) ;;
    gib) echo $((value * 1024 * 1024 * 1024)) ;;
    *)
        log_error "Invalid unit '$unit' in '$size'. Use MiB or GiB."
        return 1
        ;;
    esac
}

# --- System Checks ---

check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log_error "System is not booted in UEFI mode!"
        return 1
    fi
    log_success "System booted in UEFI mode."
}

check_internet() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connection."
        return 1
    fi
    log_success "Internet connection is available."
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

# --- User and System Configuration ---

configure_system() {
    local root_password="${CONFIG_VALUES["Root Password"]}"
    local username="${CONFIG_VALUES["Username"]}"
    local hostname="${CONFIG_VALUES["Hostname"]}"

    # Chroot and configure the system
    log_info "Entering chroot environment..."
    arch-chroot /mnt bash -c "
        # Set root password
        echo 'root:$root_password' | chpasswd;
        # Create user
        useradd -m -G wheel -s /bin/zsh '$username';
        # Add user to sudoers
        sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD ALL/%wheel ALL=(ALL:ALL) NOPASSWD ALL/' /etc/sudoers;
        # Set hostname
        echo '$hostname' > /etc/hostname;
        # Configure /etc/hosts
        cat <<EOF > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $hostname
EOF
        # Configure locale (example)
        echo 'LANG=en_US.UTF-8' > /etc/locale.conf;
        echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen;
        locale-gen;
        # Set timezone and sync hardware clock
        ln -sf /usr/share/zoneinfo/Asia/Dhaka /etc/localtime;
        hwclock --systohc;
        # Install grub
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB;

    " || {
        log_error "Failed to configure system within chroot"
        return 1
    }
    log_success "System configured successfully."

}

# ---  Keyfile Management ---

manage_keyfiles() {
    local usb_device=$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')
    local usb_mount="/mnt/usbkey"
    local key_file="luks-root.key"
    local keyfile_path="$usb_mount/$key_file"
    local luks_device="${CONFIG_VALUES["Drive"]}2"
    local luks_password="${CONFIG_VALUES["LUKS Password"]}"

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

# --- Mirror Configuration ---

update_mirrors() {
    log_info "Updating mirrorlist..."
    reflector --verbose --country India,China,Japan,Singapore,US --protocol https --sort rate --latest 20 --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist || {
        log_error "Failed to update mirrorlist"
        return 1
    }
    log_success "Mirrorlist updated successfully."
}

# --- Install GRUB ---

install_grub() {
    local luks_uuid=$(blkid -s UUID -o value "${CONFIG_VALUES["Drive"]}2")
    local usb_uuid=$(blkid -s UUID -o value $(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')3)
    local key_file="luks-root.key"

    log_info "Installing GRUB bootloader..."
    arch-chroot /mnt bash -c "
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB;
        # Update GRUB config
        sed -i \"s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$luks_uuid:cryptroot cryptkey=UUID=$usb_uuid:btrfs:/mnt/$key_file root=\/dev\/mapper\/cryptroot\"|g\" /etc/default/grub;
        grub-mkconfig -o /boot/grub/grub.cfg;
        cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI;
    " || {
        log_error "Failed to install GRUB"
        return 1
    }
    log_success "GRUB installed successfully."
}

# --- postinstallation Script Execution ---

execute_post_install() {
    local username="$username"
    log_info "Creating a postinstall script runner..."
    BASHRC="/mnt/home/$username/.bashrc"

    # Create the target script
    echo -e "# Launch the post install script\nsudo bash /home/$username/Scratch/sysgen/main.sh postinstall\nsudo mv /home/$username/Scratch/sysgen/main.sh /home/$username/Scratch/sysgen/main.sh.done\n\n# Remove self (to avoid running more than once)\nsudo rm \"$BASHRC\"\n\necho \"Bye bye!\"\npoweroff" >"$BASHRC" || {
        log_error "Failed to create post-install runner in $BASHRC"
        return 1
    }

    log_warning "postinstall script is configured to run on shell initialization."
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

################################################################################################
# Main Installation Function
################################################################################################

install() {
    set -e # Exit on error

    # Check UEFI mode and internet connectivity
    check_uefi || return 1
    read_config || return 1
    check_internet || return 1
    # Select drive if not specified in config
    if [[ "${CONFIG_VALUES["Drive"]}" == "/dev/" || -z "${CONFIG_VALUES["Drive"]}" ]]; then
        CONFIG_VALUES["Drive"]=$(select_drive) || return 1
    fi

    # Wipe the selected drive
    log_info "Wiping ${CONFIG_VALUES["Drive"]}..."
    wipefs --all --force "${CONFIG_VALUES["Drive"]}" || log_error "Failed to wipe drive" && return 1
    log_success "Drive wiped successfully."

    # Partition and format the disk
    partition_disk "${CONFIG_VALUES["Drive"]}" "${CONFIG_VALUES[@]}" || return 1
    format_partitions || return 1

    # Encrypt partitions
    encrypt_partition "${CONFIG_VALUES["Drive"]}2" "${CONFIG_VALUES["LUKS Password"]}" "cryptroot" || return 1
    encrypt_partition "${CONFIG_VALUES["Drive"]}4" "${CONFIG_VALUES["LUKS Password"]}" "crypthome" || return 1

    # Create Btrfs subvolumes
    create_btrfs_subvolumes || return 1

    # Mount partitions
    mount_partitions || return 1

    # Install base system and generate fstab.
    install_base_system || return 1
    generate_fstab || return 1

    # Manage Keyfiles on USB
    manage_keyfiles || return 1

    # Update mirrors before chroot.
    update_mirrors || return 1

    #Configure the system inside the chroot
    configure_system || return 1

    # Install GRUB after system configuration within chroot.
    install_grub || return 1

    # Execute postinstallation tasks.
    execute_post_install

    # Backup config after all operations are completed.
    backup_config || return 1

    log_success "Installation completed successfully."
    reboot
}

################################################################################################
# --- Main Script Execution ---

install
