#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "this script must be run as root" >&2
  exit 1
fi

SUSER=$(awk -F: '$3==1000 {print $1; exit}' /etc/passwd 2>/dev/null || true)
export SUSER
if [ -z "${SUSER:-}" ]; then
  echo "must create user (uid 1000) to continue" >&2
  exit 1
fi

OS=$(uname -s)
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
SLICK_CONF="/etc/lightdm/slick-greeter.conf"
BG_DIR="/usr/share/backgrounds"

apk_try() {
  apk add --no-cache "$1" || echo "warning: apk package '$1' not installed, continuing" >&2
}


setup_apk_repos_alpine() {
  _repos="/etc/apk/repositories"
  [ -f "$_repos" ] || return 0
  if grep -q '^[[:space:]]*[^#[:space:]].*community' "$_repos"; then
    return 0
  fi
  echo "enabling community repository in $_repos ..." >&2
  if grep -q 'community' "$_repos"; then
    sed -i 's/^[[:space:]]*#[[:space:]]*\(.*community.*\)/\1/' "$_repos" || true
  else
    _main=$(grep -m1 '^[[:space:]]*[^#[:space:]].*/main[[:space:]]*$' "$_repos" || true)
    if [ -n "${_main:-}" ]; then
      _community=$(printf '%s\n' "$_main" | sed 's|/main|/community|')
      if ! grep -qF "$_community" "$_repos"; then
        printf '%s\n' "$_community" >> "$_repos"
      fi
    else
      echo "warning: no active /main entry in $_repos, cannot derive community" >&2
    fi
    unset _main _community
  fi
  if ! grep -q '^[[:space:]]*[^#[:space:]].*community' "$_repos"; then
    echo "warning: community repository still not enabled in $_repos" >&2
  fi
  unset _repos
}

pkg_try() {
  pkg_add "$1" || echo "warning: pkg '$1' not installed, continuing" >&2
}

run_as_user() {
  if [ "${OS:-}" = "OpenBSD" ]; then
    doas -u "$SUSER" sh -c "$1"
  else
    su "$SUSER" -c "$1"
  fi
}

extlinux_ensure_opts() {
  _conf="$1"; shift
  if [ ! -f "$_conf" ]; then
    return 0
  fi
  _cur=$(sed -n -E 's/^[[:space:]]*default_kernel_opts=+[[:space:]]*//p' "$_conf" | tail -n 1)
  _cur=$(printf '%s' "$_cur" | sed -e 's/^=//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")
  for _tok in "$@"; do
    _cur=$(printf '%s' "$_cur" | sed -E -e "s/(^|[[:space:]])${_tok}([[:space:]]|\$)/ /g" -e 's/  */ /g' -e 's/^ //' -e 's/ $//')
  done
  _new="$_cur $*"
  _new=$(printf '%s' "$_new" | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')
  if grep -qE '^[[:space:]]*default_kernel_opts=+' "$_conf"; then
    sed -i -E "s|^[[:space:]]*default_kernel_opts=.*|default_kernel_opts=\"$_new\"|" "$_conf"
  else
    printf 'default_kernel_opts="%s"\n' "$_new" >> "$_conf"
  fi
  unset _conf _cur _new _tok
}

lightdm_set_greeter() {
  _conf="$1"
  [ -f "$_conf" ] || return 0
  if grep -qE '^[# ]*greeter-session=' "$_conf"; then
    sed -i -E 's/^[# ]*greeter-session=.*/greeter-session=slick-greeter/' "$_conf"
  elif grep -q '^\[Seat:\*\]' "$_conf"; then
    sed -i -E '/^\[Seat:\*\]/a greeter-session=slick-greeter' "$_conf"
  else
    printf '\n[Seat:*]\ngreeter-session=slick-greeter\n' >> "$_conf"
  fi
}

mkinitfs_ensure_features() {
  _conf="/etc/mkinitfs/mkinitfs.conf"
  [ -f "$_conf" ] || return 0
  for _feat in "$@"; do
    if ! grep -qE "^features=.*\\b${_feat}\\b" "$_conf"; then
      if grep -q '^features=' "$_conf"; then
        sed -i -e "s/^features=\"\(.*\)\"/features=\"\1 ${_feat}\"/" \
               -e 's/  */ /g' -e 's/ "/"/' "$_conf"
      else
        echo "features=\"${_feat}\"" >> "$_conf"
      fi
    fi
  done
}

mkinitfs_rebuild() {
  if ! command -v mkinitfs >/dev/null 2>&1; then
    return 0
  fi
  if [ -d /lib/modules ]; then
    for _k in /lib/modules/*; do
      [ -d "$_k" ] || continue
      _kv="${_k##*/}"
      echo "rebuilding initramfs for $_kv ..."
      mkinitfs -c /etc/mkinitfs/mkinitfs.conf -b / "$_kv" || echo "warning: mkinitfs failed for $_kv" >&2
    done
  else
    mkinitfs || echo "warning: mkinitfs failed" >&2
  fi
}

setup_gpu_alpine() {
  apk add --no-cache pciutils >/dev/null 2>&1 || true

  _pci=""
  if command -v lspci >/dev/null 2>&1; then
    _pci=$(lspci 2>/dev/null | grep -iE 'vga|3d|display|graphics' || true)
  fi
  echo "GPU detect: ${_pci:-unknown (no lspci match)}"

  _gpu_pkgs="xf86-video-modesetting xf86-video-vesa xf86-video-fbdev mesa mesa-dri-gallium"
  _is_intel=0
  _is_amd=0
  _is_vbox=0

  case "$_pci" in
    *Intel*)  _is_intel=1 ;;
  esac
  case "$_pci" in
    *AMD*|*ATI*|*Radeon*) _is_amd=1 ;;
  esac
  case "$_pci" in
    *VirtualBox*|*VBox*|*80ee:beef*|*80EE:CAFE*)
      _is_vbox=1 ;;
  esac
  # DMI fallback for VirtualBox when PCI text is inconclusive.
  if [ "$_is_vbox" -eq 0 ]; then
    if [ -r /sys/class/dmi/id/product_name ] && grep -qi 'virtualbox' /sys/class/dmi/id/product_name 2>/dev/null; then
      _is_vbox=1
    elif [ -r /sys/class/dmi/id/sys_vendor ] && grep -qi 'innotek\|virtualbox' /sys/class/dmi/id/sys_vendor 2>/dev/null; then
      _is_vbox=1
    fi
  fi

  if [ "$_is_intel" -eq 1 ]; then
    echo "GPU: Intel detected"
    _gpu_pkgs="$_gpu_pkgs xf86-video-intel linux-firmware-intel mesa-vulkan-intel"
  fi
  if [ "$_is_amd" -eq 1 ]; then
    echo "GPU: AMD/ATI detected"
    _gpu_pkgs="$_gpu_pkgs xf86-video-amdgpu xf86-video-ati linux-firmware-amdgpu linux-firmware-radeon mesa-vulkan-radeon"
  fi
  if [ "$_is_vbox" -eq 1 ]; then
    echo "GPU: VirtualBox detected"
    _gpu_pkgs="$_gpu_pkgs virtualbox-guest-additions virtualbox-guest-additions-x11 xf86-video-vboxvideo --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing"
  fi
  if [ "$_is_intel" -eq 0 ] && [ "$_is_amd" -eq 0 ] && [ "$_is_vbox" -eq 0 ]; then
    echo "GPU: no Intel/AMD/VirtualBox match, using generic modesetting/vesa"
  fi

  for _p in $_gpu_pkgs; do
    apk_try "$_p"
  done

  if [ "$_is_vbox" -eq 1 ]; then
    rc-update add virtualbox-guest-additions default || true
  fi
}

setup_plymouth_alpine() {
  THEME="simplefuture"
  THEME_DIR="/usr/share/plymouth/themes/$THEME"

  if [ -d "$THEME_DIR/.git" ]; then
    echo "updating plymouth theme $THEME ..."
    git -C "$THEME_DIR" pull --ff-only || echo "warning: theme update failed" >&2
  else
    [ ! -e "$THEME_DIR" ] || rm -rf "$THEME_DIR"
    echo "installing plymouth theme $THEME ..."
    git clone https://github.com/dgv/simplefuture "$THEME_DIR" \
      || echo "warning: could not clone plymouth theme" >&2
  fi

  if [ -f "$THEME_DIR/$THEME.plymouth" ] && command -v plymouth-set-default-theme >/dev/null 2>&1; then
    echo "setting plymouth theme to $THEME ..."
    # -R rebuilds initramfs on distros that support it; fall back gracefully.
    plymouth-set-default-theme "$THEME" -R \
      || plymouth-set-default-theme "$THEME" \
      || echo "warning: plymouth-set-default-theme failed" >&2
  elif [ -f "$THEME_DIR/$THEME.plymouth" ]; then
    echo "warning: plymouth-set-default-theme missing, theme installed but not activated" >&2
  fi

  _pconf="/etc/plymouth/plymouthd.conf"
  if [ -f "$_pconf" ]; then
    if grep -qE '^[# ]*ShowDelay=' "$_pconf"; then
      sed -i -E 's/^[# ]*ShowDelay=.*/ShowDelay=0/' "$_pconf"
    elif grep -q '^\[Daemon\]' "$_pconf"; then
      sed -i -E '/^\[Daemon\]/a ShowDelay=0' "$_pconf"
    else
      printf '[Daemon]\nShowDelay=0\n' >> "$_pconf"
    fi
  else
    echo "warning: $_pconf missing, theme may not be activated" >&2
  fi
  unset _pconf

  mkinitfs_ensure_features kms
  mkinitfs_rebuild

  if [ -f /etc/update-extlinux.conf ]; then
    extlinux_ensure_opts /etc/update-extlinux.conf quiet splash
    if command -v update-extlinux >/dev/null 2>&1; then
      update-extlinux || echo "warning: update-extlinux failed" >&2
    fi
  fi

  if [ -f /etc/kernel-hooks.d/secureboot.conf ]; then
    if ! grep -q '\bquiet\b' /etc/kernel-hooks.d/secureboot.conf; then
      echo 'note: add "quiet splash" to /etc/kernel-hooks.d/secureboot.conf cmdline, then run update-kernel' >&2
    fi
  fi

  if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    echo "available plymouth themes:"
    plymouth-set-default-theme -l || true
    _active=$(plymouth-set-default-theme 2>/dev/null || true)
    if [ "${_active:-}" = "$THEME" ]; then
      echo "plymouth theme active: $_active"
    else
      echo "warning: active plymouth theme is '${_active:-unknown}', expected '$THEME'" >&2
    fi
    unset _active
  fi
  ls -l /boot/initramfs-* 2>/dev/null || echo "note: no /boot/initramfs-* found" >&2
  echo "note: test the splash without rebooting (takes over console):"
  echo "  plymouthd --mode=boot --attach-to-session && plymouth --show-splash && sleep 8; plymouth quit"
}

case "$OS" in
    Linux*)
        if [ ! -f /etc/alpine-release ]; then
          echo "Linux branch supports Alpine Linux only (no GRUB). /etc/alpine-release not found." >&2
          exit 1
        fi

        setup_apk_repos_alpine
        apk update; setup-xorg-base mate-desktop-environment flatpak \
          mpv lightdm dconf dpkg lightdm-openrc wget \
          htop slick-greeter git papirus-icon-theme font-cantarell \
          cups cups-openrc system-config-printer librewolf starship atril eom \
          gparted networkmanager network-manager-applet networkmanager-openrc \
          abiword gnumeric fastfetch plymouth plymouth-drm plymouth-openrc-plugin \
          rclone rofi wpa_supplicant libimobiledevice-progs blueman \
          gvfs-mtp gvfs-fuse usbmuxd ifuse transmission-gtk xpad \
          dbus dbus-x11 dbus-openrc elogind elogind-openrc polkit polkit-elogind \
          xorg-server xf86-input-libinput mesa mesa-dri-gallium mesa-egl \
          pciutils doas bash bash-completion util-linux \
          lm-sensors lm-sensors-sensord lm-sensors-detect 
        
        wget http://ftp.br.debian.org/debian/pool/main/a/arc-theme/arc-theme_20221218-1_all.deb
        dpkg --force-all -i arc-theme_20221218-1_all.deb; rm arc-theme_20221218-1_all.deb
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        
        setup_gpu_alpine

        setup_plymouth_alpine

        lightdm_set_greeter "$LIGHTDM_CONF"
        rm -f /usr/share/xsessions/lightdm-xsession.desktop
        rc-update add dbus default || true
        rc-update add elogind default || true
        rc-update add lightdm default || true
        if rc-update --help >/dev/null 2>&1; then
          # best-effort extras, ignore when package absent
          rc-update add networkmanager default 2>/dev/null || true
          rc-update add cupsd default 2>/dev/null || rc-update add cups default 2>/dev/null || true
        fi
        
        if ! grep -q "permit persist ${SUSER} as root" /etc/doas.conf 2>/dev/null; then
          echo "permit persist ${SUSER} as root" >> /etc/doas.conf
        fi

        if [ -x /bin/bash ]; then
          chsh -s /bin/bash "$SUSER" || true
        fi
    ;;
    OpenBSD*)
        LIGHTDM_CONF=""
        SLICK_CONF=""
        BG_DIR="/usr/local/share/backgrounds"
        export PATH="$PATH:/usr/local/bin:/usr/local/sbin"

        pkg_add -u || echo "warning: pkg_add -u failed, continuing" >&2

        pkg_add mate mate-extras mate-dock-applet consolekit2 dbus bash \
          sudo vim git curl starship fastfetch firefox mpv cups \
          papirus-icon-theme arc-theme abiword gnumeric rclone rofi htop \
          dconf gimp transmission-gtk gparted \
          || echo "warning: some core packages failed, continuing" >&2

        for _p in librewolf solaar system-config-printer xpad usbmuxd \
          libimobiledevice ifuse jetbrains-mono; do
          pkg_try "$_p"
        done
        unset _p

        fw_update || echo "warning: fw_update failed, continuing" >&2

        if [ -x /usr/local/bin/bash ]; then
          chsh -s /usr/local/bin/bash "$SUSER" || true
        fi
        usermod -G wheel "$SUSER" || echo "warning: usermod wheel failed" >&2

        rcctl enable messagebus || true
        rcctl enable xenodm || true
        rcctl enable apmd 2>/dev/null || true
        rcctl enable cupsd 2>/dev/null || true
        rcctl start messagebus || echo "warning: messagebus start failed" >&2

        _xs="/home/$SUSER/.xsession"
        cat > "$_xs" <<'XEOF'
exec /usr/local/bin/ck-launch-session /usr/local/bin/mate-session
XEOF
        chown "$SUSER" "$_xs"
        chmod 755 "$_xs"
        unset _xs

        if ! grep -q "permit persist ${SUSER} as root" /etc/doas.conf 2>/dev/null; then
          echo "permit persist ${SUSER} as root" >> /etc/doas.conf
        fi
    ;;
    *)  echo "$OS not supported" >&2; exit 1;;
esac

mkdir -p "$BG_DIR"
if ! grep -q 'starship init bash' "/home/$SUSER/.bashrc" 2>/dev/null; then
  echo 'eval "$(starship init bash)"' >> "/home/$SUSER/.bashrc"
fi
if [ -n "${SLICK_CONF:-}" ]; then
  cat << EOF > "$SLICK_CONF"
[Greeter]
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
background=$BG_DIR/ghibli_kodamas.png

EOF
fi


rm -rf "/home/$SUSER/.config"; run_as_user 'git clone https://github.com/dgv/omatekase -b dotfiles /home/$SUSER/.config'
run_as_user 'mkdir -p ~/.local/share'
if [ -d "/home/$SUSER/.config/fonts" ]; then
  mv "/home/$SUSER/.config/fonts" "/home/$SUSER/.local/share/" || true
  run_as_user 'fc-cache -vf' || true
fi

mv "/home/$SUSER/.config/"*.png "$BG_DIR/" 2>/dev/null || true
if [ -f "/home/$SUSER/.config/dconf.backup" ]; then
  run_as_user 'dbus-launch dconf load / < ~/.config/dconf.backup' || true
fi

echo "setup done."
