#!/bin/bash

set -e # Exit on error

# Check if system is booted in UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    echo "Error: System is not booted in UEFI mode!"
    exit 1
fi

CONFIG_FILE="install.conf"

# If config file doesn't exist, run the script to generate it
[[ ! -f "$CONFIG_FILE" ]] && bash utils/getconfig.sh

# Function to extract values
extract_value() {
    grep -E "^$1:" "$CONFIG_FILE" | awk -F': ' '{print $2}'
}

# Read configuration values
declare -A CONFIG_VALUES
for key in "Username" "Hostname" "Drive" \
    "Boot Partition" "Root Partition" "Swap Partition" "Home Partition" "Network Type" \
    "Password" "LUKS Password" "Root Password" "WiFi SSID" "WiFi Password"; do
    CONFIG_VALUES["$key"]=$(extract_value "$key")
done

# Handle LUKS and Root passwords
PASSWORD=${CONFIG_VALUES["Password"]}
if [[ -n "$PASSWORD" ]]; then
    CONFIG_VALUES["LUKS Password"]=$PASSWORD
    CONFIG_VALUES["Root Password"]=$PASSWORD
fi

# Check if DRIVE is only "/dev/"
if [[ "${CONFIG_VALUES["Drive"]}" == "/dev/" || -z "${CONFIG_VALUES["Drive"]}" ]]; then
    echo "No drive specified. Please select a drive:"

    # List available drives (excluding partitions)
    DRIVE_SELECTION=$(lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme|/dev/mmcblk" | fzf --prompt="Select a drive: " --height=10 --border --reverse | awk '{print $1}')

    if [[ -n "$DRIVE_SELECTION" ]]; then
        CONFIG_VALUES["Drive"]="$DRIVE_SELECTION"
        echo "Selected drive: ${CONFIG_VALUES["DRIVE"]}"
    else
        echo "No drive selected. Exiting."
        exit 1
    fi
fi

# Connect to the wifi
if [[ "${CONFIG_VALUES["Network Type"]}" == "wifi" ]]; then
    echo "WiFi SSID: ${CONFIG_VALUES["WiFi SSID"]}"
    iwctl --passphrase "${CONFIG_VALUES["WiFi Password"]}" station wlan0 connect "${CONFIG_VALUES["WiFi SSID"]}"
fi

# Check if there is internet
if ping -c 1 8.8.8.8 &>/dev/null; then
    echo "Internet connection is available."
else
    echo "Error: No internet connection."
    exit 1
fi

# Wipe the selected drive
echo "Wiping ${CONFIG_VALUES["Drive"]}..."
wipefs --all --force "${CONFIG_VALUES["Drive"]}"

# Function to convert MiB or GiB to bytes
unit_to_bytes() {
    local u="$1"
    local val=$(echo "$u" | sed 's/[A-Za-z]*$//')
    local ut=$(echo "$u" | sed 's/^[0-9]*//' | tr '[:upper:]' '[:lower:]')

    case "$ut" in
    mib) echo $((val * 1024 * 1024)) ;;
    gib) echo $((val * 1024 * 1024 * 1024)) ;;
    *)
        echo "Error: Invalid unit (MiB or GiB): $u"
        exit 1
        ;;
    esac
}

# Function to convert bytes to MiB for parted.
bytes_to_mib() {
    local b="$1"
    echo "$(($b / (1024 * 1024)))MiB"
}

# Partition the disk
echo "Creating partitions..."
parted -s "${CONFIG_VALUES["Drive"]}" mklabel gpt
start_size=$(unit_to_bytes "1MiB") # Start at 1MiB in bytes

# Boot Partition
boot_size=$(unit_to_bytes "${CONFIG_VALUES["Boot Partition"]}")
end_size=$((start_size + boot_size))
parted -s "${CONFIG_VALUES["Drive"]}" mkpart primary fat32 "$(bytes_to_mib "$start_size")" "$(bytes_to_mib "$end_size")"
parted -s "${CONFIG_VALUES["Drive"]}" set 1 esp on
start_size="$end_size"

# Root Partition
root_size=$(unit_to_bytes "${CONFIG_VALUES["Root Partition"]}")
end_size=$((start_size + root_size))
parted -s "${CONFIG_VALUES["Drive"]}" mkpart primary "$(bytes_to_mib "$start_size")" "$(bytes_to_mib "$end_size")"
start_size="$end_size"

# Swap partition
if [[ "${CONFIG_VALUES["Swap Partition"]}" != "0" ]]; then
    swap_size=$(unit_to_bytes "${CONFIG_VALUES["Swap Partition"]}")
    end_size=$((start_size + swap_size))
    parted -s "${CONFIG_VALUES["Drive"]}" mkpart primary linux-swap "$(bytes_to_mib "$start_size")" "$(bytes_to_mib "$end_size")"
    start_size="$end_size"
fi

# Home partition
home_size=$(unit_to_bytes "${CONFIG_VALUES["Home Partition"]}")
end_size=$((start_size + home_size))
parted -s "${CONFIG_VALUES["Drive"]}" mkpart primary "$(bytes_to_mib "$start_size")" "$(bytes_to_mib "$end_size")"

echo "Partitions created!"

# Get partition names
BOOT_PART="${CONFIG_VALUES["Drive"]}1"
ROOT_PART="${CONFIG_VALUES["Drive"]}2"
if [[ "${CONFIG_VALUES["Swap Partition"]}" != "0" ]]; then
    SWAP_PART="${CONFIG_VALUES["Drive"]}3"
    HOME_PART="${CONFIG_VALUES["Drive"]}4"
else
    HOME_PART="${CONFIG_VALUES["Drive"]}3"
fi

# Encrypt root and home partitions
echo "Encrypting root partition..."
echo -n "${CONFIG_VALUES["LUKS Password"]}" | cryptsetup luksFormat "$ROOT_PART"
echo -n "${CONFIG_VALUES["LUKS Password"]}" | cryptsetup open "$ROOT_PART" cryptroot

echo "Encrypting home partition..."
echo -n "${CONFIG_VALUES["LUKS Password"]}" | cryptsetup luksFormat "$HOME_PART"
echo -n "${CONFIG_VALUES["LUKS Password"]}" | cryptsetup open "$HOME_PART" crypthome

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$BOOT_PART" -n BOOT
mkfs.btrfs -f /dev/mapper/cryptroot -L ROOT
mkfs.btrfs -f /dev/mapper/crypthome -L HOME
if [[ "${CONFIG_VALUES["Swap Partition"]}" != "0" ]]; then
    mkswap "$SWAP_PART" -L SWAP
    swapon "$SWAP_PART"
fi

# Create Btrfs subvolumes
echo "Creating Btrfs subvolumes..."
mount --mkdir /dev/mapper/cryptroot /mnt
mount --mkdir /dev/mapper/crypthome /mnt/home
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/home/@home
umount /mnt/home && umount /mnt

# Mount subvolumes
echo "Mounting subvolumes..."
mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/home
mount -o compress=zstd,subvol=@home /dev/mapper/crypthome /mnt/home

# Mount boot partition
echo "Mounting boot partition..."
mkdir -p /mnt/boot/efi
mount "$BOOT_PART" /mnt/boot/efi

# Verify partitions, filesystems, and mounts
verify_partitions() {
    local errors=0

    # Check boot partition
    if ! blkid "${BOOT_PART}" | grep -q "TYPE=\"vfat\""; then
        echo "Error: Boot partition is not formatted as FAT32"
        errors=$((errors + 1))
    fi

    # Check root partition
    if ! cryptsetup status cryptroot | grep -q "type:      LUKS2"; then
        echo "Error: Root partition is not encrypted with LUKS2"
        errors=$((errors + 1))
    fi

    if ! blkid /dev/mapper/cryptroot | grep -q "TYPE=\"btrfs\""; then
        echo "Error: Root partition is not formatted as Btrfs"
        errors=$((errors + 1))
    fi

    # Check home partition
    if ! cryptsetup status crypthome | grep -q "type:      LUKS2"; then
        echo "Error: Home partition is not encrypted with LUKS2"
        errors=$((errors + 1))
    fi

    if ! blkid /dev/mapper/crypthome | grep -q "TYPE=\"btrfs\""; then
        echo "Error: Home partition is not formatted as Btrfs"
        errors=$((errors + 1))
    fi

    # Check swap partition if it exists
    if [[ "${CONFIG_VALUES["Swap Partition"]}" != "0" ]]; then
        if ! blkid "${SWAP_PART}" | grep -q "TYPE=\"swap\""; then
            echo "Error: Swap partition is not formatted as swap"
            errors=$((errors + 1))
        fi
    fi

    # Check mounts
    if ! findmnt /mnt | grep -q "/dev/mapper/cryptroot"; then
        echo "Error: Root partition is not mounted at /mnt"
        errors=$((errors + 1))
    fi

    if ! findmnt /mnt/home | grep -q "/dev/mapper/crypthome"; then
        echo "Error: Home partition is not mounted at /mnt/home"
        errors=$((errors + 1))
    fi

    if ! findmnt /mnt/boot/efi | grep -q "${BOOT_PART}"; then
        echo "Error: Boot partition is not mounted at /mnt/boot/efi"
        errors=$((errors + 1))
    fi

    # Check Btrfs subvolumes
    if ! btrfs subvolume list /mnt | grep -q "@"; then
        echo "Error: Root Btrfs subvolume '@' not found"
        errors=$((errors + 1))
    fi

    if ! btrfs subvolume list /mnt | grep -q "@home"; then
        echo "Error: Home Btrfs subvolume '@home' not found"
        errors=$((errors + 1))
    fi

    if [ $errors -eq 0 ]; then
        echo "All partitions, filesystems, and mounts verified successfully."
        return 0
    else
        echo "Verification failed with $errors errors."
        return 1
    fi
}

# Run the verification
if verify_partitions; then
    echo "Partition verification passed. Continuing with installation..."
else
    echo "Partition verification failed. Please check the errors and fix before continuing."
    exit 1
fi

# Update the mirrors
reflector --verbose --country India,China,Japan,Singapore,US --protocol https --sort rate --latest 20 --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist

# Install base system
echo "Installing base system..."
pacstrap /mnt base base-devel linux linux-headers linux-lts linux-lts-headers linux-zen linux-zen-headers linux-firmware nano vim networkmanager iw wpa_supplicant dialog

# Generate fstab
genfstab -U /mnt >>/mnt/etc/fstab
cat /mnt/etc/fstab

# Chroot into the new system
echo "Changing root..."
arch-chroot /mnt /bin/bash

# Create a key file for the home partition
echo "Creating key file for home partition..."
dd if=/dev/urandom of=/mnt/root/home.key bs=512 count=4
chmod 600 /mnt/root/home.key

# Add the key file to the LUKS home partition
echo "Adding key file to home partition..."
echo -n "${CONFIG_VALUES["LUKS Password"]}" | cryptsetup luksAddKey "$HOME_PART" /mnt/root/home.key

# Ensure the home partition is unlocked by initramfs using the key file
echo "Configuring home partition to be unlocked by initramfs using the key file..."
echo "crypthome  UUID=$(blkid -s UUID -o value $HOME_PART)  /root/home.key  luks" >>/mnt/etc/crypttab

# Ensure the key file is included in the initramfs
echo "Adding key file to initramfs..."
sed -i '/^FILES=/ s/)/ \/root\/home.key)/' /mnt/etc/mkinitcpio.conf

# Update mkinitcpio HOOKS to replace 'filesystems' with 'encrypt btrfs'
echo "Updating mkinitcpio hooks..."
sed -i '/^HOOKS=/ s/\bfilesystems\b/encrypt btrfs/' /etc/mkinitcpio.conf
mkinitcpio -P

# Ensure autoboot via passkey for root decryption
echo "Configuring autoboot via passkey for root decryption..."

USB_DEVICE="$(lsblk -o NAME,TYPE,RM | grep -E 'disk.*1' | awk '{print "/dev/"$1}')3"
USB_MOUNT="/mnt/usbkey"
KEY_FILE="luks-root.key"
KEYFILE_PATH="$USB_MOUNT/$KEY_FILE"

LUKS_DEVICE="${CONFIG_VALUES["Drive"]}2" # LUKS-encrypted partition
LUKS_NAME="cryptroot"                    # Name for the decrypted LUKS mapping

# Create a mount point for the USB if it doesn't exist
mkdir -p "$USB_MOUNT"

# Mount the USB drive
echo "Mounting USB drive..."
mount "$USB_DEVICE" "$USB_MOUNT"

# Generate a secure keyfile
echo "Creating keyfile..."
dd if=/dev/urandom of="$KEYFILE_PATH" bs=512 count=4
chmod 600 "$KEYFILE_PATH"

# Add keyfile to LUKS
echo "Adding keyfile to LUKS..."
echo -n "${CONFIG_VALUES["LUKS Password"]}" | cryptsetup luksAddKey "$LUKS_DEVICE" "$KEYFILE_PATH"

# Get UUIDs for fstab and GRUB config
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_DEVICE")
USB_UUID=$(blkid -s UUID -o value "$USB_DEVICE")

# Unmount the USB drive
echo "Unmounting USB drive..."
umount "$USB_MOUNT"

# Set root password
echo "Setting root password..."
echo "root:${CONFIG_VALUES["Root Password"]}" | chpasswd

# Create user
echo "Creating user ${CONFIG_VALUES["Username"]}..."
useradd -m -G wheel -s /bin/bash "${CONFIG_VALUES["Username"]}"

# Ensure user has sudo privileges
echo "Configuring sudo privileges..."
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD ALL/%wheel ALL=(ALL:ALL) NOPASSWD ALL/' /etc/sudoers

# Set hostname
echo "Setting hostname..."
echo "${CONFIG_VALUES["Hostname"]}" >/etc/hostname

# Configure /etc/hosts
echo "Configuring /etc/hosts..."
cat <<EOF >/etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${CONFIG_VALUES["Hostname"]}
EOF

# Configure locale
echo "Configuring locale..."
echo "LANG=en_AU.UTF-8" >/etc/locale.conf
echo "LC_ALL=en_AU.UTF-8" >>/etc/locale.conf
echo "en_AU.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen

# Set timezone and sync hardware clock
echo "Setting timezone and syncing hardware clock..."
ln -sf /usr/share/zoneinfo/Asia/Dhaka /etc/localtime
hwclock --systohc

# Update and install necessary packages
echo "Installing essential packages..."
pacman -Sy --noconfirm grub efibootmgr dosfstools os-prober mtools fuse3 zsh

# Mount EFI partition and install GRUB
echo "Installing GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# Ensure GRUB includes cryptdevice and cryptkey
echo "Updating GRUB configuration..."
GRUB_CFG="/etc/default/grub"
sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME cryptkey=UUID=$USB_UUID:btrfs:/$KEY_FILE root=\/dev\/mapper\/cryptroot\"|" "$GRUB_CFG"

grub-mkconfig -o /boot/grub/grub.cfg

# Backup the EFI file as a failsafe
mkdir -p /boot/efi/EFI/BOOT
cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI

# Change shell to zsh
echo "Changing shell to zsh..."
chsh -s /bin/zsh

# Change user
echo "Changing user to ${CONFIG_VALUES["Username"]}..."
su ${CONFIG_VALUES["Username"]}

# Ensure the post install script executes once
echo "Creating post-install script runner..."
ZSHRC="/home/${CONFIG_VALUES["Username"]}/.zshrc"

# Create the target script
cat <<EOF >$ZSHRC
# Launch the post install script
sudo bash /home/${CONFIG_VALUES["Username"]}/Scratch/sysgen/main.sh post-install
mv /home/${CONFIG_VALUES["Username"]}/Scratch/sysgen/main.sh /home/${CONFIG_VALUES["Username"]}/Scratch/sysgen/main.sh.done

# Remove self (to avoid running more than once)
sudo rm "$ZSHRC"

echo "Bye bye!"
poweroff
EOF

# Mount the drive
STORAGE_MOUNT="/mnt/storage"
mkdir -p $STORAGE_MOUNT
if ! mount /dev/sdb3 $STORAGE_MOUNT; then
    echo "Error: Failed to mount sdb3."
    exit 1
fi

# Copy the script directory
if ! cp -r /backup/sysgen /home/${CONFIG_VALUES["Username"]}/Scratch/; then
    echo "Error: Failed to copy the backup directory."
    exit 1
fi

echo "Installation completed successfully."
exit
umount -R /mnt
reboot
