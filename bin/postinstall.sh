#!/bin/bash

###############################################################################
# Script Name: postinstall.sh
# Description: Automates the initial configuration of a freshly installed Arch
#              Linux system as per the author's preferences.
# Author: Shashoto Nur

# Version: 1.1
# License: MIT
###############################################################################

postinstall() {
    # Load configuration
    config_values=$(read_config "install.conf")
    eval "$config_values"

    # Handle LUKS and Root passwords
    if [[ -v config_values["Password"] ]]; then
        PASSWORD=${config_values["Password"]}
        config_values["LUKS Password"]=$PASSWORD
        config_values["Root Password"]=$PASSWORD
    fi

    # Mount USB
    readarray -t mount_info < <(mount_usb_drive)
    usb_device="${mount_info[0]}"
    multiboot_mount="${mount_info[1]}"
    storage_mount="${mount_info[2]}"
    log_debug "USB_DEVICE=$usb_device, MULTIBOOT_MOUNT=$multiboot_mount, STORAGE_MOUNT=$storage_mount"

    # Setup Internet
    setup_internet_connection || exit 1

    # System operations
    update_keymap || exit 1
    remove_cryptkey_and_delete_slot || exit 1
    setup_system_clock || exit 1
    update_pacman_mirrorlist || exit 1
    update_system_keyring || exit 1
    set_user_password "$config_values["Username"]" "$config_values["Root Password"]" || exit 1

    # Essential packages and configs
    install_essential_packages || exit 1
    create_user_directories || exit 1
    copy_backup_files "$usb_device" "$multiboot_mount" "$storage_mount" || exit 1

    # Bootloader, Network and app managment
    configure_bootloader_theme || exit 1
    configure_network || exit 1
    setup_flatpak || exit 1
    enable_chaotic_aur || exit 1

    # Apps
    install_pacman_applications || exit 1
    install_yay_applications || exit 1
    install_flatpak_applications || exit 1

    # Hyprland
    setup_hyprland || exit 1
    initialize_browser || exit 1
    restore_file_manager_config || exit 1
    restore_zsh_config || exit 1

    # System config
    setup_zram || exit 1
    configure_hdd_performance || exit 1
    update_firmware || exit 1
    set_numlock || exit 1
    setup_paccache || exit 1
    enable_system_commands || exit 1
    setup_network_time_protocol || exit 1
    setup_hdmi_sharing || exit 1
    limit_journal_size || exit 1
    disable_core_dump || exit 1
    prevent_overheating || exit 1
    optimize_network_congestion || exit 1
    setup_firewall || exit 1
    setup_bluetooth || exit 1
    setup_graphics_driver || exit 1
    setup_oomd || exit 1
    setup_avro_keyboard || exit 1
    setup_brightness_service || exit 1
    download_iptv_playlist || exit 1
    install_vscode_extensions || exit 1
    update_zen_browser_config || exit 1
    terminal_apps_setup || exit 1
    setup_gemini_console "$config_values["Gemini API Key"]" || exit 1
    configure_tmux || exit 1
    configure_syncthing "${config_values["Username"]}" || exit 1
    install_gaming_packages || exit 1
    setup_bottles || exit 1
    configure_git_ssh "$config_values["Full Name"]" "$config_values["Email"]" || exit 1
    configure_gpg || exit 1
    clone_github_repos "$config_values["Github Token"]" || exit 1
    setup_music_playlist "$config_values["Music Playlist Link"]" || exit 1
    download_wikipedia_archive || exit 1
    configure_timeshift || exit 1
    setup_onefilelinux || exit 1
    setup_apparmor_audit || exit 1
    setup_neovim || exit 1
    link_git_directories || exit 1
    setup_qbittorrent_theme || exit 1
    download_torrents || exit 1
    set_sddm_background || exit 1
    setup_mega_cmd "$config_values["Mega Key"]" "$config_values["Email"]" "$config_values["Mega Password"]" || exit 1
    setup_mega_sync || exit 1
    setup_zsh || exit 1
    restore_user_backups || exit 1

    #QEMU setup
    setup_nixos_qemu_kvm || exit 1

    #Unmount and wipe USB
    unmount_usb_partitions "$usb_device" || exit 1
    wipe_usb_drive "$usb_device" || exit 1

    # System info
    log_system_info || exit 1

    echo "Post installation completed successfully."
}
