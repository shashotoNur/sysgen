#!/bin/bash

###############################################################################
# Script Name: install.sh
# Description: Automates the installation of a custom Arch Linux system to a
#              specified drive, including partitioning, encryption, base system
#              installation, and setup postinstallation script.
# Author: Shashoto Nur
# Date: 07/03/2025
# Version: 1.1
# License: MIT
###############################################################################

# --- Configuration ---
set -euo pipefail # Exit on error, unset variable, or pipeline failure

# --- Global Variables ---
CONFIG_FILE="install.conf"
SCRIPT_DIR="$(dirname "$0")" # Get the directory of the script

# --- Source files ---
source ./source.sh
source_lib_files ../lib/

install() {
    check_uefi || return 1
    read_config || return 1
    check_internet || return 1

    if [[ "${CONFIG_VALUES["Drive"]}" == "/dev/" || -z "${CONFIG_VALUES["Drive"]}" ]]; then
        CONFIG_VALUES["Drive"]=$(select_drive) || return 1
    fi

    log_info "Wiping ${CONFIG_VALUES["Drive"]}..."
    wipefs --all --force "${CONFIG_VALUES["Drive"]}" || log_error "Failed to wipe drive" && return 1
    log_success "Drive wiped successfully."

    partition_disk "${CONFIG_VALUES["Drive"]}" "${CONFIG_VALUES[@]}" || return 1
    format_partitions || return 1

    encrypt_partition "${CONFIG_VALUES["Drive"]}2" "${CONFIG_VALUES["LUKS Password"]}" "cryptroot" || return 1
    encrypt_partition "${CONFIG_VALUES["Drive"]}4" "${CONFIG_VALUES["LUKS Password"]}" "crypthome" || return 1

    create_btrfs_subvolumes || return 1
    mount_partitions || return 1
    install_base_system || return 1
    generate_fstab || return 1
    manage_keyfiles || return 1

    update_mirrors || return 1
    configure_system || return 1
    install_grub || return 1
    ensure_auto_login "${CONFIG_VALUES["Username"]}" || return 1
    execute_post_install
    backup_config || return 1

    log_success "Installation completed successfully."
    reboot
}

################################################################################################
# --- Main Script Execution ---

install
