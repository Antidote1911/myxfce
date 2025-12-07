#!/bin/bash

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

username="$(logname)"

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo."
  exit 1
fi

echo "${green}Install full desktop or minimal ?${reset}"
read -p "1 - Full, 0 - Minimal: " vm_setting

# Deploy system configs
echo "Deploying system configs..."
rsync -a --chown=root:root etc/ /etc/
rsync -a --chown=root:root usr/ /usr/
rsync -a --chown=root:root .config/ /root/.config
sed -i -e 's|color_scheme=nordic.conf|color_scheme=dark-colors.conf|g' /root/.config/geany/geany.conf

rm /etc/sudoers.d/10-installer


# Install the custom package list
echo "Installing needed packages..."
pacman -Syy
pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-repository.txt)

########## Only for full install ###########################
if [[ $vm_setting == 1 ]]; then
  echo "${green}Enter password to decrypt personal archive:${reset}"
  read -p "Password: " password
  echo "${green}Install full desktop and applications${reset}"
  pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<extra_pkgs.txt)
  sudo -u "${username}" rustup toolchain install stable
  
  ## Add syno nfs share to autofs
  mkdir /mnt/Partage /mnt/Photos
  
  tee -a /etc/fstab << EOL
  
## Synology DS918
192.168.1.96:/volume1/Partage /mnt/Partage nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
192.168.1.96:/volume1/Photos  /mnt/Photos  nfs _netdev,noauto,x-systemd.automount,x-systemd.mount-timeout=10,timeo=14,x-systemd.idle-timeout=1min 0 0
EOL

  modprobe vboxdrv
  cryptyrust_cli -d myEncryptedFile -p ${password} -o tmp.tar.gz
  tar -xf tmp.tar.gz -C /home/${username}/
  sudo -u "${username}" eval `ssh-agent -s`
  sudo -u "${username}" /home/${username}/./gitconfig.sh
  sudo -u "${username}" yay -S --noconfirm --answerdiff None --answerclean None filebot rustrover rustrover-jre
fi
####################################################

# Deploy user configs
echo "Deploying user configs..."
rsync -a .config "/home/${username}/"
rsync -a home_config/ "/home/${username}/"
# Restore user ownership
chown -R "${username}:${username}" "/home/${username}"

mkdir -p /usr/share/oh-my-zsh/themes/
cp -r /usr/share/zsh-theme-powerlevel10k /usr/share/oh-my-zsh/themes/powerlevel10k
sed -i -e 's|background=/usr/share/endeavouros/backgrounds/endeavouros-wallpaper.png|background=/usr/share/backgrounds/packarch/default.jpg|g' /etc/lightdm/slick-greeter.conf
sed -i -e 's|Exec=geany %F|Exec=geany -i %F|g' /usr/share/applications/geany.desktop
sudo -u "${username}" env DISPLAY="${DISPLAY}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" xfce4-set-wallpaper /usr/share/backgrounds/packarch/default.jpg
sudo -u "${username}" env DISPLAY="${DISPLAY}" DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" xfconf-query --channel xsettings --property /Gtk/CursorThemeSize --set 24
systemctl enable lightdm.service

## Set zsh shell for root and user
chsh -s $(which zsh) root
chsh -s $(which zsh) "${username}"

## Hide Unnecessary Apps
adir="/usr/share/applications"
apps=(avahi-discover.desktop bssh.desktop bvnc.desktop xfce4-about.desktop \
	org.pulseaudio.pavucontrol.desktop java-java-openjdk.desktop xfce4-mail-reader.desktop \
	hdajackretask.desktop hdspconf.desktop hdspmixer.desktop jconsole-java-openjdk.desktop jshell-java-openjdk.desktop \
	libfm-pref-apps.desktop eos-quickstart.desktop lstopo.desktop \
	uxterm.desktop nm-connection-editor.desktop xterm.desktop \
	qvidcap.desktop stoken-gui.desktop stoken-gui-small.desktop assistant.desktop \
	qv4l2.desktop qdbusviewer.desktop mpv.desktop java-java-openjdk.desktop jconsole-java-openjdk.desktop jshell-java-openjdk.desktop yad-settings.desktop)

for app in "${apps[@]}"; do
	if [[ -e "$adir/$app" ]]; then
		sed -i '$s/$/\nNoDisplay=true/' "$adir/$app"
	fi
done



# Check if the script is running in a virtual machine
if systemd-detect-virt | grep -vq "none"; then
  echo "Virtual machine detected..."

fi

# Remove the repo
echo "Removing the EOS Community Sway repo..."
rm -rf ../myxfce

echo "Installation complete."

