#!/bin/bash

username="$(logname)"

# Check for sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo."
  exit 1
fi

# Deploy system configs
echo "Deploying system configs..."
rsync -a --chown=root:root etc/ /etc/
rsync -a --chown=root:root usr/ /usr/
rsync -a --chown=root:root .config/ /root/

rm /etc/sudoers.d/10-installer

# Install the custom package list
echo "Installing needed packages..."
pacman -Syy
pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(<packages-repository.txt)

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
		sudo sed -i '$s/$/\nNoDisplay=true/' "$adir/$app"
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

