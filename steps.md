**Booting new system:**
> Ensure internet:
> ```
> sudo systemctl enable --now NetworkManager.service
> nmcli device wifi connect _SSID_ password _password_
> ```
> Update keymap: `sudo nano /etc/vconsole.conf` > `KEYMAP=us`

**System configurations:**
> Essential packages: `sudo pacman -Syu xdg-user-dirs alsa-firmware alsa-utils pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber wget git intel-ucode fuse2 lshw powertop inxi acpi plasma sddm dolphin konsole tree --needed`
> 
> Create additional user directories: `mkdir -p Workspace Backups Archives Scratch Scripts Games Designs Logs`
> Create primary user dirs: `xdg-user-dirs-update && ls`
> 
> Enable display manager: `sudo systemctl enable --now sddm`

**Retrieve and filter the latest pacman mirrorlist:**
> Install reflector: `sudo pacman -S reflector`
> ```
> sudo reflector --verbose -c India -c China -c Japan -c Singapore -c US --protocol https --sort rate --latest 20 --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist
> ```
> Schedule weekly mirror update: `sudo systemctl enable reflector.timer`


> Disable kde's duplicate dunst activation: `sudo mv org.kde.plasma.Notifications.service org.kde.plasma.Notifications.service.disabled`

**Bootloader theme:**

> Clone: `git clone --depth 1 https://github.com/shashotoNur/grub-dark-theme`
> Copy to grub's directory: `sudo cp -r grub-dark-theme/theme /boot/grub/themes/`
> Configure theme and timeout: `nvim /etc/default/grub` > 
> ```
> GRUB_TIMEOUT=1
> GRUB_THEME="/boot/grub/themes/theme/theme.txt"
> ```
> Update grub: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
> 
> Adjust dolphin configuration

**Network configurations:**
> Addons: `sudo pacman -S resolvconf nm-connection-editor networkmanager-openvpn --needed`
> Configure:
> ```
> sudo systemctl enable systemd-resolved.service
> sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
> sudo systemctl enable --now wpa_supplicant.service
> ```

**Update the system:**
> Install PGP keyring: `sudo pacman -S archlinux-keyring --needed`
> Initialize: `sudo pacman-key --init && sudo pacman-key --populate archlinux`
> Update the local keyring: `sudo pacman-key --refresh-keys`
> > Key location: `/etc/pacman.d/gnupg`
> 
> Uncomment options: `sudo nano /etc/pacman.conf`
> Sync and upgrade: `sudo pacman -Syu`

**Setup flatpak:**
> Install: `sudo pacman -S flatpak`
> Add flathub: `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`
> Cleaning up: `sudo rm -rfv /var/tmp/flatpak-cache-*` and `flatpak uninstall --unused`

**Setup shell and terminal:**
> Install: `sudo pacman -S zsh # because fish is not POSIX compliant`
> Initialize: `zsh /usr/share/zsh/functions/Newuser/zsh-newuser-install -f`
> Change shell to zsh: `chsh -s $(which zsh)`
>
> Framework OMZ: `sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`\
> Add plugins to the framework:
> > 1. Syntax Highlighting:
> > ```
> > git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
> > ```
>
> > 2. Autocomplete:
> > ```
> > git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
> > ```
>
> > 3. Jumping directories:
> > ```
> > sudo git clone --depth 1 https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
> > ```
>
> > 4. Fuzzy finder:
> > ```
> > git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
> > ```
>
> > 5. Alias reminder:
> > ```
> > sudo git clone --depth 1 https://github.com/MichaelAquilina/zsh-you-should-use.git $ZSH_CUSTOM/plugins/you-should-use
> > ```
>
> > 6. Theme:
> > ```
> > git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
> > ```
>
> > 7. Setup Atuin:
> > ```
> > zsh <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
> > ```
>
> > 8. Keep only `arch.png` for fastfetch logo: `cd ~/.config/fastfetch/pngs && find . -type f ! -name "arch.png" -delete`
>
> > 9. Auto-notify:
> > ```
> > sudo git clone https://github.com/MichaelAquilina/zsh-auto-notify.git $ZSH_CUSTOM/plugins/auto-notify
> > ```

**Install required apps and packages:**
> With pacman:
> ```
> sudo pacman -S intel-media-driver grub-btrfs nodejs npm fortune-mod cowsay lolcat jrnl inotify-tools supertux testdisk bat ripgrep bandwhich oath-toolkit asciinema neovim hexyl syncthing thefuck duf procs sl cmatrix gum gnome-keyring dnsmasq dmenu btop eza hdparm tmux telegram-desktop ddgr less sshfs onefetch tmate navi code nethogs tldr gping detox fastfetch bitwarden yazi direnv xorg-xhost rclone fwupd bleachbit picard timeshift jp2a gparted obs-studio veracrypt rust aspell-en libmythes mythes-en languagetool pacseek kolourpaint kicad kdeconnect cpu-x github-cli kolourpaint kalarm cpufetch kate plasma-browser-integration ark okular kamera krename ipython filelight kdegraphics-thumbnailers qt5-imageformats kimageformats espeak-ng --needed
> ```
> 
> With yay:
> ```
> yay -S ventoy-bin steghide go pkgx-git stacer-git nsnake gpufetch nudoku arch-update mongodb-bin hyprland-qtutils pet-git musikcube tauon-music-box hollywood no-more-secrets nodejs-mapscii noti megasync-bin mongodb-compass smassh affine-bin solidtime-bin ngrok scc rmtrash nomacs cbonsai vrms-arch-git browsh timer sql-studio-bin posting lowfi dooit --needed
> ```
>
> With flatpak:
> ```
> flatpak install com.github.tchx84.Flatseal io.ente.auth com.notesnook.Notesnook us.zoom.Zoom org.speedcrunch.SpeedCrunch net.scribus.Scribus org.kiwix.desktop org.localsend.localsend_app com.felipekinoshita.Wildcard io.github.prateekmedia.appimagepool com.protonvpn.www org.librecad.librecad dev.fredol.open-tv org.kde.krita com.opera.Opera org.audacityteam.Audacity com.usebottles.bottles io.github.zen_browser.zen org.torproject.torbrowser-launcher org.qbittorrent.qBittorrent org.onlyoffice.desktopeditors org.blender.Blender org.kde.labplot2 org.kde.kwordquiz org.kde.kamoso org.kde.skrooge org.kde.kdenlive -y
> ```
> 
> SPF: `bash -c "$(curl -sLo- https://superfile.netlify.app/install.sh)"`

**Initialize browser:**
> Install: `sudo pacman -S firefox-developer-edition`
> Keybinding: `nano ~/.config/hypr/keybindings.conf` > change `browser` variable to `firefox-developer-edition`
> Tweaks:
> > 1. browser.preferences.defaultPerformanceSettings.enabled: true => false
> > 2. browser.cache.disk.enable: true => false
> > 3. browser.cache.memory.enable: false => true
> > 4. browser.sessionstore.resume_from_crash: true => false
> > 5. extensions.pocket.enabled: true => false
> > 6. layout.css.dpi: -1 => 0
> > 8. general.smoothScroll.msdPhysics.enabled: false => true
> > 9. media.hardware-video-decoding.force-enabled: false => true
> > 10. middlemouse.paste: false => true
> > 11. webgl.msaa-force: false => true
> > > security.sandbox.content.read_path_whitelist = /sys/
> > 12. browser.download.alwaysOpenPanel: true => false
> > 13. network.ssl_tokens_cache_capacity = 32768
> > 14. media.ffmpeg.vaapi.enabled = true
> > 15. accessibility.force_disabled = 1
> > 16. browser.eme.ui.enabled = false
>


**Configure compressed block device:**
> Create a zram service: `sudo nano /etc/systemd/system/zram.service` > 
> > ```
> > [Unit]
> > Description=ZRAM Swap Service
> > 
> > [Service]
> > Type=oneshot
> > ExecStart=/usr/bin/bash -c "modprobe zram && echo lz4 > /sys/block/zram0/comp_algorithm && echo 4G > /sys/block/zram0/disksize && mkswap --label zram0 /dev/zram0 && swapon --priority 100 /dev/zram0"
> > ExecStop=/usr/bin/bash -c "swapoff /dev/zram0 && rmmod zram"
> > RemainAfterExit=yes
> > 
> > [Install]
> > WantedBy=multi-user.target
> > ```
>
> Enable the service: `sudo systemctl enable --now zram`
> Check: `sudo dmesg | grep zram`

**Preliminary configurations:**
> Better HDD performance:
> `sudo nano /etc/systemd/system/hdparm.service`
> > ```
> > [Unit]
> > Description=Set APM for HDD
> > Before=local-fs.target
> > DefaultDependencies=no
> > 
> > [Service]
> > Type=oneshot
> > ExecStart=/sbin/hdparm -B 192 /dev/sda
> > RemainAfterExit=true
> > 
> > [Install]
> > WantedBy=multi-user.target
> > ```
>
> `sudo systemctl enable --now hdparm.service`
> Enable write cache: `sudo hdparm -W 1 /dev/sda`
>
> Firmware updates: `yes | fwupdmgr get-updates`
>
> Numlock:
> > Install: `yay -S mkinitcpio-numlock`
> > Add the `numlock` mkinitcpio hook before `encrypt` in the `/etc/mkinitcpio.conf` HOOKS array
> > SDDM configuration: `echo "Numlock=on" | sudo tee -a "/etc/sddm.conf"`
>
> Paccache:
> > Check the size of your package cache: `du -sh /var/cache/pacman/pkg/`
> > Install: `sudo pacman -S pacman-contrib`
> > Activate: `sudo systemctl enable paccache.timer`
>
> Enable direct command issue to kernel: `echo 'kernel.sysrq=1' | sudo tee /etc/sysctl.d/99-reisub.conf`
>
> Network Time Protocol:
> > ```
> > sudo pacman -S openntpd
> > sudo systemctl disable --now systemd-timesyncd
> > sudo systemctl enable openntpd
> > ```
> > Update servers at `/etc/ntpd.conf`:
> > > ```
> > > server 0.pool.ntp.org
> > > server 1.pool.ntp.org
> > > server 2.pool.ntp.org
> > > server 3.pool.ntp.org
> > > ```
> > 
> > Adjust initial drift `sudo nano /var/db/ntpd.drift`: `0.0`
> 
> HDMI sharing:
> > Screen: Modify line in`~/.config/hypr/hyprland.conf` to `monitor = ,preferred,auto,1,mirror,eDP-1`
> > 
> > Audio:
> > > View status: `wpctl status | grep HDMI`
> > > Set sink: `wpctl set-default <device_id>` e.g. `wpctl set-default 44`

**Optimizations:**
> Limit journal size:
> > Uncomment and modify lines in: `sudo nano /etc/systemd/journald.conf` to:
> > ```
> > SystemMaxUse=256M
> > MaxRetentionSec=2weeks
> > MaxFileSec=1month
> > Audit=yes
> > ```
>
> Disable core dump:
> > Add config: `sudo nano /etc/sysctl.d/50-coredump.conf` > `kernel.core_pattern=/dev/null`
> > Reload: `sudo sysctl -p /etc/sysctl.d/50-coredump.conf`
>
> Prevent overheating:
> > Install: `yay -S --needed thermald`
> > Configure service: `sudo nano /usr/lib/systemd/system/thermald.service` > `ExecStart=/usr/bin/thermald --no-daemon --dbus-enable --ignore-cpuid-check`
> > Enable: `sudo systemctl enable --now thermald`
>
> Risky CPU optimization:
> > Edit: `sudo nano /etc/default/grub` > `GRUB_CMDLINE_LINUX="... mitigations=off`
> > Update: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
>
> Network congestion algorithm: `echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee /etc/sysctl.d/98-misc.conf`

**Setup firewall:**
> Install: `sudo pacman -S ufw`
> Rules:
> ```
> sudo ufw limit 22/tcp \
> && sudo ufw allow 80/tcp \
> && sudo ufw allow 443/tcp \
> && sudo ufw default deny incoming \
> && sudo ufw default allow outgoing \
> && sudo ufw allow 1714:1764/udp \
> && sudo ufw allow 1714:1764/tcp # for kde connect
> ```
> Enable firewall: `sudo systemctl enable --now ufw && sudo ufw enable`

**Setup bluetooth:**
> Install packages: `sudo pacman -S bluez bluez-utils blueman`
> Load module: `sudo modprobe btusb`
> Enable service: `sudo systemctl enable bluetooth`
> Unblock: `rfkill unblock bluetooth`

**Enable graphics driver:** 
> Enable: `sudo systemctl enable nvidia-persistenced.service`
> Install prime: `sudo pacman -S nvidia-prime`
> Command: `prime-run <command>`
> Nvidia and vulkan modules:
> ```
> sudo pacman -S nvidia-dkms nvidia-settings nvidia-utils lib32-nvidia-utils lib32-opencl-nvidia opencl-nvidia libvdpau lib32-libvdpau libxnvctrl vulkan-icd-loader lib32-vulkan-icd-loader vkd3d lib32-vkd3d opencl-headers opencl-clhpp vulkan-validation-layers lib32-vulkan-validation-layers --needed
> ```
> Enable: `sudo nano /etc/mkinitcpio.conf` > `MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`
> Update: `sudo mkinitcpio -P`
>
> Modify kernel parameters: `sudo nano /etc/default/grub` > `GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash nvidia_drm.modeset=1 retbleed=off spectre_v2=retpoline,force nowatchdog mitigations=off"`
> Update config: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
> 
> Verify: `sudo cat /sys/module/nvidia_drm/parameters/modeset`

**Memory management:**
> Enable manager: `sudo systemctl enable --now systemd-oomd`
> Configure:
> > `sudo systemctl edit user@service`
> > ```
> > [Service]
> > ManagedOOMMemoryPressure=kill
> > ManagedOOMMemoryPressureLimit=50%
> > ```
> > `sudo systemctl edit user.slice`
> > ```
> > [Slice]
> > ManagedOOMSwap=kill
> > ```
>
> Check:
> > `cat /etc/systemd/system.conf`
> > ```
> > ...
> > [Manager]
> > DefaultCPUAccounting=yes
> > DefaultIOAccounting=yes
> > DefaultMemoryAccounting=yes
> > DefaultTasksAccounting=yes
> > ```
> > `cat /etc/systemd/oomd.conf`
> > ```
> > [OOM]
> > SwapUsedLimitPercent=90%
> > DefaultMemoryPressureDurationSec=20s
> > ```
>
> For testing: `systemd-run --user tail /dev/zero`

**Setup avro:**
> Install: `yay -S ibus-avro-git`
> Start IBUS: `ibus-daemon -rxRd`
> IBUS Preferences => Input Method => Add Avro
>
> Configure apps to use IBUS for input: `/etc/environment`
> ```
> GTK_IM_MODULE=ibus
> QT_IM_MODULE=ibus
> XMODIFIERS=@im=ibus
> ```
>
> Write a script to toggle input method: `nano ~/.config/hypr/toggle_ibus.sh` >
> ```
> #!/bin/bash
> [ "$(ibus engine)" = "xkb:us::eng" ] && ibus engine ibus-avro || ibus engine xkb:us::eng
> ```
> 
> Make the script executable: `chmod +x ~/.config/hypr/toggle_ibus.sh`
> Add keybind to toggle input method: `nano ~/.config/hypr/hyprland.conf` >
> ```
> bind=SUPER,SPACE,exec,~/.config/hypr/toggle_ibus.sh
> ```
> `hyprctl reload`
> 
> Enable autostart: `nano ~/.config/hypr/hyprland.conf` > `exec-once = ibus-daemon -rxRd # start ibus demon`)

**Configure default brightness:**
> Create a new service file:
> ```
> sudo nano /etc/systemd/system/set-brightness.service
> ```
> Add the following content:
> ```
> [Unit]
> Description=Set screen brightness to 5% at startup
> After=multi-user.target
>
> [Service]
> Type=oneshot
> ExecStart=/bin/bash -c "echo 50 > /sys/class/backlight/intel_backlight/brightness"
>
> [Install]
> WantedBy=multi-user.target
> ```
> Enable service: `sudo systemctl enable --now set-brightness.service`

> > `wget -c https://iptv-org.github.io/iptv/index.m3u`
>
> 
> Docmost:
> > ```
> > sudo pacman -S docker docker-compose
> > sudo systemctl enable --now docker
> > sudo systemctl status docker
> > mkdir docmost
> > cd docmost
> > curl -O https://raw.githubusercontent.com/docmost/docmost/main/docker-compose.yml
> > nvim docker-compose.yml
> > # For APP_SECRET: openssl rand -hex 32
> > # For POSTGRES_PASSWORD: pwgen.sh
> > docker compose up -d
> > ```
> 
> VS Code extensions:
> > ```
> > #!/bin/bash
> >
> > # Array of extension IDs
> > mapfile -t extensions < ext_list.txt
> >
> > # Loop through the extensions and install each one
> > for extension in "${extensions[@]}"; do
> >   echo "Installing extension: $extension"
> >   code --install-extension "$extension"
> >   # Check the return code to see if the installation was successful
> >   if [[ $? -eq 0 ]]; then
> >     echo "Extension $extension installed successfully."
> >   else
> >     echo "Error installing extension $extension.  Check for network issues or if the extension name is correct."
> >   fi
> > done
> >
> > echo "Installation process complete."
> > ```

**Setup terminal apps:**
> Preload:
> > Install: `yay -S preload`
> > Enable: `sudo systemctl enable preload`
> > Start: `sudo systemctl start preload`
>
> thefuck:
> > Run: `eval $(thefuck --alias)`
> > Source: `source ~/.zshrc`
>
> Neovim:
> > ```
> > git clone --depth 1 git@github.com:omerxx/dotfiles.git
> > cp dotfiles/nvim ~/.config/nvim
> > rm -rf ~/.config/nvim/.git
> > ```
>
> Configure jrnl
> > Path: `/home/axiom/Documents/data/journal.txt`
> > Editor: `nvim ~/.config/jrnl/jrnl.yaml`
>
> Gnome-keyring PAM initialization:
> > Include the following lines in `sudo nano /etc/pam.d/login` at the end of `auth` and `session` section respectively
> > ```
> > auth       optional     pam_gnome_keyring.so
> > session    optional     pam_gnome_keyring.so auto_start
> > ```
>
> Pip:
> > Install: `sudo pacman -S python-pip`
> > Disable global package install restriction:
> > ```
> > sudo mv /usr/lib/python3.12/EXTERNALLY-MANAGED /usr/lib/python3.12/EXTERNALLY-MANAGED.old
> > ```
>
> Makedown: `pip install makedown`
> Diff-so-fancy:
> > Install: `npm i -g diff-so-fancy`
> > Setup with git:
> > ```
> > git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX" \
> > && git config --global interactive.diffFilter "diff-so-fancy --patch" \
> > && git config --global color.ui true
> > ```
> > Usage: `git diff`
>
> Gemini console:
> > Clone : `git clone --depth 1 https://github.com/flameface/gemini-console-chat.git ~/Scripts/`
> > Dependencies: `cd ~/Scripts/gemini-console-chat && npm install`
> > Add api key: `nano index.js` from `aistudio.google.com/app`

**TMUX setup:**
> Update config: `nvim ~/.tmux.conf` >
> > ```
> > unbind r
> > bind r source-file ~/.tmux.conf
> > 
> > set -g default-terminal "tmux-256color"
> > set -ag terminal-overrides ",xterm-256color:RGB"
> > 
> > set -g prefix C-s
> > 
> > set -g mouse on
> > 
> > set-window-option -g mode-keys vi
> > 
> > bind-key h select-pane -L
> > bind-key j select-pane -D
> > bind-key k select-pane -U
> > bind-key l select-pane -R
> > 
> > set-option -g status-position top
> > 
> > # set -g @catppuccin_flavor "mocha"
> > set -g @catppuccin_window_status_style "rounded"
> > 
> > # List of plugins
> > set -g @plugin 'tmux-plugins/tpm'
> > set -g @plugin 'christoomey/vim-tmux-navigator'
> > set -g @plugin 'catppuccin/tmux#v2.1.0'
> > 
> > set -g status-left ""
> > set -g status-right "#{E:@catppuccin_status_application} #{E:@catppuccin_status_session}"
> > 
> > # Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
> > run '~/.tmux/plugins/tpm/tpm'
> > 
> > set -g status-style bg=default
> > ```
> 
> Plugin manager: `git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm`

**Syncthing:**
> Create startup service: `sudo nano /etc/systemd/system/syncthing@axiom.service`
> > ```
> > [Unit]
> > Description=Syncthing - Open Source Continuous File Synchronization for %I
> > Documentation=man:syncthing(1)
> > After=network.target
> > StartLimitIntervalSec=60
> > StartLimitBurst=4
> > 
> > [Service]
> > User=%i
> > ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --logflags=0
> > Restart=on-failure
> > RestartSec=1
> > SuccessExitStatus=3 4
> > RestartForceExitStatus=3 4
> > 
> > # Hardening
> > ProtectSystem=full
> > PrivateTmp=true
> > SystemCallArchitectures=native
> > MemoryDenyWriteExecute=true
> > NoNewPrivileges=true
> > 
> > # Elevated permissions to sync ownership (disabled by default),
> > # see https://docs.syncthing.net/advanced/folder-sync-ownership
> > #AmbientCapabilities=CAP_CHOWN CAP_FOWNER
> > 
> > [Install]
> > WantedBy=multi-user.target
> > ```
> 
> Enable service: `sudo systemctl enable --now syncthing@axiom.service`
> Connect to phone

**Configure Appimage Launcher:**
> Install: `yay -S appimagelauncher-bin`


**Gaming:**
> Install gamemode: `sudo pacman -S gamemode lib32-gamemode gamescope --needed`
>
> Native wine (optional): `sudo pacman -S wine wine-gecko wine-mono --needed && sudo systemctl restart systemd-binfmt`
> 
> Optional dependencies:
> > ```
> > sudo pacman -S fluidsynth lib32-fluidsynth gvfs gvfs-nfs libkate gst-plugins-good gst-plugins-bad gst-libav lib32-gst-plugins-good gst-plugin-gtk lib32-gstreamer lib32-gst-plugins-base-libs lib32-libxvmc libxvmc smpeg faac x264 lib32-pipewire pipewire-zeroconf mac lib32-opencl-icd-loader --needed
> > ```


**Setup Git with credentials:**
> Information:
> > Add name: `git config --global user.name "Shashoto Nur"`
> > Add email: `git config --global user.email "shashoto.nur@proton.me"`
> > Add editor: `git config --global core.editor "nvim"`
>
> SSH key:
> > Generate key: `ssh-keygen -t ed25519 -C "shashoto.nur@proton.me"`
> > Copy key: `cat ~/.ssh/id_ed25519.pub` and add it at `https://github.com/settings/keys`
> > Start ssh agent and add key: 
> > > ```
> > > eval `ssh-agent -s`
> > > ssh-add ~/.ssh/id_ed25519
> > > ```
> 
> Signing Key:
> > Import gpg key:
> > ```
> > gpg --import public-key.asc && \
> > gpg --import private-key.asc
> > ```
> 
> > Generate gpg key: `gpg --full-generate-key`
> > Get key id: `gpg --list-secret-keys --keyid-format=long`
> > > Output format: `sec   algorithm/key-id generation-date [SC] [expires: YYYY-MM-DD]`
> >
> > Export public key: `gpg --armor --export key-id`
> > Copy output and add it at: `https://github.com/settings/keys` > `GPG Keys`
> > Configure signing all commits by default: `git config --global commit.gpgsign true`
> > Add signing key to git: `git config --global user.signingkey key-id`
> > Set GPG tty variable in `~/.zshrc`: `export GPG_TTY=$(tty)`

**Get user files:** 
> Import Github repositories:
> > Clone script: `git clone --depth 1 git@github.com:shashotoNur/clone-repos.git ~/Workspace`
> > Login to Github CLI: `gh auth login`
> > Clone the repos: `cd ~/Workspace/clone-repos && ./clone.sh`
>
> Import Music:
> > Prepare directory: `MUSICDIR=~/Music/Sound\ Of\ My\ Life && mkdir -p $MUSICDIR && cd $MUSICDIR`
> > Get dependency: `pip install yt-dlp`
> > 
> > Download: `yt-dlp -x --audio-format mp3 --download-archive archive.txt --embed-thumbnail --embed-metadata https://www.youtube.com/playlist\?list\=PLQIOayL9eHnZWdvnDyYbOAlcU7B1PKtYG`
> > Detox filenames: `detox -r .`
> 

> > Add `.git` files to relevant directories
>
> Get the latest wikipedia archive:
> ```
> #!/bin/bash
>
> BASE_URL="https://dumps.wikimedia.org/other/kiwix/zim/wikipedia/"
> PREFIX="wikipedia_en_all_maxi_"
> EXT=".zim"
>
> # Fetch the page, extract relevant file names, and sort by date
> LATEST_FILE=$(curl -s "$BASE_URL" | grep -oP "${PREFIX}\d{4}-\d{2}${EXT}" | sort -t'_' -k4,4 -r | head -n 1)
>
> # Construct the full URL of the latest file
> if [[ -n "$LATEST_FILE" ]]; then
>     wget -c "${BASE_URL}/${LATEST_FILE}"
> else
>     echo "No matching files found."
> fi
> ```
> Copy ISOs and Backups from USB partitions

**Setup AppArmor:**
> Check available security modules: `zgrep CONFIG_LSM= /proc/config.gz` or `cat /sys/kernel/security/lsm`
> > Loader entry location: `/efi/loader/entries/`
>
> Modify kernel options at `/etc/default/grub`
> > Add Security Module: `lsm=apparmor,<other modules>`
> > Enable Audit: `audit=1 audit_backlog_limit=8192`
> > Update grub: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
>
> Install: `sudo pacman -S apparmor`
> Enable: `sudo systemctl enable --now apparmor.service`
> Reboot and check: `aa-enabled` and `sudo aa-status`
> > To disable: `sudo aa-teardown`
>
> Enable Audit Framework: `sudo systemctl enable --now auditd.service`
> Enable reading Audit logs:
> > `sudo groupadd -r audit` && `sudo gpasswd -a $USER audit`
> > Add / modify line in `/etc/audit/auditd.conf` to: `log_group = audit`
>
> Increase netlink buffer size: `sudo nano /etc/sysctl.conf` >
> > ```
> > net.core.rmem_max = 8388608
> > net.core.wmem_max = 8388608
> > ```
>
> Increase buffer size: `sudo nano /etc/audit/audit.rules` > `-b 65536`
> Desktop Launcher: `~/.config/autostart/apparmor-notify.desktop` ->
> ```
> [Desktop Entry]
> Type=Application
> Name=AppArmor Notify
> Comment=Receive on screen notifications of AppArmor denials
> TryExec=aa-notify
> Exec=aa-notify -p -s 1 -w 60 -f /var/log/audit/audit.log
> StartupNotify=false
> NoDisplay=true
> ```
> Enable caching AppArmor profiles: Uncomment `write-cache` in `/etc/apparmor/parser.conf`

**Setup system backup**
> Run through the wizard (weekly: 1, daily: 2, boot: 2)
> Enable cronie for scheduling: `sudo systemctl enable --now cronie.service`
>
> Update grub-btrfs config: `sudo /etc/grub.d/41_snapshots-btrfs`
> Update grub config: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
> Start service: `sudo systemctl enable --now grub-btrfsd`
>
> Configure grub-btrfs for timeshift: `sudo systemctl edit --full grub-btrfsd`
> Modify `ExecStart` line to `ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto`
>
> Setup `OneFileLinux` to boot:
> > Download [OneFileLinux.efi](https://github.com/zhovner/OneFileLinux/releases) to `~/Backups/ISOs/`
> > Copy file to `efi` partition: `sudo cp ~/Backups/ISOs/OneFileLinux.efi /boot/efi/EFI/BOOT/`
> > 
> > Add entry `sudo nano /etc/grub.d/40_custom`:
> > ```
> > menuentry "One File Linux" {
> >   search --file --no-floppy --set=root /EFI/Boot/OneFileLinux.efi
> >   chainloader /EFI/Boot/OneFileLinux.efi
> > }
> > ```
> > Update config: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
>
> Repair btrfs partition: `sudo btrfs check --repair /dev/sdaX`

**Create a virtual machine with QEMU-KVM:**
> Check CPU is ready for virtualization: `lscpu | grep -i Virtualization` : `VT-x`
> Install required packages: `sudo pacman -S qemu-full qemu-img libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm guestfs-tools libosinfo && yay -S tuned`
> Enable libvirt: `sudo systemctl enable libvirtd.service`
>
> Enable IOMMU:
> > Add to `/etc/default/grub`: `GRUB_CMDLINE_LINUX="... intel_iommu=on iommu=pt"`
> > Regenerate config: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
> > Reboot: `reboot`
> > Verify: `sudo virt-host-validate qemu`
>
> Enable TuneD for better performance: `sudo systemctl enable --now tuned.service`
> Check: `tuned-adm list`
> Set profile to `virtual-host`: `sudo tuned-adm profile virtual-host`
> Verify: `sudo tuned-adm verify`
>
> Configure libvirt: `/etc/libvirt/libvirtd.conf`
> > ```
> > unix_sock_group = "libvirt"
> > unix_sock_rw_perms = "0770"
> > ```
>
> Add your user to the libvirt group: `sudo usermod -aG libvirt $USER`
> Create vm with virt-manager or qemu cli:
> > Download ISO
> > Create a disk image: `qemu-img create -f qcow2 virtdisk.img 128G`
> > Install OS in VM: `qemu-system-x86_64 -enable-kvm -cdrom <iso_file> -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on`
> >
> > Start VM once installed: `qemu-system-x86_64 -enable-kvm -boot menu=on -drive file=virtdisk.img -m 4G -cpu host -vga virtio -display sdl,gl=on`







**Reboot & benchmark:**
> Systemd: `systemd-analyze plot > boot.svg`
> `sudo systemd-analyze blame > blame.txt`
> Journal logs: `journalctl -p err..alert`
> > Upload logs for remote access: `sudo journalctl -b | curl -F 'file=@-' 0x0.st`
>
> Storage check: `sudo hdparm -Tt /dev/sda` & KDiskMark
> CPU check: `sudo pacman -S sysbench` & `sysbench --threads="$(nproc)" --cpu-max-prime=20000 cpu run`
> or`sudo pacman -S p7zip` & `7z b`
>
> Battery: `sudo powertop`
> I/O: `sudo pacman -S fio` & `sudo fio --filename=/mnt/test.fio --size=8GB --direct=1 --rw=randrw --bs=4k --ioengine=libaio --iodepth=256 --runtime=120 --numjobs=4 --time_based --group_reporting --name=iops-test-job --eta-newline=1`
>
> Graphics: `glxinfo | grep "direct rendering"` > expected output: `Yes` & `yay -S unigine-valley` & `unigine-valley`
> CPU vulnerabilities: `grep -r . /sys/devices/system/cpu/vulnerabilities/`
> Check kernel `uname -r`
>
> Overview: `fastfetch`

Firefox
> Update Search Engines: Brave Search, Arch Wiki, Wikipedia, Perplexity, GitHub
>
> Block Youtube shorts in Ublock Origin filters: `https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt`

Appimages from Appimage Pool:
> > 1. Arduino
> > 2. Encrypt Pad
> > 3. Armagetron
> > 4. Eagle Mode
> > 5. Edex UI

> Configure bottles' permissions and preferences
> Download the game's setup files: [RDR](https://dodi-repacks.site/red-dead-redemption/), [Drain Mansion](https://steamunlocked.net/2fb535-drain-mansion-free-download/)
> Create a bottle, install the game and play
>
> Native games: [Minoria](https://freelinuxpcgames.com/minoria/), [VCP](https://freelinuxpcgames.com/virtual-circuit-board/), [Wedding Witch](https://freelinuxpcgames.com/wedding-witch/)
> > For portable games, run `.x86_64` file

> Cloud sync:
> > Setup sync with Mega Desktop
> > Enable autostart: `nano ~/.config/hypr/hyprland.conf` > `exec-once = bash -c "sleep 10 && megasync --no-window" # start megasync once system tray is initialized`
> > 

**Setup GUI apps:**
> Log into *Bitwarden*, *Notesnook*, *Ente Auth* and *Mega*
> Configure *KDE Connect*, *Telegram*, *ProtonVPN*, *Zoom*, *Open TV*, *Veracrypt*

> Firefox DE: *Mozilla*, *Proton Mail*, *Github*, *Reddit*, *Daily Dev*
> Zen: *Google*, *ChatGPT*, *Messenger*, *WhatsApp*

**Install hyprland:**
> Clone repo: `git clone --depth 1 https://github.com/prasanthrangan/hyprdots ~/HyDE`
> Install: `cd ~/HyDE/Scripts && ./install.sh`
>
> Setup: `Hyde-install`
> Add Chaotic AUR
> Choose themes => SDDM: Corners; Desktop: One Dark, Dracula, Catpuccin Mocha, Graphite Mono, Tokyo Night, Red Stone, Rain Dark, Eternal Arctic
> 
> Change sddm background: `sudo cp .config/hyde/themes/Catppuccin\ Mocha/wallpapers/cat_leaves.png /usr/share/sddm/themes/Corners/backgrounds/bg.png`
> 
> Qbittorrent theme: `https://github.com/catppuccin/qbittorrent/releases/`

> Time configurations:
> ```
> sudo localectl set-locale LANG=en_AU.UTF-8
> sudo timedatectl set-ntp true
> timedatectl status
> ```
