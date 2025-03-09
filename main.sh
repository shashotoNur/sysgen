#!/bin/bash

###############################################################################
# Script Name: main.sh
# Description: Orchestrates the system generation process, handling preinstall,
#              install, and postinstall phases.
# Author: Shashoto Nur

# Version: 1.1
# License: MIT
###############################################################################

# --- Configuration ---
set -euo pipefail # Exit on error, unset variable, or pipeline failure

# --- Functions ---

check_root_privileges() {
    log_info "Checking for root privileges..."
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run with root privileges (using sudo)."
        exit 1
    fi
    log_success "Root privileges confirmed."
}

check_fzf_installation() {
    log_info "Checking if fzf is installed..."
    if ! command -v fzf &>/dev/null; then
        log_error "fzf is not installed. Please install it before proceeding."
        exit 1
    fi
    log_success "fzf is installed."
}

select_installation_phase() {
    log_info "Determining installation phase..."
    if [[ -n "$1" ]]; then
        log_info "Installation phase provided as argument: $1"
        PHASE="$1"
    else
        log_info "No installation phase provided, prompting user for selection..."
        # Define the available phases
        PHASES=("preinstall" "install" "postinstall")
        PHASE=$(printf "%s\n" "${PHASES[@]}" | fzf --prompt="Select Phase: " --height=5 --reverse)
        if [[ -z "$PHASE" ]]; then
            log_error "No phase selected. Exiting."
            exit 1
        fi
        log_info "User selected phase: $PHASE"
    fi
}

execute_phase() {
    local phase="$1"
    local user="$2"

    log_info "Executing phase: $phase"
    local script_path="./bin/${phase}.sh"
    if [[ ! -f "$script_path" ]]; then
        log_error "Script for phase '$phase' not found at '$script_path'."
        exit 1
    fi
    log_info "Script path: $script_path"

    # Check for execution permission
    if [[ ! -x "$script_path" ]]; then
        log_warning "Script '$script_path' is not executable. Attempting to set executable permission..."
        chmod +x "$script_path"
        if [[ $? -ne 0 ]]; then
            log_error "Failed to set executable permission on '$script_path'. Please check permissions and try again."
            exit 1
        fi
        log_success "Successfully set executable permission on '$script_path'."
    fi

    log_info "Running script: sudo \"$script_path\" \"$user\""
    sudo "$script_path" "$user"

    if [[ $? -eq 0 ]]; then
        log_success "Phase '$phase' completed successfully."
    else
        log_error "Phase '$phase' failed with an error."
        exit 1
    fi
}

print_project_introduction () {
    local script_name=$(basename "$0")
    local project_name="System Generator (SysGen)"
    local description="A comprehensive toolkit for automating Arch Linux system setup as per author's preferences."
    local version="1.1"
    local author="Shashoto Nur"

    # ANSI color codes
    local reset="\e[0m"
    local bold="\e[1m"
    local green="\e[32m"
    local cyan="\e[36m"
    local yellow="\e[33m"

    echo -e "${bold}${cyan}===========================================================================================================${reset}"
    echo -e "${bold}${green}  $project_name ${reset}"
    echo -e "${bold}  Version: ${yellow}$version${reset}"
    echo -e "${bold}  Author:  ${yellow}$author${reset}"
    echo -e "${bold}  Script:  ${yellow}$script_name${reset}"
    echo -e "${bold}${cyan}===========================================================================================================${reset}"
    echo -e "${bold}  Description:${reset} $description"
    echo -e "${bold}${cyan}===========================================================================================================${reset}"
}


# --- Main Script Execution ---
main () {
    print_project_introduction

    check_root_privileges
    check_fzf_installation
    select_installation_phase "$1"

    execute_phase "$PHASE" "$SUDO_USER"
    log_success "Script execution completed."
}

main "$1"
