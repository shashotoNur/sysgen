#!/bin/bash

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

extract_value() {
    grep -E "^$1:" "$config_file" | awk -F': ' '{print $2}'
}

# Function to check if a command is available
command_exists() {
    command -v "$1" &>/dev/null
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

setup_tmux_session() {
    local data_dir="./backup/data"
    local script_dir="sysgen"

    # Start a new tmux session for parallel jobs
    session_name="sysgen"
    log_info "Starting a new tmux session: $session_name..."
    tmux new-session -d -s "$session_name"

    # Pane 1: Build a modified version of the Arch ISO
    tmux send-keys -t "$session_name" "echo 'Cloning ArchISO and building.'; source ./source.sh && source_lib_files ../lib/ && build_custom_arch_iso . && exit" C-m

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

clean_up() {
    log_info "Cleaning up temporary files..."
    sudo rm -rf archiso iso work out backup sysgen ./*.lst ./*.conf
    log_success "Temporary files cleaned up."
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

# --- System Checks ---
check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log_error "System is not booted in UEFI mode!"
        return 1
    fi
    log_success "System booted in UEFI mode."
}

# --- Postinstallation Script Execution ---
execute_post_install() {
    local username="$username"
    log_info "Creating a postinstall script runner..."
    PROFILE="/mnt/home/$username/.bash_profile"

    # Create the target script
    echo -e "# Launch the post install script\nsudo bash /home/$username/Scratch/sysgen/main.sh postinstall\nsudo mv /home/$username/Scratch/sysgen/main.sh /home/$username/Scratch/sysgen/main.sh.done\n\n# Remove self (to avoid running more than once)\nsudo rm \"$PROFILE\"\n\necho \"Bye bye!\"\npoweroff" >"$PROFILE" || {
        log_error "Failed to create post-install runner in $PROFILE"
        return 1
    }

    log_warning "postinstall script is configured to run on shell initialization."
}

# --- System Information Logging ---
log_system_info() {
    log_info "Logging system information..."
    mkdir -p ~/Logs || {
        log_error "Could not create log directory"
        return 1
    }
    systemd-analyze plot >~/Logs/boot.svg || log_warning "Failed to plot boot analysis."
    sudo systemd-analyze blame >~/Logs/blame.txt || log_warning "Failed to log boot blame."
    journalctl -p err..alert >~/Logs/journal.log || log_warning "Failed to log journal errors."
    sudo hdparm -Tt /dev/sda >~/Logs/storage.log || log_warning "Failed to perform storage test."

    sudo pacman -S --needed --noconfirm sysbench fio
    sysbench --threads="$(nproc)" --cpu-max-prime=20000 cpu run >~/Logs/cpu.log || log_warning "Failed to perform CPU test."
    sudo fio --filename=/mnt/test.fio --size=8GB --direct=1 --rw=randrw --bs=4k --ioengine=libaio --iodepth=256 --runtime=120 --numjobs=4 --time_based --group_reporting --name=iops-test-job --eta-newline=1 >~/Logs/io.log || log_warning "Failed to perform I/O test."

    glxinfo | grep "direct rendering" >~/Logs/graphics.log || log_warning "Failed to log graphics info."
    grep -r . /sys/devices/system/cpu/vulnerabilities/ >~/Logs/cpu_vulnerabilities.log || log_warning "Failed to log CPU vulnerabilities."

    uname -r >~/Logs/kernel.log || log_warning "Failed to log kernel version."
    fastfetch >~/Logs/overview.log || log_warning "Failed to log system overview."
    log_success "System information logged."
}

# --- Write Remaining Steps ---
write_remaining_steps() {
    log_info "Writing remaining setup steps to a file..."
    cat <<EOF >~/Documents/remaining_setup.md
TODO:
1. Paste \`cat ~/Scratch/ublock-ytshorts.txt | wl-copy\` to ublock filters
2. Setup GUI apps:
    Log into *Bitwarden*, *Notesnook*, *Ente Auth* and *Mega*
    Configure *KDE Connect*, *Telegram*, *ProtonVPN*, *Zoom*, *Open TV*, *Veracrypt*
3. Paste \`cat ~/.ssh/id_ed25519.pub | wl-copy\` at https://github.com/settings/keys
4. Check the files obtained over torrents: \`ls ~/Scratch\`
5. Install NixOS on QEMU-KVM: \`cd ~/Workspace/ && qemu-system-x86_64 -enable-kvm -cdrom ~/Backups/ISOs/\$ISO_FILE -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on\`
EOF
    log_success "Remaining setup steps written to ~/Documents/remaining_setup.md"
}
