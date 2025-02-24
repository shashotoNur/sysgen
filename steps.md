
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

Zen
> Safe Workspace: *Mozilla*, *Proton Mail*, *Github*, *Reddit*, *Daily Dev*
> Unsafe Workspace: *Google*, *ChatGPT*, *Messenger*, *WhatsApp*

**Install hyprland:**
> Clone repo: `git clone --depth 1 https://github.com/prasanthrangan/hyprdots ~/HyDE`
> Install: `cd ~/HyDE/Scripts && ./install.sh`
>
> Setup: `Hyde-install`
> Add Chaotic AUR
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
> nmcli device wifi connect _SSID_ password _password_

> > Add `.git` files to relevant directories

> Neovim
