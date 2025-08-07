#!/bin/bash

set -ouex pipefail

if [[ BUILD_SHELL -eq "1" ]]; then
    dnf5 install -y \
        screen \
        git \
        git-lfs \
        qpdf \
        vim \
        htop \
        p7zip
fi
