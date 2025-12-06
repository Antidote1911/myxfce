#!/usr/bin/env bash
username="$1"

# Clone the repo
echo "Cloning the xfce repo..."
git clone https://github.com/Antidote1911/myxfce.git

rm /etc/sudoers.d/10-installer

# Install the custom package list
echo "Installing needed packages..."
pacman -S --noconfirm --noprogressbar --needed --disable-download-timeout $(< ./xfce/packages-repository.txt)

# Deploy user configs
echo "Deploying user configs..."
rsync -a xfce/.config "/home/${username}/"
rsync -a xfce/.local "/home/${username}/"
rsync -a xfce/home_config/ "/home/${username}/"
# Restore user ownership
chown -R "${username}:${username}" "/home/${username}"

# Deploy system configs
echo "Deploying system configs..."
rsync -a --chown=root:root xfce/etc/ /etc/
rsync -a --chown=root:root xfce/usr/ /usr/

# Check if the script is running in a virtual machine
if systemd-detect-virt | grep -vq "none"; then
  echo "Virtual machine detected..."
  
fi

# Remove the repo
echo "Removing the xfce repo..."
rm -rf myxfce

# Enable some service
echo "Enabling the some service..."

echo "Installation complete."
