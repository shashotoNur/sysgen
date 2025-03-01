#!/bin/bash

CONFIG_FILE="install.conf"

# If config file doesn't exist, run the script to generate it
[[ ! -f "$CONFIG_FILE" ]] && exit 1

# Function to extract values
extract_value() {
    grep -E "^$1:" "$CONFIG_FILE" | awk -F': ' '{print $2}'
}

# Read configuration values
declare -A CONFIG_VALUES
for key in "Full Name" "Email" "Username" "Hostname" "Local Installation" "Drive" "Drive Size" \
    "Boot Partition" "Root Partition" "Swap Partition" "Home Partition" "Network Type" \
    "Password" "LUKS Password" "Root Password" "WiFi SSID" "WiFi Password"; do
    CONFIG_VALUES["$key"]=$(extract_value "$key")
done

# Mount the USB drive
usb_device=$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')
multiboot_mount="/mnt/multiboot"
storage_mount="/mnt/storage"

sudo mkdir -p "$multiboot_mount"
sudo mkdir -p "$storage_mount"

sudo mount "${usb_device}1" "$multiboot_mount"
sudo mount "${usb_device}3" "$storage_mount"

# Ensure internet
sudo systemctl enable --now NetworkManager.service
nmcli device wifi connect ${CONFIG_VALUES["WiFi SSID"]} password ${CONFIG_VALUES["WiFi Password"]}

# Update keymap
echo "KEYMAP=us" | sudo tee /etc/vconsole.conf

# Remove cryptkey boot parameter safely & delete the slot for keyfile
sudo sed -i 's/ cryptkey=UUID=[^ ]*\( \|"\)/\1/g' /etc/default/grub
SECOND_SLOT=1  # slots start from zero; first slot is for passphrase
sudo cryptsetup luksKillSlot "${CONFIG_VALUES["Drive"]}2" $SECOND_SLOT

# Set up the system clock
sudo localectl set-locale LANG=en_AU.UTF-8
sudo timedatectl set-ntp true

# Install essential packages
sudo pacman -Syu --noconfirm --needed xdg-user-dirs alsa-firmware alsa-utils pipewire pipewire-alsa pipewire-pulse \
    pipewire-jack wireplumber wget git intel-ucode fuse2 lshw powertop inxi acpi plasma sddm dolphin konsole \
    tree downgrade xdg-desktop-portal-gtk emote mangohud cava

# Create additional user directories
mkdir -p ~/Workspace ~/Backups ~/Archives ~/Scratch ~/Scripts ~/Games ~/Designs ~/Logs
mkdir -p ~/Backups/ISOs

# Create primary user dirs
xdg-user-dirs-update && ls

# Copy the backup to disk
cp -r $storage_mount/backup/* ~/Backups/
cp -r $multiboot_mount/* ~/Backups/ISOs

# Unmount USB drive
sudo umount "${usb_device}1"
sudo umount "${usb_device}3"

# Wipe the USB drive
sudo wipefs --all "${usb_device}"

# Enable display manager
sudo systemctl enable sddm

# Retrieve and filter the latest pacman mirrorlist
sudo pacman -S --needed --noconfirm reflector
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
sudo pacman -S --needed --noconfirm resolvconf nm-connection-editor networkmanager-openvpn
sudo systemctl enable systemd-resolved.service
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl enable --now wpa_supplicant.service

# Update system and keyring
sudo pacman -S --needed --noconfirm archlinux-keyring
sudo pacman-key --init && sudo pacman-key --populate archlinux
sudo pacman -Syu

# Setup Flatpak
sudo pacman -S --needed --noconfirm flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Setup shell and terminal
zsh /usr/share/zsh/functions/Newuser/zsh-newuser-install -f
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "Setting up zsh plugins..."
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

# Enable Chaotic AUR
echo "Enabling Chaotic AUR..."
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf

# Install required apps and packages (Pacman)
sudo pacman -S --needed --noconfirm intel-media-driver grub-btrfs nodejs npm fortune-mod cowsay lolcat jrnl inotify-tools supertux \
    testdisk bat ripgrep bandwhich oath-toolkit asciinema neovim hexyl syncthing thefuck duf procs sl cmatrix gum \
    gnome-keyring dnsmasq dmenu btop eza hdparm tmux telegram-desktop ddgr less sshfs onefetch tmate navi code \
    nethogs tldr gping detox fastfetch bitwarden yazi aria2 direnv xorg-xhost rclone fwupd bleachbit picard timeshift \
    jp2a gparted obs-studio veracrypt rust aspell-en libmythes mythes-en languagetool pacseek kolourpaint kicad \
    kdeconnect cpu-x github-cli kolourpaint kalarm cpufetch kate plasma-browser-integration ark okular kamera \
    krename ipython filelight kdegraphics-thumbnailers qt5-imageformats mdless kimageformats espeak-ng armagetronad

# Install required apps and packages (Yay)
yay -S --needed --noconfirm ventoy-bin steghide go pkgx-git stacer-git nsnake gpufetch nudoku arch-update mongodb-bin \
    hyprland-qtutils pet-git musikcube tauon-music-box hollywood no-more-secrets nodejs-mapscii noti megasync-bin \
    mongodb-compass smassh affine-bin solidtime-bin ngrok scc rmtrash nomacs cbonsai vrms-arch-git browsh timer \
    sql-studio-bin posting dooit edex-ui-bin trash-cli-git

# Install required apps and packages (Flatpak)
flatpak install -y com.github.tchx84.Flatseal io.ente.auth com.notesnook.Notesnook us.zoom.Zoom \
    org.speedcrunch.SpeedCrunch net.scribus.Scribus org.kiwix.desktop org.localsend.localsend_app \
    com.felipekinoshita.Wildcard io.github.prateekmedia.appimagepool com.protonvpn.www org.librecad.librecad \
    dev.fredol.open-tv org.kde.krita com.opera.Opera org.audacityteam.Audacity com.usebottles.bottles \
    io.github.zen_browser.zen org.torproject.torbrowser-launcher org.qbittorrent.qBittorrent \
    org.onlyoffice.desktopeditors org.blender.Blender org.kde.labplot2 org.kde.kwordquiz org.kde.kamoso \
    org.kde.skrooge org.kde.kdenlive md.obsidian.Obsidian

# Install and configure hyprland with HyDE
git clone --depth 1 https://github.com/prasanthrangan/hyprdots ~/HyDE
bash ~/HyDE/Scripts/install.sh

# Install spf
bash -c "$(curl -sLo- https://superfile.netlify.app/install.sh)"

# Initialize browser
sudo pacman -S --needed --noconfirm firefox-developer-edition
sed -i 's/browser=firefox/browser=firefox-developer-edition/' ~/.config/hypr/keybindings.conf

# Restore file manager configurations
cp ~/Backups/dolphin/dolphinrc ~/.config/dolphinrc
cp ~/Backups/dolphin/dolphinui.rc ~/.local/share/kxmlgui5/dolphin/dolphinui.rc

# Restore zsh configuration
cp ~/Backups/zsh/.zshrc ~/.zshrc

# Create the zram service file
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

# Enable and check the zram service
sudo systemctl enable --now zram.service
sudo systemctl status zram.service

# Check swap usage
sudo swapon --show

# Configure HDD performance
sudo systemctl enable --now hdparm.service
sudo hdparm -W 1 /dev/sda

# Firmware updates
yes | fwupdmgr get-updates

# Configure numlock to be on by default
yay -S --needed --noconfirm mkinitcpio-numlock
sed -i '/^HOOKS=/ s/\bencrypt\b/numlock encrypt/' /etc/mkinitcpio.conf # Replace 'encrypt' with 'numlock encrypt'
sudo mkinitcpio -P
echo "Numlock=on" | sudo tee -a "/etc/sddm.conf"

# Enable Paccache
sudo pacman -S --needed --noconfirm pacman-contrib
sudo systemctl enable paccache.timer

# Enable system commands for kernel
echo 'kernel.sysrq=1' | sudo tee /etc/sysctl.d/99-reisub.conf

# Configure network time protocol
sudo pacman -S --needed --noconfirm openntpd
sudo systemctl disable --now systemd-timesyncd
sudo systemctl enable openntpd
sudo sed -i '/^servers/i server 0.pool.ntp.org\nserver 1.pool.ntp.org\nserver 2.pool.ntp.org\nserver 3.pool.ntp.org' /etc/ntpd.conf
echo "0.0" | sudo tee -a "/var/db/ntpd.drift"

# HDMI Sharing
sed -i 's/^monitor =/#&/; /^#monitor =/a monitor = ,preferred,auto,1,mirror,eDP-1' ~/.config/hypr/hyprland.conf

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

# Prevent overheating
echo "Installing and configuring thermald..."
yay -S --needed --noconfirm thermald
sudo sed -i 's|ExecStart=.*|ExecStart=/usr/bin/thermald --no-daemon --dbus-enable --ignore-cpuid-check|' /usr/lib/systemd/system/thermald.service
sudo systemctl enable --now thermald

# Optimize network congestion algorithm
echo "Enabling BBR TCP congestion control..."
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee /etc/sysctl.d/98-misc.conf
sudo sysctl -p /etc/sysctl.d/98-misc.conf

# Setup firewall
echo "Installing and configuring UFW..."
sudo pacman -S --needed --noconfirm ufw
sudo ufw limit 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 1714:1764/udp # for KDE Connect
sudo ufw allow 1714:1764/tcp
sudo systemctl enable --now ufw
sudo ufw enable

# Setup Bluetooth
echo "Installing and enabling Bluetooth services..."
sudo pacman -S --needed --noconfirm bluez bluez-utils blueman
sudo modprobe btusb
sudo systemctl enable --now bluetooth

# Enable graphics driver
echo "Installing and configuring NVIDIA drivers..."
sudo pacman -S --needed --noconfirm nvidia-prime nvidia-dkms nvidia-settings nvidia-utils lib32-nvidia-utils lib32-opencl-nvidia opencl-nvidia libvdpau lib32-libvdpau libxnvctrl vulkan-icd-loader lib32-vulkan-icd-loader vkd3d lib32-vkd3d opencl-headers opencl-clhpp vulkan-validation-layers lib32-vulkan-validation-layers
sudo systemctl enable nvidia-persistenced.service
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$|GRUB_CMDLINE_LINUX_DEFAULT="\1 echolevel=3 quiet splash nvidia_drm.modeset=1 retbleed=off spectre_v2=retpoline,force nowatchdog mitigations=off"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo sed -i 's/MODULES=\((.*)\)/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sudo mkinitcpio -P
echo "NVIDIA setup completed. Verify with: cat /sys/module/nvidia_drm/parameters/modeset"

# Memory management with OOMD
echo "Enabling and configuring systemd OOMD..."
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

# Setup Avro keyboard
echo "Installing and configuring Avro keyboard..."
yay -S --noconfirm ibus-avro-git
ibus-daemon -rxRd
echo -e "GTK_IM_MODULE=ibus\nQT_IM_MODULE=ibus\nXMODIFIERS=@im=ibus" | sudo tee -a /etc/environment
echo '#!/bin/bash
[ "$(ibus engine)" = "xkb:us::eng" ] && ibus engine ibus-avro || ibus engine xkb:us::eng' >~/.config/hypr/toggle_ibus.sh
chmod +x ~/.config/hypr/toggle_ibus.sh
echo 'bind=SUPER,SPACE,exec,~/.config/hypr/toggle_ibus.sh' >>~/.config/hypr/hyprland.conf

# Insert ibus command after the last line starting with "exec-once"
last_exec_once=$(grep -n '^exec-once' ~/.config/hypr/hyprland.conf | tail -n 1 | cut -d ':' -f 1)
sed -i "${last_exec_once}a exec-once = ibus-daemon -rxRd # start ibus demon" ~/.config/hypr/hyprland.conf

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
wget -c -P ~/Scratch/iptv_playlist.m3u https://iptv-org.github.io/iptv/index.m3u

# Setup VS Code extensions
echo "Installing VS Code extensions..."
EXTLIST_FILE=~/Backups/code/ext.lst
if [ -f $EXTLIST_FILE ]; then
    while IFS= read -r extension; do
        code --install-extension "$extension" || echo "Error installing $extension"
    done <$EXTLIST_FILE
else
    echo "$EXTLIST_FILE not found, skipping..."
fi

# Update Zen browser config
# Define the configs to check and replace/add
configs=(
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

profile_dir_name=$(cat ~/.var/app/app.zen_browser.zen/.zen/installs.ini | grep "Default=" | cut -d '=' -f 2)
prefs_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "prefs.js" -path "*/$profile_dir_name/*")
search_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "search.json.mozlz4" -path "*/$profile_dir_name/*")
theme_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "zen-themes.css" -path "*/$profile_dir_name/*")

for config in "${configs[@]}"; do
  # Extract the prefix (part before the first comma)
  prefix=$(echo "$config" | cut -d ',' -f 1)

  # Check if the config exists in the file
  if grep -q "$prefix" "$prefs_file"; then
    # Replace the line
    sed -i "/$prefix/c\\$config" "$prefs_file"
    echo "Replaced: $config"
  else
    # Add the line to the end of the file
    echo "$config" >> "$prefs_file"
    echo "Added: $prefix"
  fi
done

mv ~/Backups/zen/search.json.mozlz4 "$search_file"
wget -c -P "$HOME/Scratch/ublock-ytshorts.txt" https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt

echo "Adding code to zen-themes.css..."
echo "a[href$=\".pdf\"]:after {
  font-size: smaller;
  content: \" [pdf] \";
}" >> "$theme_file"

echo "Zen configurations have been updated!"

# Setup preload
echo "Installing preload..."
yay -S --noconfirm preload
sudo systemctl enable --now preload

# Configure jrnl
echo "Setting up jrnl configuration..."
mkdir -p ~/.config/jrnl
echo -e "colors:\n  body: none\n  date: black\n  tags: yellow\n  title: cyan\ndefault_hour: 9\ndefault_minute: 0\neditor: 'nvim'\nencrypt: false\nhighlight: true\nindent_character: '|'\njournals:\n  default:\n    journal: /home/${CONFIG_VALUES["Username"]}/Documents/data/journal.txt\nlinewrap: 79\ntagsymbols: '#@'\ntemplate: false\ntimeformat: '%F %r'\nversion: v4.2" >~/.config/jrnl/jrnl.yaml

# Gnome-keyring PAM initialization
echo "Configuring PAM for GNOME Keyring..."
sudo sed -i '/^auth /i auth       optional     pam_gnome_keyring.so' /etc/pam.d/login
sudo sed -i '/^session /i session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/login

# Install pip and disable global package install restriction
echo "Installing pip..."
sudo pacman -S --needed --noconfirm python-pip
PY_VER=$(python --version 2>&1 | awk '{print $2}' | cut -d '.' -f 1,2)
sudo mv /usr/lib/python$PY_VER/EXTERNALLY-MANAGED /usr/lib/python$PY_VER/EXTERNALLY-MANAGED.old

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
sed -i 's/YOUR_API_KEY/$CONFIG_VALUES["Gemini API Key"]/' index.js

# Configure TMUX
echo "Configuring TMUX..."
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
cat <<EOF >~/.tmux.conf
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
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/syncthing@${CONFIG_VALUES["Username"]}.service
sudo systemctl enable --now syncthing@${CONFIG_VALUES["Username"]}.service

# Install AppImageLauncher
yay -S --needed appimagelauncher-bin

# Install gaming packages
echo "Installing gaming packages..."
sudo pacman -S --needed --noconfirm gamemode lib32-gamemode gamescope
sudo pacman -S --needed --noconfirm wine wine-gecko wine-mono && sudo systemctl restart systemd-binfmt
sudo pacman -S --needed --noconfirm fluidsynth lib32-fluidsynth gvfs gvfs-nfs libkate gst-plugins-good gst-plugins-bad gst-libav lib32-gst-plugins-good gst-plugin-gtk lib32-gstreamer lib32-gst-plugins-base-libs lib32-libxvmc libxvmc smpeg faac x264 lib32-pipewire pipewire-zeroconf mac lib32-opencl-icd-loader

# Provide user files access to bottles
flatpak override --filesystem=home com.usebottles.bottles

# Create a gaming bottle
echo "Creating a gaming bottle..."
flatpak run --command=bottles-cli com.usebottles.bottles new --bottle-name GamingBottle --environment gaming

# Configure Git with credentials
echo "Configuring Git..."
git config --global user.name ${CONFIG_VALUES["Full Name"]}
git config --global user.email ${CONFIG_VALUES["Email"]}
git config --global core.editor "nvim"

ssh-keygen -t ed25519 -C "${CONFIG_VALUES["Email"]}"
cat ~/.ssh/id_ed25519.pub

eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519

# Configure GPG for signing
echo "Configuring GPG for commit signing..."
gpg --import public-key.asc
gpg --import private-key.asc
SIGNING_KEY=$(gpg --list-secret-keys --keyid-format=long | grep "commit" -B 2 | awk '/sec/{split($2, a, "/"); print a[2]}')
git config --global user.signingkey $SIGNING_KEY

# Import Github repositories
git clone --depth 1 git@github.com:shashotoNur/clone-repos.git ~/Workspace
echo "$CONFIG_VALUES["Github Token"]" | gh auth login --with-token
cd ~/Workspace/clone-repos && ./clone.sh

# Import music playlist
echo "Fetching music playlist..."
MUSICDIR=~/Music/Sound\ Of\ My\ Life && mkdir -p $MUSICDIR && cd $MUSICDIR
pip install yt-dlp
yt-dlp -x --audio-format mp3 --download-archive archive.txt --embed-thumbnail --embed-metadata CONFIG_VALUES["Music Playlist Link"]
detox -r .

# Fetch Wikipedia archive
echo "Fetching Wikipedia archive..."
BASE_URL="https://dumps.wikimedia.org/other/kiwix/zim/wikipedia/"
LATEST_FILE=$(curl -s "$BASE_URL" | grep -oP "wikipedia_en_all_maxi_\d{4}-\d{2}.zim" | sort -t'_' -k4,4 -r | head -n 1)
wget -c "$BASE_URL/$LATEST_FILE"

# Setup Timeshift for backups
echo "Configuring Timeshift..."
sudo cp ~/Backups/timeshift/timeshift.json /etc/timeshift/timeshift.json
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

echo "Setting up AppArmor..."

# Check available security modules
echo "Checking available security modules..."
LSM=$(cat /sys/kernel/security/lsm)

# Modify kernel options
echo "Modifying kernel options..."
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$|GRUB_CMDLINE_LINUX_DEFAULT="\1 lsm=apparmor,$LSM audit=1 audit_backlog_limit=8192"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Install and enable AppArmor and Audit
echo "Installing and enabling AppArmor and Audit..."
sudo pacman -S --needed --noconfirm apparmor
sudo systemctl enable --now apparmor.service
sudo systemctl enable --now auditd.service

# Enable reading Audit logs
echo "Setting up Audit log reading..."
sudo groupadd -r audit
sudo gpasswd -a $USER audit
sudo sed -i 's/^log_group =.*/log_group = audit/' /etc/audit/auditd.conf

# Increase netlink buffer size
echo "Increasing netlink buffer size..."
echo "net.core.rmem_max = 8388608" | sudo tee -a /etc/sysctl.conf
echo "net.core.wmem_max = 8388608" | sudo tee -a /etc/sysctl.conf

# Increase audit buffer size
echo "Increasing audit buffer size..."
sudo sed -i '$a-b 65536' /etc/audit/audit.rules

# Create desktop launcher for AppArmor notifications
echo "Creating AppArmor notification desktop launcher..."
mkdir -p ~/.config/autostart
cat <<EOF >~/.config/autostart/apparmor-notify.desktop
[Desktop Entry]
Type=Application
Name=AppArmor Notify
Comment=Receive on screen notifications of AppArmor denials
TryExec=aa-notify
Exec=aa-notify -p -s 1 -w 60 -f /var/log/audit/audit.log
StartupNotify=false
NoDisplay=true
EOF

# Enable caching AppArmor profiles
echo "Enabling AppArmor profile caching..."
sudo sed -i 's/^#write-cache/write-cache/' /etc/apparmor/parser.conf

echo "AppArmor setup complete."

echo "Setting up Nixos on QEMU-KVM..."
# Check CPU virtualization support
if ! lscpu | grep -i Virtualization | grep -q VT-x; then
    echo "Error: CPU does not support virtualization (VT-x)"
fi

# Install required packages
echo "Installing required packages..."
sudo pacman -S --needed --noconfirm qemu-full qemu-img libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm guestfs-tools libosinfo
yay -S --needed tuned

# Enable libvirt
echo "Enabling libvirt service..."
sudo systemctl enable libvirtd.service

# Enable IOMMU
echo "Enabling IOMMU..."
sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$|GRUB_CMDLINE_LINUX_DEFAULT="\1 intel_iommu=on iommu=pt"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Enable TuneD
echo "Enabling TuneD..."
sudo systemctl enable --now tuned.service
sudo tuned-adm profile virtual-host
sudo tuned-adm verify

# Configure libvirt
echo "Configuring libvirt..."
sudo sed -i '/#unix_sock_group = "libvirt"/s/^#//' /etc/libvirt/libvirtd.conf
sudo sed -i '/#unix_sock_rw_perms = "0770"/s/^#//' /etc/libvirt/libvirtd.conf

# Add user to libvirt group
echo "Adding user to libvirt group..."
sudo usermod -aG libvirt $USER

# Create a sample VM
echo "Creating a sample VM..."
qemu-img create -f qcow2 ~/Workspace/virtdisk.img 128G

url="https://nixos.org/download/"
link=$(curl -s "$url" | grep -oE 'https://channels.nixos.org/nixos-[^/]+/latest-nixos-gnome-x86_64-linux.iso' | head -n 1)
wget -c -P ~/Backups/ISOs/ "$link"

ISO_FILE=$(basename $link)
echo "To install OS on VM, run:"
echo "qemu-system-x86_64 -enable-kvm -cdrom ~/Backups/ISOs/$ISO_FILE -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on"
echo "To start VM once installed, run:"
echo "qemu-system-x86_64 -enable-kvm -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on"

# Setup Neovim
echo "Setting up Neovim..."
git clone --depth 1 git@github.com:shashoto/nvim-config.git
cp -r nvim-config ~/.config/nvim
rm -rf ~/.config/nvim/.git

# Add `.git` files to cloud synced directories
echo 'gitdir: ~/Workspace/Repositories/data/.git' | sudo tee ~/Documents/data/.git
echo 'gitdir: ~/Workspace/Repositories/college-resources/.git' | sudo tee ~/Documents/college-resources/.git

# Get Qbittorrent theme
echo "Setting up QBittorrent theme..."
REPO="catppuccin/qbittorrent"
FILE_NAME="catppuccin-mocha.qbtheme"

# Fetch the latest release version using GitHub API
LATEST_VERSION=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | jq -r .tag_name)
echo "Latest release version: $LATEST_VERSION"

# Download the file to the specified directory
wget -O ~/Scratch/"$FILE_NAME" "https://github.com/$REPO/releases/download/$LATEST_VERSION/$FILE_NAME"
echo "Downloaded $FILE_NAME to $DEST_DIR"

echo "Torrents are about to start..."
TORRENT_FILES=(~/Backups/torrents/*.torrent)

if [[ ! -e "${TORRENT_FILES[0]}" ]]; then
    echo "No torrent files found in ~/Backups/torrents/"
else
    for TORRENT_FILE in "${TORRENT_FILES[@]}"; do
        echo "Starting download for: $TORRENT_FILE"
        aria2c --dir=~/Scratch/ --seed-time=0 --follow-torrent=mem --max-concurrent-downloads=5 \
            --bt-max-peers=50 --bt-tracker-connect-timeout=10 --bt-tracker-timeout=10 \
            --bt-tracker-interval=60 --bt-stop-timeout=300 "$TORRENT_FILE"
    done
    echo "All downloads completed."
fi

# Change sddm background
sudo cp .config/hyde/themes/Catppuccin\ Mocha/wallpapers/cat_leaves.png /usr/share/sddm/themes/Corners/backgrounds/bg.png

# Set user password
echo "${CONFIG_VALUES["Username"]}:${CONFIG_VALUES["Root Password"]}" | sudo chpasswd

# Set up Mega CMD for background synchronization
yay -S megacmd-bin ffmpeg-compat-59 --needed --noconfirm

time_step=30

while true; do
    current_time=$(date +%s)
    expiring_in=$((time_step - (current_time % time_step)))

    if [[ $expiring_in -ge 15 ]]; then
        totp_code=$(oathtool -b --totp "$CONFIG_VALUES["MEGA KEY"]" -c $((current_time / time_step)) 2>&1)
        break
    else
        sleep "$expiring_in"
    fi
done

# Log in to MegaSync
echo "Logging in to MegaSync..."
mega-login $CONFIG_VALUES["Username"] $CONFIG_VALUES["Mega Password"] --auth-code="$totp_code"

# Get the email from mega-whoami
user=$(mega-whoami | grep "Account e-mail:" | awk '{print $3}')

# Verify login status
if [[ "$user" == "${CONFIG_VALUES["Email"]}" ]]; then
    echo "Login to mega.nz has been successful!"

    while IFS= read -r line; do
        mkdir -p ~/"$line"
        mega-sync ~/"$line" "/$line"
    done <selected_directories.txt

    # Ensure megacmd launches on boot
    echo 'while IFS= read -r line; do
        mega-sync ~/"$line" "/$line"
    done <~/Documents/sync_directories.lst' > ~/.config/hypr/megacmd-launch.sh

    cp ~/Backups/sync_directories.lst ~/Documents/

    last_exec_once=$(grep -n '^exec-once' ~/.config/hypr/hyprland.conf | tail -n 1 | cut -d ':' -f 1)
    sed -i "${last_exec_once}a exec-once = ~/.config/hypr/megacmd-launch.sh # start megacmd sync" ~/.config/hypr/hyprland.conf
else
    echo "Login to mega.nz failed..."
fi

# Log system information
systemd-analyze plot >~/Logs/boot.svg
sudo systemd-analyze blame >~/Logs/blame.txt
journalctl -p err..alert >~/Logs/journal.log

sudo hdparm -Tt /dev/sda >~/Logs/storage.log
sudo pacman -S --needed --noconfirm sysbench && sysbench --threads="$(nproc)" --cpu-max-prime=20000 cpu run >~/Logs/cpu.log

sudo pacman -S --needed --noconfirm fio && sudo fio --filename=/mnt/test.fio --size=8GB --direct=1 --rw=randrw --bs=4k --ioengine=libaio --iodepth=256 --runtime=120 --numjobs=4 --time_based --group_reporting --name=iops-test-job --eta-newline=1 >~/Logs/io.log

glxinfo | grep "direct rendering" >~/Logs/graphics.log
grep -r . /sys/devices/system/cpu/vulnerabilities/ >~/Logs/cpu_vulnerabilities.log

uname -r >~/Logs/kernel.log
fastfetch >~/Logs/overview.log

# Write the remaining setup steps
echo "TODO:
1. Paste \`cat ~/Scratch/ublock-ytshorts.txt | wl-copy\` to ublock filters
2. Setup GUI apps:
    Log into *Bitwarden*, *Notesnook*, *Ente Auth* and *Mega*
    Configure *KDE Connect*, *Telegram*, *ProtonVPN*, *Zoom*, *Open TV*, *Veracrypt*
3. Paste \`cat ~/.ssh/id_ed25519.pub | wl-copy\` at https://github.com/settings/keys
4. Check the files obtained over torrents: \`ls ~/Scratch\`
5. Install NixOS on QEMU-KVM: \`cd ~/Workspace/ && qemu-system-x86_64 -enable-kvm -cdrom ~/Backups/ISOs/$ISO_FILE -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on\`
" > ~/Documents/remaining_setup.md

# Exit the script (let the zshrc complete)
echo "Exiting the post install script."
exit 0
