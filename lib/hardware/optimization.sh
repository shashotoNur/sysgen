#!/bin/bash

# --- Paccache setup ---
setup_paccache() {
    log_info "Setting up paccache..."
    sudo pacman -S --needed --noconfirm pacman-contrib
    sudo systemctl enable paccache.timer
    log_success "Paccache setup complete"
}

#--- Enable system commands for kernel ---
enable_system_commands() {
    log_info "Enabling system commands for kernel..."
    echo 'kernel.sysrq=1' | sudo tee /etc/sysctl.d/99-reisub.conf
    log_success "System commands for kernel enabled"
}

# --- HDMI Sharing ---
setup_hdmi_sharing() {
    log_info "Setting up HDMI sharing..."
    sed -i 's/^monitor =/#&/; /^#monitor =/a monitor = ,preferred,auto,1,mirror,eDP-1' ~/.config/hypr/hyprland.conf
}

# --- Limit journal size ---
limit_journal_size() {
    log_info "Configuring systemd journal size..."
    sudo sed -i '/^#SystemMaxUse=/c\SystemMaxUse=256M' /etc/systemd/journald.conf
    sudo sed -i '/^#MaxRetentionSec=/c\MaxRetentionSec=2weeks' /etc/systemd/journald.conf
    sudo sed -i '/^#MaxFileSec=/c\MaxFileSec=1month' /etc/systemd/journald.conf

    sudo sed -i '/^#Audit=/c\Audit=yes' /etc/systemd/journald.conf
    sudo systemctl restart systemd-journald

    log_success "Journal size configured"
}

# --- Disable core dump ---
disable_core_dump() {
    log_info "Disabling core dumps..."
    echo 'kernel.core_pattern=/dev/null' | sudo tee /etc/sysctl.d/50-coredump.conf
}

# --- Prevent Overheating ---
prevent_overheating() {
    log_info "Installing and configuring thermald..."
    yay -S --needed --noconfirm thermald

    sudo sed -i 's|ExecStart=.*|ExecStart=/usr/bin/thermald --no-daemon --dbus-enable --ignore-cpuid-check|' /usr/lib/systemd/system/thermald.service
    sudo systemctl enable --now thermald

    log_success "Overheating prevention configured"
}

# --- Optimize network ---
optimize_network_congestion() {
    log_info "Enabling BBR TCP congestion control..."
    echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee /etc/sysctl.d/98-misc.conf
    sudo sysctl -p /etc/sysctl.d/98-misc.conf
    log_success "TCP congestion control set to BBR."
}

# --- Firewall Setup ---
setup_firewall() {
    log_info "Installing and configuring UFW..."
    sudo pacman -S --needed --noconfirm ufw

    sudo ufw limit 22/tcp
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp

    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    sudo ufw allow 1714:1764/udp
    sudo ufw allow 1714:1764/tcp

    sudo systemctl enable --now ufw
    sudo ufw enable

    log_success "UFW installed and configured."
}

# --- OOMD Setup ---
setup_oomd() {
    log_info "Enabling and configuring systemd OOMD..."
    sudo systemctl enable --now systemd-oomd

    sudo tee -a /etc/systemd/system.conf >/dev/null <<EOF

[Manager]
DefaultCPUAccounting=yes
DefaultIOAccounting=yes
DefaultMemoryAccounting=yes
DefaultTasksAccounting=yes
EOF
    sudo tee -a /etc/systemd/oomd.conf >/dev/null <<EOF

[OOM]
SwapUsedLimitPercent=90%
DefaultMemoryPressureDurationSec=20s
EOF
    log_success "Systemd OOMD enabled and configured."
}

# --- Brightness Service Setup ---
setup_brightness_service() {
    log_info "Configuring brightness service..."
    sudo bash -c 'cat << EOF > /etc/systemd/system/set-brightness.service
[Unit]
Description=Set screen brightness to 5% at startup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "echo 50 > /sys/class/backlight/intel_backlight/brightness"

[Install]
WantedBy=multi-user.target
EOF'

    sudo systemctl enable --now set-brightness.service || {
        log_error "Failed to enable brightness service."
        return 1
    }
    log_success "Brightness service configured."
}

# --- AppArrmor and Audit Setup ---
setup_apparmor_audit() {
    log_info "Setting up AppArmor..."
    local LSM
    LSM=$(cat /sys/kernel/security/lsm)
    log_debug "Detected LSMs: $LSM"

    log_info "Modifying kernel options..."
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"\$|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 lsm=apparmor,$LSM audit=1 audit_backlog_limit=8192\"|" /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "Kernel options updated."

    log_info "Installing and enabling AppArmor and Audit..."
    sudo pacman -S --needed --noconfirm apparmor
    sudo systemctl enable --now apparmor.service
    sudo systemctl enable --now auditd.service
    log_success "AppArmor and Audit installed and enabled."

    log_info "Setting up Audit log reading..."
    sudo groupadd -r audit
    sudo gpasswd -a "$USER" audit || {
        log_error "Failed to add user to audit group."
        return 1
    }
    sudo sed -i 's/^log_group =.*/log_group = audit/' /etc/audit/auditd.conf || {
        log_error "Failed to modify audit group."
        return 1
    }
    log_success "Audit log reading configured."

    log_info "Increasing netlink buffer size..."
    echo "net.core.rmem_max = 8388608" | sudo tee -a /etc/sysctl.conf
    echo "net.core.wmem_max = 8388608" | sudo tee -a /etc/sysctl.conf
    log_success "Netlink buffer size increased."

    log_info "Increasing audit buffer size..."
    sudo sed -i '$a-b 65536' /etc/audit/audit.rules

    log_info "Creating AppArmor notification desktop launcher..."
    mkdir -p ~/.config/autostart
    echo -e "[Desktop Entry]\nType=Application\nName=AppArmor Notify\nComment=Receive on screen notifications of AppArmor denials\nTryExec=aa-notify\nExec=aa-notify\nIcon=security-high\nCategories=Security;System;" >"$desktop_file" || {
        log_error "Failed to create AppArmor notification launcher."
        return 1
    }
    log_success "AppArmor notification launcher created."
}
