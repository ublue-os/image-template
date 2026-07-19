#!/bin/bash

set -ouex pipefail

BUILD_VARIANT="${BUILD_VARIANT:-bazzite-nvidia-open}"
echo "Building variant: ${BUILD_VARIANT}"

# Workaround for bootc-image-builder ISO depsolve bug
# https://github.com/osbuild/bootc-image-builder/issues/1188
# BIB depsolve runs in an isolated environment and can't resolve file:// GPG
# key paths from the source container image. Disable gpgcheck for affected repos
# so ISO builds can complete. Remove once BIB fixes path translation for GPG keys.
for repo in /etc/yum.repos.d/terra*.repo; do
    if [ -f "$repo" ] && grep -q 'gpgkey=file://' "$repo"; then
        sed -i -e 's/^gpgcheck=1/gpgcheck=0/' -e 's/^repo_gpgcheck=1/repo_gpgcheck=0/' "$repo"
    fi
done

# Copy the contents of system_files/ into the image
cp -avf "/ctx/system_files"/. /

######################
# common build steps #
######################
/ctx/build-common.sh

################################
# variant-specific build steps #
################################
case "${BUILD_VARIANT}" in
    bazzite-deck)
        echo "Running deck-specific build..."
        /ctx/build-deck.sh
        ;;
    *)
        echo "Running desktop-specific build..."
        /ctx/build-desktop.sh
        ;;
esac
