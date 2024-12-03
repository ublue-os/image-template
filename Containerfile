FROM ghcr.io/ublue-os/base-main:latest

## Nvidia users use this instead
# FROM ghcr.io/ublue-os/base-nvidia:latest


## Install a Desktop

RUN dnf5 group install kde-desktop kde-apps

## Install applications
# Anything in Fedora

RUN dnf5 install vlc

## Add COPRs
# RUN dnf copr enable (copr-author/name)

## Manage services
# systemctl enable foo.service