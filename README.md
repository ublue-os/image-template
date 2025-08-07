# Custom Bazzite Image with KDE Plasma & Hyprland

This repository contains a set of scripts to install all the prerequisites for a custom [bazzite](https://bazzite.gg/) image to run on my Razer Blade 14 laptop.
It's organised in a configurable way so that it should be simple to modify it to create your own image.

This repository is not meant to create some new "base" image that others should build upon.
Please see the excellent [upstream repo](https://github.com/ublue-os/image-template) if you want to create your own custom bazzite image.

This repository is meant to be a template for building your own custom [bootc](https://github.com/bootc-dev/bootc) image. This template is the recommended way to make customizations to any image published by the Universal Blue Project.

## Use This Image

The recommended way to install this image is to rebase from another [Fedora Atomic](https://fedoraproject.org/atomic-desktops/) installation (e.g., bazzite KDE).
This can be done as follows (sources:
[1](https://bazzite.gg/#image-picker),
[2](https://docs.bazzite.gg/Installing_and_Managing_Software/Updates_Rollbacks_and_Rebasing/rebase_guide/)):

```bash
rpm-ostree reset
rpm-ostree rebase ostree-unverified-registry:ghcr.io/nickfraser/bazzite-kdeland-razer:latest
ujust _install-system-flatpaks # Optional, but recommended
```

## Environment Variables

In order to control what packages are installed you can modify the following variables:

 - `BUILD_FROM_IMAGE=<base_image>` the base image, default: `ghcr.io/ublue-os/bazzite-nvidia-open:stable`
 - `BUILD_SHELL=<0|1>` add various commandline utilities, default=1
 - `BUILD_HYPRLAND=<0|1>` add [hyprland](https://hypr.land/) and some other utils to get my preferred configuration running, default=1
 - `BUILD_LAPTOP=<0|1>` add various features which only makes sense on laptops, default=1
 - `BUILD_LAPTOP_CLAMSHELL=<0|1>` do not suspend when laptop lid is closed when in SDDM, default=1
 - `BUILD_LAPTOP_OPENRAZER=<0|1>` install open-razer utilities, default=0
 - `BUILD_CITRIX=<0|1>` install Citrix Workspace, default=0

## Build Locally

In order to debug various issues, `build-local.sh` is setup to build the image with everything enabled.

## build.sh

The [build.sh](./build_files/build.sh) file is called from your Containerfile.
It is the entry-point for installing all other applications.

## build.yml

The [build.yml](./.github/workflows/build.yml) is configured to build the image with the [defaults specified](#environment-variables) and publishes it to the Github Container Registry (GHCR).

## Post-Installation Steps

I still need to install:

 - [ ] OpenRazer
 - [ ] Citrix

## Acknowledgements

 - [bootc](https://github.com/bootc-dev/bootc) - the underlying technology
 - [bazzite](https://bazzite.gg/) - the base image
 - bazzite's [image-template](https://github.com/ublue-os/image-template) - the excellent upstream that allowed me to put together a PoC in an afternoon

## Community Examples

These are images derived from this template (or similar enough to this template). Reference them when building your image!

- [m2Giles' OS](https://github.com/m2giles/m2os)
- [bOS](https://github.com/bsherman/bos)
- [Homer](https://github.com/bketelsen/homer/)
- [Amy OS](https://github.com/astrovm/amyos)
- [VeneOS](https://github.com/Venefilyn/veneos)
