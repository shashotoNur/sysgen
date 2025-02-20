#!/bin/bash

set -e  # Exit on error

# Ensure script is run with sudo
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script as root (using sudo)."
    exit 1
fi

# Get installation phase from argument or prompt
if [[ -n "$1" ]]; then
    PHASE="$1"
else
    # Check if fzf is installed
    if ! command -v fzf &>/dev/null; then
        echo "fzf is not installed. Falling back to manual selection."
        USE_FZF=0
    else
        USE_FZF=1
    fi

    # Define the available phases
    PHASES=("pre-install" "install" "post-install")

    if [[ $USE_FZF -eq 1 ]]; then
        # Use fzf for interactive selection
        PHASE=$(printf "%s\n" "${PHASES[@]}" | fzf --prompt="Select Phase: " --height=5 --reverse)
    else
        # Fallback to manual numbered selection
        echo "Available Phases:"
        for i in "${!PHASES[@]}"; do
            echo "$((i+1)). ${PHASES[i]}"
        done

        read -rp "Enter the number of the phase: " CHOICE

        # Validate input
        if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#PHASES[@]} )); then
            echo "Invalid selection. Exiting..."
            exit 1
        fi

        # Set the selected phase
        PHASE="${PHASES[CHOICE-1]}"
    fi
fi

sudo "./${PHASE}.sh" $SUDO_USER
