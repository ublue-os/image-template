#!/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/lib-verify.sh

# Packages we want to be sure we always have latest version of
UPDATE_PACKAGES=(
    ca-certificates
)

# Common packages for all variants
# Verified installed after the transaction; a missing one fails the build.
COMMON_PACKAGES=(
    age
    below # per-cgroup resource history on disk; replay after an OOM or a hard reset
    bitstream-vera-fonts-all
    chezmoi
    etckeeper
    btrfsmaintenance # scrub/balance timers; openvox-control profile::btrfs drives them
    firacode-nerd-fonts
    firamono-nerd-fonts
    google-android-emoji-fonts
    google-roboto-fonts
    htop
    joe
    jupp
    keychain # 3.0.4-4+ gates /etc/profile.d/keychain.sh on ~/.keychainrc (rhbz#2529776)
    ms-core-tahoma-fonts
    ms-core-verdana-fonts
    nano
    powertop
    tailscale
)

# Installed the same way but not verified: nice to have, not worth a red
# build when terra lags a Fedora bump.
COMMON_PACKAGES_OPTIONAL=(
    bitstreamverasansmono-nerd-fonts
    chezmoi-bash-completion
    chezmoi-fish-completion
    droidsansmono-nerd-fonts
    noto-nerd-fonts
    robotomono-nerd-fonts
    ubuntu-nerd-fonts
    ubuntumono-nerd-fonts
    ubuntusans-nerd-fonts
)

# Common services for all variants
COMMON_SYSTEMCTL=(
    below.service
    etckeeper.timer
    tailscaled.service
)

# Enable tailscale repo
dnf5 config-manager setopt tailscale-stable.enabled=true

dnf5 -y upgrade --enable-repo=terra "${UPDATE_PACKAGES[@]}"

dnf5 -y install --skip-unavailable --skip-broken --enable-repo=terra \
    "${COMMON_PACKAGES[@]}" "${COMMON_PACKAGES_OPTIONAL[@]}"

systemctl enable "${COMMON_SYSTEMCTL[@]}"

tailscale completion fish > /etc/fish/completions/tailscale.fish
tailscale completion bash > /etc/bash_completion.d/tailscale

##############################
# OpenVox agent + g10k       #
##############################
# Masterless fleet config lives in the openvox-control repo; see openvox.md.
# Repo file ships in system_files/etc/yum.repos.d/openvox.repo.
#
# /opt is a real directory in this image (Containerfile un-symlinks it), so
# /opt/puppetlabs ships in the image proper and updates with it -- the
# Aurora/Bluefin /var/opt seed-once trap does not apply. No relocation needed.

# OpenVox publishes one repo per Fedora release and lags GA by ~6 weeks; fall
# back to the previous release while the current one does not exist, and pick
# the current one up automatically once it appears. Only a definite 404
# counts: a network blip reports 000, leaves $releasever alone, and the dnf
# install below then fails the build rather than silently pinning wrong.
openvox_release="$(rpm -E %fedora)"
openvox_status="$(curl -sSo /dev/null -w '%{http_code}' \
    "https://yum.voxpupuli.org/openvox9/fedora/${openvox_release}/$(uname -m)/repodata/repomd.xml" || true)"
if [ "${openvox_status}" = "404" ]; then
    echo "NOTE: openvox9 fedora/${openvox_release} is not published; falling back to fedora/$((openvox_release - 1))"
    sed -i "s/[$]releasever/$((openvox_release - 1))/g" /etc/yum.repos.d/openvox.repo
fi

dnf5 -y install --enable-repo=openvox* openvox-agent

# vardir defaults to /opt/puppetlabs/puppet/cache, read-only at runtime on
# bootc. server=localhost because OpenVox 9 raises ArgumentError when run as
# root with server unset, even under `puppet apply`.
printf '[main]\nserver = localhost\nvardir = /var/lib/puppetlabs/puppet/cache\npublicdir = /var/lib/puppetlabs/puppet/public\n' \
    > /etc/puppetlabs/puppet/puppet.conf

# Do NOT enable puppet.service: masterless fleet, profile::base masks it.

# Runs the vendored Ruby, so this is the standing falsifier for "does the fc44
# AIO actually execute on this Fedora release" -- it fails the build the day a
# base bump breaks the vendored toolchain.
/opt/puppetlabs/bin/puppet --version

# g10k: single static binary, deploys the Puppetfile without a gem toolchain.
G10K_VERSION=0.10.0
G10K_SHA256=a1817f7a4ee0d75be44ff8b1054b80ee016a72a42e8682d733c3ae8e33852f12
curl -fsSL -o /tmp/g10k.tar.gz \
    "https://github.com/voxpupuli/g10k/releases/download/v${G10K_VERSION}/g10k_${G10K_VERSION}_linux_amd64.tar.gz"
echo "${G10K_SHA256}  /tmp/g10k.tar.gz" | sha256sum -c -
tar -xzf /tmp/g10k.tar.gz -C /usr/bin g10k
chmod 0755 /usr/bin/g10k
rm -f /tmp/g10k.tar.gz
/usr/bin/g10k -version

# Fail the build if any requested package didn't actually get installed
verify_packages_installed "${COMMON_PACKAGES[@]}" openvox-agent
