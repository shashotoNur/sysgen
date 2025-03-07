#!/bin/bash

###############################################################################
# Script Name: postinstall.sh (Initial Setup)
# Description: Automates the initial configuration of a freshly installed Arch
#              Linux system as per the author's preferences.
# Author: Shashoto Nur
# Date: 07/03/2025
# Version: 1.1
# License: MIT
###############################################################################

# --- Configuration ---
set -euo pipefail # Exit on error, unset variable, or pipeline failure

# --- Global Variables ---
CONFIG_FILE="install.conf"
SCRIPT_DIR="$(dirname "$0")"

# --- Logging Functions ---
log_info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$1" >&2; }
log_warning() { printf "\033[1;33m[WARNING]\033[0m %s\n" "$1" >&2; }
log_error() { printf "\033[1;31m[ERROR]\033[0m %s\n" "$1" >&2; }
log_success() { printf "\033[1;32m[SUCCESS]\033[0m %s\n" "$1" >&2; }
log_debug() { printf "\e[90mDEBUG:\e[0m %s\n" "$1" >&2; }

# --- Utility Functions ---

# Check if the configuration file exists and is readable.
validate_config_file() {
    log_info "Validating configuration file: $CONFIG_FILE"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file '$CONFIG_FILE' does not exist. Exiting."
        return 1
    fi
    if [[ ! -r "$CONFIG_FILE" ]]; then
        log_error "Configuration file '$CONFIG_FILE' is not readable. Exiting."
        return 1
    fi
    log_success "Configuration file '$CONFIG_FILE' is valid and readable."
    return 0
}

# Function to check if a command is available
command_exists() {
    command -v "$1" &>/dev/null
}

# Extract a value from the configuration file
extract_config_value() {
    local key="$1"
    local config_file="${2:-$CONFIG_FILE}"

    if ! [[ -f "$config_file" ]]; then
        log_error "Config file '$config_file' not found."
        return 1
    fi

    grep -E "^$key:" "$config_file" | awk -F': ' '{print $2}'
}

# --- System Preparation Functions ---

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

# Function to establish an internet connection
setup_internet_connection() {
    log_info "Setting up Internet Connection"

    #Check if networkmanager is available.
    if ! command_exists nmcli; then
        log_error "nmcli is not installed. Please install NetworkManager."
        return 1
    fi

    local wifi_ssid=$(extract_config_value "WiFi SSID")
    local wifi_password=$(extract_config_value "WiFi Password")

    log_debug "Connecting to WiFi: SSID=$wifi_ssid"

    sudo systemctl enable --now NetworkManager.service || {
        log_error "Failed to enable and start NetworkManager service."
        return 1
    }

    nmcli device wifi connect "$wifi_ssid" password "$wifi_password" || {
        log_error "Failed to connect to WiFi: $wifi_ssid."
        return 1
    }

    log_success "Internet connection established."
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

# Function to install essential packages
install_essential_packages() {
    log_info "Installing essential packages."

    if ! command_exists pacman; then
        log_error "pacman is not available. Exiting"
        return 1
    fi

    local packages=(
        xdg-user-dirs
        alsa-firmware
        alsa-utils
        pipewire
        pipewire-alsa
        pipewire-pulse
        pipewire-jack
        wireplumber
        wget
        git
        intel-ucode
        fuse2
        lshw
        powertop
        inxi
        acpi
        plasma
        sddm
        dolphin
        konsole
        tree
        downgrade
        xdg-desktop-portal-gtk
        emote
        mangohud
        cava
    )

    sudo pacman -Syu --noconfirm --needed "${packages[@]}" || {
        log_error "Failed to install essential packages."
        return 1
    }
    log_success "Essential packages installed successfully."
}

# Function to create user directories
create_user_directories() {
    log_info "Creating user directories."
    local directories=(
        ~/Workspace
        ~/Backups
        ~/Backups/ISOs
        ~/Archives
        ~/Scratch
        ~/Scripts
        ~/Games
        ~/Designs
        ~/Logs
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    done

    xdg-user-dirs-update || {
        log_error "Failed to update primary user directories."
        return 1
    }

    log_success "User directories created successfully."
}

# Function to copy backup files to disk
copy_backup_files() {
    log_info "Copying backup files to disk."
    local storage_mount="$3"
    local multiboot_mount="$2"

    if [[ -z "$multiboot_mount" || -z "$storage_mount" ]]; then
        log_error "Either the multiboot or storage mount variable is empty."
        return 1
    fi

    cp -r "$storage_mount/backup/"* ~/Backups/ || {
        log_error "Failed to copy backup files from storage to ~/Backups/."
        return 1
    }
    cp -r "$multiboot_mount/"* ~/Backups/ISOs || {
        log_error "Failed to copy backup files from multiboot to ~/Backups/ISOs."
        return 1
    }

    log_success "Backup files copied to disk successfully."
}

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

# Function to wipe the USB drive
wipe_usb_drive() {
    log_info "Securely wiping the USB drive."
    local usb_device="$1"
    sudo dd if=/dev/zero of="${usb_device}" bs=4M status=progress || {
        log_error "Failed to wipe USB drive with dd."
        return 1
    }
}

# --- Mirrorlist management ---
update_pacman_mirrorlist() {
    log_info "Updating Pacman mirrorlist..."
    if ! command_exists reflector; then
        log_error "reflector is not installed. Please install it."
        return 1
    fi

    sudo reflector --verbose -c India -c China -c Japan -c Singapore -c US --protocol https --sort rate --latest 20 \
        --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist || {
        log_error "Failed to update the mirrorlist."
        return 1
    }

    sudo systemctl enable reflector.timer || {
        log_error "Failed to enable reflector.timer"
        return 1
    }

    log_success "Pacman mirrorlist updated successfully."
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

# --- Network Configuration ---
configure_network() {
    log_info "Configuring network..."
    sudo pacman -S --needed --noconfirm resolvconf nm-connection-editor networkmanager-openvpn || {
        log_error "Failed to install network packages."
        return 1
    }

    sudo systemctl enable systemd-resolved.service
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    sudo systemctl enable --now wpa_supplicant.service

    log_success "Network configured successfully."
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

# --- Flatpak Setup ---
setup_flatpak() {
    log_info "Setting up Flatpak..."
    sudo pacman -S --needed --noconfirm flatpak || {
        log_error "Failed to install Flatpak."
        return 1
    }

    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    log_success "Flatpak setup completed."
}

# --- Zsh Setup ---
setup_zsh() {
    log_info "Setting up Zsh..."

    sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
        log_error "Failed to install Oh My Zsh."
        return 1
    }

    log_info "Installing Zsh plugins..."
    local ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}

    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    sudo git clone --depth 1 https://github.com/agkozak/zsh-z "$ZSH_CUSTOM/plugins/zsh-z"
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
    sudo git clone --depth 1 https://github.com/MichaelAquilina/zsh-you-should-use.git "$ZSH_CUSTOM/plugins/you-should-use"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
    zsh <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
    sudo git clone https://github.com/MichaelAquilina/zsh-auto-notify.git "$ZSH_CUSTOM/plugins/auto-notify"

    if [[ -d ~/.config/fastfetch/pngs ]]; then
        find ~/.config/fastfetch/pngs -type f ! -name "arch.png" -delete || {
            log_warning "Could not find fastfetch to delete its files"
        }
    fi

    log_success "Zsh setup completed."
}

#--- Chaotic AUR Management ---
enable_chaotic_aur() {
    log_info "Enabling Chaotic AUR..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf || {
        log_error "Failed to add Chaotic AUR to pacman.conf."
        return 1
    }

    log_success "Chaotic AUR enabled."
}

# --- Essential Application Installation (Pacman) ---
install_pacman_applications() {
    log_info "Installing Pacman applications..."

    local packages=(
        intel-media-driver grub-btrfs nodejs npm fortune-mod cowsay lolcat jrnl inotify-tools supertux
        testdisk bat ripgrep bandwhich oath-toolkit asciinema neovim hexyl syncthing thefuck duf procs sl
        cmatrix gum gnome-keyring dnsmasq dmenu btop eza hdparm tmux telegram-desktop ddgr less sshfs onefetch
        tmate navi code nethogs tldr gping detox fastfetch bitwarden yazi aria2 direnv xorg-xhost rclone fwupd
        bleachbit picard timeshift jp2a gparted obs-studio veracrypt rust aspell-en libmythes mythes-en
        languagetool pacseek kolourpaint kicad kdeconnect cpu-x github-cli kolourpaint kalarm cpufetch kate
        plasma-browser-integration ark okular kamera krename ipython filelight kdegraphics-thumbnailers
        qt5-imageformats mdless kimageformats espeak-ng armagetronad
    )

    sudo pacman -S --needed --noconfirm "${packages[@]}" || {
        log_error "Failed to install Pacman applications."
        return 1
    }
    log_success "Pacman applications installed."
}

# --- Essential Application Installation (Yay) ---
install_yay_applications() {
    log_info "Installing Yay applications..."

    local packages=(
        ventoy-bin steghide go pkgx-git stacer-git nsnake gpufetch nudoku arch-update mongodb-bin
        hyprland-qtutils pet-git musikcube tauon-music-box hollywood no-more-secrets nodejs-mapscii
        noti megasync-bin mongodb-compass smassh affine-bin solidtime-bin ngrok scc rmtrash nomacs cbonsai
        vrms-arch-git browsh timer sql-studio-bin posting dooit edex-ui-bin trash-cli-git appimagelauncher-bin
    )

    yay -S --needed --noconfirm "${packages[@]}" || {
        log_error "Failed to install Yay applications."
        return 1
    }
    log_success "Yay applications installed."
}

# --- Essential Application Installation (Flatpak) ---
install_flatpak_applications() {
    log_info "Installing Flatpak applications..."

    local packages=(
        com.github.tchx84.Flatseal io.ente.auth com.notesnook.Notesnook us.zoom.Zoom
        org.speedcrunch.SpeedCrunch net.scribus.Scribus org.kiwix.desktop org.localsend.localsend_app
        com.felipekinoshita.Wildcard io.github.prateekmedia.appimagepool com.protonvpn.www org.librecad.librecad
        dev.fredol.open-tv org.kde.krita com.opera.Opera org.audacityteam.Audacity com.usebottles.bottles
        io.github.zen_browser.zen org.torproject.torbrowser-launcher org.qbittorrent.qBittorrent
        org.onlyoffice.desktopeditors org.blender.Blender org.kde.labplot2 org.kde.kwordquiz org.kde.kamoso
        org.kde.skrooge org.kde.kdenlive md.obsidian.Obsidian
    )

    for package in "${packages[@]}"; do
        flatpak install -y "$package" || {
            log_error "Failed to install Flatpak application: $package"
            return 1
        }
    done
    log_success "Flatpak applications installed."
}

# --- Hyprland Setup ---
setup_hyprland() {
    log_info "Setting up Hyprland..."
    git clone --depth 1 https://github.com/prasanthrangan/hyprdots ~/HyDE
    bash ~/HyDE/Scripts/install.sh || {
        log_error "Failed to install Hyprland config from HyDE."
        return 1
    }
    log_success "Hyprland setup completed."
}

# --- Browser initialization ---
initialize_browser() {
    log_info "Initializing browser..."
    sed -i 's/browser=firefox/browser=app.zen_browser.zen/' ~/.config/hypr/keybindings.conf || {
        log_error "Could not replace firefox with zen in keybindings."
        return 1
    }
    log_success "Browser initialized"
}

# --- Restore file manager config ---
restore_file_manager_config() {
    log_info "Restoring file manager config..."
    cp ~/Backups/dolphin/dolphinrc ~/.config/dolphinrc
    cp ~/Backups/dolphin/dolphinui.rc ~/.local/share/kxmlgui5/dolphin/dolphinui.rc
    log_success "File manager config restored"
}

# --- Restore zsh config ---
restore_zsh_config() {
    log_info "Restoring zsh config..."
    cp ~/Backups/zsh/.zshrc ~/.zshrc
    log_success "zsh config restored"
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

# --- Bluetooth Setup ---
setup_bluetooth() {
    log_info "Installing and enabling Bluetooth services..."
    sudo pacman -S --needed --noconfirm bluez bluez-utils blueman

    sudo modprobe btusb
    sudo systemctl enable --now bluetooth
    log_success "Bluetooth services installed and enabled."
}

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

# --- Avro Keyboard Setup ---
setup_avro_keyboard() {
    log_info "Installing and configuring Avro keyboard..."
    yay -S --noconfirm ibus-avro-git

    ibus-daemon -rxRd || {
        log_error "Failed to start ibus-daemon."
        return 1
    }

    echo -e "GTK_IM_MODULE=ibus\nQT_IM_MODULE=ibus\nXMODIFIERS=@im=ibus" | sudo tee -a /etc/environment

    echo '#!/bin/bash
[ "$(ibus engine)" = "xkb:us::eng" ] && ibus engine ibus-avro || ibus engine xkb:us::eng' >~/.config/hypr/toggle_ibus.sh
    chmod +x ~/.config/hypr/toggle_ibus.sh

    echo 'bind=SUPER,SPACE,exec,~/.config/hypr/toggle_ibus.sh' >>~/.config/hypr/hyprland.conf

    # Insert ibus command after the last line starting with "exec-once"
    last_exec_once=$(grep -n '^exec-once' ~/.config/hypr/hyprland.conf | tail -n 1 | cut -d ':' -f 1)
    sed -i "${last_exec_once}a exec-once = ibus-daemon -rxRd # start ibus demon" ~/.config/hypr/hyprland.conf || {
        log_error "Failed to add start to hyprland config."
        return 1
    }

    log_success "Avro keyboard installed and configured."
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

# --- IPTV Playlist Download ---
download_iptv_playlist() {
    log_info "Downloading IPTV playlist..."
    wget -O ~/Scratch/iptv_playlist.m3u https://iptv-org.github.io/iptv/index.m3u
}

# --- VS Code Extensions ---
install_vscode_extensions() {
    log_info "Installing VS Code extensions..."
    local EXTLIST_FILE=~/Backups/code/ext.lst
    if [[ -f "$EXTLIST_FILE" ]]; then
        while IFS= read -r extension; do
            code --install-extension "$extension" || log_error "Error installing $extension"
        done <"$EXTLIST_FILE"
        log_success "VS Code extensions installed."
    else
        log_warning "$EXTLIST_FILE not found, skipping..."
    fi
}

# --- Zen Browser Configuration ---
update_zen_browser_config() {
    log_info "Updating Zen browser config..."
    local configs=(
        "user_pref(\"browser.preferences.defaultPerformanceSettings.enabled\", false);"
        "user_pref(\"browser.cache.disk.enable\", false);"
        "user_pref(\"browser.cache.memory.enable\", true);"
        "user_pref(\"browser.sessionstore.resume_from_crash\", false);"
        "user_pref(\"extensions.pocket.enabled\", false);"
        "user_pref(\"layout.css.dpi\", 0);"
        "user_pref(\"general.smoothScroll.msdPhysics.enabled\", true);"
        "user_pref(\"media.hardware-video-decoding.force-enabled\", true);"
        "user_pref(\"middlemouse.paste\", true);"
        "user_pref(\"webgl.msaa-force\", true);"
        "user_pref(\"security.sandbox.content.read_path_whitelist\", \"/sys/\");"
        "user_pref(\"browser.download.alwaysOpenPanel\", false);"
        "user_pref(\"network.ssl_tokens_cache_capacity\", 32768);"
        "user_pref(\"media.ffmpeg.vaapi.enabled\", true);"
        "user_pref(\"accessibility.force_disabled\", 1);"
        "user_pref(\"browser.eme.ui.enabled\", false);"
    )

    local profile_dir_name=$(cat ~/.var/app/app.zen_browser.zen/.zen/installs.ini | grep "Default=" | cut -d '=' -f 2)
    local prefs_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "prefs.js" -path "*/$profile_dir_name/*")
    local search_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "search.json.mozlz4" -path "*/$profile_dir_name/*")
    local theme_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "zen-themes.css" -path "*/$profile_dir_name/*")

    for config in "${configs[@]}"; do
        local prefix=$(echo "$config" | cut -d ',' -f 1)

        if grep -q "$prefix" "$prefs_file"; then
            sed -i "/$prefix/c\\$config" "$prefs_file"
            log_debug "Replaced: $config"
        else
            echo "$config" >>"$prefs_file"
            log_debug "Added: $prefix"
        fi
    done

    mv ~/Backups/zen/search.json.mozlz4 "$search_file" || {
        log_warning "Could not restore zen search."
    }

    wget -c -P "$HOME/Scratch/ublock-ytshorts.txt" https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt || {
        log_warning "Could not add to zen search."
    }

    echo "Adding code to zen-themes.css..."
    echo "a[href$=\".pdf\"]:after {
  font-size: smaller;
  content: \" [pdf] \";
}" >>"$theme_file" || {
        log_error "Failed to append to zen-themes.css"
        return 1
    }

    log_success "Zen configurations have been updated!"
}

# --- Terminal Apps Setup ---
terminal_apps_setup() {
    log_info "Configuring terminal apps..."

    # Preload
    yay -S --noconfirm preload
    sudo systemctl enable --now preload

    # Jrnl
    mkdir -p ~/.config/jrnl
    echo -e "colors:\n  body: none\n  date: black\n  tags: yellow\n  title: cyan\ndefault_hour: 9\ndefault_minute: 0\neditor: 'nvim'\nencrypt: false\nhighlight: true\nindent_character: '|'\njournals:\n  default:\n    journal: /home/${CONFIG_VALUES["Username"]}/Documents/data/journal.txt\nlinewrap: 79\ntagsymbols: '#@'\ntemplate: false\ntimeformat: '%F %r'\nversion: v4.2" >~/.config/jrnl/jrnl.yaml || {
        log_error "Failed to create jrnl config file."
        return 1
    }

    # File manager
    bash -c "$(curl -sLo- https://superfile.netlify.app/install.sh)"

    # Gnome keyring
    sudo sed -i '/^auth /i auth       optional     pam_gnome_keyring.so' /etc/pam.d/login || {
        log_error "Failed to add auth rule for pam_gnome_keyring."
        return 1
    }
    sudo sed -i '/^session /i session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/login || {
        log_error "Failed to add session rule for pam_gnome_keyring."
        return 1
    }

    # Pip
    sudo pacman -S --needed --noconfirm python-pip
    local PY_VER=$(python --version 2>&1 | awk '{print $2}' | cut -d '.' -f 1,2)
    sudo mv /usr/lib/python$PY_VER/EXTERNALLY-MANAGED /usr/lib/python$PY_VER/EXTERNALLY-MANAGED.old || {
        log_error "Failed to disable global package install restriction."
        return 1
    }

    # Makedown
    pip install makedown

    # Diff so fancy
    npm i -g diff-so-fancy
    git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
    git config --global interactive.diffFilter "diff-so-fancy --patch"
    git config --global color.ui true

    log_success "Terminal apps configured."
}

# --- Gemini Console Setup ---
setup_gemini_console() {
    log_info "Setting up Gemini console..."

    git clone --depth 1 https://github.com/flameface/gemini-console-chat.git ~/Scripts/
    cd ~/Scripts/gemini-console-chat
    npm install

    sed -i "s/YOUR_API_KEY/${CONFIG_VALUES["Gemini API Key"]}/" index.js || {
        log_error "Failed to set Gemini API key in index.js."
        return 1
    }
    log_success "Gemini console setup completed."
}

# --- TMUX Setup ---
configure_tmux() {
    log_info "Configuring TMUX..."
    mkdir -p ~/.tmux/plugins
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

    echo -e "unbind r\nbind r source-file ~/.tmux.conf\n\nset -g default-terminal \"tmux-256color\"\nset -ag terminal-overrides \",xterm-256color:RGB\"\n\nset -g prefix C-s\n\nset -g mouse on\n\nset-window-option -g mode-keys vi\n\nbind-key h select-pane -L\nbind-key j select-pane -D\nbind-key k select-pane -U\nbind-key l select-pane -R\n\nset-option -g status-position top\n\nset -g @catppuccin_window_status_style \"rounded\"\n\nset -g @plugin 'tmux-plugins/tpm'\nset -g @plugin 'christoomey/vim-tmux-navigator'\nset -g @plugin 'catppuccin/tmux#v2.1.0'\n\nset -g status-left \"\"\nset -g status-right \"\#{E:@catppuccin_status_application} \#{E:@catppuccin_status_session}\"\n\nrun '~/.tmux/plugins/tpm/tpm'\n\nset -g status-style bg=default" >~/.tmux.conf || {
        log_error "Failed to create ~/.tmux.conf file."
        return 1
    }

    log_success "TMUX configuration complete."
}

# --- Syncthing Configuration ---
configure_syncthing() {
    log_info "Configuring Syncthing..."
    sudo tee /etc/systemd/system/syncthing@${CONFIG_VALUES["Username"]}.service >/dev/null <<EOF
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization for %I
Documentation=man:syncthing(1)
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=4

[Service]
User=%i
ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --logflags=0
Restart=on-failure
RestartSec=1
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

ProtectSystem=full
PrivateTmp=true
SystemCallArchitectures=native
MemoryDenyWriteExecute=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable --now syncthing@${CONFIG_VALUES["Username"]}.service || {
        log_error "Failed to enable syncthing service."
        return 1
    }
    log_success "Syncthing configured."
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

# --- Git Credentials and SSH Setup ---
configure_git_ssh() {
    log_info "Configuring Git..."
    git config --global user.name "${CONFIG_VALUES["Full Name"]}"
    git config --global user.email "${CONFIG_VALUES["Email"]}"
    git config --global core.editor "nvim"
    log_success "Git configured."

    log_info "Generating SSH key..."
    ssh-keygen -t ed25519 -C "${CONFIG_VALUES["Email"]}" -N "" -f ~/.ssh/id_ed25519 || {
        log_error "Failed to generate SSH key."
        return 1
    }
    log_success "SSH key generated."

    log_info "Starting SSH agent and adding SSH key..."
    eval $(ssh-agent -s)
    ssh-add ~/.ssh/id_ed25519
    log_success "SSH agent started and key added."
}

# --- GPG Signing Setup ---
configure_gpg() {
    log_info "Configuring GPG for commit signing..."
    gpg --import ~/Backups/data/public-key.asc || {
        log_warning "Could not import public-key.asc"
    }
    gpg --import ~/Backups/data/private-key.asc || {
        log_warning "Could not import private-key.asc"
    }

    local SIGNING_KEY
    SIGNING_KEY=$(gpg --list-secret-keys --keyid-format=long | grep "commit" -B 2 | awk '/sec/{split($2, a, "/"); print a[2]}') || {
        log_error "Failed to retrieve GPG signing key."
        return 1
    }
    git config --global user.signingkey "$SIGNING_KEY"
    log_success "GPG configured for commit signing."
}

# --- GitHub Repository Cloning ---
clone_github_repos() {
    log_info "Importing Github repositories..."
    git clone --depth 1 git@github.com:shashotoNur/clone-repos.git ~/Workspace

    log_info "Logging in to GitHub CLI..."
    echo "${CONFIG_VALUES["Github Token"]}" | gh auth login --with-token

    mv ~/Workspace/clone-repos/clone.sh ~/Workspace/
    bash ~/Workspace/clone.sh

    rm -rf ~/Workspace/clone-repos ~/Workspace/clone.sh
    log_success "GitHub repositories cloned successfully."
}

# --- Music Playlist Setup ---
setup_music_playlist() {
    log_info "Fetching music playlist..."
    local MUSICDIR="~/Music/Sound Of My Life"

    mkdir -p "$MUSICDIR"
    cd "$MUSICDIR"
    pip install yt-dlp

    yt-dlp -x --audio-format mp3 --download-archive archive.txt --embed-thumbnail --embed-metadata "${CONFIG_VALUES["Music Playlist Link"]}" || {
        log_error "Failed to download music playlist."
        return 1
    }
    detox -r .
    log_success "Music playlist downloaded."
}

# --- Wikipedia Archive Download ---
download_wikipedia_archive() {
    log_info "Fetching Wikipedia archive..."
    local BASE_URL="https://dumps.wikimedia.org/other/kiwix/zim/wikipedia/"
    local LATEST_FILE

    LATEST_FILE=$(curl -s "$BASE_URL" | grep -oP "wikipedia_en_all_maxi_\d{4}-\d{2}.zim" | sort -t'_' -k4,4 -r | head -n 1) || {
        log_error "Failed to fetch latest Wikipedia ZIM filename."
        return 1
    }
    wget -c "$BASE_URL/$LATEST_FILE" || {
        log_error "Failed to download Wikipedia archive."
        return 1
    }
    log_success "Wikipedia archive downloaded."
}

# --- Timeshift Backup Configuration ---
configure_timeshift() {
    log_info "Configuring Timeshift..."
    sudo cp ~/Backups/timeshift/timeshift.json /etc/timeshift/timeshift.json
    sudo systemctl enable --now cronie.service
    sudo /etc/grub.d/41_snapshots-btrfs
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    sudo systemctl enable --now grub-btrfsd
    sudo sed -i 's|ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' /etc/systemd/system/grub-btrfsd.service || {
        log_error "Failed to edit grub-btrfsd service."
        return 1
    }

    log_success "Timeshift configured successfully."
}

# --- OneFileLinux Setup ---
setup_onefilelinux() {
    log_info "Setting up OneFileLinux..."
    wget -O ~/Backups/ISOs/OneFileLinux.efi "https://github.com/zhovner/OneFileLinux/releases/latest/download/OneFileLinux.efi" || {
        log_error "Failed to download OneFileLinux.efi."
        return 1
    }
    sudo cp ~/Backups/ISOs/OneFileLinux.efi /boot/efi/EFI/BOOT/

    echo 'menuentry "One File Linux" {
  search --file --no-floppy --set=root /EFI/Boot/OneFileLinux.efi
  chainloader /EFI/Boot/OneFileLinux.efi
}' | sudo tee -a /etc/grub.d/40_custom

    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "OneFileLinux setup completed."
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

# --- Neovim setup ---
setup_neovim() {
    log_info "Setting up Neovim..."
    git clone --depth 1 git@github.com:shashoto/nvim-config.git
    cp -r nvim-config ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    log_success "Neovim setup complete"
}

# --- Git Directory Linking ---
link_git_directories() {
    log_info "Adding $(.git) files to cloud synced directories"
    echo 'gitdir: ~/Workspace/Repositories/data/.git' | sudo tee ~/Documents/data/.git
    echo 'gitdir: ~/Workspace/Repositories/college-resources/.git' | sudo tee ~/Documents/college-resources/.git
    log_success "Linked git directories"
}

# --- Qbittorrent Theme Setup ---
setup_qbittorrent_theme() {
    log_info "Setting up QBittorrent theme..."
    local REPO="catppuccin/qbittorrent"
    local FILE_NAME="catppuccin-mocha.qbtheme"
    local SCRATCH_DIR="~/Scratch"

    local LATEST_VERSION=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | jq -r .tag_name) || {
        log_error "Failed to fetch the latest QBittorrent theme version."
        return 1
    }
    log_info "Latest release version: $LATEST_VERSION"

    mkdir -p "$SCRATCH_DIR"

    wget -O "$SCRATCH_DIR/$FILE_NAME" "https://github.com/$REPO/releases/download/$LATEST_VERSION/$FILE_NAME"
    log_success "Downloaded QBittorrent theme to: $SCRATCH_DIR/$FILE_NAME"
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

# --- SDDM Background Setup ---
set_sddm_background() {
    log_info "Setting up sddm background"
    local WALLPAPER_FILE=".config/hyde/themes/Catppuccin\ Mocha/wallpapers/cat_leaves.png"
    local TARGET_FILE="/usr/share/sddm/themes/Corners/backgrounds/bg.png"
    sudo cp "$WALLPAPER_FILE" "$TARGET_FILE"
    log_success "SDDM Background changed successfully"
}

# --- User Password Setup ---
set_user_password() {
    log_info "Setting user password..."
    echo "${CONFIG_VALUES["Username"]}:${CONFIG_VALUES["Root Password"]}" | sudo chpasswd || {
        log_error "Failed to set user password."
        return 1
    }
    log_success "User password set."
}

# --- Mega CMD Setup ---
setup_mega_cmd() {
    log_info "Setting up MegaCMD..."
    yay -S megacmd-bin ffmpeg-compat-59 --needed --noconfirm

    mega_login
    log_success "MegaCMD setup completed."
}

# Function to generate totp code
generate_totp_code() {
    log_info "Generating TOTP code..."
    local time_step=30
    local current_time
    local totp_code
    while true; do
        current_time=$(date +%s)
        local expiring_in=$((time_step - (current_time % time_step)))

        if [[ $expiring_in -ge 15 ]]; then
            totp_code=$(oathtool -b --totp "${CONFIG_VALUES["MEGA KEY"]}" -c $((current_time / time_step)) 2>&1) || {
                log_error "Failed to generate TOTP code."
                return 1
            }
            break
        else
            log_debug "Sleeping for $expiring_in seconds"
            sleep "$expiring_in"
        fi
    done
    log_debug "Generated TOTP code: $totp_code"
    echo "$totp_code"
}

# Function to log in to mega
mega_login() {
    local totp_code
    totp_code=$(generate_totp_code)
    log_info "Logging in to Mega..."
    mega-login "${CONFIG_VALUES["Email"]}" "${CONFIG_VALUES["Mega Password"]}" --auth-code="$totp_code" || {
        log_error "Failed to log in to Mega."
        return 1
    }

    local user
    user=$(mega-whoami | grep "Account e-mail:" | awk '{print $3}')

    if [[ "$user" == "${CONFIG_VALUES["Email"]}" ]]; then
        log_success "Login to mega.nz has been successful!"
        return 0
    else
        log_error "Login to mega.nz failed..."
        return 1
    fi
}

# --- Mega Sync Setup ---
setup_mega_sync() {
    log_info "Setting up Mega synchronization..."
    echo 'while IFS= read -r line; do
        mega-sync ~/"$line" "/$line"
    done <~/Documents/sync_directories.lst' >~/.config/hypr/megacmd-launch.sh || {
        log_error "Failed to create megacmd launch script."
        return 1
    }

    cp ~/Backups/sync_directories.lst ~/Documents/

    local last_exec_once
    last_exec_once=$(grep -n '^exec-once' ~/.config/hypr/hyprland.conf | tail -n 1 | cut -d ':' -f 1)
    sed -i "${last_exec_once}a exec-once = ~/.config/hypr/megacmd-launch.sh # start megacmd sync" ~/.config/hypr/hyprland.conf
    log_success "Mega synchronization setup completed."

    while IFS= read -r line; do
        mkdir -p ~/"$line"
        mega-sync ~/"$line" "/$line"
    done <~/Documents/sync_directories.lst
}

# --- Restore User Backups ---
restore_user_backups() {
    log_info "Restoring user backups..."
    local backup_base="~/Backups/data/home/"

    find "$backup_base" -maxdepth 1 -type d ! -name "." -print0 | while IFS= read -r -d $'\0' user_dir; do
        local user_name=$(basename "$user_dir")
        log_info "Restoring backup for user: $user_name"
        cp -r "$user_dir"/* ~/
    done
    log_success "Backup restoration for all users completed!"
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

################################################################################################
# Main Postinstallation Function
################################################################################################

postinstall() {
    # Load configuration
    load_configuration || exit 1

    # Mount USB
    readarray -t mount_info < <(mount_usb_drive)
    usb_device="${mount_info[0]}"
    multiboot_mount="${mount_info[1]}"
    storage_mount="${mount_info[2]}"
    log_debug "USB_DEVICE=$usb_device, MULTIBOOT_MOUNT=$multiboot_mount, STORAGE_MOUNT=$storage_mount"

    # Setup Internet
    setup_internet_connection || exit 1

    # System operations
    update_keymap || exit 1
    remove_cryptkey_and_delete_slot || exit 1
    setup_system_clock || exit 1
    update_pacman_mirrorlist || exit 1
    update_system_keyring || exit 1
    set_user_password || exit 1

    # Essential packages and configs
    install_essential_packages || exit 1
    create_user_directories || exit 1
    copy_backup_files "$usb_device" "$multiboot_mount" "$storage_mount" || exit 1

    # Bootloader, Network and app managment
    configure_bootloader_theme || exit 1
    configure_network || exit 1
    setup_flatpak || exit 1
    enable_chaotic_aur || exit 1

    # Apps
    install_pacman_applications || exit 1
    install_yay_applications || exit 1
    install_flatpak_applications || exit 1

    # Hyprland
    setup_hyprland || exit 1
    initialize_browser || exit 1
    restore_file_manager_config || exit 1
    restore_zsh_config || exit 1

    # System config
    setup_zram || exit 1
    configure_hdd_performance || exit 1
    update_firmware || exit 1
    set_numlock || exit 1
    setup_paccache || exit 1
    enable_system_commands || exit 1
    setup_network_time_protocol || exit 1
    setup_hdmi_sharing || exit 1
    limit_journal_size || exit 1
    disable_core_dump || exit 1
    prevent_overheating || exit 1
    optimize_network_congestion || exit 1
    setup_firewall || exit 1
    setup_bluetooth || exit 1
    setup_graphics_driver || exit 1
    setup_oomd || exit 1
    setup_avro_keyboard || exit 1
    setup_brightness_service || exit 1
    download_iptv_playlist || exit 1
    install_vscode_extensions || exit 1
    update_zen_browser_config || exit 1
    terminal_apps_setup || exit 1
    setup_gemini_console || exit 1
    configure_tmux || exit 1
    configure_syncthing || exit 1
    install_gaming_packages || exit 1
    setup_bottles || exit 1
    configure_git_ssh || exit 1
    configure_gpg || exit 1
    clone_github_repos || exit 1
    setup_music_playlist || exit 1
    download_wikipedia_archive || exit 1
    configure_timeshift || exit 1
    setup_onefilelinux || exit 1
    setup_apparmor_audit || exit 1
    setup_neovim || exit 1
    link_git_directories || exit 1
    setup_qbittorrent_theme || exit 1
    download_torrents || exit 1
    set_sddm_background || exit 1
    setup_mega_cmd || exit 1
    setup_mega_sync || exit 1
    setup_zsh || exit 1
    restore_user_backups || exit 1

    #QEMU setup
    setup_nixos_qemu_kvm || exit 1

    #Unmount and wipe USB
    unmount_usb_partitions "$usb_device" || exit 1
    wipe_usb_drive "$usb_device" || exit 1

    # System info
    log_system_info || exit 1

    echo "Post installation completed successfully."
}
################################################################################################
# --- Main Script Execution ---

postinstall "$@"
