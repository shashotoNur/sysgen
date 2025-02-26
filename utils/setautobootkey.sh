#!/bin/bash

set -e          # Exit on error
set -o pipefail # Fail if any command in a pipeline fails

# Define variables
USB_DEVICE="/dev/$1"
PASSPHRASE="$2"
USB_MOUNT="/mnt/usbkey" # Temporary mount point for USB
KEY_FILE="luks-home.key"
KEYFILE_PATH="$USB_MOUNT/$KEY_FILE"

LUKS_DEVICE="/dev/sda4" # LUKS-encrypted partition
LUKS_NAME="home_crypt"  # Name for the decrypted LUKS mapping
MOUNTPOINT="/home"      # Mount point for the decrypted partition
BTRFS_SUBVOL="@home"    # Btrfs subvolume for home

# Ensure dependencies are installed
if ! command -v cryptsetup &>/dev/null; then
    echo "cryptsetup is not installed. Install it with: sudo pacman -S cryptsetup"
    exit 1
fi

# Create a mount point for the USB if it doesn't exist
mkdir -p "$USB_MOUNT"

# Mount the USB drive
echo "Mounting USB drive..."
sudo mount "$USB_DEVICE" "$USB_MOUNT"

# Generate a secure keyfile
echo "Creating keyfile..."
sudo dd if=/dev/urandom of="$KEYFILE_PATH" bs=512 count=4
sudo chmod 600 "$KEYFILE_PATH"

# Add keyfile to LUKS
echo "Adding keyfile to LUKS..."
echo -n "${PASSPHRASE}" | sudo cryptsetup luksAddKey "$LUKS_DEVICE" "$KEYFILE_PATH"

# Get UUIDs for fstab and GRUB config
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_DEVICE")
USB_UUID=$(blkid -s UUID -o value "$USB_DEVICE")

# Ensure fstab mounts the decrypted partition
FSTAB_ENTRY="UUID=$LUKS_UUID $MOUNTPOINT btrfs defaults,noatime,compress=zstd,subvol=$BTRFS_SUBVOL 0 2"
echo "Updating /etc/fstab..."
grep -q "$LUKS_UUID" /etc/fstab || echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab

# Ensure GRUB includes cryptdevice and cryptkey
GRUB_CFG="/etc/default/grub"
echo "Updating GRUB configuration..."
sudo sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME cryptkey=UUID=$USB_UUID:btrfs:/$KEY_FILE\"|" "$GRUB_CFG"

# Regenerate GRUB config
echo "Updating GRUB..."
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Unmount the USB drive
echo "Unmounting USB drive..."
sudo umount "$USB_MOUNT"

echo "LUKS keyfile setup complete!"
