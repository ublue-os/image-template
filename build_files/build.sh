#!/bin/bash

set -ouex pipefail

shopt -s nullglob

cp -avf "/ctx/system_files"/. /

dnf5 -y config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo

dnf5 -y install fuse
dnf5 -y install python3-uv
dnf5 -y install nodejs npm
dnf5 -y install rust cargo
dnf5 -y install ruby
dnf5 -y install golang
dnf5 -y install gcc clang

dnf5 -y install toolbox podman buildah flatpak
dnf5 -y install @cosmic-desktop-environment

dnf5 -y install dnf-plugins-core
dnf5 -y config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
dnf5 -y install brave-origin
dnf5 -y install torbrowser-launcher

dnf5 -y copr enable cubewhy/jetbrains
dnf5 -y install tealdeer fastfetch micro zed jetbrains-pycharm gh git desktop-plus-bin gnome-boxes lact obs-studio mediawriter

dnf5 -y install bpftune

# dnf5 -y install steam faugus-launcher heroic-games-launcher protonplus
# dnf5 -y install "https://github.com/hydralauncher/hydra/releases/download/v4.1.6/hydralauncher-4.1.6.x86_64.rpm"
dnf5 -y install discord-openasar

wget https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.3.0/AmneziaVPN_5.0.3.0_linux_x64.run
chmod +x AmneziaVPN_5.0.3.0_linux_x64.run
export HOME=/tmp/amneziavpn
mkdir -p "$HOME"
QT_QPA_PLATFORM=offscreen ./AmneziaVPN_5.0.3.0_linux_x64.run --accept-licenses --default-answer --confirm-command install
rm -rf AmneziaVPN_5.0.3.0_linux_x64.run "$HOME"
ln -sf /opt/AmneziaVPN/bin/AmneziaVPN /usr/bin/AmneziaVPN
ln -sf /opt/AmneziaVPN/bin/AmneziaVPN /usr/sbin/AmneziaVPN

dnf5 -y install v2ray-geoip v2ray-domain-list-community xray
dnf5 -y install v2raya
wget -O /usr/bin/v2raya_core https://github.com/v2rayA/v2rayA/releases/download/v2.5.10/v2raya_core_linux_x64_2.5.10
chmod +x /usr/bin/v2raya_core
mkdir -p /usr/share /usr/local/share
ln -sf /usr/share/v2ray /usr/share/v2raya
ln -sf /usr/share/v2ray /usr/local/share/v2raya

dnf5 -y copr enable bieszczaders/kernel-cachyos-lto
dnf5 -y copr enable bieszczaders/kernel-cachyos-addons
dnf5 -y swap zram-generator-defaults cachyos-settings

dnf5 -y remove firefox
dnf5 -y autoremove

systemctl enable podman
systemctl enable cosmic-greeter
systemctl enable lactd
systemctl enable bpftune
systemctl enable AmneziaVPN
systemctl enable v2raya

# add zapret2, add proper comments to everything
