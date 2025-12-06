# My Xfce Setup and Theme for EndeavourOS

[![Maintenance](https://img.shields.io/maintenance/yes/2025.svg)]()

## To Install Xfce

### With the EOS Installer

1. In the live environment, choose "Fetch your install customization file" from the Welcome app.
2. Type or paste the URL for the Xfce user_commands.bash file.
```
https://raw.githubusercontent.com/Antidote1911/myxfce/master/setup_xfce_isomode.bash
```
![welcome_install-customization-file](https://github.com/user-attachments/assets/b4b9e882-0e53-4e11-be10-a92e5b55cefb)

3. Click <kbd> OK </kbd>, then back in the Welcome app click <kbd> Start the Installer </kbd> and proceed with an online installation. Be sure to choose "no desktop" on the DE selection screen.

![installer-no_desktop](https://github.com/user-attachments/assets/f9146bf2-e0ab-4e0a-9b6a-89ad5eed5a29)


### Manually (Post-Installation)

Alternatively, you can add Sway after the installation is complete by cloning the repo and running the `sway-install.sh` script.

    git clone https://github.com/Antidote1911/myxfce.git

    cd xfce

    sudo ./xfce-install.sh
