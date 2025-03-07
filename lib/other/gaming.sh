#!/bin/bash

# --- Graphics Driver Setup ---
setup_graphics_driver() {
    log_info "Installing and configuring NVIDIA drivers..."
    sudo pacman -S --needed --noconfirm nvidia-prime nvidia-dkms nvidia-settings nvidia-utils lib32-nvidia-utils lib32-opencl-nvidia opencl-nvidia libvdpau lib32-libvdpau libxnvctrl vulkan-icd-loader lib32-vulkan-icd-loader vkd3d lib32-vkd3d opencl-headers opencl-clhpp vulkan-validation-layers lib32-vulkan-validation-layers

    sudo systemctl enable nvidia-persistenced.service

    sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$|GRUB_CMDLINE_LINUX_DEFAULT="\1 echolevel=3 quiet splash nvidia_drm.modeset=1 retbleed=off spectre_v2=retpoline,force nowatchdog mitigations=off"|' /etc/default/grub || {
        log_error "Failed to update GRUB_CMDLINE_LINUX_DEFAULT."
        return 1
    }
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    sudo sed -i 's/MODULES=\((.*)\)/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf || {
        log_error "Failed to update MODULES in mkinitcpio.conf."
        return 1
    }
    sudo mkinitcpio -P

    log_info "NVIDIA setup completed. Verify with: cat /sys/module/nvidia_drm/parameters/modeset"
    log_success "NVIDIA drivers configured successfully."
}

# --- Gaming Packages Installation ---
install_gaming_packages() {
    log_info "Installing gaming packages..."
    local packages=(
        gamemode lib32-gamemode gamescope wine wine-gecko wine-mono fluidsynth lib32-fluidsynth
        gvfs gvfs-nfs libkate gst-plugins-good gst-plugins-bad gst-libav lib32-gst-plugins-good
        gst-plugin-gtk lib32-gstreamer lib32-gst-plugins-base-libs lib32-libxvmc libxvmc smpeg faac
        x264 lib32-pipewire pipewire-zeroconf mac lib32-opencl-icd-loader
    )

    sudo pacman -S --needed --noconfirm "${packages[@]}" || {
        log_error "Failed to install gaming packages."
        return 1
    }

    log_success "Gaming packages installed."
}

# --- Bottles Setup ---
setup_bottles() {
    log_info "Setting up Bottles..."

    flatpak override --filesystem=home com.usebottles.bottles
    log_success "User files access enabled for bottles."

    log_info "Creating a gaming bottle..."
    flatpak run --command=bottles-cli com.usebottles.bottles new --bottle-name GamingBottle --environment gaming || {
        log_error "Failed to create a new gaming bottle."
        return 1
    }

    log_success "Gaming bottle created successfully."
}

# --- Torrent Download ---
download_torrents() {
    log_info "Starting torrent downloads..."
    local TORRENT_DIR="~/Backups/torrents"
    local DOWNLOAD_DIR="~/Scratch"

    local TORRENT_FILES=("$TORRENT_DIR"/*.torrent)

    if [[ ! -e "${TORRENT_FILES[0]}" ]]; then
        log_warning "No torrent files found in: $TORRENT_DIR"
    else
        for TORRENT_FILE in "${TORRENT_FILES[@]}"; do
            log_info "Starting download for: $TORRENT_FILE"
            aria2c --dir="$DOWNLOAD_DIR" --seed-time=0 --follow-torrent=mem --max-concurrent-downloads=5 \
                --bt-max-peers=50 --bt-tracker-connect-timeout=10 --bt-tracker-timeout=10 \
                --bt-tracker-interval=60 --bt-stop-timeout=300 "$TORRENT_FILE" || {
                log_error "Failed to download torrent file: $TORRENT_FILE"
            }
        done
        log_success "All downloads completed."
    fi
}

# Function to set up NixOS on QEMU-KVM
setup_nixos_qemu_kvm() {
    log_info "Setting up NixOS on QEMU-KVM..."

    # Check CPU virtualization support
    if ! lscpu | grep -i Virtualization | grep -q VT-x; then
        log_error "Error: CPU does not support virtualization (VT-x)"
        return 1
    fi

    # Install required packages
    log_info "Installing required packages..."
    sudo pacman -S --needed --noconfirm qemu-full qemu-img libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm guestfs-tools libosinfo
    yay -S --needed tuned

    # Enable libvirt
    log_info "Enabling libvirt service..."
    sudo systemctl enable libvirtd.service

    # Enable IOMMU
    log_info "Enabling IOMMU..."
    sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$|GRUB_CMDLINE_LINUX_DEFAULT="\1 intel_iommu=on iommu=pt"|' /etc/default/grub || {
        log_error "Failed to modify GRUB for IOMMU."
        return 1
    }
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # Enable TuneD
    log_info "Enabling TuneD..."
    sudo systemctl enable --now tuned.service
    sudo tuned-adm profile virtual-host
    sudo tuned-adm verify

    # Configure libvirt
    log_info "Configuring libvirt..."
    sudo sed -i '/#unix_sock_group = "libvirt"/s/^#//' /etc/libvirt/libvirtd.conf
    sudo sed -i '/#unix_sock_rw_perms = "0770"/s/^#//' /etc/libvirt/libvirtd.conf

    # Add user to libvirt group
    log_info "Adding user to libvirt group..."
    sudo usermod -aG libvirt "$USER"

    # Create a sample VM storage
    log_info "Creating a sample VM..."
    qemu-img create -f qcow2 ~/Workspace/virtdisk.img 128G || {
        log_error "Failed to create virtual disk image."
        return 1
    }

    url="https://nixos.org/download/"
    link=$(curl -s "$url" | grep -oE 'https://channels.nixos.org/nixos-[^/]+/latest-nixos-gnome-x86_64-linux.iso' | head -n 1)
    wget -c -P ~/Backups/ISOs/ "$link" || {
        log_error "Failed to download NixOS ISO."
        return 1
    }

    ISO_FILE=$(basename "$link")
    echo "To install OS on VM, run:"
    echo "qemu-system-x86_64 -enable-kvm -cdrom ~/Backups/ISOs/$ISO_FILE -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on"
    echo "To start VM once installed, run:"
    echo "qemu-system-x86_64 -enable-kvm -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on"

    log_success "NixOS on QEMU-KVM setup completed."
}
