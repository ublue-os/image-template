#!/usr/bin/env bash
# Run inside a container to populate /var/cache/dnf based on a package list.
set -euo pipefail

LOG_PREFIX="[dnf-cache]"

log() {
    printf '%s %s\n' "${LOG_PREFIX}" "$*" >&2
}

read_list() {
    local rel="${1:-}"
    local base="${WORKSPACE_ROOT:-/workspace}"
    local abs

    if [[ -z "${rel}" ]]; then
        return
    fi

    if [[ "${rel}" == /* ]]; then
        abs="${rel}"
    else
        abs="${base}/${rel}"
    fi

    if [[ -f "${abs}" ]]; then
        grep -Ev '^\s*(#|$)' "${abs}" || true
    fi
}

cache_dir="${DNF_CACHE_DIR:-/var/cache/dnf}"
keepcache_opt="--setopt=keepcache=1"
cachedir_opt="--setopt=cachedir=${cache_dir}"

log "Refreshing repository metadata"
dnf -y ${keepcache_opt} ${cachedir_opt} makecache

mapfile -t selected_pkgs < <(read_list "${DNF_PACKAGES_FILE:-}")
pkg_count=${#selected_pkgs[@]}

if (( pkg_count == 0 )); then
    log "No packages listed; metadata refresh only"
    exit 0
fi

log "Downloading ${pkg_count} package(s)"
dnf -y ${keepcache_opt} ${cachedir_opt} install --downloadonly "${selected_pkgs[@]}"

if [[ -d /cache-yum-repos ]]; then
    src="$(realpath /etc/yum.repos.d 2>/dev/null || echo /etc/yum.repos.d)"
    dest="$(realpath /cache-yum-repos 2>/dev/null || echo /cache-yum-repos)"
    if [[ -d "${src}" ]]; then
        src_id="$(stat -c '%d:%i' "${src}" 2>/dev/null || echo "")"
        dest_id="$(stat -c '%d:%i' "${dest}" 2>/dev/null || echo "")"
        if [[ "${src_id}" != "${dest_id}" ]]; then
            log "Capturing repository definitions"
            rm -rf /cache-yum-repos/*
            cp -a /etc/yum.repos.d/. /cache-yum-repos/
        else
            log "Skipping repo snapshot (source and destination share underlying path)"
        fi
    fi
fi
