#!/usr/bin/env bash
# Emit podman flags/env vars for proxy-aware builds. Prints nothing when no proxy is configured.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

raw_http_proxy="${http_proxy:-${HTTP_PROXY:-}}"
raw_https_proxy="${https_proxy:-${HTTPS_PROXY:-}}"
raw_no_proxy="${no_proxy:-${NO_PROXY:-}}"

sanitize_proxy() {
    local value="${1:-}"
    [[ -z "${value}" ]] && return 0

    local scheme="" remainder="${value}" credentials="" host="" port=""

    if [[ "${remainder}" == *"://"* ]]; then
        scheme="${remainder%%://*}"
        remainder="${remainder#*://}"
    fi

    if [[ "${remainder}" == *"@"* ]]; then
        credentials="${remainder%%@*}"
        remainder="${remainder#*@}"
    fi

    remainder="${remainder%%/*}"

    host="${remainder%%:*}"
    port="${remainder#*:}"
    if [[ "${port}" == "${host}" ]]; then
        port=""
    fi

    if [[ -z "${port}" ]]; then
        if [[ "${scheme}" == "https" || "${scheme}" == "HTTPS" ]]; then
            port="443"
        else
            port="3128"
        fi
    fi

    if [[ "${host}" == "127.0.0.1" || "${host}" == "localhost" || "${host}" == "0.0.0.0" ]]; then
        host="host.containers.internal"
    fi

    local rebuilt=""
    if [[ -n "${scheme}" ]]; then
        rebuilt+="${scheme}://"
    fi
    if [[ -n "${credentials}" ]]; then
        rebuilt+="${credentials}@"
    fi
    rebuilt+="${host}"
    if [[ -n "${port}" ]]; then
        rebuilt+=":${port}"
    fi

    printf '%s' "${rebuilt}"
}

augment_no_proxy() {
    local value="${1:-}"
    if [[ -z "${value}" ]]; then
        printf 'host.containers.internal'
        return 0
    fi
    case ",${value}," in
        *,host.containers.internal,*) printf '%s' "${value}" ;;
        *) printf '%s,host.containers.internal' "${value}" ;;
    esac
}

host_http_proxy="$(sanitize_proxy "${raw_http_proxy}")"
host_https_proxy="$(sanitize_proxy "${raw_https_proxy}")"
host_no_proxy="$(augment_no_proxy "${raw_no_proxy}")"

proxy_ca_hint="${repo_root}/cache/https-proxy-ca.pem"
proxy_ca="${HTTPS_PROXY_CA:-}"
if [[ -z "${proxy_ca}" && -f "${proxy_ca_hint}" ]]; then
    proxy_ca="${proxy_ca_hint}"
fi

if [[ -n "${raw_https_proxy}" ]]; then
    if [[ -z "${proxy_ca}" ]]; then
        printf 'https_proxy=%s detected but no proxy CA found.\n' "${raw_https_proxy}" >&2
        printf 'Run `just proxy-cert` to capture it into %s before proceeding.\n' "${proxy_ca_hint}" >&2
        exit 1
    fi
    if [[ ! -f "${proxy_ca}" ]]; then
        printf 'Proxy CA file not found at %s. Run `just proxy-cert` to refresh it.\n' "${proxy_ca}" >&2
        exit 1
    fi
fi

flags=()

if [[ -n "${host_http_proxy}" ]]; then
    flags+=(--env "http_proxy=${host_http_proxy}" --env "HTTP_PROXY=${host_http_proxy}")
fi

if [[ -n "${host_https_proxy}" ]]; then
    flags+=(--env "https_proxy=${host_https_proxy}" --env "HTTPS_PROXY=${host_https_proxy}")
fi

if [[ -n "${host_no_proxy}" ]]; then
    flags+=(--env "no_proxy=${host_no_proxy}" --env "NO_PROXY=${host_no_proxy}")
fi

if [[ -n "${proxy_ca}" ]]; then
    proxy_ca_abs="$(cd "$(dirname "${proxy_ca}")" && pwd)/$(basename "${proxy_ca}")"
    flags+=(--env "CURL_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem")
    flags+=(--env "SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem")
    flags+=(--env "REQUESTS_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem")
    flags+=(--volume "${proxy_ca_abs}:/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem:ro,z")
    flags+=(--volume "${proxy_ca_abs}:/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt:ro,z")
fi

if [[ "${#flags[@]}" -gt 0 ]]; then
    printf '%s\n' "${flags[@]}"
fi
