# omatekase

## motivation

I miss the old days running Lubuntu with LXDE (old one, not LXQT), a lite desktop environment on stable linux distribution, nowadays most distributions require 4GB of RAM, any GNOME/KDE plasma environment consumes ~1.5GB of RAM, LXDE/QT or IceWM became clunky/clumsy, XFCE not support tiling natively, Zorin Lite was deprecated and not support arm64, also don't wanna go full on tiling environments using sway or hyprland...

expectations
- <1GB memory footprint
- tiling support
- dark/light theme
- familiar UI/shortcuts etc (from win/macos ux)

requirements
- Debian / FreeBSD last stable release
- amd64 or aarch64 device
- 2GB of RAM 
- 6GB of disk space

## boot (simple plymouth theme)
![boot](/boot.png)

## login (lightdm using slick-greeter)
![login](/login.png)

## desktop (mate desktop environment)
![desktop](/desktop.png)

![fastfetch](/fastfetch.png)

## default apps

- Web browser: LibreWolf
- Mail Reader: Geary
- Image Viewer: Eye 
- Media Player: mpv
- Text Editor: Pluma
- Terninal: MATE Terminal
- File Manager: Caja
- Calculator: MATE Calc
- Doc Viewer: Atril
- Word Processor: AbiWord
- Spreadsheet: Gnumeric

## installation

Just install as usual and add a standard user (default uid 1000), then after first reboot run as root:

```bash
fetch -o - https://dgv.dev.br/omatekase/setup.sh | sh
```
