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

# Get passphrase for GPG key export
read -rsp "Enter passphrase for GPG key export: " GPG_PASSPHRASE
echo ""

# Prompt user to backup necessary files
DATA_DIR="./backup/data"
mkdir -p $DATA_DIR

SELECTED="/tmp/fzf_selected"
SIZE="/tmp/fzf_total"

# Clear previous selections
>"$SELECTED"
>"$SIZE"

# Use fzf to select multiple files and directories
SELECTED_ITEMS=$(
    find ~ -mindepth 1 -maxdepth 5 | fzf --multi --preview 'du -sh {}' \
        --bind "space:execute-silent(
        grep -Fxq {} $SELECTED && sed -i '\|^{}$|d' $SELECTED || echo {} >> $SELECTED;
        du -ch \$(cat $SELECTED 2>/dev/null) | grep total$ > $SIZE
    )+toggle" \
        --bind "ctrl-r:execute-silent(truncate -s 0 $SELECTED; truncate -s 0 $SIZE)+reload(find ~ -mindepth 1 -maxdepth 5)" \
        --preview 'cat /tmp/fzf_total' \
        --bind "ctrl-a:execute-silent(find ~ -mindepth 1 -maxdepth 5 > $SELECTED; du -ch \$(cat $SELECTED) | grep total$ > $SIZE)+select-all"
)

if [[ -z "$SELECTED_ITEMS" ]]; then
    echo "No files or directories selected. Exiting."
else
    # Display the final total size
    TOTAL_SIZE=$(du -ch $(cat "$SELECTED" 2>/dev/null) | grep "total$" | awk '{print $1}')
    echo "Total size of selected items: $TOTAL_SIZE"
    echo "Files and directories selected:"
    echo $SELECTED_ITEMS
fi

# Get the installation configurations
bash utils/getconfig.sh

# Get the mega sync directories
read -p "Do you want to select directories to backup your MEGA sync data? (y/n): " choice

if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    echo "Select the directories you want to sync on MEGA."
    find ~ -type d | fzf --multi >selected_directories.txt
else
    echo "MEGA sync backup selection skipped."
fi

# Check if the device has any mounted partitions
MOUNTED_PARTITIONS=$(mount | grep "^$USB_DEVICE" | awk '{print $1}')

if [[ -n "$MOUNTED_PARTITIONS" ]]; then
    echo "Unmounting partitions on $USB_DEVICE..."
    for PARTITION in $MOUNTED_PARTITIONS; do
        sudo umount -l "$PARTITION" || sudo umount -f "$PARTITION"
        echo "Unmounted: $PARTITION"
    done
else
    echo "$USB_DEVICE is not mounted."
fi

# Wipe existing filesystem signatures
echo "Wiping existing filesystems..."
wipefs --all "$USB_DEVICE"

# Get total size of USB in GB
TOTAL_SIZE_GB=$(lsblk -b -n -o SIZE "$USB_DEVICE" | awk '{print $1/1024/1024/1024}')
TOTAL_SIZE_MB=$(lsblk -b -n -o SIZE "$USB_DEVICE" | awk '{print $1/1024/1024}')
TOTAL_SIZE_GB=${TOTAL_SIZE_GB%.*} # Remove decimals

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

STORAGE_SIZE_MB=$((STORAGE_SIZE_GB * 1024))
MULTIBOOT_SIZE_MB=$((TOTAL_SIZE_MB - STORAGE_SIZE_MB))

echo "Storage Partition: ${STORAGE_SIZE_GB}GB (${STORAGE_SIZE_MB}MB)"
echo "Multiboot Partition: $((TOTAL_SIZE_GB - STORAGE_SIZE_GB))GB (${MULTIBOOT_SIZE_MB}MB)"

# Backup VS Code extensions
echo "Backing up VS Code settings and extensions..."
mkdir -p ./backup/code
sudo -u "$1" code --list-extensions >./backup/code/ext.lst
sudo cp /home/$1/.config/Code\ -\ OSS/User/settings.json ./backup/code

# Backup dotfiles
mkdir -p ./backup/dolphin
cp ~/.local/share/kxmlgui5/dolphin/dolphinui.rc ./backup/dolphin
cp ~/.config/dolphinrc ./backup/dolphin/
mkdir -p ./backup/zsh/
cp ~/.zshrc ./backup/zsh/
mkdir -p ./backup/timeshift
cp /etc/timeshift/timeshift.json ./backup/timeshift/

# Create script directory
SCRIPT_DIR="sysgen"
mkdir -p "$SCRIPT_DIR"
cp -r ./*.sh utils/ install.conf "$SCRIPT_DIR"

# Start a new tmux session for parallel jobs
SESSION_NAME="system_generator"
tmux new-session -d -s "$SESSION_NAME"

# Pane 1: Build a modified version of the Arch ISO
tmux send-keys -t "$SESSION_NAME" "echo 'Cloning ArchISO and building.'; sudo bash utils/buildiso.sh . && exit" C-m

# Pane 2: Install Ventoy on multiboot partition
tmux split-window -h -t "$SESSION_NAME"
tmux send-keys -t "$SESSION_NAME" "echo 'Setting up Ventoy on $USB_DEVICE...'; yes | sudo ventoy -L MULTIBOOT -r $STORAGE_SIZE_MB -I $USB_DEVICE && exit" C-m

# Pane 3: Export GPG keys
tmux split-window -v -t "$SESSION_NAME"
tmux send-keys -t "$SESSION_NAME" "echo 'Exporting GPG keys...'; gpg --export-secret-keys --pinentry-mode loopback --passphrase '$GPG_PASSPHRASE' > private.asc && gpg --export --armor > public.asc && exit" C-m

# Pane 4: Copy the selected files for backup
tmux split-window -h -t "$SESSION_NAME"
tmux send-keys -t "$SESSION_NAME" "echo 'Moving files...'; mv $SELECTED_ITEMS $DATA_DIR && echo 'Move complete!' && exit" C-m

# Attach to the tmux session and wait for user to close panes
tmux attach-session -t "$SESSION_NAME"

# Check if the key files are empty
if [ ! -s private.asc ] || [ ! -s public.asc ]; then
    echo "Warning: At least one of the key files is empty!"
fi

# Move the key files to backup
mkdir -p ./backup/keys
mv ./*.asc ./backup/keys

# Create storage partition on unallocated space
echo "Creating storage partition..."
parted -s "$USB_DEVICE" mkpart primary btrfs "${MULTIBOOT_SIZE_MB}MiB" 100%

if [[ -z "${USB_DEVICE}3" ]]; then
    echo "Error: Could not detect the storage partition."
    exit 1
fi

# Format the storage partition as FAT32
echo "Formatting "${USB_DEVICE}3" as FAT32 (STORAGE)..."
mkfs.btrfs -L STORAGE "${USB_DEVICE}3"

# Mount the partitions
STORAGE_MOUNT="/mnt/storage"
MULTIBOOT_MOUNT="/mnt/multiboot"

mkdir -p "$STORAGE_MOUNT" "$MULTIBOOT_MOUNT"
mount "${USB_DEVICE}3" "$STORAGE_MOUNT"
mount "${USB_DEVICE}1" "$MULTIBOOT_MOUNT"

# Copy necessary files
echo "Copying the arch iso to the USB drive..."
cp iso/sysgen_archlinux.iso "$MULTIBOOT_MOUNT"

echo "Copying backup to the USB drive..."
cp -r $SCRIPT_DIR backup
cp -r backup "$STORAGE_MOUNT"

sudo rm -rf archiso iso work out backup $SCRIPT_DIR

# Create Ventoy config directory if it doesn't exist
mkdir -p "$MULTIBOOT_MOUNT/ventoy"

# Write Ventoy JSON config
cat <<EOF | sudo tee "$MULTIBOOT_MOUNT/ventoy/ventoy.json"
{
    "control": [
        { "VTOY_MENU_TIMEOUT": "0" },
        { "VTOY_SECONDARY_TIMEOUT": "0" }
    ]
}
EOF

echo "Ventoy is configured to boot the first ISO in normal mode automatically!"

# Get the boot number for EFI USB Device
USB_BOOT_NUM=$(efibootmgr | awk '/EFI USB Device/ {gsub("[^0-9]", "", $1); print $1}')

# Check if a USB boot entry was found
if [[ -z "$USB_BOOT_NUM" ]]; then
    echo "Error: No EFI USB Device found in efibootmgr output. You would have to manually boot into the USB Device."
    systemctl reboot --firmware-setup
fi

echo "Found EFI USB Device with Boot Number: $USB_BOOT_NUM"

# Set the USB device as the next boot option
sudo efibootmgr --bootnext "$USB_BOOT_NUM"
systemctl reboot
