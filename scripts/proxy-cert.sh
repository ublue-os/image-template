#!/usr/bin/env bash
# Extract the proxy-provided TLS certificate when https_proxy is configured.
set -euo pipefail

proxy_url="${https_proxy:-${HTTPS_PROXY:-}}"
output_path="${1:-cache/https-proxy-ca.pem}"
target_host="${PROXY_CERT_TARGET_HOST:-example.com}"
target_port="${PROXY_CERT_TARGET_PORT:-443}"

if [[ -z "${proxy_url}" ]]; then
    printf 'https_proxy is not set; nothing to capture.\n' >&2
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    printf 'openssl is required to capture the proxy certificate.\n' >&2
    exit 1
fi

scheme="${proxy_url%%://*}"
rest="${proxy_url#*://}"
if [[ "${scheme}" == "${rest}" ]]; then
    # No scheme detected; assume raw host[:port]
    rest="${proxy_url}"
fi

# Strip credentials if present.
if [[ "${rest}" == *"@"* ]]; then
    rest="${rest#*@}"
fi

# Drop any trailing path component.
rest="${rest%%/*}"

proxy_host="${rest%%:*}"
proxy_port="${rest##*:}"
if [[ "${proxy_port}" == "${proxy_host}" ]]; then
    if [[ "${scheme}" == "https" || "${scheme}" == "HTTPS" ]]; then
        proxy_port="443"
    else
        proxy_port="3128"
    fi
fi

if [[ -z "${proxy_host}" ]]; then
    printf 'Unable to parse https_proxy="%s". Expected host[:port].\n' "${proxy_url}" >&2
    exit 1
fi

mkdir -p "$(dirname "${output_path}")"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
tmp_output="${tmp_dir}/s_client.out"

printf 'Fetching proxy certificate via %s:%s -> %s:%s ...\n' "${proxy_host}" "${proxy_port}" "${target_host}" "${target_port}"
if ! openssl s_client \
        -proxy "${proxy_host}:${proxy_port}" \
        -connect "${target_host}:${target_port}" \
        -servername "${target_host}" \
        -showcerts \
        < /dev/null > "${tmp_output}" 2> "${tmp_dir}/s_client.err"; then
    printf 'Failed to connect via proxy. Details:\n' >&2
    cat "${tmp_dir}/s_client.err" >&2
    exit 1
fi

certificate="$(awk '
    /-----BEGIN CERTIFICATE-----/ { capture=1 }
    capture { print }
    /-----END CERTIFICATE-----/ { exit }
' "${tmp_output}")"

if [[ -z "${certificate}" ]]; then
    printf 'No certificate block found in proxy response. See %s for raw output.\n' "${tmp_output}" >&2
    exit 1
fi

printf '%s\n' "${certificate}" > "${output_path}"
chmod 0644 "${output_path}"

printf 'Wrote proxy CA to %s\n' "${output_path}"
printf 'Mount this file into your podman builds at:\n' >&2
printf '  /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem\n' >&2
printf '  /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt\n' >&2
