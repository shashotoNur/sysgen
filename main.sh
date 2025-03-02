#!/bin/bash

set -e  # Exit on error

# Ensure script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script as root (using sudo)."
    exit 1
fi

# Check if fzf is available
if ! command -v fzf &>/dev/null; then
    echo "Error: fzf is not installed. Please install it before proceeding."
    exit 1
fi

# Get installation phase from argument or prompt
if [[ -n "$1" ]]; then
    PHASE="$1"
else
    # Define the available phases
    PHASES=("pre-install" "install" "post-install")
    PHASE=$(printf "%s\n" "${PHASES[@]}" | fzf --prompt="Select Phase: " --height=5 --reverse)
fi

sudo "./${PHASE}.sh" $SUDO_USER
