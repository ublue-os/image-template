#!/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/lib-verify.sh

# Common packages for all variants
COMMON_PACKAGES=(
    age
    bitstream-vera-fonts-all
    bitstreamverasansmono-nerd-fonts
    chezmoi
    chezmoi-bash-completion
    chezmoi-fish-completion
    droidsansmono-nerd-fonts
    easyeffects
    etckeeper
    firacode-nerd-fonts
    firamono-nerd-fonts
    google-android-emoji-fonts
    google-noto-emoji-vf-fonts
    google-roboto-fonts
    htop
    joe
    jupp
    keychain
    ms-core-tahoma-fonts
    ms-core-verdana-fonts
    nano
    noto-nerd-fonts
    powertop
    robotomono-nerd-fonts
    tailscale
    ubuntu-nerd-fonts
    ubuntumono-nerd-fonts
    ubuntusans-nerd-fonts
    wiremix
)

# Common services for all variants
COMMON_SYSTEMCTL=(
    etckeeper.timer
    tailscaled.service
)

# Enable tailscale repo
dnf5 config-manager setopt tailscale-stable.enabled=true

dnf5 -y install --skip-unavailable --skip-broken --enable-repo=terra "${COMMON_PACKAGES[@]}"

systemctl enable "${COMMON_SYSTEMCTL[@]}"

tailscale completion fish > /etc/fish/completions/tailscale
tailscale completion bash > /etc/bash_completion.d/tailscale

# Fail the build if any requested package didn't actually get installed
verify_packages_installed "${COMMON_PACKAGES[@]}"
