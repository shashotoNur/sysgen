#!/usr/bin/env bash

set -e  # Exit on error

OUTPUT_FILE="install_config.txt"

# Ask for user details
read -p "Enter your full name: " FULL_NAME
read -p "Enter your email: " EMAIL
read -p "Enter your username: " USERNAME
read -p "Enter your hostname: " HOSTNAME

# Ask if installing on this device or another
read -p "Is the installation happening on this device? (y/N): " LOCAL_INSTALL

convert_to_gib() {
    local SIZE_NUM=$1
    local SIZE_UNIT=$2
    case "$SIZE_UNIT" in
        G) echo $(awk "BEGIN {printf \"%d\", $SIZE_NUM * 1000000000 / 1073741824}") ;;  # Convert GB → GiB
        T) echo $(awk "BEGIN {printf \"%d\", $SIZE_NUM * 1000000000000 / 1073741824}") ;;  # Convert TB → GiB
        *) echo "Invalid size format"; exit 1 ;;
    esac
}

if [[ "$LOCAL_INSTALL" == "y" ]]; then
    # List drives and select one with fzf
    DRIVE=$(lsblk -d -n -o NAME,SIZE | fzf --prompt="Select installation drive: " | awk '{print $1}')
    RAW_SIZE=$(lsblk -d -n -o SIZE "/dev/$DRIVE" | awk '{print int($1)}')  # Get raw size (e.g., "931G" or "1T")

    DRIVE_SIZE=$RAW_SIZE
else
    read -p "Enter the size of the drive on the other device (e.g., 126G, 1T): " DRIVE_SIZE
    SIZE_UNIT=${DRIVE_SIZE: -1}
    SIZE_NUM=${DRIVE_SIZE::-1}

    DRIVE_SIZE=$(convert_to_gib "$SIZE_NUM" "$SIZE_UNIT")  # Convert to GiB
fi

# Convert to integer (ensuring no decimal places)
AVAILABLE_SPACE=$DRIVE_SIZE

echo "Available space: ${AVAILABLE_SPACE} GiB"

# Function to get partition size while checking limits
get_partition_size() {
    local PART_NAME=$1
    local PART_SIZE

    while true; do
        echo "Available space before $PART_NAME: ${AVAILABLE_SPACE} GiB"
        read -p "Enter $PART_NAME partition size in GiB: " PART_SIZE

        if [[ "$PART_SIZE" =~ ^[0-9]+$ ]] && [[ "$PART_SIZE" -le "$AVAILABLE_SPACE" ]]; then
            AVAILABLE_SPACE=$((AVAILABLE_SPACE - PART_SIZE))  # Update global variable
            eval "${PART_NAME}_SIZE=$PART_SIZE"  # Assign dynamically
            break
        else
            echo "Invalid size or exceeds available space. Try again."
        fi
    done
}

# Get partition sizes (Updating AVAILABLE_SPACE properly)
get_partition_size "BOOT"
get_partition_size "ROOT"
get_partition_size "SWAP"
get_partition_size "HOME"

# Confirm final available space
echo "Final available space after partitioning: ${AVAILABLE_SPACE} GiB"

# Network preferences
read -p "Will you use Ethernet or WiFi? (eth/wifi): " NETWORK_TYPE
if [[ "$NETWORK_TYPE" == "wifi" ]]; then
    read -p "Enter WiFi SSID: " WIFI_SSID
    read -s -p "Enter WiFi Password: " WIFI_PASSWORD
    echo
fi

# LUKS and root password preferences
read -p "Use the same password for LUKS and root? (y/N): " SAME_PASSWORD
if [[ "$SAME_PASSWORD" == "y" ]]; then
    read -s -p "Enter password: " PASSWORD
    echo
else
    read -s -p "Enter LUKS password: " LUKS_PASSWORD
    echo
    read -s -p "Enter root password: " ROOT_PASSWORD
    echo
fi

# Save details to file
{
    echo "Full Name: $FULL_NAME"
    echo "Email: $EMAIL"
    echo "Username: $USERNAME"
    echo "Hostname: $HOSTNAME"
    echo "Local Installation: $LOCAL_INSTALL"
    echo "Drive: /dev/$DRIVE"
    echo "Drive Size: ${DRIVE_SIZE}GiB"
    echo "Boot Partition: ${BOOT_SIZE}GiB"
    echo "Root Partition: ${ROOT_SIZE}GiB"
    echo "Swap Partition: ${SWAP_SIZE}GiB"
    echo "Home Partition: ${HOME_SIZE}GiB"
    echo "Network Type: $NETWORK_TYPE"
    [[ "$NETWORK_TYPE" == "wifi" ]] && {
        echo "WiFi SSID: $WIFI_SSID"
        echo "WiFi Password: $WIFI_PASSWORD"
    }
    if [[ "$SAME_PASSWORD" == "y" ]]; then
        echo "Password: $PASSWORD"
    else
        echo "LUKS Password: $LUKS_PASSWORD"
        echo "Root Password: $ROOT_PASSWORD"
    fi
} > "$OUTPUT_FILE"

echo "Installation configuration saved to $OUTPUT_FILE"
