#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

fix_autostart_desktop() {
    local desktop_file="${1:-polkit-mate-authentication-agent-1.desktop}"
    local system_dir="/etc/xdg/autostart"

    echo ":: Fix autostart desktop"
    
    # Check if the system desktop file exists
    if [ ! -f "$system_dir/$desktop_file" ]; then
        if [ -f "/usr/share/applications/$desktop_file" ]; then
            system_dir="/usr/share/applications"
        else
            echo "Error: Desktop file '$desktop_file' not found in $system_dir or /usr/share/applications."
            return 1
        fi
    fi

    # Remove Desktop Environment restrictions (OnlyShowIn & NotShowIn)
    echo "Removing desktop environment restrictions..."
    sed -i -E '/^(OnlyShowIn|NotShowIn)=/d' "$system_dir/$desktop_file"

    echo "Success: '$desktop_file' has been configured for user autostart in $system_dir."
}

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
# dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

dnf5 install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
dnf5 -y copr enable tranduong1988/fcitx5-bamboo

dnf5 install -y sddm breeze-cursor-theme 

dnf5 install -y dunst rofi mate-polkit xdg-user-dirs \
                qt6ct arc-theme papirus-icon-theme \
                waypaper nwg-look  # packages from terra repo

dnf5 install -y niri noctalia

dnf5 install -y xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xsetroot \
                        bspwm sxhkd polybar picom dunst xsecurelock scrot ImageMagick dex-autostart xss-lock feh

dnf5 install -y alacritty neovim zsh fzf sysstat htop btop git stow eza curl wget fastfetch rsync brightnessctl pamixer xclip wl-clipboard \
                7zip-standalone 7zip unrar unzip tar \
                smartmontools \
                starship # packages from terra repo

dnf5 install -y fuse fuse-libs 

dnf5 install -y pass pinentry pinentry-qt gnupg2 xdotool wtype pwgen

dnf5 install -y thunar vlc qbittorrent gimp atril

dnf5 install -y fcitx5 fcitx5-configtool fcitx5-qt fcitx5-autostart fcitx5-bamboo
    # fcitx5-bamboo from copr tranduong1988/fcitx5-bamboo

dnf5 install -y network-manager-applet NetworkManager-openvpn NetworkManager-wifi wpa_supplicant iwlwifi-mvm-firmware

dnf5 install -y bluez bluez-libs blueman

dnf5 install -y asusctl # package from terra repo

dnf5 install -y \
            google-noto-fonts-all \
            google-noto-cjk-fonts \
            google-noto-color-emoji-fonts \
            google-noto-emoji-fonts 

dnf5 install -y ubuntu-family-fonts # package from copr tranduong1988/fcitx5-bamboo  

dnf5 install -y jetbrainsmono-nerd-fonts # packages from terra repo

curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh

dnf5 install -y @virtualization

fix_autostart_desktop "polkit-mate-authentication-agent-1.desktop"
#### Example for enabling a System Unit File
systemctl set-default graphical.target
systemctl enable sddm.service
systemctl enable brew-setup.service
systemctl enable podman.socket
