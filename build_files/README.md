# Build Files

This directory contains helper scripts used during the container image build process.

## Scripts

### build.sh
Main build script that runs during the container build. Add your customizations here:
- Install packages with `dnf5 install`
- Enable system services with `systemctl enable`
- Copy configuration files
- Run other setup commands

### nvidia-install.sh
Installs Nvidia drivers into the image. This script:
- Removes conflicting packages (nvidia-gpu-firmware, rocm packages)
- Installs Nvidia driver packages from the akmods repository
- Configures the system for Nvidia GPU support
- Sets up proper kernel module loading

**Note**: This script is automatically downloaded from ublue-os/main during the build process to ensure you always get the latest version. The version in this repository is provided as a reference.

### ghcurl
Helper script for making authenticated requests to GitHub API. This helps avoid rate limiting when downloading files from GitHub during the build process.

## Nvidia Support

To add Nvidia support to your image, see:
- [Containerfile.nvidia](../Containerfile.nvidia) - Example Containerfile with Nvidia drivers
- [README.md](../README.md#adding-nvidia-driver-support) - Full documentation on adding Nvidia support

The Nvidia implementation in this template matches the approach used by [ublue-os/bazzite](https://github.com/ublue-os/bazzite) and other Universal Blue projects.
