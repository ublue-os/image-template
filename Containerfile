## 1. BUILD ARGS
# These allow changing the produced image by passing different build args to adjust
# the source from which your image is built.
# Build args can be provided on the commandline when building locally with:
#   podman build -f Containerfile --build-arg FEDORA_VERSION=40 -t local-image

# SOURCE_IMAGE arg can be anything from ublue upstream which matches your desired version:
# See list here: https://github.com/orgs/ublue-os/packages?repo_name=main
# - "silverblue"
# - "kinoite"
# - "sericea"
# - "onyx"
# - "lazurite"
# - "vauxite"
# - "base"
#
#  "aurora", "bazzite", "bluefin" or "ucore" may also be used but have different suffixes.
ARG SOURCE_IMAGE="silverblue"

## SOURCE_SUFFIX arg should include a hyphen and the appropriate suffix name
# These examples all work for silverblue/kinoite/sericea/onyx/lazurite/vauxite/base
# - "-main"
# - "-nvidia"
# - "-asus"
# - "-asus-nvidia"
# - "-surface"
# - "-surface-nvidia"
#
# aurora, bazzite and bluefin each have unique suffixes. Please check the specific image.
# ucore has the following possible suffixes
# - stable
# - stable-nvidia
# - stable-zfs
# - stable-nvidia-zfs
# - (and the above with testing rather than stable)
ARG SOURCE_SUFFIX="-main"

## FEDORA_VERSION arg must be a version built by ublue: eg, 39 or 40
ARG FEDORA_VERSION="39"


### 2. SOURCE IMAGE
## this is a standard Containerfile FROM using the build ARGs above to select the right upstream image
FROM ghcr.io/ublue-os/${SOURCE_IMAGE}${SOURCE_SUFFIX}:${FEDORA_VERSION}


### 3. PRE-MODIFICATIONS
## This section is meant for any modifications to the image before the main modifications are made.

## this directory is needed to prevent failure with some RPM installs
RUN mkdir -p /var/lib/alternatives


### 4. MODIFICATIONS
## make modifications desired in your image and install packages here, a few examples follow

#### Install packages

# install a package from standard fedora repo or rpmfusion repo
# RPMfusion packages are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1
RUN rpm-ostree install screen
# example package from rpmfusion
#RUN rpm-ostree install vlc

#### Installation of static binaries

# static binaries can sometimes by added using a COPY directive like these below. 
COPY --from=cgr.dev/chainguard/kubectl:latest /usr/bin/kubectl /usr/bin/kubectl
#COPY --from=docker.io/docker/compose-bin:latest /docker-compose /usr/bin/docker-compose

#### Change to System Configuration Files

# modify default timeouts on system to prevent slow reboots from services that won't stop
RUN sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/user.conf && \
  sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/system.conf


### 5. POST-MODIFICATIONS
## these commands leave the image in a clean state after local modifications
RUN rm -rf /tmp/* /var/* && \
  ostree container commit && \
  mkdir -p /tmp /var/tmp && \
  chmod 1777 /tmp /var/tmp
