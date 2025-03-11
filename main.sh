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

# --- Source files ---
while IFS= read -r -d '' script; do
    source "$script"
done < <(find bin/ lib/ -type f -name "*.sh" -print0)

# --- Global Variables ---
CONFIG_FILE="install.conf"
SCRIPT_DIR="$(dirname "$0")" # Get the directory of the script

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

    log_info "Attempting to execute phase: $phase"

    # Check if the function exists
    if declare -F "$phase" >/dev/null; then
        log_info "Function '$phase' exists, executing..."
        "$phase" "$user"

        local result=$?
        if [[ "$result" -eq 0 ]]; then
            log_success "Phase '$phase' completed successfully."
        else
            log_error "Phase '$phase' failed with an error (exit code $result)."
            return "$result"
        fi
    else
        log_error "Function '$phase' not found."
        return 1
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
