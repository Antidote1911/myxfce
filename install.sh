#!/bin/bash

# ==========================================
# CONFIGURATION GLOBALE & LOGGING
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="install_log_$(date +%F_%H-%M).txt"

set -euo pipefail

# Variables Globales
USERNAME="${SUDO_USER:-$(logname)}"
NAS_IP="192.168.1.65"
VM_SETTING="0"
BROWSER="none"

# ==========================================
# BOOTSTRAP
# ==========================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "[ERREUR] Ce script doit être lancé avec sudo." >&2
        exit 1
    fi
}

ensure_dialog() {
    if ! command -v dialog &>/dev/null; then
        echo "Installation de dialog..."
        pacman -S --noconfirm dialog
    fi
}

# ==========================================
# HELPERS UI
# ==========================================

TITLE="  Installation myxfce  "

ui_info() {
    dialog --title "$TITLE" --infobox "\n$1" 6 58
    sleep 1
}

ui_msg() {
    dialog --title "$TITLE" --msgbox "\n$1" 8 58
}

ui_error() {
    dialog --title " Erreur " --msgbox "\n$1" 8 58
}

log() {
    echo "[INFO] $1"
}

trap 'ui_error "Erreur ligne $LINENO — installation interrompue."; exit 1' ERR

# ==========================================
# FONCTIONS D'ÉTAPE
# ==========================================

# Étape 0 : Choix du mode
ask_install_mode() {
    VM_SETTING=$(dialog --title "$TITLE" \
        --menu "\nChoisissez le mode d'installation :" 12 58 2 \
        "0" "Installation normale (minimale)" \
        "1" "Installation complète (Desktop Antidote)" \
        3>&1 1>&2 2>&3) || { ui_error "Installation annulée."; exit 1; }
}

# Étape 0b : Choix du navigateur
choose_browser() {
    BROWSER=$(dialog --title "$TITLE" \
        --menu "\nChoisissez votre navigateur internet :" 14 58 5 \
        "firefox"    "Firefox" \
        "chromium"   "Chromium (Google sans compte)" \
        "vivaldi"    "Vivaldi" \
        "librewolf"  "LibreWolf (Firefox renforcé vie privée)" \
        "none"       "Aucun navigateur" \
        3>&1 1>&2 2>&3) || { ui_error "Installation annulée."; exit 1; }
}

# Étape 1 : Configuration Système
configure_system_files() {
    ui_info "Déploiement des configurations système..."
    log "Copie des fichiers système..."

    rsync -a --chown=root:root etc/ /etc/
    rsync -a --chown=root:root usr/ /usr/
    rsync -a --chown=root:root config_root/ /root/.config
    rm -f /etc/sudoers.d/10-installer

    log "Suppression du thème GRUB EndeavourOS..."
    sed -i '/^GRUB_THEME=/d' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
}

# Étape 2 : Paquets de base
install_base_packages() {
    ui_info "Installation des paquets de base..."
    mapfile -t PKGS < <(grep -v '^[[:space:]]*$' packages-base.txt)
    pacman -Sy
    pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout "${PKGS[@]}"
}

# Étape 3 : Navigateur
install_browser() {
    if [[ "$BROWSER" == "none" ]]; then
        log "Aucun navigateur sélectionné, étape ignorée."
        return 0
    fi

    # EndeavourOS no-desktop installe firefox par défaut — le supprimer si un autre est choisi
    if [[ "$BROWSER" != "firefox" ]] && pacman -Qi firefox &>/dev/null; then
        ui_info "Suppression de Firefox (installé par EndeavourOS)..."
        pacman -Qi firefox-i18n-fr &>/dev/null && pacman -R --noconfirm firefox-i18n-fr
        pacman -Rns --noconfirm firefox
    fi

    if [[ "$BROWSER" == "firefox" ]] && pacman -Qi firefox &>/dev/null; then
        log "Firefox déjà installé, étape ignorée."
        return 0
    fi

    ui_info "Installation du navigateur : $BROWSER..."
    if [[ "$BROWSER" == "vivaldi" ]]; then
        pacman -S --noconfirm --noprogressbar --needed vivaldi vivaldi-ffmpeg-codecs
    else
        pacman -S --noconfirm --noprogressbar --needed "$BROWSER"
    fi
}

# Étape 4 : Installation Complète (Optionnelle)
install_full_suite() {
    if [[ "$VM_SETTING" != "1" ]]; then
        ui_info "Mode minimal sélectionné. Étape complète ignorée."
        return 0
    fi

    PASSWORD=$(dialog --title "$TITLE" \
        --passwordbox "\nMot de passe pour l'archive personnelle :" 9 58 \
        3>&1 1>&2 2>&3) || { ui_error "Installation annulée."; exit 1; }

    ui_info "Installation des paquets supplémentaires..."
    mapfile -t PKGS_EXTRA < <(grep -v '^[[:space:]]*$' packages-extra.txt)
    pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout "${PKGS_EXTRA[@]}"

    ui_info "Installation de la toolchain Rust..."
    sudo -u "${USERNAME}" rustup toolchain install stable

    log "Configuration NFS / Fstab..."
    mkdir -p /mnt/medias
    cat >> /etc/fstab <<-EOL

	## Synology DS918
	${NAS_IP}:/mnt/user/medias /mnt/medias nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
	EOL

    if command -v cryptyrust &>/dev/null; then
        ui_info "Déchiffrement de l'archive personnelle..."
        cryptyrust --decrypt myEncryptedFile -p "${PASSWORD}" -o tmp.tar.gz
        tar -xf tmp.tar.gz -C "/home/${USERNAME}/"
        rm tmp.tar.gz
        chmod +x "/home/${USERNAME}/gitconfig.sh"
        sudo -u "${USERNAME}" "/home/${USERNAME}/gitconfig.sh"
    else
        ui_msg "cryptyrust non trouvé — étape de déchiffrement ignorée."
    fi
}

# Étape 5 : Configuration Utilisateur
configure_user_environment() {
    ui_info "Déploiement des configurations utilisateur..."

    rsync -a --chown="${USERNAME}:${USERNAME}" .config "/home/${USERNAME}/"
    rsync -a --chown="${USERNAME}:${USERNAME}" home_config/ "/home/${USERNAME}/"

    mkdir -p /usr/share/oh-my-zsh/themes/
    cp -r /usr/share/zsh-theme-powerlevel10k /usr/share/oh-my-zsh/themes/powerlevel10k

    sed -i 's|background=/usr/share/endeavouros/backgrounds/endeavouros-wallpaper.png|background=/usr/share/backgrounds/packarch/default.jpg|g' /etc/lightdm/slick-greeter.conf
    sed -i 's|Exec=geany %F|Exec=geany -i %F|g' /usr/share/applications/geany.desktop

    sed -i "s|antidote|${USERNAME}|g" "/home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml"
    sed -i "s|antidote|${USERNAME}|g" "/home/${USERNAME}/.config/gtk-3.0/bookmarks"

    sudo -u "${USERNAME}" env DISPLAY="${DISPLAY:-}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
        xfce4-set-wallpaper /usr/share/backgrounds/packarch/default.jpg || true

    systemctl enable lightdm.service

    chsh -s "$(which zsh)" root
    chsh -s "$(which zsh)" "${USERNAME}"

    log "Activation du TRIM hebdomadaire pour SSD..."
    systemctl enable --now fstrim.timer
}

# Étape 6 : Nettoyage des menus
hide_useless_apps() {
    ui_info "Nettoyage des entrées de menu..."
    local apps_dir="/usr/share/applications"
    local apps_to_hide=(
        "avahi-discover.desktop" "bssh.desktop" "bvnc.desktop" "xfce4-about.desktop"
        "org.pulseaudio.pavucontrol.desktop" "java-java-openjdk.desktop" "xfce4-mail-reader.desktop"
        "hdajackretask.desktop" "hdspconf.desktop" "hdspmixer.desktop" "jconsole-java-openjdk.desktop"
        "jshell-java-openjdk.desktop" "libfm-pref-apps.desktop" "eos-quickstart.desktop" "lstopo.desktop"
        "uxterm.desktop" "nm-connection-editor.desktop" "xterm.desktop" "qvidcap.desktop"
        "stoken-gui.desktop" "stoken-gui-small.desktop" "assistant.desktop" "qv4l2.desktop"
        "qdbusviewer.desktop" "mpv.desktop" "yad-settings.desktop"
    )

    for app in "${apps_to_hide[@]}"; do
        if [[ -f "$apps_dir/$app" ]]; then
            if ! grep -q "NoDisplay=true" "$apps_dir/$app"; then
                echo "NoDisplay=true" >> "$apps_dir/$app"
            fi
        fi
    done
}

# Étape 7 : Finalisation
finalize_installation() {
    if [ "$(systemd-detect-virt)" != "none" ]; then
        ui_msg "Machine virtuelle détectée."
    fi

    log "Sauvegarde du log..."
    cp "$LOGFILE" "/home/${USERNAME}/$LOGFILE"
    chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/$LOGFILE"

    log "Suppression du dossier repo..."
    rm -rf "$SCRIPT_DIR"

    dialog --title "$TITLE" \
        --yesno "\nInstallation terminée !\n\nVoulez-vous redémarrer maintenant ?" 9 48 \
        3>&1 1>&2 2>&3 && reboot || true
}

# ==========================================
# MAIN
# ==========================================

main() {
    check_root
    ensure_dialog
    cd "$SCRIPT_DIR"

    # Choix interactifs avant de démarrer le log
    ask_install_mode
    choose_browser

    # Démarrage du log
    exec > >(tee -i "$LOGFILE") 2>&1

    configure_system_files
    install_base_packages
    install_browser
    install_full_suite
    configure_user_environment
    hide_useless_apps
    finalize_installation
}

main
