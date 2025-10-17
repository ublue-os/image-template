#!/usr/bin/env bash
# Extract the proxy-provided TLS certificate when https_proxy is configured.
set -euo pipefail

proxy_url="${https_proxy:-${HTTPS_PROXY:-}}"
output_path="${1:-cache/https-proxy-ca.pem}"
target_host="${PROXY_CERT_TARGET_HOST:-example.com}"
target_port="${PROXY_CERT_TARGET_PORT:-443}"

if [[ "${output_path}" == "--help" || "${output_path}" == "-h" ]]; then
    cat <<'EOF'
Usage: proxy-get-ca [OUTPUT]
Fetch the proxy signing certificate advertised by https_proxy and save it to OUTPUT (default: cache/https-proxy-ca.pem).
EOF
    exit 0
fi

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

cert_dir="${tmp_dir}/certs"
mkdir -p "${cert_dir}"

# Split output into individual PEM files.
awk -v dir="${cert_dir}" '
    /-----BEGIN CERTIFICATE-----/ {
        file_index++
        file=sprintf("%s/cert-%02d.pem", dir, file_index)
        in_cert=1
    }
    in_cert { print >> file }
    /-----END CERTIFICATE-----/ {
        close(file)
        in_cert=0
    }
' "${tmp_output}"

chain_output="${output_path%.*}.chain.pem"
if [[ "${chain_output}" == "${output_path}" ]]; then
    chain_output="${output_path}.chain.pem"
fi

> "${output_path}"
> "${chain_output}"
chmod 0644 "${output_path}" "${chain_output}"

ca_count=0
total_count=0

for pem in "${cert_dir}"/*.pem; do
    [[ -f "${pem}" ]] || continue
    total_count=$(( total_count + 1 ))
    cat "${pem}" >> "${chain_output}"
    printf '\n' >> "${chain_output}"

    if ! command -v openssl >/dev/null 2>&1; then
        continue
    fi

    if openssl x509 -in "${pem}" -noout -text 2>/dev/null | grep -q 'CA:TRUE'; then
        cat "${pem}" >> "${output_path}"
        printf '\n' >> "${output_path}"
        ca_count=$(( ca_count + 1 ))
    fi
done

if (( total_count == 0 )); then
    printf 'No certificate blocks found in proxy response. See %s for raw output.\n' "${tmp_output}" >&2
    exit 1
fi

if (( ca_count == 0 )); then
    # Fall back to the last certificate if no CA flag detected.
    fallback="$(ls -1 "${cert_dir}"/*.pem 2>/dev/null | tail -n 1)"
    if [[ -n "${fallback}" ]]; then
        printf 'Warning: no certificates with CA:TRUE detected; falling back to %s\n' "${fallback}" >&2
        cat "${fallback}" > "${output_path}"
    else
        printf 'No certificates suitable for CA trust were found.\n' >&2
        exit 1
    fi
fi

if command -v openssl >/dev/null 2>&1; then
    printf 'Captured %d certificate(s), %d flagged as CA:TRUE\n' "${total_count}" "${ca_count}"
    while read -r line; do
        printf '%s\n' "${line}"
    done < <(openssl x509 -in "${output_path}" -noout -fingerprint -sha256 -dates -subject -issuer -text |
             grep -E 'Fingerprint|notBefore|notAfter|Subject:|Issuer:|Basic Constraints|Key Usage' || true)
else
    printf 'openssl not available; skipping subject/fingerprint print\n' >&2
fi

printf 'Wrote proxy CA bundle to %s\n' "${output_path}"
printf 'Full captured chain available at %s\n' "${chain_output}"
printf 'Mount this file into your podman builds at:\n' >&2
printf '  /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem\n' >&2
printf '  /etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt\n' >&2
