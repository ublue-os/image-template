#!/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/lib-verify.sh

# Desktop variants:
# Includes: chezmoi, starship, 1password, VSCode, and programming tools

dnf5 -y copr enable atim/starship

# https://code.visualstudio.com/docs/setup/linux#_rhel-fedora-and-centos-based-distributions
rpm --import https://packages.microsoft.com/keys/microsoft.asc &&
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo

# https://support.1password.com/install-linux/#fedora-or-red-hat-enterprise-linux
rpm --import https://downloads.1password.com/linux/keys/1password.asc
echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" > /etc/yum.repos.d/1password.repo

# https://support.mozilla.org/en-US/kb/install-firefox-linux#w_install-firefox-rpm-package-recommended
dnf5 config-manager addrepo --id=mozilla \
  --set=baseurl=https://packages.mozilla.org/rpm/firefox \
  --set=gpgkey=https://packages.mozilla.org/rpm/firefox/signing-key.gpg \
  --set=gpgcheck=1 --set=repo_gpgcheck=0 --set=priority=10

DESKTOP_PACKAGES=(
    # I'd prefer non-flatpak browser so I can do 1password desktop integration easier
    firefox

    # 1Password (Integrations struggle in Flatpak install)
    1password
    1password-cli

    # Fave prompt
    starship

    # Programming stuff I find handy
#    code
    gh
    git-filter-repo
    git-koji
    git-lfs
#    git-subtree
#    jq
    nodejs
    nodejs-npm
    perl-App-cpanminus
#    perl-CPAN
    perltidy
    pre-commit
    ruff
    ShellCheck
    shfmt
    sqlite
    sqlite-analyzer
    sqlite-debug
    sqlite-docs
    sqlite-tools
    uv
    yamllint
    yq

    # DevOps/Sysadmin tools
#    podman-machine
#    podman-tui
#    qemu
#    libvirt
#    qemu-kvm
#    virt-manager
#    edk2-ovmf
#    guestfs-tools

    # Try zed out
#    zed

    # Handy tools
#    fzf
    thefuck
    plocate
#    mtr
    netcat
#    rclone

    # Prefer "native" over flathub so Rich Presence works better
    vesktop
    discord
    discord-canary

    # Various (de)compression tools
#    bzip2
    bzip3
    bzip3-grep
    bzip3-tools
#    gzip
    ncompress
#    p7zip
#    unzip
#    xz
#    zip

    # Website thingy
    hugo
)

# Services I like to be sure are set up
DESKTOP_SYSTEMCTL=(
    chrony-wait.service
    man-db-cache-update.service
    man-db-restart-cache-update.service
    plocate-updatedb.timer
    podman.socket
)

dnf -y install --skip-unavailable --enable-repo=terra "${DESKTOP_PACKAGES[@]}"

systemctl enable "${DESKTOP_SYSTEMCTL[@]}"

# redirect $HOME because starship and 1password/op really like to write cache files under /root/
HOME=/var/tmp starship completions fish > /etc/fish/completions/starship
HOME=/var/tmp starship completions bash > /etc/bash_completion.d/starship

HOME=/var/tmp op --cache=false completion fish > /etc/fish/completions/op
HOME=/var/tmp op --cache=false completion bash > /etc/bash_completion.d/op

npm completion > /etc/bash_completion.d/npm

# Fail the build if any requested package didn't actually get installed
verify_packages_installed "${DESKTOP_PACKAGES[@]}"
