#!/bin/bash

set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/lib-verify.sh

BUILD_VARIANT="${BUILD_VARIANT:-bazzite-dx-nvidia}"
echo "Building variant: ${BUILD_VARIANT}"

# Workaround for bootc-image-builder ISO depsolve bug
# https://github.com/osbuild/bootc-image-builder/issues/1188
# BIB depsolve runs in an isolated environment and can't resolve file:// GPG
# key paths from the source container image. Disable gpgcheck for affected repos
# so ISO builds can complete. Remove once BIB fixes path translation for GPG keys.
# terra-release moved its repo files from /etc/yum.repos.d to
# /usr/share/dnf5/repos.d in Fedora 45; look in both. Fail if neither has
# any: --skip-unavailable would otherwise drop every terra package silently.
shopt -s nullglob
terra_repos=(/etc/yum.repos.d/terra*.repo /usr/share/dnf5/repos.d/terra*.repo)
shopt -u nullglob
if [ "${#terra_repos[@]}" -eq 0 ]; then
    echo "ERROR: no terra repo files found" >&2
    exit 1
fi

for repo in "${terra_repos[@]}"; do
    if grep -q 'gpgkey=file://' "$repo"; then
        sed -i -e 's/^gpgcheck=1/gpgcheck=0/' -e 's/^repo_gpgcheck=1/repo_gpgcheck=0/' "$repo"
    fi
done

# Terra's metalink advertises a repomd checksum that its mirrors -- including
# the fyralabs origin -- do not always have yet. dnf rejects every mirror
# ("Usable URL not found"), the repo goes unusable, and --skip-unavailable then
# drops every terra package without failing. Go straight to the origin: no
# advertised hash, no mirror race. terra-release ships the baseurl commented
# out next to each metalink.
sed -i -e 's/^metalink=/#metalink=/' -e 's/^#baseurl=/baseurl=/' "${terra_repos[@]}"

# Terra publishes one repo per Fedora release and can lag a Fedora bump; fall
# back to the previous release while the current one does not exist. Only a
# definite 404 counts -- a network failure reports 000 and is left alone, so a
# blip cannot silently pin the wrong release.
terra_release="$(rpm -E %fedora)"
terra_status="$(curl -sSo /dev/null -w '%{http_code}' \
    "https://repos.fyralabs.com/terra${terra_release}/repodata/repomd.xml" || true)"
if [ "${terra_status}" = "404" ]; then
    echo "NOTE: terra${terra_release} is not published; falling back to terra$((terra_release - 1))"
    sed -i "s/[$]releasever/$((terra_release - 1))/g" "${terra_repos[@]}"
fi

# Mirror upstream bazzite c9ef733: lock qt6/plasma at the base image's
# versions so our own dnf installs can't drift qt6-qtbase past the Plasma/KF6
# builds linked against its private ABI (Qt_6.11_PRIVATE_API symbol node --
# the 2026-09-02 black-screen breaker). RPM deps don't catch this: the
# qt6-qtbase-private-abi provide is identical across same-version rebuilds.
# Redundant (harmless) once bazzite stable ships the same lock in the base.
dnf5 versionlock add 'qt6-*' 'plasma-*'

# Copy the contents of system_files/ into the image
cp -avf "/ctx/system_files"/. /

# Snapshot /var so we can tell what this build adds. /var is machine-local on
# bootc and is only seeded on a fresh install, so anything created here has to
# be recreated by tmpfiles.d rather than shipped in the image.
# (/var/cache and /var/log are build mounts, not part of the image.)
var_dirs() {
    find /var -mindepth 1 \
        \( -path /var/cache -o -path /var/log -o -path /var/tmp \) -prune -o \
        -type d -print | sort
}
var_dirs >/tmp/var-dirs-before

######################
# common build steps #
######################
/ctx/build-common.sh

################################
# variant-specific build steps #
################################
# Login-manager binaries for the runtime linkage check below. They differ per
# variant: the desktop variants get plasma-login-manager (Fedora's Plasma 6.7
# replacement for SDDM), while bazzite-deck is still SDDM and autologins into
# gamescope via /usr/libexec/bazzite-autologin.
LINK_CHECK_VARIANT=()

case "${BUILD_VARIANT}" in
    bazzite-deck)
        echo "Deck variant: nothing extra for now"
        # TODO: add deck's SDDM binaries here once their paths are confirmed
        # against the bazzite-deck image. Guessing them would trade this
        # variant's build being red for it being red in a less obvious way.
        ;;
    *)
        echo "Running desktop-specific build..."
        /ctx/build-desktop.sh
        LINK_CHECK_VARIANT+=(
            /usr/bin/plasmalogin
            /usr/libexec/plasmalogin-helper
            /usr/libexec/plasma-login-greeter
            /usr/bin/startplasma-login-wayland
            /usr/bin/plasma-discover
            /usr/lib64/qt6/plugins/discover/kns-backend.so
        )
        ;;
esac

############################
# runtime linkage check    #
############################
# Everything below is dlopen'd or exec'd only at login time, so a broken ABI
# ships green and fails on the user's monitor. Checked after both build legs so
# the list reflects the finished image.
#
# Add anything whose breakage is only visible at runtime. Globs work: they
# expand here, and `verify_libs_resolve` fails on a path that does not exist,
# so a rename shows up as a red build rather than a silently skipped check.
LINK_CHECK=(
    # Wallpaper plugin. This is what broke on 2026-09-03: it failed to resolve,
    # the greeter's Main.qml never instantiated, and the image booted to a
    # cursor on a black screen with no way in.
    /usr/lib64/qt6/qml/org/kde/plasma/wallpapers/image/libplasma_wallpaper_image.so

    # Screen locker. Same failure mode as the greeter, except it locks you out
    # of a session you were already using.
    /usr/libexec/kscreenlocker_greet

    # Compositor and shell.
    /usr/bin/kwin_wayland
    /usr/bin/startplasma-wayland
    /usr/bin/plasmashell
    /usr/bin/ksmserver
    /usr/bin/kded6

    # QML plugin stacks the greeter, locker and shell all dlopen.
    /usr/lib64/qt6/qml/org/kde/plasma/core/libcorebindingsplugin.so
    /usr/lib64/qt6/qml/org/kde/plasma/plasmoid/libplasmoidplugin.so
    /usr/lib64/qt6/qml/org/kde/kirigami/libKirigamiplugin.so

    # Gaming-mode session (bazzite-deck, and Steam's gamescope session on
    # desktop) does not go through plasmashell at all.
    /usr/bin/gamescope

    # Desktop apps whose breakage is loud but not lockout-grade.
    /usr/bin/systemsettings
    /usr/bin/dolphin
)

verify_libs_resolve "${LINK_CHECK[@]}" "${LINK_CHECK_VARIANT[@]}"

####################
# image hygiene    #
####################

# 1Password's scriptlets create these groups directly instead of shipping
# sysusers.d, which `bootc container lint` flags, and the build container
# allocates them from the 1000+ range. The setgid helpers (BrowserSupport,
# 1password-mcp, op) carry that numeric GID in the image, so on a real system
# they land on a human's group (1000 = eric, 1001 = kat). Setgid to your own
# group is no privilege change, the kernel leaves AT_SECURE unset, and
# BrowserSupport aborts ("running without libc's security"): the browser
# extension shows "Connection problem". Pin the GIDs and re-own the files.
# 1500-1502: the desktop app rejects a helper whose setgid group is below 1000
# ("invalid group attempted to connect", then PipeAuthError(NoCreds)), so the
# system range is out; 1500+ stays clear of the GIDs useradd hands out from 1000.
# Hosts whose /etc/group predates this keep their old numbers (systemd-sysusers
# never renumbers), so each existing host needs `groupmod -g` once to match.
# `docker` is flagged too but comes from the bazzite-dx base -- pinning a GID we
# do not own would fight upstream if they ever change it.
declare -A OP_GIDS=([onepassword]=1500 [onepassword-mcp]=1501 [onepassword-cli]=1502)
: >/usr/lib/sysusers.d/freizzite-1password.conf
for group in onepassword onepassword-mcp onepassword-cli; do
    old_gid="$(getent group "${group}" | cut -d: -f3)" || continue
    new_gid="${OP_GIDS[${group}]}"
    if [ "${old_gid}" != "${new_gid}" ]; then
        groupmod -g "${new_gid}" "${group}"
        # chgrp clears setgid; put it back on files that had it
        find /usr /opt -xdev -gid "${old_gid}" -print0 | while IFS= read -r -d '' f; do
            mode="$(stat -c %a "${f}")"
            chgrp -h "${new_gid}" "${f}"
            [ -L "${f}" ] || chmod "${mode}" "${f}"
        done
    fi
    echo "g ${group} ${new_gid}" >>/usr/lib/sysusers.d/freizzite-1password.conf
done
[ -s /usr/lib/sysusers.d/freizzite-1password.conf ] ||
    rm -f /usr/lib/sysusers.d/freizzite-1password.conf
for f in /opt/1Password/1Password-BrowserSupport /opt/1Password/1password-mcp /usr/bin/op; do
    [ -e "${f}" ] || continue
    stat -c '%a %G %n' "${f}"
    [ "$(stat -c %a "${f}")" = 2755 ] || { echo "ERROR: ${f} lost setgid" >&2; exit 1; }
done

# dnf4 state (dragged in by etckeeper-dnf/dnf-plugins-core), rpm-state and
# /run/dnf are build artifacts. `dnf clean all` does not touch these -- the
# caches it clears live on a build mount and never enter the image. Drop them
# before the /var snapshot so we do not bother recreating them at boot.
rm -rf /var/lib/dnf /var/lib/rpm-state /run/dnf

# Everything else this build added under /var gets a tmpfiles.d entry (so it is
# recreated on a fresh deploy) and is then removed from the image.
var_dirs >/tmp/var-dirs-after
comm -13 /tmp/var-dirs-before /tmp/var-dirs-after >/tmp/var-dirs-new
{
    echo "# Generated at image build time by build_files/build.sh"
    while read -r d; do
        printf 'd %s 0%s %s %s - -\n' \
            "$d" "$(stat -c '%a' "$d")" "$(stat -c '%U' "$d")" "$(stat -c '%G' "$d")"
    done </tmp/var-dirs-new
} >/usr/lib/tmpfiles.d/freizzite-var.conf

tac /tmp/var-dirs-new | while read -r d; do
    rm -rf "$d"
done

###################
# image branding  #
###################
# Last, after every dnf transaction: /usr/lib/os-release is rpm-owned.
/ctx/image-info
