#!/bin/bash

# ==========================================
# CONFIGURATION GLOBALE & LOGGING
# ==========================================

LOGFILE="install_log_$(date +%F_%H-%M).txt"
exec > >(tee -i "$LOGFILE") 2>&1

# Arrêter le script à la moindre erreur
set -e

# Couleurs
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# Variables Globales
USERNAME="$(logname)"
NAS_IP="192.168.1.96"
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

# ==========================================
# FONCTIONS D'ÉTAPE (BUSINESS LOGIC)
# ==========================================

# Étape 0 : Choix de l'utilisateur
ask_install_mode() {
    info "Installation : Desktop Complet (1) ou Minimal (0) ?"
    read -p "Votre choix : " input_setting
    # On met à jour la variable globale
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
}

update_mirrors() {
    info "Optimisation des miroirs de téléchargement (Reflector)..."
    # Trie les 10 miroirs HTTPS les plus récents et rapides en France (ou change le pays)
    reflector --country France --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
    # Force la mise à jour de la base de données
    pacman -Syy
}

# Étape 2 : Paquets de base
install_base_packages() {
    info "Installation des paquets de base..."
    pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-base.txt)
}

# Étape 3 : Installation Complète (Optionnelle)
install_full_suite() {
    # On vérifie la variable globale définie dans ask_install_mode
    if [[ "$VM_SETTING" != "1" ]]; then
        info "Mode minimal sélectionné. Passage de l'étape complète."
        return 0
    fi

    info "Saisir le mot de passe pour l'archive personnelle :"
    read -p "Password: " PASSWORD
    echo "" 

    info "Installation des paquets supplémentaires..."
    pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-extra.txt)
    
    info "Installation de la toolchain Rust..."
    sudo -u "${USERNAME}" rustup toolchain install stable
    
    # Configuration NFS / Fstab
    mkdir -p /mnt/Partage /mnt/Photos
    
    cat >> /etc/fstab <<-EOL
	
	## Synology DS918
	${NAS_IP}:/volume1/Partage /mnt/Partage nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
	${NAS_IP}:/volume1/Photos  /mnt/Photos  nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
	EOL

    # Gestion Archive Chiffrée
    modprobe vboxdrv
    if command -v cryptyrust_cli &> /dev/null; then
        # Note: PASSWORD est une variable locale à cette fonction ou au scope appelant
        cryptyrust_cli -d myEncryptedFile -p "${PASSWORD}" -o tmp.tar.gz
        tar -xf tmp.tar.gz -C "/home/${USERNAME}/"
        rm tmp.tar.gz 
        
        chmod +x "/home/${USERNAME}/gitconfig.sh"
        sudo -u "${USERNAME}" "/home/${USERNAME}/gitconfig.sh"
    else
        error "cryptyrust_cli non trouvé, saut de l'étape de déchiffrement."
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

    sed -i "s|antidote|${USERNAME}|g" /home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml
    sed -i "s|antidote|${USERNAME}|g" /home/${USERNAME}/.config/gtk-3.0/bookmarks

    # Paramètres XFCE (tolérance aux erreurs si X n'est pas up)
    sudo -u "${USERNAME}" env DISPLAY="${DISPLAY}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" xfce4-set-wallpaper /usr/share/backgrounds/packarch/default.jpg || true
    sudo -u "${USERNAME}" env DISPLAY="${DISPLAY}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" xfconf-query --channel xsettings --property /Gtk/CursorThemeSize --set 24 || true

    systemctl enable lightdm.service

    # Changement de Shell
    chsh -s "$(which zsh)" root
    chsh -s "$(which zsh)" "${USERNAME}"
    
    # Vérifie si c'est un disque rotatif (0) ou SSD (non-0, souvent 0 sur SSD nvme/sata modernes mais check simple)
    # Le plus simple est d'activer le timer, systemd est intelligent et ne fera rien si pas supporté
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
    # Check VM (informatif)
    if systemd-detect-virt | grep -vq "none"; then
        info "Machine virtuelle détectée."
    fi

    info "Sauvegarde du log et nettoyage..."

    cp "$LOGFILE" "/home/${USERNAME}/$LOGFILE"
    chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/$LOGFILE"
    info "Log copié dans /home/${USERNAME}/$LOGFILE"

    info "Suppression du dossier repo..."
    # On remonte d'un niveau pour supprimer le dossier courant
    cd ..
    # Attention: on suppose que le dossier s'appelle 'myxfce'. 
    # Pour être plus robuste, on pourrait supprimer le dossier $OLDPWD ou le dossier actuel avant le cd ..
    rm -rf myxfce

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
    ask_install_mode
    configure_system_files
    update_mirrors
    install_base_packages
    install_full_suite
    configure_user_environment
    hide_useless_apps
    finalize_installation
}

# Exécution
main
