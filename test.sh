#!/bin/bash

# Arrêter le script à la moindre erreur
set -e

# Définition des couleurs
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

USERNAME="$(logname)"
NAS_IP="192.168.1.96"

# Fonction pour afficher des messages formatés
info() { echo "${GREEN}[INFO] $1${RESET}"; }
error() { echo "${RED}[ERREUR] $1${RESET}"; }

# Vérification Root
if [ "$EUID" -ne 0 ]; then
  error "Ce script doit être lancé avec sudo."
  exit 1
fi

# --- Choix de l'installation ---
info "Installation : Desktop Complet (1) ou Minimal (0) ?"
read -p "Votre choix : " VM_SETTING

# --- 1. Configuration Système ---
info "Déploiement des configurations système..."
# Copie avec préservation des droits, plus efficace
rsync -a --chown=root:root etc/ /etc/
rsync -a --chown=root:root usr/ /usr/
rsync -a --chown=root:root .config/ /root/.config

# Modification Geany
sed -i 's|color_scheme=nordic.conf|color_scheme=dark-colors.conf|g' /root/.config/geany/geany.conf
rm -f /etc/sudoers.d/10-installer

# --- 2. Installation des Paquets de base ---
info "Installation des paquets de base..."
pacman -Syy
pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-base.txt)

# --- 3. Installation Complète (Optionnelle) ---
if [[ "$VM_SETTING" == "1" ]]; then
  info "Saisir le mot de passe pour l'archive personnelle :"
  read -p "Password: " PASSWORD
  echo "" # Retour à la ligne après la saisie

  info "Installation des paquets supplémentaires..."
  pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-extra.txt)
  
  info "Installation de la toolchain Rust..."
  sudo -u "${USERNAME}" rustup toolchain install stable
  
  # Configuration NFS / Fstab
  mkdir -p /mnt/Partage /mnt/Photos
  
  # Utilisation de <<-EOL pour ignorer l'indentation (tabs) dans le script
  cat >> /etc/fstab <<-EOL
	
	## Synology DS918
	${NAS_IP}:/volume1/Partage /mnt/Partage nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
	${NAS_IP}:/volume1/Photos  /mnt/Photos  nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
	EOL

  # Gestion Archive Chiffrée
  modprobe vboxdrv
  if command -v cryptyrust_cli &> /dev/null; then
      cryptyrust_cli -d myEncryptedFile -p "${PASSWORD}" -o tmp.tar.gz
      tar -xf tmp.tar.gz -C "/home/${USERNAME}/"
      rm tmp.tar.gz # Nettoyage immédiat
      # Exécution du script gitconfig (correction des droits d'exécution si besoin)
      chmod +x "/home/${USERNAME}/gitconfig.sh"
      sudo -u "${USERNAME}" "/home/${USERNAME}/gitconfig.sh"
  else
      error "cryptyrust_cli non trouvé, saut de l'étape de déchiffrement."
  fi
fi

# --- 4. Configuration Utilisateur ---
info "Déploiement des configurations utilisateur..."

# Rsync direct avec le bon propriétaire, évite le chown récursif lourd après coup
rsync -a --chown="${USERNAME}:${USERNAME}" .config "/home/${USERNAME}/"
rsync -a --chown="${USERNAME}:${USERNAME}" home_config/ "/home/${USERNAME}/"

# Thèmes et UI
THEME_DIR="/usr/share/oh-my-zsh/themes"
mkdir -p "$THEME_DIR"
[ -d "/usr/share/zsh-theme-powerlevel10k" ] && cp -r /usr/share/zsh-theme-powerlevel10k "$THEME_DIR/powerlevel10k"

# Tweaks fichiers de conf
sed -i 's|background=/usr/share/endeavouros/backgrounds/endeavouros-wallpaper.png|background=/usr/share/backgrounds/packarch/default.jpg|g' /etc/lightdm/slick-greeter.conf
sed -i 's|Exec=geany %F|Exec=geany -i %F|g' /usr/share/applications/geany.desktop

# Paramètres XFCE (Attention: peut échouer si X n'est pas lancé, on ajoute || true pour ne pas bloquer le script)
sudo -u "${USERNAME}" env DISPLAY="${DISPLAY}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" xfce4-set-wallpaper /usr/share/backgrounds/packarch/default.jpg || true
sudo -u "${USERNAME}" env DISPLAY="${DISPLAY}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" xfconf-query --channel xsettings --property /Gtk/CursorThemeSize --set 24 || true

systemctl enable lightdm.service

# Changement de Shell
chsh -s "$(which zsh)" root
chsh -s "$(which zsh)" "${USERNAME}"

# --- 5. Masquer les applications inutiles ---
info "Nettoyage des entrées de menu..."
APPS_DIR="/usr/share/applications"
APPS_TO_HIDE=(
    "avahi-discover.desktop" "bssh.desktop" "bvnc.desktop" "xfce4-about.desktop"
    "org.pulseaudio.pavucontrol.desktop" "java-java-openjdk.desktop" "xfce4-mail-reader.desktop"
    "hdajackretask.desktop" "hdspconf.desktop" "hdspmixer.desktop" "jconsole-java-openjdk.desktop"
    "jshell-java-openjdk.desktop" "libfm-pref-apps.desktop" "eos-quickstart.desktop" "lstopo.desktop"
    "uxterm.desktop" "nm-connection-editor.desktop" "xterm.desktop" "qvidcap.desktop"
    "stoken-gui.desktop" "stoken-gui-small.desktop" "assistant.desktop" "qv4l2.desktop"
    "qdbusviewer.desktop" "mpv.desktop" "yad-settings.desktop"
)

for app in "${APPS_TO_HIDE[@]}"; do
    if [[ -f "$APPS_DIR/$app" ]]; then
        # Ajoute NoDisplay seulement si pas déjà présent
        if ! grep -q "NoDisplay=true" "$APPS_DIR/$app"; then
            echo "NoDisplay=true" >> "$APPS_DIR/$app"
        fi
    fi
done

# --- 6. Finalisation ---
# Check VM (informatif)
if systemd-detect-virt | grep -vq "none"; then
  info "Machine virtuelle détectée."
fi

info "Suppression du dossier repo..."
rm -rf ../myxfce

info "Installation terminée avec succès !"
