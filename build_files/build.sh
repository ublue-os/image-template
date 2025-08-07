#!/bin/bash

set -ouex pipefail

BASEDIR="$(dirname "$(realpath "$0")")"

### Install packages
${BASEDIR}/scripts/shell.sh # BUILD_SHELL=1 to install shell tools
${BASEDIR}/scripts/hyprland.sh # BUILD_HYPRLAND=1 to install hyprland
${BASEDIR}/scripts/laptop.sh # BUILD_LAPTOP=1 to install laptop settings
