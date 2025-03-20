#!/bin/bash

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

# --- Essential Application Installation (Yay) ---
install_yay_applications() {
    log_info "Installing Yay applications..."

    local packages=(
        ventoy-bin steghide go pkgx-git stacer-git nsnake gpufetch nudoku arch-update mongodb-bin doggo-bin
        hyprland-qtutils pet-git musikcube tauon-music-box hollywood no-more-secrets nodejs-mapscii shc
        noti megasync-bin mongodb-compass smassh affine-bin solidtime-bin ngrok scc rmtrash nomacs cbonsai
        vrms-arch-git browsh timer sql-studio-bin posting dooit edex-ui-bin trash-cli-git appimagelauncher-bin
    )

    yay -S --needed --noconfirm "${packages[@]}" || {
        log_error "Failed to install Yay applications."
        return 1
    }
    log_success "Yay applications installed."
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
