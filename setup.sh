#!/bin/sh

# checks
if [[ $EUID -ne 0 ]]; then
  echo "this script must be run as root"
  exit 1
fi
export SUSER=$(grep ":1001:" /etc/passwd | cut -d: -f1)
if [ -z $SUSER ]; then
  echo "must create user (uid 1001) to continue"
  exit 1
fi


# install all required packages
pkg update; pkg install --yes xorg mate brisk-menu mate-desktop mate-dock-applet \
lightdm htop slick-greeter git solaar papirus-icon-theme system-config-printer \
cups librewolf gtk-arc-themes abiword gnumeric fastfetch rclone unrar xpad rofi \
jetbrains-mono usbmuxd wpa_supplicant wpa_supplicant wpa_supplicant_gui dconf bash \
dconf-editor android-tools vulkan-loader vulkan-headers vulkan-tools doas drm-kmod \
git-gui git-lfs mtr meld tcpdump valgrind gdb minicom starship curl gimp mpv transmission-gtk

# uncomment to load your videocard/gpu on kernel
# AMD
#sysrc kld_list+=amdgpu
# Intel
#sysrc kld_list+=i915kms
# nvidia
#sysrc kld_list+=nvidia-modeset

sysrc dbus_enable="YES"
sysrc lightdm_enable="YES"
echo kern.evdev.rcpt_mask=6 >> /etc/sysctl.conf
pw groupmod video -m $SUSER
pw groupmod network -m $SUSER
pw groupmod usbmuxd -m $SUSER
pw groupmod wheel -m $SUSER

echo 'eval "$(starship init bash)"' >> /home/$SUSER/.bashrc
# setup login dm
chsh -s /usr/local/bin/bash $SUSER
sed -i '' -E 's/#greeter-session=.*/greeter-session=slick-greeter/' /usr/local/etc/lightdm/lightdm.conf
echo "permit $SUSER as root" > /usr/local/etc/doas.conf
cat << EOF > /usr/local/etc/lightdm/slick-greeter.conf
[Greeter]
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
background=/usr/local/share/backgrounds/ghibli_kodamas.png

EOF

# fetch config/theme
rm -rf /home/$SUSER/.config; su $SUSER -c 'git clone https://github.com/dgv/ombian -b dotfiles /home/$SUSER/.config'
su $SUSER -c 'mkdir -p ~/.local/share'; mv /home/$SUSER/.config/fonts /home/$SUSER/.local/share; su $SUSER -c 'fc-cache -vf'
mv /home/$SUSER/.config/*.png /usr/local/share/backgrounds/
service dbus start
su $SUSER -c 'dbus-launch dconf load / < ~/.config/dconf.backup'

echo "setup done. rebooting..."
sleep 3
/sbin/reboot
