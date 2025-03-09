#!/bin/bash

# Check if the configuration file exists and is readable.
validate_config_file() {
    log_info "Validating configuration file: $CONFIG_FILE"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file '$CONFIG_FILE' does not exist. Exiting."
        return 1
    fi
    if [[ ! -r "$CONFIG_FILE" ]]; then
        log_error "Configuration file '$CONFIG_FILE' is not readable. Exiting."
        return 1
    fi
    log_success "Configuration file '$CONFIG_FILE' is valid and readable."
    return 0
}

# Extract a value from the configuration file
extract_config_value() {
    local key="$1"
    local config_file="${2:-$CONFIG_FILE}"

    if ! [[ -f "$config_file" ]]; then
        log_error "Config file '$config_file' not found."
        return 1
    fi

    grep -E "^$key:" "$config_file" | awk -F': ' '{print $2}'
}

# Read configuration from install.conf
read_config() {
    local key
    local value
    declare -A config_values

    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file '$CONFIG_FILE' not found."
        return 1
    fi

    while IFS='=' read -r key value; do
        key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        value=$(echo "$value" | tr -d '[:space:]')
        config_values["$key"]="$value"
    done < <(sed '/^#/d;s/^[[:blank:]]*//;s/[[:blank:]]*$//' "$CONFIG_FILE") #remove comments and trim whitespace

    # Output key-value pairs in a format that can be read back into an associative array
    printf "%s=\"%s\"\n" "${!config_values[@]}" "${config_values[@]}"
}

# Prompts the user for various installation settings
get_installation_config() {
    set -e # Exit on error

    OUTPUT_FILE="install.conf"
    DRIVE=""

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
        G) echo $(awk "BEGIN {printf \"%d\", $SIZE_NUM * 1000000000 / 1073741824}") ;;    # Convert GB → GiB
        T) echo $(awk "BEGIN {printf \"%d\", $SIZE_NUM * 1000000000000 / 1073741824}") ;; # Convert TB → GiB
        *)
            echo "Invalid size format"
            exit 1
            ;;
        esac
    }

    if [[ "$LOCAL_INSTALL" == "y" ]]; then
        # List drives and select one with fzf
        DRIVE=$(lsblk -d -n -o NAME,SIZE | fzf --prompt="Select installation drive: " | awk '{print $1}')
        RAW_SIZE=$(lsblk -d -n -o SIZE "/dev/$DRIVE" | awk '{print int($1)}') # Get raw size (e.g., "931G" or "1T")

        DRIVE_SIZE=$RAW_SIZE
    else
        read -p "Enter the size of the drive on the other device (e.g., 128G, 1T): " DRIVE_SIZE
        SIZE_UNIT=${DRIVE_SIZE: -1}
        SIZE_NUM=${DRIVE_SIZE::-1}

        DRIVE_SIZE=$(convert_to_gib "$SIZE_NUM" "$SIZE_UNIT") # Convert to GiB
    fi

    # Convert to integer (ensuring no decimal places)
    AVAILABLE_SPACE=$DRIVE_SIZE

    echo "Available space: ${AVAILABLE_SPACE} GiB"

    # Function to get partition size while checking limits
    get_partition_size() {
        local PART_NAME=$1
        local PART_SIZE

        while true; do
            read -p "Enter $PART_NAME partition size in GiB (${AVAILABLE_SPACE} GiB left): " PART_SIZE

            if [[ "$PART_SIZE" =~ ^[0-9]+$ ]] && [[ "$PART_SIZE" -le "$AVAILABLE_SPACE" ]]; then
                AVAILABLE_SPACE=$((AVAILABLE_SPACE - PART_SIZE)) # Update global variable
                eval "${PART_NAME}_SIZE=$PART_SIZE"              # Assign dynamically
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

    # Get Gemini API Key
    read -s -p "Enter Gemini API Key: " GEMINI_API_KEY
    echo

    # Get Mega Password and Key
    read -s -p "Enter Mega Password: " MEGA_PASSWORD
    echo
    read -s -p "Enter Mega TOTP Key: " MEGA_KEY
    echo

    # Get Music Playlist Link
    read -p "Enter Music Playlist Link: " MUSIC_PLAYLIST_LINK

    # Get Github Token
    read -s -p "Enter Github Token: " GITHUB_TOKEN
    echo

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
        echo "Gemini API Key: $GEMINI_API_KEY"
        echo "Mega Password: $MEGA_PASSWORD"
        echo "Mega Key: $MEGA_KEY"
        echo "Music Playlist Link: $MUSIC_PLAYLIST_LINK"
        echo "Github Token: $GITHUB_TOKEN"
    } >"$OUTPUT_FILE"

    echo "Installation configuration saved to $OUTPUT_FILE"
}

get_installation_configuration() {
    log_info "Getting installation configuration..."
    get_installation_config
    log_success "Installation configuration retrieved."
}
