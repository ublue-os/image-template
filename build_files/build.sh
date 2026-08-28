#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

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
# rm /opt && mkdir /opt

dnf5 remove -y firefox firefox-langpacks spice-vdagent

dnf5 install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
dnf5 -y copr enable tranduong1988/fcitx5-bamboo


dnf5 install -y rofi qt6ct nwg-look
                
dnf5 install -y niri noctalia

dnf5 install -y alacritty zsh fzf sysstat git stow curl wget fastfetch rsync brightnessctl pamixer xclip wl-clipboard \
                7zip-standalone 7zip unrar unzip tar \
                smartmontools 

dnf5 install -y fuse fuse-libs 

dnf5 install -y pass pinentry pinentry-qt gnupg2 xdotool wtype pwgen

dnf5 install -y vlc qbittorrent atril
# gimp

dnf5 install -y fcitx5 fcitx5-configtool fcitx5-qt fcitx5-autostart fcitx5-bamboo
    # fcitx5-bamboo from copr tranduong1988/fcitx5-bamboo

dnf5 install -y bluez bluez-libs blueman

dnf5 install -y asusctl # package from terra repo

dnf5 install -y ubuntu-family-fonts # package from copr tranduong1988/fcitx5-bamboo  

# dnf5 install -y jetbrainsmono-nerd-fonts # packages from terra repo

# curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh

dnf5 install -y @virtualization

dnf5 -y copr disable tranduong1988/fcitx5-bamboo
dnf5 remove -y terra-release


#### Example for enabling a System Unit File
systemctl disable flatpak-preinstall.service
systemctl enable podman.socket
