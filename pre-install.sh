#!/bin/bash

# Ensure required commands are available
for cmd in wget ventoy tmux mkarchiso lsblk fzf mkfs.vfat parted; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' is not installed. Please install it before proceeding."
        exit 1
    fi
done

# List only sdX devices (excluding loop devices and partitions)
USB_DEVICE=$(lsblk -dno NAME,MODEL,SIZE | grep '^sd' | fzf --prompt="Select USB device: " --height=10 --reverse | awk '{print "/dev/" $1}')

# Check if a device was selected
if [[ -z "$USB_DEVICE" ]]; then
    echo "No device selected. Exiting..."
    exit 1
fi

# Show warning before formatting
echo "WARNING: This will completely erase all data on $USB_DEVICE!"
read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 1
fi

# Wipe existing filesystem signatures
echo "Wiping existing filesystems..."
wipefs --all "$USB_DEVICE"

# Get total size of USB in GB
TOTAL_SIZE_GB=$(lsblk -b -n -o SIZE "$USB_DEVICE" | awk '{print $1/1024/1024/1024}')
TOTAL_SIZE_MB=$(lsblk -b -n -o SIZE "$USB_DEVICE" | awk '{print $1/1024/1024}')
TOTAL_SIZE_GB=${TOTAL_SIZE_GB%.*}  # Remove decimals

echo "Detected USB Size: ${TOTAL_SIZE_GB}GB"

# Get storage size from user (in GB) and convert to MB
while true; do
    read -rp "Enter storage partition size (in GB, max: ${TOTAL_SIZE_GB}): " STORAGE_SIZE_GB
    if [[ "$STORAGE_SIZE_GB" =~ ^[0-9]+$ ]] && [[ "$STORAGE_SIZE_GB" -gt 0 ]] && [[ "$STORAGE_SIZE_GB" -lt "$TOTAL_SIZE_GB" ]]; then
        break
    else
        echo "Invalid input. Please enter a valid number between 1 and ${TOTAL_SIZE_GB}."
    fi
done

STORAGE_SIZE_MB=$(( STORAGE_SIZE_GB * 1024 ))
MULTIBOOT_SIZE_MB=$(( TOTAL_SIZE_MB - STORAGE_SIZE_MB ))

echo "Storage Partition: ${STORAGE_SIZE_GB}GB (${STORAGE_SIZE_MB}MB)"
echo "Multiboot Partition: $((TOTAL_SIZE_GB - STORAGE_SIZE_GB))GB (${MULTIBOOT_SIZE_MB}MB)"

# Backup VS Code extensions
echo "Backing up VS Code settings and extensions..."
mkdir -p ./backup/code
sudo -u "$1" code --list-extensions > ./backup/code/ext_list.txt
sudo cp /home/$1/.config/Code\ -\ OSS/User/settings.json ./backup/code

# Get passphrase for GPG key export
read -rsp "Enter passphrase for GPG key export: " GPG_PASSPHRASE
echo ""

# Prompt user to backup necessary files
echo "Ensure you have backed up important files to ./backup."
read -p "Press Enter to continue..."

ISO_NAME="archlinux-x86_64.iso"

# Start a new tmux session for parallel jobs
SESSION_NAME="arch_install"
tmux new-session -d -s "$SESSION_NAME"

# Pane 1: Download Arch Linux ISO and verify integrity
tmux send-keys -t "$SESSION_NAME" "echo 'Downloading Arch ISO...'; wget -c https://mirrors.edge.kernel.org/archlinux/iso/latest/$ISO_NAME && wget -c https://mirrors.edge.kernel.org/archlinux/iso/latest/$ISO_NAME.sig && exit" C-m

# Pane 2: Install Ventoy on multiboot partition
tmux split-window -h -t "$SESSION_NAME"
tmux send-keys -t "$SESSION_NAME" "echo 'Setting up Ventoy on $USB_DEVICE...'; yes | sudo ventoy -L MULTIBOOT -r $STORAGE_SIZE_MB -I $USB_DEVICE && exit" C-m

# Pane 3: Export GPG keys
tmux split-window -v -t "$SESSION_NAME"
tmux send-keys -t "$SESSION_NAME" "echo 'Exporting GPG keys...'; gpg --export-secret-keys --pinentry-mode loopback --passphrase '$GPG_PASSPHRASE' > private.asc && gpg --export --armor > public.asc && exit" C-m

# Attach to the tmux session and wait for user to close panes
tmux attach-session -t "$SESSION_NAME"

# Once tmux session is closed, continue the script

# Verify integrity of Arch ISO
gpg --verify $ISO_NAME.sig $ISO_NAME

# Check if the key files are empty
if [ ! -s private.asc ] || [ ! -s public.asc ]; then
  read -p "At least one of the key files is empty! Press Enter to continue..."
fi

# Move the key files to backup
mkdir -p ./backup/keys
mv ./*.asc ./backup/keys

# Create storage partition on unallocated space
echo "Creating storage partition..."
parted -s "$USB_DEVICE" mkpart primary fat32 "${MULTIBOOT_SIZE_MB}MiB" 100%

if [[ -z "${USB_DEVICE}3" ]]; then
    echo "Error: Could not detect the storage partition."
    exit 1
fi

# Format the storage partition as FAT32
echo "Formatting "${USB_DEVICE}3" as FAT32 (STORAGE)..."
mkfs.vfat -F32 "${USB_DEVICE}3" -n STORAGE

# Mount the storage partition to verify it is properly formatted
mount "${USB_DEVICE}3" /mnt/storage

# Mount the partitions
STORAGE_MOUNT="/mnt/storage"
MULTIBOOT_MOUNT="/mnt/multiboot"

mkdir -p "$STORAGE_MOUNT" "$MULTIBOOT_MOUNT"
mount "${USB_DEVICE}3" "$STORAGE_MOUNT"
mount "${USB_DEVICE}1" "$MULTIBOOT_MOUNT"

# Ensure the installation script runs on boot
WORK_DIR="./archiso"

# Prepare working directories
mkdir -p "$WORK_DIR"
sudo mount -o loop "$ISO_NAME" /mnt
cp -r /mnt "$WORK_DIR/iso"
sudo umount /mnt

# Copy installation script
sudo mkdir -p "$WORK_DIR/iso/airootfs/root"
sudo cp ./*.sh "$WORK_DIR/iso/airootfs/root/"

# Ensure the script runs on boot
sudo bash -c "echo 'sudo /root/main.sh install' >> $WORK_DIR/iso/airootfs/root/.bashrc"

# Build the modified ISO
echo "Building the modified arch ISO..."
sudo mkarchiso -v -w "$WORK_DIR/work" -o "$WORK_DIR/out" "$WORK_DIR/iso"

# Output final ISO location
echo "Custom Arch ISO created at: $WORK_DIR/out"

# Copy necessary files
echo "Copying the arch iso to the USB drive..."
cp $WORK_DIR/out/*.iso "$MULTIBOOT_MOUNT"

rm $ISO_NAME
rm -rf $WORK_DIR

echo "Copying the scripts and backup to the USB drive..."
cp -r "$(dirname "$0")" "$STORAGE_MOUNT"

# Create Ventoy config directory if it doesn't exist
mkdir -p "$MULTIBOOT_MOUNT/ventoy"

# Write Ventoy JSON config
cat <<EOF | sudo tee "$MULTIBOOT_MOUNT/ventoy/ventoy.json"
{
    "control": [
        { "VTOY_DEFAULT_MENU_MODE": "1" },
        { "VTOY_TIMEOUT": "1" },
        { "VTOY_DEFAULT_SEARCH_ROOT": "1" }
    ]
}
EOF

echo "Ventoy is configured to boot the first ISO automatically\!"

# Get the boot number for EFI USB Device
USB_BOOT_NUM=$(efibootmgr | awk '/EFI USB Device/ {gsub("[^0-9]", "", $1); print $1}')

# Check if a USB boot entry was found
if [[ -z "$USB_BOOT_NUM" ]]; then
    echo "Error: No EFI USB Device found in efibootmgr output."
    systemctl reboot --firmware-setup
fi

echo "Found EFI USB Device with Boot Number: $USB_BOOT_NUM"

# Set the USB device as the next boot option
efibootmgr --bootnext "$USB_BOOT_NUM"
systemctl reboot
