#!/bin/bash

# --- Terminal Apps Setup ---
terminal_apps_setup() {
    log_info "Configuring terminal apps..."

    # Preload
    yay -S --noconfirm preload
    sudo systemctl enable --now preload

    # Jrnl
    mkdir -p ~/.config/jrnl
    echo -e "colors:\n  body: none\n  date: black\n  tags: yellow\n  title: cyan\ndefault_hour: 9\ndefault_minute: 0\neditor: 'nvim'\nencrypt: false\nhighlight: true\nindent_character: '|'\njournals:\n  default:\n    journal: /home/${CONFIG_VALUES["Username"]}/Documents/data/journal.txt\nlinewrap: 79\ntagsymbols: '#@'\ntemplate: false\ntimeformat: '%F %r'\nversion: v4.2" >~/.config/jrnl/jrnl.yaml || {
        log_error "Failed to create jrnl config file."
        return 1
    }

    # File manager
    bash -c "$(curl -sLo- https://superfile.netlify.app/install.sh)"

    # Gnome keyring
    sudo sed -i '/^auth /i auth       optional     pam_gnome_keyring.so' /etc/pam.d/login || {
        log_error "Failed to add auth rule for pam_gnome_keyring."
        return 1
    }
    sudo sed -i '/^session /i session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/login || {
        log_error "Failed to add session rule for pam_gnome_keyring."
        return 1
    }

    # Pip
    sudo pacman -S --needed --noconfirm python-pip
    local PY_VER=$(python --version 2>&1 | awk '{print $2}' | cut -d '.' -f 1,2)
    sudo mv /usr/lib/python$PY_VER/EXTERNALLY-MANAGED /usr/lib/python$PY_VER/EXTERNALLY-MANAGED.old || {
        log_error "Failed to disable global package install restriction."
        return 1
    }

    # Makedown
    pip install makedown

    # Diff so fancy
    npm i -g diff-so-fancy
    git config --global core.pager "diff-so-fancy | less --tabs=4 -RFX"
    git config --global interactive.diffFilter "diff-so-fancy --patch"
    git config --global color.ui true

    log_success "Terminal apps configured."
}

# --- Gemini Console Setup ---
setup_gemini_console() {
    log_info "Setting up Gemini console..."

    git clone --depth 1 https://github.com/flameface/gemini-console-chat.git ~/Scripts/
    cd ~/Scripts/gemini-console-chat
    npm install

    sed -i "s/YOUR_API_KEY/${CONFIG_VALUES["Gemini API Key"]}/" index.js || {
        log_error "Failed to set Gemini API key in index.js."
        return 1
    }
    log_success "Gemini console setup completed."
}

# --- TMUX Setup ---
configure_tmux() {
    log_info "Configuring TMUX..."
    mkdir -p ~/.tmux/plugins
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

    echo -e "unbind r\nbind r source-file ~/.tmux.conf\n\nset -g default-terminal \"tmux-256color\"\nset -ag terminal-overrides \",xterm-256color:RGB\"\n\nset -g prefix C-s\n\nset -g mouse on\n\nset-window-option -g mode-keys vi\n\nbind-key h select-pane -L\nbind-key j select-pane -D\nbind-key k select-pane -U\nbind-key l select-pane -R\n\nset-option -g status-position top\n\nset -g @catppuccin_window_status_style \"rounded\"\n\nset -g @plugin 'tmux-plugins/tpm'\nset -g @plugin 'christoomey/vim-tmux-navigator'\nset -g @plugin 'catppuccin/tmux#v2.1.0'\n\nset -g status-left \"\"\nset -g status-right \"\#{E:@catppuccin_status_application} \#{E:@catppuccin_status_session}\"\n\nrun '~/.tmux/plugins/tpm/tpm'\n\nset -g status-style bg=default" >~/.tmux.conf || {
        log_error "Failed to create ~/.tmux.conf file."
        return 1
    }

    log_success "TMUX configuration complete."
}

# --- Syncthing Configuration ---
configure_syncthing() {
    log_info "Configuring Syncthing..."
    sudo tee /etc/systemd/system/syncthing@${CONFIG_VALUES["Username"]}.service >/dev/null <<EOF
[Unit]
Description=Syncthing - Open Source Continuous File Synchronization for %I
Documentation=man:syncthing(1)
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=4

[Service]
User=%i
ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --logflags=0
Restart=on-failure
RestartSec=1
SuccessExitStatus=3 4
RestartForceExitStatus=3 4

ProtectSystem=full
PrivateTmp=true
SystemCallArchitectures=native
MemoryDenyWriteExecute=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable --now syncthing@${CONFIG_VALUES["Username"]}.service || {
        log_error "Failed to enable syncthing service."
        return 1
    }
    log_success "Syncthing configured."
}

# --- Hyprland Setup ---
setup_hyprland() {
    log_info "Setting up Hyprland..."
    git clone --depth 1 https://github.com/prasanthrangan/hyprdots ~/HyDE
    bash ~/HyDE/Scripts/install.sh || {
        log_error "Failed to install Hyprland config from HyDE."
        return 1
    }
    log_success "Hyprland setup completed."
}

# --- Bluetooth Setup ---
setup_bluetooth() {
    log_info "Installing and enabling Bluetooth services..."
    sudo pacman -S --needed --noconfirm bluez bluez-utils blueman

    sudo modprobe btusb
    sudo systemctl enable --now bluetooth
    log_success "Bluetooth services installed and enabled."
}

# --- Git Credentials and SSH Setup ---
configure_git_ssh() {
    log_info "Configuring Git..."
    git config --global user.name "${CONFIG_VALUES["Full Name"]}"
    git config --global user.email "${CONFIG_VALUES["Email"]}"
    git config --global core.editor "nvim"
    log_success "Git configured."

    log_info "Generating SSH key..."
    ssh-keygen -t ed25519 -C "${CONFIG_VALUES["Email"]}" -N "" -f ~/.ssh/id_ed25519 || {
        log_error "Failed to generate SSH key."
        return 1
    }
    log_success "SSH key generated."

    log_info "Starting SSH agent and adding SSH key..."
    eval $(ssh-agent -s)
    ssh-add ~/.ssh/id_ed25519
    log_success "SSH agent started and key added."
}

# --- GPG Signing Setup ---
configure_gpg() {
    log_info "Configuring GPG for commit signing..."
    gpg --import ~/Backups/data/public-key.asc || {
        log_warning "Could not import public-key.asc"
    }
    gpg --import ~/Backups/data/private-key.asc || {
        log_warning "Could not import private-key.asc"
    }

    local SIGNING_KEY
    SIGNING_KEY=$(gpg --list-secret-keys --keyid-format=long | grep "commit" -B 2 | awk '/sec/{split($2, a, "/"); print a[2]}') || {
        log_error "Failed to retrieve GPG signing key."
        return 1
    }
    git config --global user.signingkey "$SIGNING_KEY"
    log_success "GPG configured for commit signing."
}

# --- Neovim setup ---
setup_neovim() {
    log_info "Setting up Neovim..."
    git clone --depth 1 git@github.com:shashoto/nvim-config.git
    cp -r nvim-config ~/.config/nvim
    rm -rf ~/.config/nvim/.git
    log_success "Neovim setup complete"
}

# --- Git Directory Linking ---
link_git_directories() {
    log_info "Adding $(.git) files to cloud synced directories"
    echo 'gitdir: ~/Workspace/Repositories/data/.git' | sudo tee ~/Documents/data/.git
    echo 'gitdir: ~/Workspace/Repositories/college-resources/.git' | sudo tee ~/Documents/college-resources/.git
    log_success "Linked git directories"
}
