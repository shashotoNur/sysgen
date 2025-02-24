#!/bin/bash

set -e  # Exit on error

# Check if system is booted in UEFI mode
UEFI_MODE=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "Not UEFI")
if [[ "$UEFI_MODE" != "64" && "$UEFI_MODE" != "32" ]]; then
    echo "Error: System is not booted in UEFI mode!"
    exit 1
fi

CONFIG_FILE="install_config.txt"

# If config file doesn't exist, run the script to generate it
if [[ ! -f "$CONFIG_FILE" ]]; then
    bash utils/getconfig.sh
fi

# Function to extract values
extract_value() {
    grep -E "^$1:" "$CONFIG_FILE" | awk -F': ' '{print $2}'
}

# Read configuration values
FULL_NAME=$(extract_value "Full Name")
EMAIL=$(extract_value "Email")
USERNAME=$(extract_value "Username")
HOSTNAME=$(extract_value "Hostname")
LOCAL_INSTALL=$(extract_value "Local Installation")
INSTALL_DRIVE=$(extract_value "Drive")
DRIVE_SIZE=$(extract_value "Drive Size")
BOOT_SIZE=$(extract_value "Boot Partition")
ROOT_SIZE=$(extract_value "Root Partition")
SWAP_SIZE=$(extract_value "Swap Partition")
HOME_SIZE=$(extract_value "Home Partition")
NETWORK_TYPE=$(extract_value "Network Type")
PASSWORD=$(extract_value "Password")
LUKS_PASS=$(extract_value "LUKS Password")
ROOT_PASS=$(extract_value "Root Password")

# Handle LUKS and Root passwords
if [[ -n "$PASSWORD" ]]; then
    LUKS_PASS=$PASSWORD
    ROOT_PASS=$PASSWORD
fi

# Handle WiFi details if applicable
if [[ "$NETWORK_TYPE" == "wifi" ]]; then
    WIFI_SSID=$(extract_value "WiFi SSID")
    WIFI_PASSWORD=$(extract_value "WiFi Password")
fi

# Debug: Print extracted variables (excluding passwords for security)
echo "Name: $FULL_NAME"
echo "Username: $USERNAME"
echo "Hostname: $HOSTNAME"
echo "Install Drive: $INSTALL_DRIVE"
echo "Drive Size: $DRIVE_SIZE"
echo "Boot: $BOOT_SIZE, Root: $ROOT_SIZE, Swap: $SWAP_SIZE, Home: $HOME_SIZE"
echo "Network Type: $NETWORK_TYPE"
[[ "$NETWORK_TYPE" == "wifi" ]] && echo "WiFi SSID: $WIFI_SSID"

# Wipe the selected drive
echo "Wiping $INSTALL_DRIVE..."
wipefs --all --force "$INSTALL_DRIVE"

# Partition the disk
echo "Creating partitions..."
parted -s "$INSTALL_DRIVE" mklabel gpt
parted -s "$INSTALL_DRIVE" mkpart primary fat32 1MiB "$BOOT_SIZE"
parted -s "$INSTALL_DRIVE" set 1 esp on
parted -s "$INSTALL_DRIVE" mkpart primary "$BOOT_SIZE" "$ROOT_SIZE"
if [[ "$SWAP_SIZE" != "0" ]]; then
    parted -s "$INSTALL_DRIVE" mkpart primary linux-swap "$ROOT_SIZE" "$SWAP_SIZE"
fi
parted -s "$INSTALL_DRIVE" mkpart primary "$SWAP_SIZE" "$HOME_SIZE"

# Get partition names dynamically
BOOT_PART="${INSTALL_DRIVE}1"
ROOT_PART="${INSTALL_DRIVE}2"
if [[ "$SWAP_SIZE" != "0" ]]; then
    SWAP_PART="${INSTALL_DRIVE}3"
    HOME_PART="${INSTALL_DRIVE}4"
else
    HOME_PART="${INSTALL_DRIVE}3"
fi

# Encrypt root and home partitions
echo "Encrypting root partition..."
echo -n "$LUKS_PASS" | cryptsetup luksFormat "$ROOT_PART"
echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot

echo "Encrypting home partition..."
echo -n "$LUKS_PASS" | cryptsetup luksFormat "$HOME_PART"
echo -n "$LUKS_PASS" | cryptsetup open "$HOME_PART" crypthome

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$BOOT_PART" -n BOOT
mkfs.btrfs -f /dev/mapper/cryptroot -L ROOT
mkfs.btrfs -f /dev/mapper/crypthome -L HOME
if [[ "$SWAP_SIZE" != "0" ]]; then
    mkswap "$SWAP_PART" -L SWAP
    swapon "$SWAP_PART"
fi

# Create Btrfs subvolumes
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt

# Mount subvolumes
mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o compress=zstd,subvol=@home /dev/mapper/crypthome /mnt/home

# Mount boot partition
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi

# Verify setup
lsblk -f "$INSTALL_DRIVE"

# Install base system
echo "Installing base system..."
pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers linux-zen linux-zen-headers linux-firmware nano vim networkmanager iw wpa_supplicant diaecho

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab

# Chroot into the new system
echo "Changing root"
arch-chroot /mnt /bin/bash

# Ensure partitions are unlocked at boot
echo "Configuring LUKS partitions to unlock at boot..."
echo "cryptroot  UUID=$(blkid -s UUID -o value $ROOT_PART)  none  luks" >> /etc/crypttab
echo "crypthome  UUID=$(blkid -s UUID -o value $HOME_PART)  none  luks" >> /etc/crypttab

# Update mkinitcpio HOOKS
echo "Updating mkinitcpio hooks..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block encrypt btrfs keyboard keymap consolefont fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Set root password
echo "Setting root password..."
echo "root:$ROOT_PASS" | chpasswd

# Create user and set password
echo "Creating user $USERNAME..."
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$ROOT_PASS" | chpasswd

# Ensure user has sudo privileges
echo "Configuring sudo privileges..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Set hostname
echo "Setting hostname..."
echo "$HOSTNAME" > /etc/hostname

# Configure /etc/hosts
echo "Configuring /etc/hosts..."
cat <<EOF > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME
EOF

# Configure locale
echo "Configuring locale..."
echo "LANG=en_AU.UTF-8" > /etc/locale.conf
echo "LC_ALL=en_AU.UTF-8" >> /etc/locale.conf
echo "en_AU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# Set timezone and sync hardware clock
echo "Setting timezone and syncing hardware clock..."
ln -sf /usr/share/zoneinfo/Asia/Dhaka /etc/localtime
hwclock --systohc

# Update and install necessary packages
echo "Installing essential packages..."
pacman -Sy --noconfirm grub efibootmgr dosfstools os-prober mtools fuse3

# Mount EFI partition and install GRUB
echo "Installing GRUB bootloader..."
mkdir -p /boot/efi
mount "$BOOT_PART" /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# Ensure cryptdevice is in GRUB boot parameters
echo "Configuring GRUB for LUKS..."
sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value $ROOT_PART):cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Backup the EFI file as a failsafe
mkdir /boot/efi/EFI/BOOT 
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

# Ensure internet
sudo systemctl enable --now NetworkManager.service

# Update keymap
echo "KEYMAP=us" | sudo tee /etc/vconsole.conf

# Install essential packages
sudo pacman -Syu --needed xdg-user-dirs alsa-firmware alsa-utils pipewire pipewire-alsa pipewire-pulse \
    pipewire-jack wireplumber wget git intel-ucode fuse2 lshw powertop inxi acpi plasma sddm dolphin konsole tree

# Create additional user directories
mkdir -p ~/Workspace ~/Backups ~/Archives ~/Scratch ~/Scripts ~/Games ~/Designs ~/Echos

# Create primary user dirs
xdg-user-dirs-update && ls

# Enable display manager
sudo systemctl enable --now sddm

# Retrieve and filter the latest pacman mirrorlist
sudo pacman -S --needed reflector
sudo reflector --verbose -c India -c China -c Japan -c Singapore -c US --protocol https --sort rate --latest 20 \
    --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist
sudo systemctl enable reflector.timer

# Disable KDE duplicate dunst activation
sudo mv /usr/share/dbus-1/services/org.kde.plasma.Notifications.service \
    /usr/share/dbus-1/services/org.kde.plasma.Notifications.service.disabled

# Bootloader theme setup
git clone --depth 1 https://github.com/shashotoNur/grub-dark-theme
sudo cp -r grub-dark-theme/theme /boot/grub/themes/
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
sudo sed -i 's|^#\?GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/theme/theme.txt"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Network configurations
sudo pacman -S --needed resolvconf nm-connection-editor networkmanager-openvpn
sudo systemctl enable systemd-resolved.service
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl enable --now wpa_supplicant.service

# Update system and keyring
sudo pacman -S --needed archlinux-keyring
sudo pacman-key --init && sudo pacman-key --populate archlinux
sudo pacman-key --refresh-keys
sudo pacman -Syu

# Setup Flatpak
sudo pacman -S --needed flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo rm -rf /var/tmp/flatpak-cache-*
flatpak uninstall --unused

# Setup shell and terminal
sudo pacman -S --needed zsh
zsh /usr/share/zsh/functions/Newuser/zsh-newuser-install -f
chsh -s $(which zsh)
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
sudo git clone --depth 1 https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
sudo git clone --depth 1 https://github.com/MichaelAquilina/zsh-you-should-use.git $ZSH_CUSTOM/plugins/you-should-use
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
zsh <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
cd ~/.config/fastfetch/pngs && find . -type f ! -name "arch.png" -delete
sudo git clone https://github.com/MichaelAquilina/zsh-auto-notify.git $ZSH_CUSTOM/plugins/auto-notify

# Install required apps and packages (Pacman)
sudo pacman -S --needed intel-media-driver grub-btrfs nodejs npm fortune-mod cowsay lolcat jrnl inotify-tools supertux \
    testdisk bat ripgrep bandwhich oath-toolkit asciinema neovim hexyl syncthing thefuck duf procs sl cmatrix gum \
    gnome-keyring dnsmasq dmenu btop eza hdparm tmux telegram-desktop ddgr less sshfs onefetch tmate navi code \
    nethogs tldr gping detox fastfetch bitwarden yazi direnv xorg-xhost rclone fwupd bleachbit picard timeshift \
    jp2a gparted obs-studio veracrypt rust aspell-en libmythes mythes-en languagetool pacseek kolourpaint kicad \
    kdeconnect cpu-x github-cli kolourpaint kalarm cpufetch kate plasma-browser-integration ark okular kamera \
    krename ipython filelight kdegraphics-thumbnailers qt5-imageformats kimageformats espeak-ng

# Install required apps and packages (Yay)
yay -S --needed ventoy-bin steghide go pkgx-git stacer-git nsnake gpufetch nudoku arch-update mongodb-bin \
    hyprland-qtutils pet-git musikcube tauon-music-box hollywood no-more-secrets nodejs-mapscii noti megasync-bin \
    mongodb-compass smassh affine-bin solidtime-bin ngrok scc rmtrash nomacs cbonsai vrms-arch-git browsh timer \
    sql-studio-bin posting lowfi dooit

# Install required apps and packages (Flatpak)
flatpak install -y com.github.tchx84.Flatseal io.ente.auth com.notesnook.Notesnook us.zoom.Zoom \
    org.speedcrunch.SpeedCrunch net.scribus.Scribus org.kiwix.desktop org.localsend.localsend_app \
    com.felipekinoshita.Wildcard io.github.prateekmedia.appimagepool com.protonvpn.www org.librecad.librecad \
    dev.fredol.open-tv org.kde.krita com.opera.Opera org.audacityteam.Audacity com.usebottles.bottles \
    io.github.zen_browser.zen org.torproject.torbrowser-launcher org.qbittorrent.qBittorrent \
    org.onlyoffice.desktopeditors org.blender.Blender org.kde.labplot2 org.kde.kwordquiz org.kde.kamoso \
    org.kde.skrooge org.kde.kdenlive

# Initialize browser
sudo pacman -S --needed firefox-developer-edition
echo "browser=firefox-developer-edition" >> ~/.config/hypr/keybindings.conf

# Configure zram
sudo systemctl enable --now zram

# Configure HDD performance
sudo systemctl enable --now hdparm.service
sudo hdparm -W 1 /dev/sda

# Firmware updates
yes | fwupdmgr get-updates

# Enable Paccache
sudo pacman -S --needed pacman-contrib
sudo systemctl enable paccache.timer

# Enable system commands for kernel
echo 'kernel.sysrq=1' | sudo tee /etc/sysctl.d/99-reisub.conf

# Configure network time protocol
sudo pacman -S --needed openntpd
sudo systemctl disable --now systemd-timesyncd
sudo systemctl enable openntpd

# HDMI Sharing
echo 'monitor = ,preferred,auto,1,mirror,eDP-1' >> ~/.config/hypr/hyprland.conf

echo "Starting system optimizations..."

# Limit journal size
echo "Configuring systemd journal size..."
sudo sed -i '/^#SystemMaxUse=/c\SystemMaxUse=256M' /etc/systemd/journald.conf
sudo sed -i '/^#MaxRetentionSec=/c\MaxRetentionSec=2weeks' /etc/systemd/journald.conf
sudo sed -i '/^#MaxFileSec=/c\MaxFileSec=1month' /etc/systemd/journald.conf
sudo sed -i '/^#Audit=/c\Audit=yes' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald

# Disable core dump
echo "Disabling core dumps..."
echo 'kernel.core_pattern=/dev/null' | sudo tee /etc/sysctl.d/50-coredump.conf
sudo sysctl -p /etc/sysctl.d/50-coredump.conf

# Prevent overheating
echo "Installing and configuring thermald..."
yay -S --needed --noconfirm thermald
sudo sed -i 's|ExecStart=.*|ExecStart=/usr/bin/thermald --no-daemon --dbus-enable --ignore-cpuid-check|' /usr/lib/systemd/system/thermald.service
sudo systemctl enable --now thermald

# Risky CPU optimization
echo "Applying CPU optimizations..."
sudo sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="mitigations=off"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Optimize network congestion algorithm
echo "Enabling BBR TCP congestion control..."
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee /etc/sysctl.d/98-misc.conf
sudo sysctl -p /etc/sysctl.d/98-misc.conf

# Setup firewall
echo "Installing and configuring UFW..."
sudo pacman -S --noconfirm ufw
sudo ufw limit 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo systemctl enable --now ufw
sudo ufw enable

# Setup Bluetooth
echo "Installing and enabling Bluetooth services..."
sudo pacman -S --noconfirm bluez bluez-utils blueman
sudo modprobe btusb
sudo systemctl enable --now bluetooth
rfkill unblock bluetooth

# Enable graphics driver
echo "Installing and configuring NVIDIA drivers..."
sudo pacman -S --needed --noconfirm nvidia-prime nvidia-dkms nvidia-settings nvidia-utils lib32-nvidia-utils lib32-opencl-nvidia opencl-nvidia libvdpau lib32-libvdpau libxnvctrl vulkan-icd-loader lib32-vulkan-icd-loader vkd3d lib32-vkd3d opencl-headers opencl-clhpp vulkan-validation-layers lib32-vulkan-validation-layers
sudo systemctl enable nvidia-persistenced.service
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="echolevel=3 quiet splash nvidia_drm.modeset=1 retbleed=off spectre_v2=retpoline,force nowatchdog mitigations=off"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)" | sudo tee -a /etc/mkinitcpio.conf
sudo mkinitcpio -P
echo "NVIDIA setup completed. Verify with: cat /sys/module/nvidia_drm/parameters/modeset"

# Memory management
echo "Enabling systemd OOMD..."
sudo systemctl enable --now systemd-oomd
sudo bash -c 'cat << EOF > /etc/systemd/system.conf
[Manager]
DefaultCPUAccounting=yes
DefaultIOAccounting=yes
DefaultMemoryAccounting=yes
DefaultTasksAccounting=yes
EOF'
sudo bash -c 'cat << EOF > /etc/systemd/oomd.conf
[OOM]
SwapUsedLimitPercent=90%
DefaultMemoryPressureDurationSec=20s
EOF'

# Setup Avro keyboard
echo "Installing and configuring Avro keyboard..."
yay -S --noconfirm ibus-avro-git
ibus-daemon -rxRd
echo -e "GTK_IM_MODULE=ibus\nQT_IM_MODULE=ibus\nXMODIFIERS=@im=ibus" | sudo tee -a /etc/environment
mkdir -p ~/.config/hypr
echo '#!/bin/bash
[ "$(ibus engine)" = "xkb:us::eng" ] && ibus engine ibus-avro || ibus engine xkb:us::eng' > ~/.config/hypr/toggle_ibus.sh
chmod +x ~/.config/hypr/toggle_ibus.sh
echo 'bind=SUPER,SPACE,exec,~/.config/hypr/toggle_ibus.sh' >> ~/.config/hypr/hyprland.conf
hyprctl reload

# Set default brightness
echo "Configuring brightness service..."
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
sudo systemctl enable --now set-brightness.service

# Download IPTV list
echo "Downloading IPTV playlist..."
wget -c https://iptv-org.github.io/iptv/index.m3u

# Setup VS Code extensions
echo "Installing VS Code extensions..."
if [ -f ext_list.txt ]; then
    while IFS= read -r extension; do
        code --install-extension "$extension" || echo "Error installing $extension"
    done < ext_list.txt
else
    echo "ext_list.txt not found, skipping..."
fi

# Setup preload
echo "Installing preload..."
yay -S --noconfirm preload
sudo systemctl enable --now preload

# Configure jrnl
echo "Setting up jrnl configuration..."
mkdir -p ~/.config/jrnl
echo -e "colors:\n  body: none\n  date: black\n  tags: yellow\n  title: cyan\ndefault_hour: 9\ndefault_minute: 0\neditor: 'nvim'\nencrypt: false\nhighlight: true\nindent_character: '|'\njournals:\n  default:\n    journal: /home/axiom/Documents/data/journal.txt\nlinewrap: 79\ntagsymbols: '#@'\ntemplate: false\ntimeformat: '%F %r'\nversion: v4.2" > ~/.config/jrnl/jrnl.yaml

# Gnome-keyring PAM initialization
echo "Configuring PAM for GNOME Keyring..."
echo -e "auth       optional     pam_gnome_keyring.so\nsession    optional     pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/login

# Install pip and disable global package install restriction
echo "Installing pip..."
sudo pacman -S --needed python-pip
sudo mv /usr/lib/python3.12/EXTERNALLY-MANAGED /usr/lib/python3.12/EXTERNALLY-MANAGED.old

# Install makedown
pip install makedown

# Install diff-so-fancy and configure git
echo "Installing diff-so-fancy..."
npm i -g diff-so-fancy
git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
git config --global interactive.diffFilter "diff-so-fancy --patch"
git config --global color.ui true

# Clone and set up Gemini console
echo "Setting up Gemini console..."
git clone --depth 1 https://github.com/flameface/gemini-console-chat.git ~/Scripts/
cd ~/Scripts/gemini-console-chat
npm install
sed -i 's/YOUR_API_KEY/$GEMINI_API_KEY/' index.js

# Configure TMUX
echo "Configuring TMUX..."
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
cat <<EOF > ~/.tmux.conf
unbind r
bind r source-file ~/.tmux.conf

set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"

set -g prefix C-s

set -g mouse on

set-window-option -g mode-keys vi

bind-key h select-pane -L
bind-key j select-pane -D
bind-key k select-pane -U
bind-key l select-pane -R

set-option -g status-position top

set -g @catppuccin_window_status_style "rounded"

set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'christoomey/vim-tmux-navigator'
set -g @plugin 'catppuccin/tmux#v2.1.0'

set -g status-left ""
set -g status-right "#{E:@catppuccin_status_application} #{E:@catppuccin_status_session}"

run '~/.tmux/plugins/tpm/tpm'

set -g status-style bg=default
EOF

# Configure Syncthing
echo "Configuring Syncthing..."
echo "[Unit]
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
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/syncthing@axiom.service
sudo systemctl enable --now syncthing@axiom.service

# Install AppImageLauncher
yay -S --needed appimagelauncher-bin

# Install gaming packages
echo "Installing gaming packages..."
sudo pacman -S --needed gamemode lib32-gamemode gamescope
sudo pacman -S --needed wine wine-gecko wine-mono && sudo systemctl restart systemd-binfmt
sudo pacman -S --needed fluidsynth lib32-fluidsynth gvfs gvfs-nfs libkate gst-plugins-good gst-plugins-bad gst-libav lib32-gst-plugins-good gst-plugin-gtk lib32-gstreamer lib32-gst-plugins-base-libs lib32-libxvmc libxvmc smpeg faac x264 lib32-pipewire pipewire-zeroconf mac lib32-opencl-icd-loader

# Configure Git with credentials
echo "Configuring Git..."
git config --global user.name "Shashoto Nur"
git config --global user.email "shashoto.nur@proton.me"
git config --global core.editor "nvim"

ssh-keygen -t ed25519 -C "shashoto.nur@proton.me"
cat ~/.ssh/id_ed25519.pub

eval `ssh-agent -s`
ssh-add ~/.ssh/id_ed25519

# Configure GPG for signing
echo "Configuring GPG for commit signing..."
gpg --import public-key.asc
gpg --import private-key.asc
SIGNING_KEY=$(gpg --list-secret-keys --keyid-format=long | awk '/sec/{getline; print $1}')
git config --global user.signingkey $SIGNING_KEY

# Import Github repositories
git clone --depth 1 git@github.com:shashotoNur/clone-repos.git ~/Workspace

echo "Fetching Wikipedia archive..."
BASE_URL="https://dumps.wikimedia.org/other/kiwix/zim/wikipedia/"
LATEST_FILE=$(curl -s "$BASE_URL" | grep -oP "wikipedia_en_all_maxi_\d{4}-\d{2}.zim" | sort -t'_' -k4,4 -r | head -n 1)
wget -c "$BASE_URL/$LATEST_FILE"

# Setup Timeshift for backups
echo "Configuring Timeshift..."
sudo systemctl enable --now cronie.service
sudo /etc/grub.d/41_snapshots-btrfs
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo systemctl enable --now grub-btrfsd
sudo systemctl edit --full grub-btrfsd
sed -i 's|ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' /etc/systemd/system/grub-btrfsd.service

# Add OneFileLinux to boot
echo "Setting up OneFileLinux..."
wget -O ~/Backups/ISOs/OneFileLinux.efi "https://github.com/zhovner/OneFileLinux/releases/latest/download/OneFileLinux.efi"
sudo cp ~/Backups/ISOs/OneFileLinux.efi /boot/efi/EFI/BOOT/
echo 'menuentry "One File Linux" {
  search --file --no-floppy --set=root /EFI/Boot/OneFileLinux.efi
  chainloader /EFI/Boot/OneFileLinux.efi
}' | sudo tee -a /etc/grub.d/40_custom
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "Post-installation setup completed successfully!"
