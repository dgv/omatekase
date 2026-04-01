#!/bin/sh

# checks
if [ "$(id -u)" -ne 0 ]; then
  echo "this script must be run as root"
  exit 1
fi
export SUSER=$(grep ":1000:" /etc/passwd | cut -d: -f1)
if [ -z $SUSER ]; then
  echo "must create user (uid 1000) to continue"
  exit 1
fi

OS=$(uname -s)
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
SLICK_CONF="/etc/lightdm/slick-greeter.conf"
case "$OS" in
    Linux*)
        # setup apt/repos changes
        sed -i 's/non-free-firmware/non-free-firmware contrib non-free/g' /etc/apt/sources.list
        apt install extrepo -y; extrepo enable librewolf; echo 'APT::Default-Release "stable";' > /etc/apt/apt.conf

        cat << EOF > /etc/apt/preferences
Package: *
Pin: release o=Debian,a=unstable
Pin-Priority: 10

EOF
        # install all required packages
        apt update; apt install sudo mate-desktop-environment mate-dock-applet flatpak \
        vim-nox gufw ufw mpv transmission-gtk lightdm htop slick-greeter git solaar \
        papirus-icon-theme system-config-printer cups librewolf geary starship \
        gparted blueman network-manager arc-theme yubikey-manager abiword gnumeric \
        fastfetch plymouth rclone xpad rofi libimobiledevice-utils usbmuxd ipheth-utils \
        firmware-iwlwifi wpasupplicant openssh-server ifuse network-manager-applet dconf-cli \
        firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers xserver-xorg-video-all -y

        # install plymouth
        export PATH=$PATH:/usr/sbin
        git clone https://github.com/remmiculous/simplefuture /usr/share/plymouth/themes/simplefuture
        sed -i 's/quiet/quiet splash/g' /etc/default/grub
        sed -i 's/Theme=ceratopsian/Theme=simplefuture/g' /usr/share/plymouth/plymouthd.defaults
        sed -i 's/^[#g]reeter-session=.*$/greeter-session=slick-greeter/g' $LIGHTDM_CONF
        rm /usr/share/xsessions/lightdm-xsession.desktop
        /usr/sbin/adduser $SUSER sudo
        update-grub; update-initramfs -u -k all
    ;;
    FreeBSD*)
        LIGHTDM_CONF="/usr/local/etc/lightdm/lightdm.conf"
        SLICK_CONF="/usr/local/etc/lightdm/slick-greeter.conf"
        # install all required packages
        pkg update; pkg install --yes xorg mate brisk-menu mate-desktop mate-dock-applet \
        lightdm htop slick-greeter git solaar papirus-icon-theme system-config-printer \
        cups librewolf gtk-arc-themes abiword gnumeric fastfetch rclone unrar xpad rofi \
        jetbrains-mono usbmuxd wpa_supplicant wpa_supplicant wpa_supplicant_gui dconf bash \
        dconf-editor android-tools vulkan-loader vulkan-headers vulkan-tools doas drm-kmod \
        git-gui git-lfs mtr meld tcpdump valgrind gdb minicom starship curl gimp mpv transmission-gtk
        sysrc dbus_enable="YES"
        sysrc lightdm_enable="YES"
        echo kern.evdev.rcpt_mask=6 >> /etc/sysctl.conf
        pw groupmod video -m $SUSER
        pw groupmod network -m $SUSER
        pw groupmod usbmuxd -m $SUSER
        pw groupmod wheel -m $SUSER
        chsh -s /usr/local/bin/bash $SUSER
        service dbus start
        echo "permit $SUSER as root" > /usr/local/etc/doas.conf
        sed -i '' -E 's/#greeter-session=.*/greeter-session=slick-greeter/' $LIGHTDM_CONF
    ;;
    *)  echo "$OS not supported"; exit 1;;
esac

# setup login dm
mkdir -p /usr/local/share/backgrounds/
echo 'eval "$(starship init bash)"' >> /home/$SUSER/.bashrc
cat << EOF > $SLICK_CONF
[Greeter]
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
background=/usr/local/share/backgrounds/ghibli_kodamas.png

EOF

# fetch config/theme
rm -rf /home/$SUSER/.config; su $SUSER -c 'git clone https://github.com/dgv/omatekase -b dotfiles /home/$SUSER/.config'
su $SUSER -c 'mkdir -p ~/.local/share'; mv /home/$SUSER/.config/fonts /home/$SUSER/.local/share; su $SUSER -c 'fc-cache -vf'
mv /home/$SUSER/.config/*.png /usr/local/share/backgrounds/
su $SUSER -c 'dbus-launch dconf load / < ~/.config/dconf.backup'

echo "setup done."
