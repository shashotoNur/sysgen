#!/bin/bash

# Function: build_custom_arch_iso
# Purpose: Builds a custom Arch Linux ISO with specified configurations.
# Arguments:
#   $1: The root directory where the script is located.
build_custom_arch_iso() {
    set -euo pipefail # Exit on error, unset variable, or pipeline failure

    local ROOT_DIR="$1"
    local ARCHISO_DIR="$ROOT_DIR/archiso"
    local CUSTOM_PROFILE="releng"
    local PROFILE_DIR="$ARCHISO_DIR/configs/$CUSTOM_PROFILE"
    local OUTPUT_ISO_NAME="sysgen_archlinux.iso"

    log_info "Building custom Arch ISO..."

    # Clone ArchISO repository
    if [[ ! -d "$ARCHISO_DIR" ]]; then
        log_info "Cloning ArchISO repository..."
        git clone --depth=1 https://gitlab.archlinux.org/archlinux/archiso.git "$ARCHISO_DIR" || {
            log_error "Failed to clone ArchISO repository."
            return 1
        }
    fi

    # Copy user scripts into airootfs
    log_info "Copying custom scripts into airootfs..."
    mkdir -p "$PROFILE_DIR/airootfs/root/sysgen"
    cp -r install.conf sync_dirs.lst ./bin/laucher.sh "$PROFILE_DIR/airootfs/root/" || {
        log_error "Failed to copy custom scripts to airootfs."
        return 1
    }

    # Ensure the script runs on boot
    log_info "Ensuring install.sh runs on boot..."
    echo "sudo bash launcher.sh" >>"$PROFILE_DIR/airootfs/root/.zshrc" || {
        log_error "Failed to update .zshrc."
        return 1
    }

    # Define the path to loader.conf
    local LOADER_CONF="$PROFILE_DIR/efiboot/loader/loader.conf"

    # Ensure the file exists before modifying
    if [[ -f "$LOADER_CONF" ]]; then
        log_info "Modifying loader.conf..."
        # Modify the timeout value and beep setting
        sed -i 's/^timeout .*/timeout 1/' "$LOADER_CONF" || {
            log_error "Failed to update timeout in loader.conf."
            return 1
        }
        sed -i 's/^beep on$/beep off/' "$LOADER_CONF" || {
            log_error "Failed to update beep in loader.conf."
            return 1
        }

        log_info "Updated $LOADER_CONF:"
        grep -E '^timeout|^beep' "$LOADER_CONF"
    else
        log_error "Error: $LOADER_CONF not found!"
        return 1
    fi

    # Include fuzzy finder in the iso
    log_info "Adding fzf to the ISO packages..."
    echo "fzf" >>"$PROFILE_DIR/packages.x86_64" || {
        log_error "Failed to add fzf to packages.x86_64."
        return 1
    }

    # Build the custom ISO
    log_info "Building the custom ISO..."
    sudo mkarchiso -v -w work -o out "$PROFILE_DIR" || {
        log_error "Failed to build custom ISO."
        return 1
    }

    # Rename the output ISO
    log_info "Renaming the output ISO..."
    mkdir -p "$ROOT_DIR/iso"
    mv out/archlinux-*.iso "$ROOT_DIR/iso/$OUTPUT_ISO_NAME" || {
        log_error "Failed to rename the output ISO."
        return 1
    }

    # Output final ISO location
    log_success "Custom Arch ISO created at: $ROOT_DIR/iso/$OUTPUT_ISO_NAME"
}
