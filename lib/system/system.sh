#!/bin/bash

# --- User and System Configuration ---
configure_system() {
    local root_password="$1"
    local username="$2"
    local hostname="$3"

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
        echo "Installing essential packages..."
        pacman -Sy --noconfirm grub efibootmgr dosfstools os-prober mtools fuse3 zsh
    " || {
        log_error "Failed to configure system within chroot"
        return 1
    }
    log_success "System configured successfully."

}

# --- System Update and Keyring ---
update_system_keyring() {
    log_info "Updating system and keyring..."
    sudo pacman -S --needed --noconfirm archlinux-keyring || {
        log_error "Failed to update archlinux-keyring."
        return 1
    }
    sudo pacman-key --init && sudo pacman-key --populate archlinux || {
        log_error "Failed to initialize and populate archlinux keyring."
        return 1
    }
    sudo pacman -Syu || {
        log_error "Failed to update the system."
        return 1
    }
    log_success "System and keyring updated successfully."
}

# --- Network time protocol ---
setup_network_time_protocol() {
    log_info "Setting up network time protocol..."
    sudo pacman -S --needed --noconfirm openntp
    sudo systemctl disable --now systemd-timesyncd
    sudo systemctl enable openntpd

    sudo sed -i '/^servers/i server 0.pool.ntp.org\nserver 1.pool.ntp.org\nserver 2.pool.ntp.org\nserver 3.pool.ntp.org' /etc/ntpd.conf || {
        log_error "Could not add servers to /etc/ntpd.conf"
        return 1
    }
    echo "0.0" | sudo tee -a "/var/db/ntpd.drift"

    log_success "Network time protocol setup complete"
}

# Function to update the system keymap
update_keymap() {
    log_info "Updating system keymap to 'us'"
    echo "KEYMAP=us" | sudo tee /etc/vconsole.conf || {
        log_error "Failed to update system keymap."
        return 1
    }
    log_success "System keymap updated successfully."
}

# Function to set up the system clock
setup_system_clock() {
    log_info "Setting up system clock."
    sudo localectl set-locale LANG=en_AU.UTF-8 || {
        log_error "Failed to set system locale."
        return 1
    }

    sudo timedatectl set-ntp true || {
        log_error "Failed to set NTP."
        return 1
    }
    log_success "System clock set up successfully."
}

#--- ZRAM setup ---
setup_zram() {
    log_info "Setting up ZRAM"
    sudo tee /etc/systemd/system/zram.service >/dev/null <<EOF
[Unit]
Description=ZRAM Swap Service

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "modprobe zram && echo lz4 > /sys/block/zram0/comp_algorithm && echo 4G > /sys/block/zram0/disksize && mkswap --label zram0 /dev/zram0 && swapon --priority 100 /dev/zram0"
ExecStop=/usr/bin/bash -c "swapoff /dev/zram0 && rmmod zram"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl enable --now zram.service || {
        log_error "Could not enable zram service"
        return 1
    }

    log_success "ZRAM setup complete"
}

# --- HDD Performance ---
configure_hdd_performance() {
    log_info "Configuring HDD performance..."
    sudo systemctl enable --now hdparm.service || {
        log_error "Could not enable hdparm service"
        return 1
    }
    sudo hdparm -W 1 /dev/sda || {
        log_warning "Could not set /dev/sda performance, likely not present"
    }
    log_success "HDD performance configured"
}

#--- Firmware updates ---
update_firmware() {
    log_info "Updating firmware..."
    yes | fwupdmgr get-updates || {
        log_warning "Could not get updates. Skipping."
    }
}

# --- Set numlock ---
set_numlock() {
    log_info "Setting up numlock..."
    yay -S --needed --noconfirm mkinitcpio-numlock
    sed -i '/^HOOKS=/ s/\bencrypt\b/numlock encrypt/' /etc/mkinitcpio.conf || {
        log_error "Could not add numlock to HOOKS"
        return 1
    }
    sudo mkinitcpio -P

    echo "Numlock=on" | sudo tee -a "/etc/sddm.conf" || {
        log_error "Could not add Numlock=on to sddm.conf"
        return 1
    }

    log_success "Numlock setup complete"
}

# --- Auto-Login Function ---
ensure_auto_login() {
    local username="$1"
    local tty="tty1" # Default to tty1

    if [ -z "$username" ]; then
        log_info "Usage: ensure_auto_login <username> [tty]"
        log_info "  tty (optional): The tty to enable auto-login on (e.g., tty2). Defaults to tty1."
        return 1
    fi

    if [ -n "$2" ]; then
        tty="$2"
    fi

    local override_dir="/mnt/etc/systemd/system/getty@${tty}.service.d"
    local override_file="${override_dir}/override.conf"

    sudo mkdir -p "$override_dir"

    sudo tee "$override_file" >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $username --noclear %I 38400 linux
EOF

    if [ $? -eq 0 ]; then
        log_success "Auto-login enabled for user '$username' on $tty."
        return 0
    else
        log_error "Failed to enable auto-login."
        return 1
    fi
}
