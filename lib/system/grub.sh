#!/bin/bash

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

# --- Bootloader setup ---
configure_bootloader_theme() {
    log_info "Configuring bootloader theme..."

    git clone --depth 1 https://github.com/shashotoNur/grub-dark-theme || {
        log_error "Failed to clone grub-dark-theme repository."
        return 1
    }

    sudo cp -r grub-dark-theme/theme /boot/grub/themes/

    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub || {
        log_error "Failed to update GRUB_TIMEOUT."
        return 1
    }

    sudo sed -i 's|^#\?GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/theme/theme.txt"|' /etc/default/grub || {
        log_error "Failed to update GRUB_THEME."
        return 1
    }

    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "Bootloader theme configured successfully."
}

# --- SDDM Background Setup ---
set_sddm_background() {
    log_info "Setting up sddm background"
    local WALLPAPER_FILE=".config/hyde/themes/Catppuccin\ Mocha/wallpapers/cat_leaves.png"
    local TARGET_FILE="/usr/share/sddm/themes/Corners/backgrounds/bg.png"
    sudo cp "$WALLPAPER_FILE" "$TARGET_FILE"
    log_success "SDDM Background changed successfully"
}
