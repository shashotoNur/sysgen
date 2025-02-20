#!/bin/bash

set -e  # Exit on error

# Check if system is booted in UEFI mode
UEFI_MODE=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo "Not UEFI")
if [[ "$UEFI_MODE" != "64" && "$UEFI_MODE" != "32" ]]; then
    echo "Error: System is not booted in UEFI mode!"
    exit 1
fi

# List available drives and let user select installation drive
echo "Available drives:"
lsblk -dpno NAME,SIZE | grep -E "/dev/sd|nvme|mmcblk"
read -rp "Enter the drive to install the system (e.g., /dev/sdX): " INSTALL_DRIVE
if [[ ! -b "$INSTALL_DRIVE" ]]; then
    echo "Invalid drive selected."
    exit 1
fi

# Get partition sizes
read -rp "Enter boot partition size (e.g., 512M): " BOOT_SIZE
read -rp "Enter root partition size (e.g., 50G): " ROOT_SIZE
read -rp "Enter swap size (e.g., 8G, or 0 for no swap): " SWAP_SIZE
read -rp "Enter home partition size (e.g., remaining space: 100%): " HOME_SIZE

# Get Wi-Fi credentials
read -rp "Enter Wi-Fi SSID: " WIFI_SSID
read -rsp "Enter Wi-Fi Password: " WIFI_PASSWORD
echo ""

# Get username and hostname
read -rp "Enter your username: " USERNAME
read -rp "Enter hostname: " HOSTNAME

# Ask if LUKS and root password should be the same
read -rp "Use the same password for LUKS and root? (y/n): " SAME_PASS
if [[ "$SAME_PASS" == "y" ]]; then
    read -rsp "Enter the password: " ROOT_PASS
    echo ""
    LUKS_PASS="$ROOT_PASS"
else
    read -rsp "Enter LUKS password: " LUKS_PASS
    echo ""
    read -rsp "Enter root password: " ROOT_PASS
    echo ""
fi

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
pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers linux-zen linux-zen-headers linux-firmware nano vim networkmanager iw wpa_supplicant dialog

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
echo "$USERNAME:$ROOT_PASS" | chpasswd  # Using root password if the user chose same password

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

# Reboot system
echo "Installation complete! Rebooting in 5 seconds..."
sleep 5
reboot
