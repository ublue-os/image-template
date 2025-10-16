#!/usr/bin/env bash
# Manage the local Squid proxy lifecycle (setup/start/stop/status/smoke-test).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_ROOT="${REPO_ROOT}/cache/squid"
CONFIG_ROOT="${CACHE_ROOT}/config"
CONFIG_CA_DIR="${CONFIG_ROOT}/ca"
CONFIG_CONF_DIR="${CONFIG_ROOT}/conf.d"
CONFIG_TEMPLATE="${CONFIG_ROOT}/squid.sample.conf"
CONFIG_SETTINGS="${CONFIG_ROOT}/settings.env"
UPSTREAM_DIR="${CACHE_ROOT}/upstream"
STATE_ROOT="${CACHE_ROOT}/state"
STATE_CACHE_DIR="${STATE_ROOT}/cache"
STATE_LOG_DIR="${STATE_ROOT}/log"
LOCAL_CA_DIR="${CACHE_ROOT}/ca"
PROXY_PORT_FILE="${CONFIG_ROOT}/proxy-port"
ENV_DIR="${REPO_ROOT}/cache/env.d"
ENV_FILE="${ENV_DIR}/proxy.env"
PODMAN_BIN="${PODMAN:-podman}"
IMAGE="${PROXY_IMAGE:-satishweb/squid-ssl-proxy:latest}"
CONTAINER_NAME="${PROXY_CONTAINER_NAME:-local-template-squid}"
DEFAULT_BIND_HOST="${PROXY_BIND_HOST:-127.0.0.1}"
DEFAULT_PORT="${PROXY_PORT:-4128}"
DEFAULT_SUBJECT="${PROXY_CA_SUBJECT:-/CN=$(hostname)/O=$(hostname)/OU=$(basename "${REPO_ROOT}")/C=AQ}"

log() {
    printf '[proxy] %s\n' "$*" >&2
}

die() {
    log "Error: $*"
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "${cmd}" >/dev/null 2>&1 || die "required command '${cmd}' not found"
}

print_ca_details() {
    local pem="$1"
    if [[ ! -f "${pem}" ]]; then
        return
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        log "openssl not available; skipping CA detail print"
        return
    fi
    while read -r line; do
        log "${line}"
    done < <(openssl x509 -in "${pem}" -noout -fingerprint -sha256 -dates -subject -issuer -text |
             grep -E 'Fingerprint|notBefore|notAfter|Subject:|Issuer:|Basic Constraints|Key Usage' || true)
}


ensure_subvolume_or_dir() {
    local path="$1"
    if [[ -d "${path}" ]]; then
        return
    fi

    local parent
    parent="$(dirname "${path}")"
    mkdir -p "${parent}"

    if command -v btrfs >/dev/null 2>&1; then
        if [[ -d "${parent}" ]]; then
            local fs_type
            fs_type="$(stat -f -c %T "${parent}" 2>/dev/null || echo "")"
            if [[ "${fs_type}" == "btrfs" ]]; then
                if btrfs subvolume create "${path}" >/dev/null 2>&1; then
                    return
                fi
            fi
        fi
    fi

    mkdir -p "${path}"
}

apply_container_label() {
    local path="$1"
    if command -v chcon >/dev/null 2>&1; then
        chcon -R system_u:object_r:container_file_t:s0 "${path}" >/dev/null 2>&1 || \
            log "Non-fatal: unable to adjust SELinux label on ${path}"
    fi
}

ensure_layout() {
    ensure_subvolume_or_dir "${CACHE_ROOT}"
    mkdir -p "${CONFIG_ROOT}" "${CONFIG_CA_DIR}" "${CONFIG_CONF_DIR}" "${STATE_CACHE_DIR}" "${STATE_LOG_DIR}" "${LOCAL_CA_DIR}" "${UPSTREAM_DIR}"
    apply_container_label "${CACHE_ROOT}"
    apply_container_label "${STATE_ROOT}"
}

ensure_template() {
    if [[ -f "${CONFIG_TEMPLATE}" ]]; then
        return
    fi

    require_cmd "${PODMAN_BIN}"
    log "Extracting squid sample configuration from ${IMAGE}"
    local tmp_container="tmp-${CONTAINER_NAME}-$$"
    "${PODMAN_BIN}" rm -f "${tmp_container}" >/dev/null 2>&1 || true
    "${PODMAN_BIN}" create --name "${tmp_container}" "${IMAGE}" >/dev/null
    mkdir -p "$(dirname "${CONFIG_TEMPLATE}")"
    "${PODMAN_BIN}" cp "${tmp_container}:/templates/squid.sample.conf" "${CONFIG_TEMPLATE}.tmp"
    mv "${CONFIG_TEMPLATE}.tmp" "${CONFIG_TEMPLATE}"
    "${PODMAN_BIN}" rm -f "${tmp_container}" >/dev/null 2>&1 || true
}

generate_local_ca() {
    local subject="${1:-${DEFAULT_SUBJECT}}"
    local force="${2:-0}"

    mkdir -p "${LOCAL_CA_DIR}"

    if (( force )); then
        log "Forcing regeneration of proxy CA"
        rm -f "${LOCAL_CA_DIR}/private.pem" "${LOCAL_CA_DIR}/CA.der" "${LOCAL_CA_DIR}/CA.pem"
    fi

    if [[ -f "${LOCAL_CA_DIR}/private.pem" && -f "${LOCAL_CA_DIR}/CA.pem" ]]; then
        log "Proxy CA already present at ${LOCAL_CA_DIR}/CA.pem"
        install -m 0644 "${LOCAL_CA_DIR}/CA.pem" "${REPO_ROOT}/cache/https-proxy-ca.pem"
        print_ca_details "${LOCAL_CA_DIR}/CA.pem"
        return
    fi

    require_cmd openssl

    log "Generating local proxy CA subject: ${subject}"

    local key_tmp="${LOCAL_CA_DIR}/private.key.$$"
    local cert_tmp="${LOCAL_CA_DIR}/CA.cert.$$"
    local combined_tmp="${LOCAL_CA_DIR}/private.pem.$$"
    local der_tmp="${LOCAL_CA_DIR}/CA.der.$$"
    local pem_tmp="${LOCAL_CA_DIR}/CA.pem.$$"

    openssl req \
        -new \
        -newkey rsa:2048 \
        -sha256 \
        -days 3650 \
        -nodes \
        -x509 \
        -extensions v3_ca \
        -keyout "${key_tmp}" \
        -out "${cert_tmp}" \
        -subj "${subject}" \
        -utf8 \
        -nameopt multiline,utf8 >/dev/null 2>&1

    chmod 0600 "${key_tmp}"

    cat "${key_tmp}" "${cert_tmp}" > "${combined_tmp}"

    openssl x509 -in "${cert_tmp}" -outform DER -out "${der_tmp}" >/dev/null 2>&1
    openssl x509 -inform DER -in "${der_tmp}" -out "${pem_tmp}" >/dev/null 2>&1

    mv "${combined_tmp}" "${LOCAL_CA_DIR}/private.pem"
    mv "${der_tmp}" "${LOCAL_CA_DIR}/CA.der"
    mv "${pem_tmp}" "${LOCAL_CA_DIR}/CA.pem"
    rm -f "${key_tmp}" "${cert_tmp}"
    install -m 0644 "${LOCAL_CA_DIR}/CA.pem" "${REPO_ROOT}/cache/https-proxy-ca.pem"
    print_ca_details "${LOCAL_CA_DIR}/CA.pem"
}

port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        if ss -Htan "( sport = :${port} )" 2>/dev/null | grep -q .; then
            return 0
        fi
        if ss -Htan "( dport = :${port} )" 2>/dev/null | grep -q .; then
            return 0
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -Pi ":${port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
            return 0
        fi
    elif command -v nc >/dev/null 2>&1; then
        if nc -z -w 1 127.0.0.1 "${port}" >/dev/null 2>&1; then
            return 0
        fi
    else
        if (exec 3<>"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1; then
            exec 3>&-
            exec 3<&-
            return 0
        fi
    fi
    return 1
}

select_port() {
    if [[ -f "${PROXY_PORT_FILE}" ]]; then
        local saved
        saved="$(<"${PROXY_PORT_FILE}")"
        if [[ -n "${saved}" ]]; then
            printf '%s\n' "${saved}"
            return
        fi
    fi

    local port="${DEFAULT_PORT}"
    while port_in_use "${port}"; do
        port=$(( port + 1 ))
        if (( port > 65530 )); then
            die "unable to find available port"
        fi
    done

    printf '%s\n' "${port}" | tee "${PROXY_PORT_FILE}" >/dev/null
    printf '%s\n' "${port}"
}

write_settings() {
    local port="$1"
    local upstream_url="${2:-}"
    local upstream_ca="${3:-}"
    local ca_subject="${4:-${DEFAULT_SUBJECT}}"
    mkdir -p "$(dirname "${CONFIG_SETTINGS}")"
    cat > "${CONFIG_SETTINGS}" <<EOF
PORT=${port}
UPSTREAM_URL=${upstream_url}
UPSTREAM_CA=${upstream_ca}
CA_SUBJECT=${ca_subject}
EOF
}

write_env_file() {
    local port="$1"
    local proxy_url="http://localhost:${port}"
    local no_proxy="127.0.0.1,localhost,::1,host.containers.internal"
    mkdir -p "${ENV_DIR}"
    cat > "${ENV_FILE}" <<EOF
http_proxy=${proxy_url}
HTTP_PROXY=${proxy_url}
https_proxy=${proxy_url}
HTTPS_PROXY=${proxy_url}
no_proxy=${no_proxy}
NO_PROXY=${no_proxy}
EOF
}

store_upstream_ca() {
    local source_path="${1:-}"
    if [[ -z "${source_path}" ]]; then
        rm -f "${CONFIG_CA_DIR}/upstream.pem"
        rm -f "${UPSTREAM_DIR}/upstream.pem"
        return
    fi

    if [[ ! -f "${source_path}" ]]; then
        die "upstream CA not found at ${source_path}"
    fi

    install -m 0644 "${source_path}" "${UPSTREAM_DIR}/upstream.pem"
    install -m 0644 "${source_path}" "${CONFIG_CA_DIR}/upstream.pem"
}

write_upstream_snippet() {
    local upstream_url="${1:-}"
    local snippet="${CONFIG_CONF_DIR}/10-upstream.conf"
    if [[ -z "${upstream_url}" ]]; then
        rm -f "${snippet}"
        return
    fi

    local parsed="${upstream_url#*://}"
    local scheme="${upstream_url%%://*}"
    if [[ "${scheme}" == "${upstream_url}" ]]; then
        parsed="${upstream_url}"
        scheme="http"
    fi
    parsed="${parsed#//}"
    local host="${parsed%%:*}"
    local port="${parsed#*:}"
    if [[ "${host}" == "${port}" ]]; then
        port="3128"
    fi
    local sslflag=""
    if [[ "${scheme}" == "https" || "${scheme}" == "HTTPS" ]]; then
        sslflag=" ssl sslflags=DONT_VERIFY_PEER"
        if [[ -f "${CONFIG_CA_DIR}/upstream.pem" ]]; then
            sslflag+=" sslcafile=/etc/squid-cert/upstream.pem"
        fi
    fi
    mkdir -p "${CONFIG_CONF_DIR}"
    cat > "${snippet}" <<EOF
# Autogenerated upstream configuration
cache_peer ${host} parent ${port} 0 no-query default login=PASS${sslflag}
cache_peer_access ${host} allow all
always_direct deny all
never_direct allow all
prefer_direct off
EOF
}

load_settings() {
    if [[ -f "${CONFIG_SETTINGS}" ]]; then
        # shellcheck disable=SC1090
        source "${CONFIG_SETTINGS}"
    fi
}

setup() {
    local port_arg=""
    local upstream_url=""
    local upstream_ca=""

    while (($# > 0)); do
        case "$1" in
            --port=*)
                port_arg="${1#*=}"
                ;;
            --port)
                port_arg="${2-}"
                shift
                ;;
            --upstream=*)
                upstream_url="${1#*=}"
                ;;
            --upstream)
                upstream_url="${2-}"
                shift
                ;;
            --upstream-ca=*)
                upstream_ca="${1#*=}"
                ;;
            --upstream-ca)
                upstream_ca="${2-}"
                shift
                ;;
            --help|-h)
                cat <<'EOF'
Usage: proxy setup [--port PORT] [--upstream URL] [--upstream-ca PATH]
EOF
                return
                ;;
            *)
                die "unknown setup argument: $1"
                ;;
        esac
        shift
    done

    require_cmd "${PODMAN_BIN}"
    ensure_layout
    ensure_template
    generate_local_ca "${DEFAULT_SUBJECT}" 0

    local port
    if [[ -n "${port_arg}" ]]; then
        port="${port_arg}"
        printf '%s\n' "${port}" > "${PROXY_PORT_FILE}"
    else
        port="$(select_port)"
    fi

    write_settings "${port}" "${upstream_url}" "${upstream_ca}" "${DEFAULT_SUBJECT}"
    write_env_file "${port}"
    store_upstream_ca "${upstream_ca}"
    write_upstream_snippet "${upstream_url}"

    log "Proxy configured on port ${port}"
    if [[ -n "${upstream_url}" ]]; then
        log "Chaining to upstream proxy ${upstream_url}"
    fi
    log "Environment snippet written to ${ENV_FILE}"
}

create_ca() {
    local subject="${CA_SUBJECT:-${DEFAULT_SUBJECT}}"
    local force=0

    while (($# > 0)); do
        case "$1" in
            --force)
                force=1
                ;;
            --subject=*)
                subject="${1#*=}"
                ;;
            --subject)
                subject="${2-}"
                shift
                ;;
            --help|-h)
                cat <<'EOF'
Usage: proxy create-ca [--subject SUBJECT] [--force]
EOF
                return
                ;;
            *)
                subject="$1"
                ;;
        esac
        shift
    done

    load_settings
    local current_port="${PORT:-${DEFAULT_PORT}}"
    local current_upstream="${UPSTREAM_URL:-}"
    local current_upstream_ca="${UPSTREAM_CA:-}"

    ensure_layout
    generate_local_ca "${subject}" "${force}"
    write_settings "${current_port}" "${current_upstream}" "${current_upstream_ca}" "${subject}"
    log "Proxy CA available at ${LOCAL_CA_DIR}/CA.pem"
}

container_exists() {
    "${PODMAN_BIN}" container exists "${CONTAINER_NAME}"
}

container_running() {
    "${PODMAN_BIN}" inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q 'true'
}

start_proxy() {
    load_settings
    if [[ -z "${PORT:-}" ]]; then
        die "proxy not configured; run 'just proxy setup' first"
    fi

    ensure_layout
    ensure_template
    generate_local_ca "${DEFAULT_SUBJECT}" 0
    store_upstream_ca "${UPSTREAM_CA:-}"
    write_upstream_snippet "${UPSTREAM_URL:-}"

    if container_running; then
        log "Proxy already running on ${PORT}"
        return
    fi

    log "Starting proxy container ${CONTAINER_NAME}"
    "${PODMAN_BIN}" run \
        --detach \
        --replace \
        --name "${CONTAINER_NAME}" \
        --restart=unless-stopped \
        --userns keep-id \
        --user root \
        --publish "${DEFAULT_BIND_HOST}:${PORT}:4128" \
        --env "SQUID_PROXY_PORT=3128" \
        --env "SQUID_PROXY_SSLBUMP_PORT=4128" \
        --volume "${CONFIG_TEMPLATE}:/templates/squid.sample.conf:ro" \
        --volume "${LOCAL_CA_DIR}:/etc/squid-cert:Z" \
        --volume "${CONFIG_CONF_DIR}:/etc/squid/conf.d:Z" \
        --volume "${STATE_CACHE_DIR}:/var/cache/squid:Z" \
        --volume "${STATE_LOG_DIR}:/var/log/squid:Z" \
        "${IMAGE}" >/dev/null

    log "Proxy listening on http://${DEFAULT_BIND_HOST}:${PORT}"
    log "Proxy env hints:"
    log "  http_proxy=http://localhost:${PORT}"
    log "  https_proxy=http://localhost:${PORT}"
    log "  no_proxy=localhost,127.0.0.1,::1"
    log "  SSL_CERT_FILE=${REPO_ROOT}/cache/https-proxy-ca.pem"
}

stop_proxy() {
    if ! container_exists; then
        log "Proxy container not present"
        return
    fi

    if container_running; then
        local http_port=3128
        log "Requesting graceful shutdown via squidclient (port ${http_port})"
        if "${PODMAN_BIN}" exec "${CONTAINER_NAME}" \
            squidclient -h localhost -p "${http_port}" mgr:shutdown >/dev/null 2>&1; then
            log "squidclient shutdown request sent; waiting briefly"
            sleep 2
        else
            log "squidclient shutdown request failed; proceeding with container stop"
        fi
    fi

    log "Stopping proxy container ${CONTAINER_NAME}"
    "${PODMAN_BIN}" stop --ignore --time 10 "${CONTAINER_NAME}" >/dev/null || true
    "${PODMAN_BIN}" rm --ignore "${CONTAINER_NAME}" >/dev/null || true

    if [[ -d "${CACHE_ROOT}" ]]; then
        local cache_abs
        cache_abs=$(realpath "${CACHE_ROOT}" 2>/dev/null || echo "${CACHE_ROOT}")
        "${PODMAN_BIN}" unshare chown -R 0:0 "${cache_abs}" >/dev/null 2>&1 || true
    fi
}

status_proxy() {
    load_settings
    printf 'Image:     %s\n' "${IMAGE}"
    printf 'Container: %s\n' "${CONTAINER_NAME}"
    if container_exists; then
        local state
        state="$("${PODMAN_BIN}" inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")"
        printf 'State:     %s\n' "${state}"
        "${PODMAN_BIN}" port "${CONTAINER_NAME}" 2>/dev/null || true
    else
        printf 'State:     not created\n'
    fi
    if [[ -n "${PORT:-}" ]]; then
        printf 'Proxy URL: http://localhost:%s\n' "${PORT}"
    fi
    if [[ -n "${UPSTREAM_URL:-}" ]]; then
        printf 'Upstream:  %s\n' "${UPSTREAM_URL}"
    fi
    if [[ -f "${REPO_ROOT}/cache/https-proxy-ca.pem" ]]; then
        printf 'CA:        %s\n' "${REPO_ROOT}/cache/https-proxy-ca.pem"
    fi
    if [[ -n "${PORT:-}" ]]; then
        printf 'Env Hints:\n'
        printf '  http_proxy=http://localhost:%s\n' "${PORT}"
        printf '  https_proxy=http://localhost:%s\n' "${PORT}"
        printf '  no_proxy=localhost,127.0.0.1,::1\n'
        if [[ -f "${REPO_ROOT}/cache/https-proxy-ca.pem" ]]; then
            printf '  SSL_CERT_FILE=%s\n' "${REPO_ROOT}/cache/https-proxy-ca.pem"
        fi
    fi
}

smoke_test() {
    load_settings
    if [[ -z "${PORT:-}" ]]; then
        die "proxy not configured; run 'just proxy setup' first"
    fi
    local target="https://example.com"
    while (($# > 0)); do
        case "$1" in
            --target=*)
                target="${1#*=}"
                ;;
            --target)
                target="${2-}"
                shift
                ;;
            --help|-h)
                cat <<'EOF'
Usage: proxy smoke-test [--target URL]
EOF
                return
                ;;
            *)
                die "unknown smoke-test argument: $1"
                ;;
        esac
        shift
    done

    require_cmd curl
    local ca_path="${REPO_ROOT}/cache/https-proxy-ca.pem"
    if [[ ! -f "${ca_path}" ]]; then
        die "proxy CA not found at ${ca_path}; run 'just proxy get-ca'"
    fi
    print_ca_details "${ca_path}"

    log "Probing ${target} via proxy on localhost:${PORT}"
    if curl \
            --silent \
            --show-error \
            --fail \
            --head \
            --proxy "http://localhost:${PORT}" \
            --cacert "${ca_path}" \
            --max-time 20 \
            "${target}" >/dev/null; then
        log "Proxy smoke-test succeeded"
    else
        log "smoke-test failed; attempting to retrieve upstream certificate for diagnostics"
        if command -v openssl >/dev/null 2>&1; then
            openssl s_client \
                -servername "${target#https://}" \
                -showcerts \
                -connect "${target#https://}:443" </dev/null 2>/dev/null |
                awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' |
                tee "${REPO_ROOT}/cache/squid/ca/upstream-latest.pem" >/dev/null
            if [[ -s "${REPO_ROOT}/cache/squid/ca/upstream-latest.pem" ]]; then
                log "Captured upstream certificate to cache/squid/ca/upstream-latest.pem"
                print_ca_details "${REPO_ROOT}/cache/squid/ca/upstream-latest.pem"
            else
                log "Unable to capture upstream certificate"
            fi
        else
            log "openssl not available; cannot fetch upstream certificate for diagnostics"
        fi
        return 1
    fi
}

usage() {
    cat <<'EOF'
Usage: proxy-ctl.sh <command>
Commands:
  setup        Prepare configuration, CA material, and environment snippet.
  create-ca    Generate or refresh the local proxy CA bundle.
  start        Start the Squid proxy container.
  stop         Stop and remove the Squid proxy container.
  status       Show proxy container status and configuration summary.
  smoke-test   Verify proxy connectivity with a quick curl request.
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "${cmd}" in
        setup)
            setup "$@"
            ;;
        create-ca)
            create_ca "$@"
            ;;
        start)
            start_proxy "$@"
            ;;
        stop)
            stop_proxy "$@"
            ;;
        status)
            status_proxy "$@"
            ;;
        smoke-test)
            smoke_test "$@"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
