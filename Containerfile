### 1. BUILD ARGS
## These enable the produced image to be different by passing different build args.
## They are provided on the commandline when building in a terminal, but the github
## workflow provides them when building in Github Actions. Changes to the workflow
## build.yml will override changes here.

## SOURCE_IMAGE arg can be anything from ublue upstream: silverblue, kinoite, sericea, base
## See list here: https://github.com/orgs/ublue-os/packages?repo_name=main
ARG SOURCE_IMAGE="silverblue"

## SOURCE_SUFFIX arg should be "main", nvidia users should use "nvidia"
ARG SOURCE_SUFFIX="main"

## FEDORA_VERSION arg must be a version built by ublue: 37 or 38 as of today
ARG FEDORA_VERSION="39"

## NVIDIA_VERSION should only be changed if the user needs a specific nvidia driver version
## This will depend on your hardware and the version of the driver that supports it.
## if needing driver 470, this should be set to "-470". It is important to include the hyphen
ARG NVIDIA_VERSION=""


### 2. SOURCE IMAGE
## this is a standard Containerfile FROM using the build ARGs above to select the right upstream image
FROM ghcr.io/ublue-os/${SOURCE_IMAGE}-${SOURCE_SUFFIX}:${FEDORA_VERSION}${NVIDIA_VERSION}


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
# exmaple package from rpmfusion
RUN rpm-ostree install vlc

#### Installation of static binaries

# static binaries can sometimes by added using a COPY directive like these below. 
COPY --from=cgr.dev/chainguard/kubectl:latest /usr/bin/kubectl /usr/bin/kubectl
# COPY --from=docker.io/docker/compose-bin:latest /docker-compose /usr/bin/docker-compose

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
