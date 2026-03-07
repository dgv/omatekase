#!/bin/bash

# checks
if [[ $EUID -ne 0 ]]; then
  echo "this script must be run as root"
  exit 1
fi
export SUSER=$(grep ":1000:" /etc/passwd | cut -d: -f1)
if [ -z $SUSER ]; then
  echo "must create user (uid 1000) to continue"
  exit 1
fi

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
papirus-icon-theme  breeze-cursor-theme system-config-printer cups librewolf \
gparted blueman network-manager arc-theme yubikey-manager abiword gnumeric \
fastfetch plymouth geary libavcodec-extra ttf-mscorefonts-installer gdebi \
gstreamer1.0-libav gstreamer1.0-plugins-ugly firmware-misc-nonfree rclone \
unrar xpad rofi fonts-jetbrains-mono libimobiledevice-utils usbmuxd ipheth-utils \
firmware-iwlwifi wpasupplicant openssh-server \
firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers xserver-xorg-video-all \
ifuse android-tools-adb android-tools-fastboot network-manager-applet dconf-cli -y

# install plymouth
export PATH=$PATH:/usr/sbin
git clone https://github.com/remmiculous/simplefuture /usr/share/plymouth/themes/simplefuture
sed -i 's/quiet/quiet splash/g' /etc/default/grub
sed -i 's/Theme=ceratopsian/Theme=simplefuture/g' /usr/share/plymouth/plymouthd.defaults
update-grub; update-initramfs -u -k all

# setup login dm
sed -i 's/^[#g]reeter-session=.*$/greeter-session=slick-greeter/g' /etc/lightdm/lightdm.conf
rm /usr/share/xsessions/lightdm-xsession.desktop
/usr/sbin/adduser $SUSER sudo
cat << EOF > /etc/lightdm/slick-greeter.conf
[Greeter]
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
cursor-theme-name=Breeze_Light
background=/usr/share/images/desktop-base/ghibli_kodamas.png

EOF

# fetch config/theme
rm -rf /home/$SUSER/.config; su $SUSER -c 'git clone https://github.com/dgv/ombian -b dotfiles /home/$SUSER/.config'
su $SUSER -c 'mkdir -p ~/.local/usr/share'; mv /home/$SUSER/.config/fonts /home/$SUSER/.local/user/share/
mv /home/$SUSER/.config/*.png /usr/share/images/desktop-base/
su $SUSER -c 'dconf load / < ~/.config/dconf.backup'

echo "setup done. rebooting..."
sleep 3
/usr/sbin/reboot
