#!/usr/bin/env bash

set -e  # Exit on error

KEYFILE="/root/luks.key"
CRYPTTAB="/etc/crypttab"

# Replace these with your actual LUKS partitions
LUKS_ROOT="/dev/sda1"
LUKS_HOME="/dev/sda2"

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

# 1. Generate a secure keyfile
echo "Generating LUKS keyfile..."
dd if=/dev/urandom of="$KEYFILE" bs=512 count=4
chmod 600 "$KEYFILE"

# 2. Add the keyfile to LUKS-encrypted partitions
echo "Adding keyfile to LUKS root partition..."
cryptsetup luksAddKey "$LUKS_ROOT" "$KEYFILE"

echo "Adding keyfile to LUKS home partition..."
cryptsetup luksAddKey "$LUKS_HOME" "$KEYFILE"

# 3. Configure crypttab for automatic unlocking
echo "Configuring /etc/crypttab..."
echo "cryptroot  $LUKS_ROOT  $KEYFILE  luks" >> "$CRYPTTAB"
echo "crypthome  $LUKS_HOME  $KEYFILE  luks" >> "$CRYPTTAB"

# 4. Update initramfs to embed the keyfile
echo "Embedding keyfile into initramfs..."
echo "FILES=($KEYFILE)" >> /etc/mkinitcpio.conf
mkinitcpio -P

echo "Configuration complete! Your system should now automatically unlock LUKS partitions on boot."
