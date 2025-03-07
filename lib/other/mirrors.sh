#!/bin/bash

update_mirrors() {
    log_info "Updating mirrorlist..."
    reflector --verbose --country India,China,Japan,Singapore,US --protocol https --sort rate --latest 20 --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist || {
        log_error "Failed to update mirrorlist"
        return 1
    }
    log_success "Mirrorlist updated successfully."
}

# --- Mirrorlist management ---
update_pacman_mirrorlist() {
    log_info "Updating Pacman mirrorlist..."
    if ! command_exists reflector; then
        log_error "reflector is not installed. Please install it."
        return 1
    fi

    sudo reflector --verbose -c India -c China -c Japan -c Singapore -c US --protocol https --sort rate --latest 20 \
        --download-timeout 45 --threads 5 --save /etc/pacman.d/mirrorlist || {
        log_error "Failed to update the mirrorlist."
        return 1
    }

    sudo systemctl enable reflector.timer || {
        log_error "Failed to enable reflector.timer"
        return 1
    }

    log_success "Pacman mirrorlist updated successfully."
}
