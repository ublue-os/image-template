#!/usr/bin/env bash

# Originally found in blue-build bling module
# https://github.com/blue-build/modules/blob/main/modules/bling/installers/1password.sh
# credit: b-

set -ouex pipefail

#### Variables

# Can be "beta" or "stable"
RELEASE_CHANNEL="${ONEPASSWORD_RELEASE_CHANNEL:-stable}"

# Must be over 1000
GID_ONEPASSWORD="${GID_ONEPASSWORD:-1500}"

# Must be over 1000
GID_ONEPASSWORDCLI="${GID_ONEPASSWORDCLI:-1600}"

echo "Installing 1Password"

# On libostree systems, /opt is a symlink to /var/opt,
# which actually only exists on the live system. /var is
# a separate mutable, stateful FS that's overlaid onto
# the ostree rootfs. Therefore we need to install it into
# /usr/lib/1Password instead, and dynamically create a
# symbolic link /opt/1Password => /usr/lib/1Password upon
# boot.

# Prepare staging directory
mkdir -p /var/opt # -p just in case it exists

# On ostree systems, /usr/local is a symlink to /var/usrlocal which
# doesn't exist at build time. The 1Password RPM scriptlet runs
# "mkdir /usr/local/..." and fails when the symlink target is missing.
if [ -L /usr/local ]; then
  mkdir -p "$(readlink /usr/local)"
fi

# Setup repo
cat << EOF > /etc/yum.repos.d/1password.repo
[1password]
name=1Password ${RELEASE_CHANNEL^} Channel
baseurl=https://downloads.1password.com/linux/rpm/${RELEASE_CHANNEL}/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

# Import signing key
rpm --import https://downloads.1password.com/linux/keys/1password.asc

# Install packages via dnf5 instead of rpm-ostree to avoid ostree
# filesystem constraints during post-install scriptlets.
dnf5 -y install 1password 1password-cli

# Clean up the yum repo (updates are baked into new images)
rm /etc/yum.repos.d/1password.repo -f

# Move 1Password to /usr/lib so it works on the ostree rootfs.
# dnf5 installs to /opt/1Password; on the live system /opt is a
# symlink to /var/opt which is mutable, so we relocate it.
mv /opt/1Password /usr/lib/1Password

# Create a symlink /usr/bin/1password => /opt/1Password/1password
rm /usr/bin/1password
ln -s /opt/1Password/1password /usr/bin/1password

#####
# The following is a bastardization of "after-install.sh"
# which is normally packaged with 1password. You can compare with
# /usr/lib/1Password/after-install.sh if you want to see.

cd /usr/lib/1Password

# chrome-sandbox requires the setuid bit to be specifically set.
# See https://github.com/electron/electron/issues/17972
chmod 4755 /usr/lib/1Password/chrome-sandbox

# Normally, after-install.sh would create a group,
# "onepassword", right about now. But if we do that during
# the ostree build it'll disappear from the running system!
# I'm going to work around that by hardcoding GIDs and
# crossing my fingers that nothing else steps on them.
# These numbers _should_ be okay under normal use, but
# if there's a more specific range that I should use here
# please submit a PR!

# Specifically, GID must be > 1000, and absolutely must not
# conflict with any real groups on the deployed system.
# Normal user group GIDs on Fedora are sequential starting
# at 1000, so let's skip ahead and set to something higher.

# BrowserSupport binary needs setgid. This gives no extra permissions to the binary.
# It only hardens it against environmental tampering.
BROWSER_SUPPORT_PATH="/usr/lib/1Password/1Password-BrowserSupport"


# Add .desktop file and icons
if [ -d /usr/share/applications ]; then
  # xdg-desktop-menu will only be available if xdg-utils is installed, which is likely but not guaranteed
  if [ -n "$(which xdg-desktop-menu)" ]; then
    xdg-desktop-menu install --mode system --novendor /usr/lib/1Password/resources/1password.desktop
    xdg-desktop-menu forceupdate
  else
    install -m0644 /usr/lib/1Password/resources/1password.desktop /usr/share/applications
  fi
fi
if [ -d /usr/share/icons ]; then
  cp -rf /usr/lib/1Password/resources/icons/* /usr/share/icons/
  # Update icon cache
  gtk-update-icon-cache -f -t /usr/share/icons/hicolor/
fi

chgrp "${GID_ONEPASSWORD}" "${BROWSER_SUPPORT_PATH}"
chmod g+s "${BROWSER_SUPPORT_PATH}"

# onepassword-cli also needs its own group and setgid, like the other helpers.
chgrp "${GID_ONEPASSWORDCLI}" /usr/bin/op
chmod g+s /usr/bin/op

# Dynamically create the required groups via sysusers.d
# and set the GID based on the files we just chgrp'd
cat >/usr/lib/sysusers.d/onepassword.conf <<EOF
g onepassword ${GID_ONEPASSWORD}
EOF
cat >/usr/lib/sysusers.d/onepassword-cli.conf <<EOF
g onepassword-cli ${GID_ONEPASSWORDCLI}
EOF

# remove the sysusers.d entries created by onepassword RPMs.
# They don't magically set the GID like we need them to.
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword.conf
rm -f /usr/lib/sysusers.d/30-rpmostree-pkg-group-onepassword-cli.conf

# Register path symlink
# We do this via tmpfiles.d so that it is created by the live system.
cat >/usr/lib/tmpfiles.d/onepassword.conf <<EOF
L  /opt/1Password  -  -  -  -  /usr/lib/1Password
EOF

