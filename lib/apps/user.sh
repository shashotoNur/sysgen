#!/bin/bash

# Function to create user directories
create_user_directories() {
    log_info "Creating user directories."
    local directories=(
        ~/Workspace
        ~/Backups
        ~/Backups/ISOs
        ~/Archives
        ~/Scratch
        ~/Scripts
        ~/Games
        ~/Designs
        ~/Logs
    )

    for dir in "${directories[@]}"; do
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    done

    xdg-user-dirs-update || {
        log_error "Failed to update primary user directories."
        return 1
    }

    log_success "User directories created successfully."
}

# --- Zsh Setup ---
setup_zsh() {
    log_info "Setting up Zsh..."

    sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
        log_error "Failed to install Oh My Zsh."
        return 1
    }

    log_info "Installing Zsh plugins..."
    local ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}

    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    sudo git clone --depth 1 https://github.com/agkozak/zsh-z "$ZSH_CUSTOM/plugins/zsh-z"
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
    sudo git clone --depth 1 https://github.com/MichaelAquilina/zsh-you-should-use.git "$ZSH_CUSTOM/plugins/you-should-use"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
    zsh <(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)
    sudo git clone https://github.com/MichaelAquilina/zsh-auto-notify.git "$ZSH_CUSTOM/plugins/auto-notify"

    if [[ -d ~/.config/fastfetch/pngs ]]; then
        find ~/.config/fastfetch/pngs -type f ! -name "arch.png" -delete || {
            log_warning "Could not find fastfetch to delete its files"
        }
    fi

    log_success "Zsh setup completed."
}

# --- Browser initialization ---
initialize_browser() {
    log_info "Initializing browser..."
    sed -i 's/browser=firefox/browser=app.zen_browser.zen/' ~/.config/hypr/keybindings.conf || {
        log_error "Could not replace firefox with zen in keybindings."
        return 1
    }
    log_success "Browser initialized"
}

# --- Restore file manager config ---
restore_file_manager_config() {
    log_info "Restoring file manager config..."
    cp ~/Backups/dolphin/dolphinrc ~/.config/dolphinrc
    cp ~/Backups/dolphin/dolphinui.rc ~/.local/share/kxmlgui5/dolphin/dolphinui.rc
    log_success "File manager config restored"
}

# --- Restore zsh config ---
restore_zsh_config() {
    log_info "Restoring zsh config..."
    cp ~/Backups/zsh/.zshrc ~/.zshrc
    log_success "zsh config restored"
}

# --- Avro Keyboard Setup ---
setup_avro_keyboard() {
    log_info "Installing and configuring Avro keyboard..."
    yay -S --noconfirm ibus-avro-git

    ibus-daemon -rxRd || {
        log_error "Failed to start ibus-daemon."
        return 1
    }

    echo -e "GTK_IM_MODULE=ibus\nQT_IM_MODULE=ibus\nXMODIFIERS=@im=ibus" | sudo tee -a /etc/environment

    echo '#!/bin/bash
[ "$(ibus engine)" = "xkb:us::eng" ] && ibus engine ibus-avro || ibus engine xkb:us::eng' >~/.config/hypr/toggle_ibus.sh
    chmod +x ~/.config/hypr/toggle_ibus.sh

    echo 'bind=SUPER,SPACE,exec,~/.config/hypr/toggle_ibus.sh' >>~/.config/hypr/hyprland.conf

    # Insert ibus command after the last line starting with "exec-once"
    last_exec_once=$(grep -n '^exec-once' ~/.config/hypr/hyprland.conf | tail -n 1 | cut -d ':' -f 1)
    sed -i "${last_exec_once}a exec-once = ibus-daemon -rxRd # start ibus demon" ~/.config/hypr/hyprland.conf || {
        log_error "Failed to add start to hyprland config."
        return 1
    }

    log_success "Avro keyboard installed and configured."
}

# --- IPTV Playlist Download ---
download_iptv_playlist() {
    log_info "Downloading IPTV playlist..."
    wget -O ~/Scratch/iptv_playlist.m3u https://iptv-org.github.io/iptv/index.m3u
}

# --- VS Code Extensions ---
install_vscode_extensions() {
    log_info "Installing VS Code extensions..."
    local EXTLIST_FILE=~/Backups/code/ext.lst
    if [[ -f "$EXTLIST_FILE" ]]; then
        while IFS= read -r extension; do
            code --install-extension "$extension" || log_error "Error installing $extension"
        done <"$EXTLIST_FILE"
        log_success "VS Code extensions installed."
    else
        log_warning "$EXTLIST_FILE not found, skipping..."
    fi
}

# --- Zen Browser Configuration ---
update_zen_browser_config() {
    log_info "Updating Zen browser config..."
    local configs=(
        "user_pref(\"browser.preferences.defaultPerformanceSettings.enabled\", false);"
        "user_pref(\"browser.cache.disk.enable\", false);"
        "user_pref(\"browser.cache.memory.enable\", true);"
        "user_pref(\"browser.sessionstore.resume_from_crash\", false);"
        "user_pref(\"extensions.pocket.enabled\", false);"
        "user_pref(\"layout.css.dpi\", 0);"
        "user_pref(\"general.smoothScroll.msdPhysics.enabled\", true);"
        "user_pref(\"media.hardware-video-decoding.force-enabled\", true);"
        "user_pref(\"middlemouse.paste\", true);"
        "user_pref(\"webgl.msaa-force\", true);"
        "user_pref(\"security.sandbox.content.read_path_whitelist\", \"/sys/\");"
        "user_pref(\"browser.download.alwaysOpenPanel\", false);"
        "user_pref(\"network.ssl_tokens_cache_capacity\", 32768);"
        "user_pref(\"media.ffmpeg.vaapi.enabled\", true);"
        "user_pref(\"accessibility.force_disabled\", 1);"
        "user_pref(\"browser.eme.ui.enabled\", false);"
    )

    local profile_dir_name=$(cat ~/.var/app/app.zen_browser.zen/.zen/installs.ini | grep "Default=" | cut -d '=' -f 2)
    local prefs_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "prefs.js" -path "*/$profile_dir_name/*")
    local search_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "search.json.mozlz4" -path "*/$profile_dir_name/*")
    local theme_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "zen-themes.css" -path "*/$profile_dir_name/*")

    for config in "${configs[@]}"; do
        local prefix=$(echo "$config" | cut -d ',' -f 1)

        if grep -q "$prefix" "$prefs_file"; then
            sed -i "/$prefix/c\\$config" "$prefs_file"
            log_debug "Replaced: $config"
        else
            echo "$config" >>"$prefs_file"
            log_debug "Added: $prefix"
        fi
    done

    mv ~/Backups/zen/search.json.mozlz4 "$search_file" || {
        log_warning "Could not restore zen search."
    }

    wget -c -P "$HOME/Scratch/ublock-ytshorts.txt" https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt || {
        log_warning "Could not add to zen search."
    }

    echo "Adding code to zen-themes.css..."
    echo "a[href$=\".pdf\"]:after {
  font-size: smaller;
  content: \" [pdf] \";
}" >>"$theme_file" || {
        log_error "Failed to append to zen-themes.css"
        return 1
    }

    log_success "Zen configurations have been updated!"
}

backup_configurations() {
    local user=$1
    log_info "Backing up configurations..."
    mkdir -p ./backup/code
    sudo -u "$user" code --list-extensions >./backup/code/ext.lst
    sudo cp "/home/$user/.config/Code - OSS/User/settings.json" ./backup/code/
    log_info "VS Code configurations backed up."

    mkdir -p ./backup/dolphin
    cp /home/$user/.local/share/kxmlgui5/dolphin/dolphinui.rc ./backup/dolphin
    cp /home/$user/.config/dolphinrc ./backup/dolphin/
    log_info "Dolphin configurations backed up."

    mkdir -p ./backup/zsh/
    cp /home/$user/.zshrc ./backup/zsh/
    log_info "Zsh configurations backed up."

    mkdir -p ./backup/timeshift
    cp /etc/timeshift/timeshift.json ./backup/timeshift/
    log_info "Timeshift configurations backed up."

    mkdir -p ./backup/sysgen
    cp -r ./*.sh ./*.conf ./*.lst ./utils/ ./backup/sysgen/
    log_info "Sysgen scripts and configurations backed up."

    log_success "All configurations backed up."
}
