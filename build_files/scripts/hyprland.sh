#!/bin/bash

set -ouex pipefail

if [[ BUILD_HYPRLAND -eq "1" ]]; then
    dnf5 install -y \
        blueman \
        grim \
        hyprland \
        network-manager-applet \
        swaylock \
        terminator \
        tesseract \
        waybar \
        xdg-desktop-portal-hyprland
fi
