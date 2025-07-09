# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY pci_pm.rules /etc/udev/rules.d/
# Base Image
FROM  ghcr.io/ublue-os/kinoite-main:latest
#FROM ghcr.io/ublue-os/bazzite:stable

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

#RUN rpm-ostree install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
RUN rpm-ostree install distrobox just htop powertop fastfetch btop neovim figlet lolcat gparted nvtop gh cronie cronie-anacron rpmdevtools vim-common chromium vlc zsh
RUN curl -fsSL https://repo.librewolf.net/librewolf.repo > /etc/yum.repos.d/librewolf.repo &&  rpm-ostree install librewolf

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh



#RUN sed -i 's/#AutomaticUpdatePolicy.*/AutomaticUpdatePolicy=stage/' /etc/rpm-ostreed.conf && \
#    systemctl enable rpm-ostreed-automatic.timer && \
#    systemctl enable flatpak-automatic.timer && \
RUN    ostree container commit
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
