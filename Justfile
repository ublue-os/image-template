export image_name := env("IMAGE_NAME", "image-template") # output image name, usually same as repo name, change as needed
export default_tag := env("DEFAULT_TAG", "latest")
export base_image := env("BASE_IMAGE", "ghcr.io/ublue-os/bazzite:stable")
set dotenv-load := true
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Warm all configured caches (DNF, Flatpak, containers, Homebrew)
[group('Cache')]
cache:
    #!/usr/bin/env bash
    set -euo pipefail
    just cache-packages
    just cache-flatpaks
    just cache-containers
    just cache-homebrew

# Summaries for all caches
[group('Cache')]
cache-status:
    #!/usr/bin/env bash
    set -euo pipefail
    just cache-packages-status || true
    just cache-flatpaks-status || true
    just cache-containers-status || true
    just cache-homebrew-status || true

# Pre-pull container images with podman
[group('Cache')]
cache-containers base_image=base_image:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -d cache/env.d ]]; then
        shopt -s nullglob
        for env_file in cache/env.d/*.env; do
            [[ -f "${env_file}" ]] || continue
            set -a
            source "${env_file}"
            set +a
        done
        shopt -u nullglob
    fi

    mapfile -t proxy_flags < <(scripts/podman-proxy-flags.sh)

    storage_dir="$(pwd)/cache/containers"
    mkdir -p "${storage_dir}"

    helper_image="${CONTAINERS_CACHE_IMAGE:-${base_image}}"
    images_file="${CONTAINERS_IMAGES_FILE:-our-containers.list}"

    proxy_ca=""
    if [[ -n ${HTTPS_PROXY_CA:-} && -f ${HTTPS_PROXY_CA} ]]; then
        proxy_ca="${HTTPS_PROXY_CA}"
    elif [[ -f cache/https-proxy-ca.pem ]]; then
        proxy_ca="$(pwd)/cache/https-proxy-ca.pem"
    fi
    if [[ -n "${proxy_ca}" ]]; then
        registry="${helper_image%%/*}"
        cert_root="$(pwd)/cache/certs"
        cert_dir="${cert_root}/${registry}"
        mkdir -p "${cert_dir}"
        cp "${proxy_ca}" "${cert_dir}/ca.crt"
        export CONTAINERS_CERT_PATH="${cert_root}"
        export CONTAINER_CERT_PATH="${cert_root}"
        export SSL_CERT_FILE="${proxy_ca}"
        export REQUESTS_CA_BUNDLE="${proxy_ca}"
        export CURL_CA_BUNDLE="${proxy_ca}"
        printf 'Using proxy certificate %s for registry %s\n' "${proxy_ca}" "${registry}"
        if ! podman image exists "${helper_image}" >/dev/null 2>&1; then
            podman --cert-dir "${cert_root}" image pull --tls-verify=true "${helper_image}"
        fi
    elif [[ -n ${HTTPS_PROXY_CA:-} ]]; then
        printf 'Warning: HTTPS_PROXY_CA points to %s but file not found; continuing without proxy cert override.\n' "${HTTPS_PROXY_CA}"
    fi

    env_flags=(
        --env "WORKSPACE_ROOT=/workspace"
        --env "CONTAINERS_IMAGES_FILE=${images_file}"
    )
    if [[ -n ${CONTAINERS_PULL_FLAGS:-} ]]; then
        env_flags+=(--env "CONTAINERS_PULL_FLAGS=${CONTAINERS_PULL_FLAGS}")
    fi

    podman run \
        --rm \
        --user root \
        --privileged \
        --add-host host.containers.internal:10.10.10.2 \
        --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24 \
        --workdir /workspace \
        "${proxy_flags[@]}" \
        "${env_flags[@]}" \
        --volume "$(pwd):/workspace:ro" \
        --volume "${storage_dir}:/var/lib/containers/storage:Z" \
        "${helper_image}" \
        bash -lc "/workspace/scripts/cache-containers-helper.sh"

# Inspect container cache footprint
[group('Cache')]
cache-containers-status:
    #!/usr/bin/env bash
    set -euo pipefail

    storage_dir="cache/containers"
    if [[ ! -d "${storage_dir}" ]]; then
        echo "No container cache found at ${storage_dir}" >&2
        exit 0
    fi

    if command -v du >/dev/null 2>&1; then
        du -sh "${storage_dir}"
    else
        printf '%s\n' "Cache directory: ${storage_dir}"
    fi

    layer_count=$(find "${storage_dir}/overlay" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    printf 'Overlay layers: %s\n' "${layer_count}"
    if [[ -f our-containers.list ]]; then
        echo "Configured images:"
            grep -Ev '^\s*(#|$)' our-containers.list | sed 's/^/  - /'
    fi

# Warm Homebrew bundle cache
[group('Cache')]
cache-homebrew base_image=base_image:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -d cache/env.d ]]; then
        shopt -s nullglob
        for env_file in cache/env.d/*.env; do
            [[ -f "${env_file}" ]] || continue
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
        done
        shopt -u nullglob
    fi

    mapfile -t proxy_flags < <(scripts/podman-proxy-flags.sh)

    helper_image="${HOMEBREW_CACHE_IMAGE:-${base_image}}"
    if [[ -n ${HOMEBREW_CACHE_IMAGE:-} ]]; then
        printf 'Using override HOMEBREW_CACHE_IMAGE=%s\n' "${helper_image}"
    else
        if podman run --rm --entrypoint /bin/sh "${base_image}" -c "command -v brew >/dev/null 2>&1" >/dev/null; then
            helper_image="${base_image}"
            printf 'Base image %s includes brew; using it for caching.\n' "${base_image}"
        else
            helper_image="docker.io/homebrew/brew:latest"
            printf 'Base image %s lacks brew; falling back to %s.\n' "${base_image}" "${helper_image}"
        fi
    fi

    cache_dir="$(pwd)/cache/homebrew"
    mkdir -p "${cache_dir}"
    chmod 0777 "${cache_dir}" 2>/dev/null || true

    brewfile="${HOMEBREW_BREWFILE:-our-brewfile}"
    if [[ ! -f "${brewfile}" ]]; then
        echo "Homebrew Brewfile not found at ${brewfile}" >&2
        exit 1
    fi

    proxy_ca=""
    if [[ -n ${HTTPS_PROXY_CA:-} && -f ${HTTPS_PROXY_CA} ]]; then
        proxy_ca="${HTTPS_PROXY_CA}"
    elif [[ -f cache/https-proxy-ca.pem ]]; then
        proxy_ca="$(pwd)/cache/https-proxy-ca.pem"
    fi

    container_cache="/var/cache/homebrew"

    env_flags=(
        --env "WORKSPACE_ROOT=/workspace"
        --env "HOMEBREW_CACHE_ROOT=${container_cache}"
        --env "HOMEBREW_BREWFILE=/workspace/${brewfile}"
    )

    volume_flags=(
        --volume "$(pwd):/workspace:ro"
        --volume "${cache_dir}:${container_cache}:Z"
    )

    cert_flags=()
    if [[ -n "${proxy_ca}" ]]; then
        registry="${helper_image%%/*}"
        cert_root="$(pwd)/cache/certs"
        cert_dir="${cert_root}/${registry}"
        mkdir -p "${cert_dir}"
        cp "${proxy_ca}" "${cert_dir}/ca.crt"
        export CONTAINERS_CERT_PATH="${cert_root}"
        export CONTAINER_CERT_PATH="${cert_root}"
        export SSL_CERT_FILE="${proxy_ca}"
        export REQUESTS_CA_BUNDLE="${proxy_ca}"
        export CURL_CA_BUNDLE="${proxy_ca}"
        cert_flags=(--cert-dir "${cert_root}")
        printf 'Using proxy certificate %s for registry %s\n' "${proxy_ca}" "${registry}"
        if ! podman image exists "${helper_image}" >/dev/null 2>&1; then
            podman "${cert_flags[@]}" image pull --tls-verify=true "${helper_image}"
        fi
        env_flags+=(--env "SSL_CERT_FILE=/tmp/proxy-ca.pem" --env "CURL_CA_BUNDLE=/tmp/proxy-ca.pem" --env "REQUESTS_CA_BUNDLE=/tmp/proxy-ca.pem")
        volume_flags+=(--volume "${proxy_ca}:/tmp/proxy-ca.pem:ro,Z")
    elif [[ -n ${HTTPS_PROXY_CA:-} ]]; then
        printf 'Warning: HTTPS_PROXY_CA points to %s but file not found; continuing without proxy cert override.\n' "${HTTPS_PROXY_CA}"
    fi

    podman run \
        --rm \
        --privileged \
        --add-host host.containers.internal:10.10.10.2 \
        --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24 \
        --workdir /workspace \
        "${proxy_flags[@]}" \
        "${env_flags[@]}" \
        "${volume_flags[@]}" \
        "${helper_image}" \
        bash -lc "/workspace/scripts/cache-homebrew-helper.sh"

# Inspect Homebrew cache footprint
[group('Cache')]
cache-homebrew-status:
    #!/usr/bin/env bash
    set -euo pipefail

    cache_dir="cache/homebrew"
    if [[ ! -d "${cache_dir}" ]]; then
        echo "No Homebrew cache found at ${cache_dir}" >&2
        exit 0
    fi

    if command -v du >/dev/null 2>&1; then
        du -sh "${cache_dir}"
    else
        printf '%s\n' "Cache directory: ${cache_dir}"
    fi

    if [[ -f our-brewfile ]]; then
        echo "Configured formulas:"
        awk '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*brew[[:space:]]*/ {
                if (match($0, /brew[[:space:]]+"([^"]+)"/, m)) {
                    printf("  - %s\n", m[1])
                }
            }
        ' our-brewfile
    fi

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# This Justfile recipe builds a container image using Podman.
#
# Arguments:
#   $target_image - The tag you want to apply to the image (default: $image_name).
#   $tag - The tag for the image (default: $default_tag).
#
# The script constructs the version string using the tag and the current date.
# If the git working directory is clean, it also includes the short SHA of the current HEAD.
#
# just build $target_image $tag
#
# Example usage:
#   just build aurora lts
#
# This will build an image 'aurora:lts' with DX and GDX enabled.
#

# Build the image using the specified parameters
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash

    if [[ -d cache/env.d ]]; then
        shopt -s nullglob
        for env_file in cache/env.d/*.env; do
            [[ -f "${env_file}" ]] || continue
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
        done
        shopt -u nullglob
    fi

    BUILD_ARGS=()
    PODMAN_PROXY_MODE=localhost mapfile -t podman_proxy_flags < <(scripts/podman-proxy-flags.sh)
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${base_image}")
    extra_mounts=()
    if [[ -d cache/dnf ]]; then
        extra_mounts+=(--volume "$(pwd)/cache/dnf:/var/cache/dnf:Z")
    fi
    repo_mount=""
    if [[ -d cache/dnf/yum.repos.d ]] && find cache/dnf/yum.repos.d -maxdepth 1 -name '*.repo' -print -quit | grep -q .; then
        repo_mount="$(pwd)/cache/dnf/yum.repos.d"
    elif [[ -d yum.repos.d ]] && find yum.repos.d -maxdepth 1 -name '*.repo' -print -quit | grep -q .; then
        repo_mount="$(pwd)/yum.repos.d"
    fi
    if [[ -n "${repo_mount}" ]]; then
        extra_mounts+=(--volume "${repo_mount}:/etc/yum.repos.d:ro,Z")
    fi
    dnf_conf="$(pwd)/config/dnf/cache.conf"
    if [[ -f "${dnf_conf}" ]]; then
        extra_mounts+=(--volume "${dnf_conf}:/etc/dnf/dnf.conf.d/99-cache.conf:ro,Z")
    fi
    cert_flags=()
    proxy_ca=""
    if [[ -n ${HTTPS_PROXY_CA:-} && -f ${HTTPS_PROXY_CA} ]]; then
        proxy_ca="${HTTPS_PROXY_CA}"
    elif [[ -f cache/https-proxy-ca.pem ]]; then
        proxy_ca="$(pwd)/cache/https-proxy-ca.pem"
    fi
    if [[ -n "${proxy_ca}" ]]; then
        registry="${base_image%%/*}"
        cert_root="$(pwd)/cache/certs"
        cert_dir="${cert_root}/${registry}"
        mkdir -p "${cert_dir}"
        cp "${proxy_ca}" "${cert_dir}/ca.crt"
        export CONTAINERS_CERT_PATH="${cert_root}"
        export CONTAINER_CERT_PATH="${cert_root}"
        export SSL_CERT_FILE="${proxy_ca}"
        export REQUESTS_CA_BUNDLE="${proxy_ca}"
        export CURL_CA_BUNDLE="${proxy_ca}"
        cert_flags=(--cert-dir "${cert_root}")
        printf 'Using proxy certificate %s for registry %s\n' "${proxy_ca}" "${registry}"
        if ! podman image exists "${base_image}" >/dev/null 2>&1; then
            podman image pull --tls-verify=true "${cert_flags[@]}" "${base_image}"
        fi
    fi
    if [[ -n ${https_proxy:-${HTTPS_PROXY:-}} ]]; then
        printf 'https_proxy=%s\n' "${https_proxy:-${HTTPS_PROXY}}"
    fi
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    # if we are trying to reach the host loopback, it looks different depending on podman build vs podman run environment.
    # so we just map host.containers.internal to the known address of the host when we force the cidr
    podman build \
        --add-host host.containers.internal:10.10.10.2 \
        --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24 \
        "${podman_proxy_flags[@]}" \
        "${extra_mounts[@]}" \
        "${BUILD_ARGS[@]}" \
        "${cert_flags[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Command: _rootful_load_image
# Description: This script checks if the current user is root or running under sudo. If not, it attempts to resolve the image tag using podman inspect.
#              If the image is found, it loads it into rootful podman. If the image is not found, it pulls it from the repository.
#
# Parameters:
#   $target_image - The name of the target image to be loaded or pulled.
#   $tag - The tag of the target image to be loaded or pulled. Default is 'default_tag'.
#
# Example usage:
#   _rootful_load_image my_image latest
#
# Steps:
# 1. Check if the script is already running as root or under sudo.
# 2. Check if target image is in the non-root podman container storage)
# 3. If the image is found, load it into rootful podman using podman scp.
# 4. If the image is not found, pull it from the remote repository into reootful podman.

_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/bash
    set -eoux pipefail

    # Check if already running as root or under sudo
    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    # Try to resolve the image tag using podman inspect
    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        # If the image is found, load it into rootful podman
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            # If the image ID is not found or different from user, copy the image from user podman to root podman
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        # If the image is not found, pull it from the repository
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# Converts a container image to a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (default: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_build-bib $target_image $tag $type $config: (_rootful_load_image target_image tag)
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)
    mapfile -t podman_proxy_flags < <(scripts/podman-proxy-flags.sh)

    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      "${podman_proxy_flags[@]}" \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      ${args} \
      "${target_image}:${tag}"

    mkdir -p output
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Podman builds the image from the Containerfile and creates a bootable image
# Parameters:
#   target_image: The name of the image to build (ex. localhost/fedora)
#   tag: The tag of the image to build (ex. latest)
#   type: The type of image to build (ex. qcow2, raw, iso)
#   config: The configuration file to use for the build (deafult: disk_config/disk.toml)

# Example: just _rebuild-bib localhost/fedora latest qcow2 disk_config/disk.toml
_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")

# Build a RAW virtual machine image
[group('Build Virtal Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/disk.toml")

# Build an ISO virtual machine image
[group('Build Virtal Machine Image')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "iso" "disk_config/iso.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtal Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtal Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml")

# Rebuild an ISO virtual machine image
[group('Build Virtal Machine Image')]
rebuild-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/bash
    set -eoux pipefail

    # Determine the image file based on the type
    image_file="output/${type}/disk.${type}"
    if [[ $type == iso ]]; then
        image_file="output/bootiso/install.iso"
    fi

    # Build the image if it does not exist
    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Determine an available port to use
    port=8006
    while grep -q :${port} <<< $(ss -tunalp); do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    # Set up the arguments for running the VM
    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    run_args+=(--device=/dev/kvm)
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    mapfile -t podman_proxy_flags < <(scripts/podman-proxy-flags.sh)

    # Run the VM and open the browser to connect
    (sleep 30 && xdg-open http://localhost:"$port") &
    podman run "${podman_proxy_flags[@]}" "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtal Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtal Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine from an ISO
[group('Run Virtal Machine')]
run-vm-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "iso" "disk_config/iso.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtal Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=$(echo {{ ram }}| /usr/bin/numfmt --from=iec) \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shellcheck is installed
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shellcheck on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    # Check if shfmt is installed
    if ! command -v shfmt &> /dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    # Run shfmt on all Bash scripts
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'

# Capture the HTTPS proxy certificate advertised by https_proxy
[group('Proxy')]
proxy-get-ca output="cache/https-proxy-ca.pem":
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-get-ca.sh "{{ output }}"

# Print cached proxy environment variables
[group('Proxy')]
proxy-env:
    #!/usr/bin/env bash
    set -euo pipefail
    env_dir="cache/env.d"
    if [[ ! -d "${env_dir}" ]]; then
        echo "cache/env.d not found; run just proxy-setup." >&2
        exit 0
    fi
    shopt -s nullglob
    files=("${env_dir}"/*.env)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No *.env fragments in cache/env.d; run just proxy-setup." >&2
        exit 0
    fi
    for file in "${files[@]}"; do
        cat "${file}"
    done

# Download listed RPMs into cache/dnf
[group('Cache')]
cache-packages base_image=base_image:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -d cache/env.d ]]; then
        shopt -s nullglob
        for env_file in cache/env.d/*.env; do
            [[ -f "${env_file}" ]] || continue
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
        done
        shopt -u nullglob
    fi

    scripts/cache-prepare.sh cache/dnf cache/dnf/yum.repos.d

    packages_file="our-packages.list"
    if [[ ! -f "${packages_file}" ]]; then
        echo "No packages list found at ${packages_file}. Create one (one package name per line)." >&2
        exit 1
    fi

    repo_source=""
    if [[ -d cache/dnf/yum.repos.d ]] && find cache/dnf/yum.repos.d -maxdepth 1 -name '*.repo' -print -quit | grep -q .; then
        repo_source="$(pwd)/cache/dnf/yum.repos.d"
    elif [[ -d yum.repos.d ]] && find yum.repos.d -maxdepth 1 -name '*.repo' -print -quit | grep -q .; then
        repo_source="$(pwd)/yum.repos.d"
    fi

    mapfile -t proxy_flags < <(scripts/podman-proxy-flags.sh)

    cache_dir="$(pwd)/cache/dnf"
    repo_cache_dir="$(pwd)/cache/dnf/yum.repos.d"
    dnf_conf="$(pwd)/config/dnf/cache.conf"

    mkdir -p "${repo_cache_dir}"

    volume_args=(
        --volume "${cache_dir}:/var/cache/dnf:Z"
        --volume "${repo_cache_dir}:/cache-yum-repos:Z"
        --volume "$(pwd):/workspace:ro"
    )

    if [[ -n "${repo_source}" ]]; then
        volume_args+=( --volume "${repo_source}:/etc/yum.repos.d:ro,Z" )
        printf 'Using repo definitions from %s\n' "${repo_source}"
    else
        printf 'Using repo definitions shipped in %s\n' "{{ base_image }}"
    fi

    if [[ -f "${dnf_conf}" ]]; then
        volume_args+=( --volume "${dnf_conf}:/etc/dnf/dnf.conf.d/99-cache.conf:ro,Z" )
    fi
    cert_flags=()
    if [[ -f cache/https-proxy-ca.pem ]]; then
        registry="${base_image%%/*}"
        cert_root="$(pwd)/cache/certs"
        cert_dir="${cert_root}/${registry}"
        mkdir -p "${cert_dir}"
        cp cache/https-proxy-ca.pem "${cert_dir}/ca.crt"
        export CONTAINER_CERT_PATH="${cert_root}"
        export SSL_CERT_FILE="$(pwd)/cache/https-proxy-ca.pem"
        export REQUESTS_CA_BUNDLE="$(pwd)/cache/https-proxy-ca.pem"
        export CURL_CA_BUNDLE="$(pwd)/cache/https-proxy-ca.pem"
        cert_flags=(--cert-dir "${cert_root}")
        printf 'Using proxy certificate cache/https-proxy-ca.pem for registry %s\n' "${registry}"
    fi

    podman run \
        --rm \
        --privileged \
        --add-host host.containers.internal:10.10.10.2 \
        --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24 \
        "${volume_args[@]}" \
        --workdir /workspace \
        --env "WORKSPACE_ROOT=/workspace" \
        --env "CACHES_ROOT=/var/cache" \
        --env "DNF_PACKAGES_FILE=${packages_file}" \
        "${proxy_flags[@]}" \
        "{{ base_image }}" \
        bash -lc "/workspace/scripts/dnf-cache-helper.sh"

# Warm Flatpak refs and export sideload repo
[group('Cache')]
cache-flatpaks base_image=base_image:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ -d cache/env.d ]]; then
        shopt -s nullglob
        for env_file in cache/env.d/*.env; do
            [[ -f "${env_file}" ]] || continue
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
        done
        shopt -u nullglob
    fi

    mapfile -t proxy_flags < <(scripts/podman-proxy-flags.sh)

    cache_dir="$(pwd)/cache/flatpak"
    mkdir -p "${cache_dir}"

    helper_image="${FLATPAK_CACHE_IMAGE:-${base_image}}"
    refs_file="${FLATPAK_REFS_FILE:-our-flatpaks.list}"

    proxy_ca=""
    if [[ -n ${HTTPS_PROXY_CA:-} && -f ${HTTPS_PROXY_CA} ]]; then
        proxy_ca="${HTTPS_PROXY_CA}"
    elif [[ -f cache/https-proxy-ca.pem ]]; then
        proxy_ca="$(pwd)/cache/https-proxy-ca.pem"
    fi
    if [[ -n "${proxy_ca}" ]]; then
        registry="${helper_image%%/*}"
        cert_root="$(pwd)/cache/certs"
        cert_dir="${cert_root}/${registry}"
        mkdir -p "${cert_dir}"
        cp "${proxy_ca}" "${cert_dir}/ca.crt"
        export CONTAINERS_CERT_PATH="${cert_root}"
        export CONTAINER_CERT_PATH="${cert_root}"
        export SSL_CERT_FILE="${proxy_ca}"
        export REQUESTS_CA_BUNDLE="${proxy_ca}"
        export CURL_CA_BUNDLE="${proxy_ca}"
        printf 'Using proxy certificate %s for registry %s\n' "${proxy_ca}" "${registry}"
        if ! podman image exists "${helper_image}" >/dev/null 2>&1; then
            podman --cert-dir "${cert_root}" image pull --tls-verify=true "${helper_image}"
        fi
    elif [[ -n ${HTTPS_PROXY_CA:-} ]]; then
        printf 'Warning: HTTPS_PROXY_CA points to %s but file not found; continuing without proxy cert override.\n' "${HTTPS_PROXY_CA}"
    fi

    env_flags=(
        --env "WORKSPACE_ROOT=/workspace"
        --env "FLATPAK_CACHE_ROOT=/var/cache/flatpak"
        --env "FLATPAK_REFS_FILE=${refs_file}"
    )
    if [[ -n ${FLATPAK_REMOTE:-} ]]; then
        env_flags+=(--env "FLATPAK_REMOTE=${FLATPAK_REMOTE}")
    fi
    if [[ -n ${FLATPAK_REPO_URL:-} ]]; then
        env_flags+=(--env "FLATPAK_REPO_URL=${FLATPAK_REPO_URL}")
    fi
    if [[ -n ${FLATPAK_COLLECTION_ID:-} ]]; then
        env_flags+=(--env "FLATPAK_COLLECTION_ID=${FLATPAK_COLLECTION_ID}")
    fi

    podman run \
        --rm \
        --privileged \
        --add-host host.containers.internal:10.10.10.2 \
        --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24 \
        --workdir /workspace \
        "${proxy_flags[@]}" \
        "${env_flags[@]}" \
        --volume "$(pwd):/workspace:ro" \
        --volume "${cache_dir}:/var/cache/flatpak:Z" \
        --volume "${cache_dir}:/var/lib/flatpak:Z" \
        "${helper_image}" \
        bash -lc "/workspace/scripts/cache-flatpak-helper.sh"

# Inspect Flatpak cache footprint
[group('Cache')]
cache-flatpaks-status:
    #!/usr/bin/env bash
    set -euo pipefail

    cache_dir="cache/flatpak"
    repo_dir="${cache_dir}/sideload/repo"
    if [[ ! -d "${cache_dir}" ]]; then
        echo "No Flatpak cache found at ${cache_dir}" >&2
        exit 0
    fi

    if command -v du >/dev/null 2>&1; then
        du -sh "${cache_dir}"
    else
        printf '%s\n' "Cache directory: ${cache_dir}"
    fi

    if [[ -d "${repo_dir}" ]]; then
        ref_count=$(find "${repo_dir}" -type f \( -name '*.ref' -o -name '*.commit' \) 2>/dev/null | wc -l | tr -d ' ')
        printf 'Repo directory: %s (objects: %s)\n' "${repo_dir}" "${ref_count}"
    else
        printf 'Repo directory not created yet (expected at %s)\n' "${repo_dir}"
    fi

# Diff installed RPMs against our list
[group('Cache')]
cache-packages-list target=image_name tag=default_tag base_image=base_image:
    #!/usr/bin/env bash
    set -euo pipefail

    repo_list="our-packages.list"
    cache_list="cache/our-packages.list"
    upstream_list="cache/baseimage-packages.list"
    available_list="cache/available-packages.list"

    build_http_proxy="${HTTP_PROXY:-${http_proxy:-}}"
    if [[ -d cache/env.d ]]; then
        shopt -s nullglob
        for env_file in cache/env.d/*.env; do
            [[ -f "${env_file}" ]] || continue
            set -a
            # shellcheck disable=SC1090
            source "${env_file}"
            set +a
        done
        shopt -u nullglob
    fi

    target_ref="{{ target }}:{{ tag }}"
    if ! podman image exists "${target_ref}"; then
        echo "Image ${target_ref} not found. Build it first (just build)." >&2
        exit 1
    fi

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT

    # Generate available package list from cached repo definitions if present (proxy-enabled).
    repo_snap="cache/dnf/yum.repos.d"
    if [[ -d "${repo_snap}" ]]; then
        mapfile -t repoquery_proxy_flags < <(scripts/podman-proxy-flags.sh)
        if [[ -f "${available_list}" ]]; then
            printf 'Existing available package catalog at %s (delete to refresh)\n' "${available_list}"
        else
            cert_flags=()
            proxy_ca=""
            if [[ -n ${HTTPS_PROXY_CA:-} && -f ${HTTPS_PROXY_CA} ]]; then
                proxy_ca="${HTTPS_PROXY_CA}"
            elif [[ -f cache/https-proxy-ca.pem ]]; then
                proxy_ca="$(pwd)/cache/https-proxy-ca.pem"
            fi
            if [[ -n "${proxy_ca}" ]]; then
                registry="${base_image%%/*}"
                cert_root="$(pwd)/cache/certs"
                cert_dir="${cert_root}/${registry}"
                mkdir -p "${cert_dir}"
                cp "${proxy_ca}" "${cert_dir}/ca.crt"
                export CONTAINER_CERT_PATH="${cert_root}"
                export CONTAINERS_CERT_PATH="${cert_root}"
                export SSL_CERT_FILE="${proxy_ca}"
                export REQUESTS_CA_BUNDLE="${proxy_ca}"
                export CURL_CA_BUNDLE="${proxy_ca}"
                cert_flags=(--cert-dir "${cert_root}")
                printf 'Using proxy certificate %s for registry %s\n' "${proxy_ca}" "${registry}"
                if ! podman image exists "${base_image}" >/dev/null 2>&1; then
                    podman image pull --tls-verify=true "${cert_flags[@]}" "${base_image}"
                fi
            fi
            podman run --rm \
                --add-host host.containers.internal:10.10.10.2 \
                --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24 \
                "${repoquery_proxy_flags[@]}" \
                --volume "$(pwd)/cache/dnf:/var/cache/dnf:Z" \
                --volume "$(pwd)/cache/dnf/yum.repos.d:/etc/yum.repos.d:ro,Z" \
                --volume "$(pwd)/config/dnf/cache.conf:/etc/dnf/dnf.conf.d/99-cache.conf:ro,Z" \
                "${cert_flags[@]}" \
                "{{ base_image }}" \
                bash -lc 'if command -v dnf5 >/dev/null 2>&1; then dnf5 repoquery --available --qf "%{name}\n" | sort -u; else dnf repoquery --available --qf "%{name}\n" | sort -u; fi' \
                > "${available_list}"
            printf 'Wrote available package catalog to %s\n' "${available_list}"
        fi
    else
        available_list=""
    fi

    podman run --rm "${target_ref}" rpm -qa --qf '%{NAME}\n' | sort -u > "${tmpdir}/target.txt"
    if [[ -f "${upstream_list}" ]]; then
        printf 'Existing base image package list at %s (delete to refresh)\n' "${upstream_list}"
    else
        podman run --rm "{{ base_image }}" rpm -qa --qf '%{NAME}\n' | sort -u > "${upstream_list}"
        printf 'Wrote packages already installed in {{ base_image }} to %s\n' "${upstream_list}"
    fi

    podman run --rm "${target_ref}" rpm -qa --qf '%{NAME}\n' | sort -u > "${tmpdir}/target.txt"

    comm -13 "${upstream_list}" "${tmpdir}/target.txt" > "${cache_list}"

    if [[ ! -f "${repo_list}" ]]; then
        printf '# Repo our-packages.list missing – run: cp %s %s\n' "${cache_list}" "${repo_list}"
        exit 0
    fi

    repo_clean="${tmpdir}/repo.txt"
    cache_clean="${tmpdir}/cache.txt"

    grep -Ev '^\s*(#|$)' "${repo_list}" > "${repo_clean}" || true
    cp "${cache_list}" "${cache_clean}"

    if ! diff_output="$(diff -u "${repo_clean}" "${cache_clean}" 2>/dev/null)" ; then
        printf 'Detected changes between %s and %s:\n' "${repo_list}" "${cache_list}"
        printf '%s\n' "${diff_output}"
        printf '\nUpdate %s with: cp %s %s\n' "${repo_list}" "${cache_list}" "${repo_list}"
        exit 1
    fi

    printf 'our-packages.list is up to date with %s\n' "${cache_list}"
    printf 'Wrote packages installed during Containerfile build to %s\n' "${cache_list}"

# Inspect DNF cache contents
[group('Cache')]
cache-packages-status:
    #!/usr/bin/env bash
    set -euo pipefail

    cache_root="cache/dnf"
    if [[ ! -d "${cache_root}" ]]; then
        echo "No DNF cache found at ${cache_root}" >&2
        exit 0
    fi

    shopt -s nullglob
    repo_snap="${cache_root}/yum.repos.d"
    if [[ -d "${repo_snap}" ]]; then
        echo "Enabled yum repos:"
        for repo_file in "${repo_snap}"/*.repo; do
            awk '
                /^\[/ {
                    section=$0
                    gsub(/\[|\]/, "", section)
                    enabled=""
                    base=""
                    mirror=""
                    metalink=""
                }
                /^[[:space:]]*enabled[[:space:]]*=/ {
                    gsub(/^[[:space:]]*enabled[[:space:]]*=[[:space:]]*/, "", $0)
                    gsub(/[[:space:]]*/, "", $0)
                    enabled=$0
                }
                /^[[:space:]]*baseurl[[:space:]]*=/ {
                    sub(/^[[:space:]]*baseurl[[:space:]]*=[[:space:]]*/, "", $0)
                    base=$0
                }
                /^[[:space:]]*mirrorlist[[:space:]]*=/ {
                    sub(/^[[:space:]]*mirrorlist[[:space:]]*=[[:space:]]*/, "", $0)
                    mirror=$0
                }
                /^[[:space:]]*metalink[[:space:]]*=/ {
                    sub(/^[[:space:]]*metalink[[:space:]]*=[[:space:]]*/, "", $0)
                    metalink=$0
                }
                /^$/ {
                    if (section != "" && enabled == "1") {
                        printf("  %s", section)
                        if (base != "") printf(" :: baseurl=%s", base)
                        else if (mirror != "") printf(" :: mirrorlist=%s", mirror)
                        else if (metalink != "") printf(" :: metalink=%s", metalink)
                        printf("\n")
                    }
                    section=""
                }
                END {
                    if (section != "" && enabled == "1") {
                        printf("  %s", section)
                        if (base != "") printf(" :: baseurl=%s", base)
                        else if (mirror != "") printf(" :: mirrorlist=%s", mirror)
                        else if (metalink != "") printf(" :: metalink=%s", metalink)
                        printf("\n")
                    }
                }
            ' "${repo_file}"
        done
    else
        echo "No repo snapshot found at ${repo_snap}"
    fi

    echo
    printf 'DNF cache contents under %s:\n' "${cache_root}"

    repos=("${cache_root}"/*)
    have_packages=0

    for repo_dir in "${repos[@]}"; do
        repo_basename="$(basename "${repo_dir}")"
        pkg_dir="${repo_dir}/packages"
        repo_display="${repo_basename%-*}"
        if [[ "${repo_display}" == "${repo_basename}" ]]; then
            repo_display="${repo_basename}"
        fi
        if [[ -d "${pkg_dir}" ]]; then
            count=$(find "${pkg_dir}" -maxdepth 1 -type f -name '*.rpm' | wc -l | tr -d ' ')
            printf '  %s :: (%s) %s package(s)\n' "${repo_display}" "${repo_basename}" "${count}"
            find "${pkg_dir}" -maxdepth 1 -type f -name '*.rpm' -printf '      %f\n' | head -n 10
            if (( count > 10 )); then
                printf '      … (%s more)\n' "$(( count - 10 ))"
            fi
            have_packages=1
        fi
    done

    if [[ ${have_packages} -eq 0 ]]; then
            echo "  (no cached packages yet)"
    fi
# Generate a local proxy CA
[group('Proxy')]
proxy-create-ca subject=("/CN=" + `hostname` + "/O=" + `hostname` + "/OU=" + `basename "$PWD"` + "/C=AQ"):
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-ctl.sh create-ca --subject "{{ subject }}"

# Run proxy setup (creates config, CA, environment snippet)
[group('Proxy')]
proxy-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-ctl.sh setup

# Start the local proxy container
[group('Proxy')]
proxy-start:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-ctl.sh start

# Stop the local proxy container
[group('Proxy')]
proxy-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-ctl.sh stop

# Show proxy container status
[group('Proxy')]
proxy-status:
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-ctl.sh status

# Run the proxy smoke test against a target URL
[group('Proxy')]
proxy-smoke target="https://example.com":
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/proxy-ctl.sh smoke-test --target "{{ target }}"

# Run the standard proxy bootstrap sequence
[group('Proxy')]
proxy:
    #!/usr/bin/env bash
    set -euo pipefail
    just proxy-setup
    just proxy-create-ca
    just proxy-start
