#!/bin/bash
# Helpers for verifying build results.

# Fail the build if any requested package is not installed.
#
# We install with --skip-unavailable/--skip-broken so a renamed or missing
# package silently no-ops instead of failing dnf. This asserts, after the
# fact, that every package we asked for is actually present in the image.
#
# Uses `rpm -q --whatprovides` so both exact package names and virtual
# provides (e.g. `netcat` -> `nmap-ncat`) are honored, and presence is
# checked regardless of which layer (base image or ours) installed it.
verify_packages_installed() {
    local missing=()
    local pkg
    for pkg in "$@"; do
        if ! rpm -q --whatprovides "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: requested packages not installed: ${missing[*]}" >&2
        return 1
    fi
    echo "All ${#} requested packages verified installed."
}
