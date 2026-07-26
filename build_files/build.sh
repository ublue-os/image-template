#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# shellcheck source=/dev/null
source /ctx/lib-verify.sh

##################
### Repositories
##################

# Terra: nerd fonts, ms-core fonts, git-koji, lazyssh, ...
# (aurora does not ship the terra repo, unlike bazzite)
if [ ! -f /etc/yum.repos.d/terra.repo ]; then
    dnf5 -y install --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-release
fi

# Tailscale repo ships in the base image, but disabled
dnf5 config-manager setopt tailscale-stable.enabled=true

# COPRs
dnf5 -y copr enable atim/starship
dnf5 -y copr enable scottames/ghostty
# terra also ships ghostty; give the ghostty copr winning priority
dnf5 config-manager setopt 'copr:copr.fedorainfracloud.org:scottames:ghostty.priority=50'

# https://support.mozilla.org/en-US/kb/install-firefox-linux#w_install-firefox-rpm-package-recommended
dnf5 config-manager addrepo --id=mozilla \
    --set=baseurl=https://packages.mozilla.org/rpm/firefox \
    --set=gpgkey=https://packages.mozilla.org/rpm/firefox/signing-key.gpg \
    --set=gpgcheck=1 --set=repo_gpgcheck=0 --set=priority=10

# https://support.1password.com/install-linux/#fedora-or-red-hat-enterprise-linux
rpm --import https://downloads.1password.com/linux/keys/1password.asc
echo -e "[1password]\nname=1Password Stable Channel\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=\"https://downloads.1password.com/linux/keys/1password.asc\"" >/etc/yum.repos.d/1password.repo

##############
### Packages
##############

PACKAGES=(
    # I'd prefer non-flatpak browser so I can do 1password desktop integration easier
    firefox

    # 1Password (Integrations struggle in Flatpak install)
    1password
    1password-cli

    # Shell / prompt
    fish
    fzf
    starship

    # Terminals
    # copr build bundles everything; ghostty-* subpackages are terra-only and conflict
    ghostty
    terminator

    # Editors
    joe
    jupp
    nano

    # Dotfiles / keys
    # (completions generated below; terra's chezmoi-*-completion subpackages
    # hard-pin an exact chezmoi version and hold it back from updates)
    chezmoi
    keychain

    # /etc under version control
    etckeeper

    # Programming stuff I find handy
    code
    gh
    git-filter-repo
    git-koji # terra
    git-lfs
    git-subtree
    jq
    nodejs
    nodejs-npm
    perl-App-cpanminus
    perl-CPAN
    perltidy
    pre-commit
    ripgrep
    ruff
    ShellCheck
    shfmt
    sqlite
    sqlite-tools
    uv
    yamllint
    yq

    # Handy tools
    age
    htop
    hugo
    lazyssh # terra
    mtr
    netcat
    plocate
    powertop
    rclone
    tailscale
    thefuck
    wiremix

    # Fonts
    bitstream-vera-fonts-all
    bitstreamverasansmono-nerd-fonts
    droidsansmono-nerd-fonts
    fira-code-fonts
    firacode-nerd-fonts
    firamono-nerd-fonts
    google-android-emoji-fonts
    google-roboto-fonts
    ms-core-tahoma-fonts
    ms-core-verdana-fonts
    noto-nerd-fonts
    robotomono-nerd-fonts
    ubuntu-nerd-fonts
    ubuntumono-nerd-fonts
    ubuntusans-nerd-fonts

    # Running as a VM guest (VMware, qemu/kvm/libvirt)
    open-vm-tools
    open-vm-tools-desktop
    qemu-guest-agent
    spice-vdagent
    spice-webdavd

    # Various (de)compression tools
    7zip
    bzip2
    bzip3
    bzip3-grep
    bzip3-tools
    gzip
    ncompress
    unzip
    xz
    zip
    zstd
)

# 1Password's %post does a bare `mkdir /usr/local`, which fails on ostree
# images where /usr/local is a symlink to /var/usrlocal (and dnf5 fails the
# whole transaction on %post errors). Swap in a real directory for the
# transaction and restore the symlink afterwards.
usrlocal_target=""
if [ -L /usr/local ]; then
    usrlocal_target=$(readlink /usr/local)
    rm /usr/local
    mkdir /usr/local
fi

dnf5 -y install --skip-unavailable --skip-broken "${PACKAGES[@]}"

if [ -n "${usrlocal_target}" ]; then
    # keep the 1password launcher on the default PATH
    if [ -L /usr/local/bin/1password ]; then
        ln -sf "$(readlink /usr/local/bin/1password)" /usr/bin/1password
        rm /usr/local/bin/1password
    fi
    # warn about (and drop) anything else scriptlets left behind
    find /usr/local -mindepth 1 -not -type d | while read -r f; do
        echo "WARNING: discarding unexpected /usr/local content: $f" >&2
    done
    rm -rf /usr/local
    ln -s "${usrlocal_target}" /usr/local
fi

##############
### Services
##############

SYSTEMCTL=(
    chrony-wait.service
    etckeeper.timer
    man-db-cache-update.service
    man-db-restart-cache-update.service
    plocate-updatedb.timer
    podman.socket
    tailscaled.service
    # qemu-guest-agent/spice are udev/socket activated; only vmtoolsd needs enabling
    vmtoolsd.service
)

systemctl enable "${SYSTEMCTL[@]}"

#######################
### Shell completions
#######################

mkdir -p /etc/fish/completions /etc/bash_completion.d

tailscale completion fish >/etc/fish/completions/tailscale.fish
tailscale completion bash >/etc/bash_completion.d/tailscale

# redirect $HOME because starship and 1password/op really like to write cache files under /root/
HOME=/var/tmp starship completions fish >/etc/fish/completions/starship.fish
HOME=/var/tmp starship completions bash >/etc/bash_completion.d/starship

HOME=/var/tmp op --cache=false completion fish >/etc/fish/completions/op.fish
HOME=/var/tmp op --cache=false completion bash >/etc/bash_completion.d/op

npm completion >/etc/bash_completion.d/npm

HOME=/var/tmp chezmoi completion fish >/etc/fish/completions/chezmoi.fish
HOME=/var/tmp chezmoi completion bash >/etc/bash_completion.d/chezmoi

# Fail the build if any requested package didn't actually get installed
verify_packages_installed "${PACKAGES[@]}"
