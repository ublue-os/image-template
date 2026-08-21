#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# SovereigniteOS is a headless ucore-based image for K8s nodes, so we only
# install server-basics utilities here (no desktop/Bazzite packages).

# basic utilities
dnf5 install -y tmux htop curl git

# --- sovereignite packages ---
# dnf5 -y install containerd kubernetes kubelet kubeadm

# --- sovereignite services ---
# systemctl enable kubelet
# systemctl enable containerd

#### Example for enabling a System Unit File

systemctl enable podman.socket
