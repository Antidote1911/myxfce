#!/bin/bash

# ==========================================
# CONFIGURATION GLOBALE & LOGGING
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="install_log_$(date +%F_%H-%M).txt"
exec > >(tee -i "$LOGFILE") 2>&1

# Arrêter le script à la moindre erreur, variables non définies, et erreurs dans les pipes
set -euo pipefail

# Couleurs
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# Variables Globales
USERNAME="${SUDO_USER:-$(logname)}"
NAS_IP="192.168.1.65"
VM_SETTING="0" # Valeur par défaut

# ==========================================
# FONCTIONS UTILITAIRES
# ==========================================

info() {
    echo "${GREEN}[INFO] $1${RESET}"
}

error() {
    echo "${RED}[ERREUR] $1${RESET}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Ce script doit être lancé avec sudo."
        exit 1
    fi
}

trap 'error "Erreur ligne $LINENO — installation interrompue."' ERR

# ==========================================
# FONCTIONS D'ÉTAPE (BUSINESS LOGIC)
# ==========================================

# Étape 0 : Choix de l'utilisateur
ask_install_mode() {
    while true; do
        info "Installation : Desktop Antidote (1) ou Normal (0) ?"
        read -p "Votre choix [0/1] : " input_setting
        [[ "$input_setting" == "0" || "$input_setting" == "1" ]] && break
        error "Choix invalide. Entrez 0 ou 1."
    done
    VM_SETTING="$input_setting"
}

# Étape 1 : Configuration Système
configure_system_files() {
    info "Déploiement des configurations système..."

    # Copie avec préservation des droits
    rsync -a --chown=root:root etc/ /etc/
    rsync -a --chown=root:root usr/ /usr/
    rsync -a --chown=root:root config_root/ /root/.config
    rm -f /etc/sudoers.d/10-installer

    info "Suppression du thème GRUB d'EndeavourOS..."
    sed -i '/^GRUB_THEME=/d' /etc/default/grub
    grub-mkconfig -o /boot/grub/grub.cfg
}

# Étape 2 : Paquets de base
install_base_packages() {
    info "Installation des paquets de base..."
    mapfile -t PKGS < <(grep -v '^[[:space:]]*$' packages-base.txt)
    pacman -Sy
    pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout "${PKGS[@]}"
}

# Étape 3 : Installation Complète (Optionnelle)
install_full_suite() {
    if [[ "$VM_SETTING" != "1" ]]; then
        info "Mode minimal sélectionné. Passage de l'étape complète."
        return 0
    fi

    info "Saisir le mot de passe pour l'archive personnelle :"
    read -p "Password: " PASSWORD
    echo ""

    info "Installation des paquets supplémentaires..."
    mapfile -t PKGS_EXTRA < <(grep -v '^[[:space:]]*$' packages-extra.txt)
    pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout "${PKGS_EXTRA[@]}"

    info "Installation de la toolchain Rust..."
    sudo -u "${USERNAME}" rustup toolchain install stable

    # Configuration NFS / Fstab
    mkdir -p /mnt/medias

    cat >> /etc/fstab <<-EOL

	## Synology DS918
	${NAS_IP}:/mnt/user/medias /mnt/medias nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
	EOL

    # Gestion Archive Chiffrée
    if command -v cryptyrust &> /dev/null; then
        cryptyrust --decrypt myEncryptedFile -p "${PASSWORD}" -o tmp.tar.gz
        tar -xf tmp.tar.gz -C "/home/${USERNAME}/"
        rm tmp.tar.gz

        chmod +x "/home/${USERNAME}/gitconfig.sh"
        sudo -u "${USERNAME}" "/home/${USERNAME}/gitconfig.sh"
    else
        error "cryptyrust non trouvé, saut de l'étape de déchiffrement."
    fi
}

# Étape 4 : Configuration Utilisateur
configure_user_environment() {
    info "Déploiement des configurations utilisateur..."

    # Rsync direct avec le bon propriétaire
    rsync -a --chown="${USERNAME}:${USERNAME}" .config "/home/${USERNAME}/"
    rsync -a --chown="${USERNAME}:${USERNAME}" home_config/ "/home/${USERNAME}/"

    # Thèmes et UI
    mkdir -p /usr/share/oh-my-zsh/themes/
    cp -r /usr/share/zsh-theme-powerlevel10k /usr/share/oh-my-zsh/themes/powerlevel10k

    # Tweaks fichiers de conf
    sed -i 's|background=/usr/share/endeavouros/backgrounds/endeavouros-wallpaper.png|background=/usr/share/backgrounds/packarch/default.jpg|g' /etc/lightdm/slick-greeter.conf
    sed -i 's|Exec=geany %F|Exec=geany -i %F|g' /usr/share/applications/geany.desktop

    sed -i "s|antidote|${USERNAME}|g" "/home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml"
    sed -i "s|antidote|${USERNAME}|g" "/home/${USERNAME}/.config/gtk-3.0/bookmarks"

    # Paramètres XFCE (tolérance aux erreurs si X n'est pas up)
    sudo -u "${USERNAME}" env DISPLAY="${DISPLAY:-}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" xfce4-set-wallpaper /usr/share/backgrounds/packarch/default.jpg || true
    sudo -u "${USERNAME}" env DISPLAY="${DISPLAY:-}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" xfconf-query --channel xsettings --property /Gtk/CursorThemeSize --set 24 || true

    systemctl enable lightdm.service

    # Changement de Shell
    chsh -s "$(which zsh)" root
    chsh -s "$(which zsh)" "${USERNAME}"

    info "Activation du TRIM hebdomadaire pour SSD..."
    systemctl enable --now fstrim.timer
}

# Étape 5 : Nettoyage des menus
hide_useless_apps() {
    info "Nettoyage des entrées de menu..."
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

# Étape 6 : Finalisation
finalize_installation() {
    if [ "$(systemd-detect-virt)" != "none" ]; then
        info "Machine virtuelle détectée."
    fi

    info "Sauvegarde du log et nettoyage..."

    cp "$LOGFILE" "/home/${USERNAME}/$LOGFILE"
    chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/$LOGFILE"
    info "Log copié dans /home/${USERNAME}/$LOGFILE"

    info "Suppression du dossier repo..."
    rm -rf "$SCRIPT_DIR"

    info "Installation terminée !"
    read -p "Voulez-vous redémarrer maintenant ? (O/n) " response
    if [[ "$response" =~ ^[OoYy]$ ]] || [[ -z "$response" ]]; then
        reboot
    fi
}

# ==========================================
# FONCTION PRINCIPALE (MAIN)
# ==========================================

main() {
    check_root
    cd "$SCRIPT_DIR"
    ask_install_mode
    configure_system_files
    install_base_packages
    install_full_suite
    configure_user_environment
    hide_useless_apps
    finalize_installation
}

# Exécution
main
