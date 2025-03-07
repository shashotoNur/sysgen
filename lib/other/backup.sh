#!/bin/bash

# --- GitHub Repository Cloning ---
clone_github_repos() {
    log_info "Importing Github repositories..."
    git clone --depth 1 git@github.com:shashotoNur/clone-repos.git ~/Workspace

    log_info "Logging in to GitHub CLI..."
    echo "${CONFIG_VALUES["Github Token"]}" | gh auth login --with-token

    mv ~/Workspace/clone-repos/clone.sh ~/Workspace/
    bash ~/Workspace/clone.sh

    rm -rf ~/Workspace/clone-repos ~/Workspace/clone.sh
    log_success "GitHub repositories cloned successfully."
}

# --- Music Playlist Setup ---
setup_music_playlist() {
    log_info "Fetching music playlist..."
    local MUSICDIR="~/Music/Sound Of My Life"

    mkdir -p "$MUSICDIR"
    cd "$MUSICDIR"
    pip install yt-dlp

    yt-dlp -x --audio-format mp3 --download-archive archive.txt --embed-thumbnail --embed-metadata "${CONFIG_VALUES["Music Playlist Link"]}" || {
        log_error "Failed to download music playlist."
        return 1
    }
    detox -r .
    log_success "Music playlist downloaded."
}

# --- Wikipedia Archive Download ---
download_wikipedia_archive() {
    log_info "Fetching Wikipedia archive..."
    local BASE_URL="https://dumps.wikimedia.org/other/kiwix/zim/wikipedia/"
    local LATEST_FILE

    LATEST_FILE=$(curl -s "$BASE_URL" | grep -oP "wikipedia_en_all_maxi_\d{4}-\d{2}.zim" | sort -t'_' -k4,4 -r | head -n 1) || {
        log_error "Failed to fetch latest Wikipedia ZIM filename."
        return 1
    }
    wget -c "$BASE_URL/$LATEST_FILE" || {
        log_error "Failed to download Wikipedia archive."
        return 1
    }
    log_success "Wikipedia archive downloaded."
}

# --- Timeshift Backup Configuration ---
configure_timeshift() {
    log_info "Configuring Timeshift..."
    sudo cp ~/Backups/timeshift/timeshift.json /etc/timeshift/timeshift.json
    sudo systemctl enable --now cronie.service
    sudo /etc/grub.d/41_snapshots-btrfs
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    sudo systemctl enable --now grub-btrfsd
    sudo sed -i 's|ExecStart=.*|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' /etc/systemd/system/grub-btrfsd.service || {
        log_error "Failed to edit grub-btrfsd service."
        return 1
    }

    log_success "Timeshift configured successfully."
}

# --- OneFileLinux Setup ---
setup_onefilelinux() {
    log_info "Setting up OneFileLinux..."
    wget -O ~/Backups/ISOs/OneFileLinux.efi "https://github.com/zhovner/OneFileLinux/releases/latest/download/OneFileLinux.efi" || {
        log_error "Failed to download OneFileLinux.efi."
        return 1
    }
    sudo cp ~/Backups/ISOs/OneFileLinux.efi /boot/efi/EFI/BOOT/

    echo 'menuentry "One File Linux" {
  search --file --no-floppy --set=root /EFI/Boot/OneFileLinux.efi
  chainloader /EFI/Boot/OneFileLinux.efi
}' | sudo tee -a /etc/grub.d/40_custom

    sudo grub-mkconfig -o /boot/grub/grub.cfg
    log_success "OneFileLinux setup completed."
}

# --- Mega CMD Setup ---
setup_mega_cmd() {
    log_info "Setting up MegaCMD..."
    yay -S megacmd-bin ffmpeg-compat-59 --needed --noconfirm

    mega_login
    log_success "MegaCMD setup completed."
}

# Function to generate totp code
generate_totp_code() {
    log_info "Generating TOTP code..."
    local time_step=30
    local current_time
    local totp_code
    while true; do
        current_time=$(date +%s)
        local expiring_in=$((time_step - (current_time % time_step)))

        if [[ $expiring_in -ge 15 ]]; then
            totp_code=$(oathtool -b --totp "${CONFIG_VALUES["MEGA KEY"]}" -c $((current_time / time_step)) 2>&1) || {
                log_error "Failed to generate TOTP code."
                return 1
            }
            break
        else
            log_debug "Sleeping for $expiring_in seconds"
            sleep "$expiring_in"
        fi
    done
    log_debug "Generated TOTP code: $totp_code"
    echo "$totp_code"
}

# Function to log in to mega
mega_login() {
    local totp_code
    totp_code=$(generate_totp_code)
    log_info "Logging in to Mega..."
    mega-login "${CONFIG_VALUES["Email"]}" "${CONFIG_VALUES["Mega Password"]}" --auth-code="$totp_code" || {
        log_error "Failed to log in to Mega."
        return 1
    }

    local user
    user=$(mega-whoami | grep "Account e-mail:" | awk '{print $3}')

    if [[ "$user" == "${CONFIG_VALUES["Email"]}" ]]; then
        log_success "Login to mega.nz has been successful!"
        return 0
    else
        log_error "Login to mega.nz failed..."
        return 1
    fi
}

# --- Mega Sync Setup ---
setup_mega_sync() {
    log_info "Setting up Mega synchronization..."
    echo 'while IFS= read -r line; do
        mega-sync ~/"$line" "/$line"
    done <~/Documents/sync_directories.lst' >~/.config/hypr/megacmd-launch.sh || {
        log_error "Failed to create megacmd launch script."
        return 1
    }

    cp ~/Backups/sync_directories.lst ~/Documents/

    local last_exec_once
    last_exec_once=$(grep -n '^exec-once' ~/.config/hypr/hyprland.conf | tail -n 1 | cut -d ':' -f 1)
    sed -i "${last_exec_once}a exec-once = ~/.config/hypr/megacmd-launch.sh # start megacmd sync" ~/.config/hypr/hyprland.conf
    log_success "Mega synchronization setup completed."

    while IFS= read -r line; do
        mkdir -p ~/"$line"
        mega-sync ~/"$line" "/$line"
    done <~/Documents/sync_directories.lst
}

# --- Restore User Backups ---
restore_user_backups() {
    log_info "Restoring user backups..."
    local backup_base="~/Backups/data/home/"

    find "$backup_base" -maxdepth 1 -type d ! -name "." -print0 | while IFS= read -r -d $'\0' user_dir; do
        local user_name=$(basename "$user_dir")
        log_info "Restoring backup for user: $user_name"
        cp -r "$user_dir"/* ~/
    done
    log_success "Backup restoration for all users completed!"
}

backup_user_data() {
    local user="$1"
    local data_dir="./backup/data"
    local selected_file="./fzf_selected"
    local size_file="./fzf_total"
    log_info "Starting data backup process..."

    mkdir -p "$data_dir"
    >"$selected_file"
    >"$size_file"

    log_info "Prompting for files and directories to backup..."
    SELECTED_ITEMS=$(
        find /home/"$user" -mindepth 1 -maxdepth 5 | fzf --multi --preview 'du -sh {}' \
            --bind "tab:execute-silent(
            grep -Fxq {} "$selected_file" && sed -i '\|^{}$|d' "$selected_file" || echo {} >> "$selected_file";
            xargs -d '\n' du -ch 2>/dev/null < "$selected_file" | grep total$ | sed 's/total\s*/<-Total size /' > "$size_file"
        )+toggle" \
            --preview 'cat ./fzf_total'
    )

    rm "$selected_file" "$size_file"

    if [[ -z "$SELECTED_ITEMS" ]]; then
        log_info "No files or directories selected for backup."
    else
        log_info "Copying selected files to backup directory..."
        mkdir -p "$data_dir"
        cp -r --parents $(printf '%s\n' "${SELECTED_ITEMS[@]}") "$data_dir"

        log_info "Total size of selected items: \"$(du -sh $data_dir)\""
        log_success "Backup complete!"
    fi
}

get_mega_sync_directories() {
    local user="$1"
    log_info "Prompting for MEGA sync directories (if any)..."
    read -rp "Do you want to select directories to backup your MEGA sync data? (y/n): " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        log_info "Select the directories you want to sync on MEGA."
        find /home/"$user" -type d -print0 | fzf --read0 --print0 --multi >sync_dirs.lst
        log_success "MEGA sync directories selected."
    else
        log_info "MEGA sync backup selection skipped."
    fi
}
