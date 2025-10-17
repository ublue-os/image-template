#!/usr/bin/env bash
# Ensure cache directories exist, preferring Btrfs subvolumes when possible.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    printf 'Usage: %s <path> [path...]\n' "$(basename "$0")" >&2
    exit 1
fi

ensure_subvolume_or_dir() {
    local path="$1"

    if [[ -d "${path}" ]]; then
        return
    fi

    local parent
    parent="$(dirname "${path}")"
    mkdir -p "${parent}"

    if command -v btrfs >/dev/null 2>&1; then
        local fs_type
        fs_type="$(stat -f -c %T "${parent}" 2>/dev/null || echo "")"
        if [[ "${fs_type}" == "btrfs" ]]; then
            if btrfs subvolume create "${path}" >/dev/null 2>&1; then
                return
            fi
        fi
    fi

    mkdir -p "${path}"
}

apply_container_label() {
    local path="$1"
    if command -v chcon >/dev/null 2>&1; then
        chcon -R system_u:object_r:container_file_t:s0 "${path}" >/dev/null 2>&1 || true
    fi
}

for path in "$@"; do
    ensure_subvolume_or_dir "${path}"
    apply_container_label "${path}"
done
