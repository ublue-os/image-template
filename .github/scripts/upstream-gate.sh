#!/usr/bin/env bash
# Decide whether one build target actually needs rebuilding.
#
# Compares the digest of the upstream base image against the digest recorded on
# the image we last published, plus a handful of other signals. Prints a single
# JSON object on stdout:
#
#   {"build":true,"reason":"...","base_digest":"sha256:...","stream_absent":false}
#
# Fails OPEN: anything we cannot determine results in build=true, so a broken
# gate degrades to "builds like it used to" rather than silently never building
# again. The one exception is stream_absent (upstream tag genuinely 404s), where
# there is nothing to build from at all.
#
# Inputs, all via the environment:
#   BASE_REF            upstream ref to watch, e.g. ghcr.io/ublue-os/aurora-dx:stable
#   PUBLISHED_REF       our published ref,     e.g. ghcr.io/eric-eisenhart/freirora:latest
#   LABEL_NS            label namespace,       e.g. io.github.freiheit.build
#   MAX_AGE_HOURS       rebuild once the published image is older than this
#   MIN_INTERVAL_HOURS  never rebuild while the published image is younger than this
#   FORCE               "true" bypasses every content check below
#   FORCE_REASON        human-readable explanation for FORCE
#   HEAD_SHA            git commit being built
#   REG_USER, REG_PASS  credentials for PUBLISHED_REF (upstream is read anonymously,
#                       so a repo-scoped token is never sent to a foreign namespace)

set -uo pipefail

: "${BASE_REF:?BASE_REF is required}"
: "${PUBLISHED_REF:?PUBLISHED_REF is required}"
LABEL_NS="${LABEL_NS:-io.github.freiheit.build}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-168}"
MIN_INTERVAL_HOURS="${MIN_INTERVAL_HOURS:-0}"
FORCE="${FORCE:-false}"
FORCE_REASON="${FORCE_REASON:-forced}"
HEAD_SHA="${HEAD_SHA:-}"
REG_USER="${REG_USER:-}"
REG_PASS="${REG_PASS:-}"

emit() {
    # emit <build-bool> <reason> [base-digest] [stream-absent-bool]
    jq -cn \
        --argjson build "$1" \
        --arg reason "$2" \
        --arg base_digest "${3:-}" \
        --argjson stream_absent "${4:-false}" \
        '{build: $build, reason: $reason, base_digest: $base_digest, stream_absent: $stream_absent}'
    exit 0
}

# A genuine "this tag does not exist" as opposed to a transient registry fault.
# The two must not be conflated: 404 means drop the target, anything else means
# we simply do not know and must not let that masquerade as "nothing changed".
is_not_found() {
    grep -qiE 'manifest unknown|name unknown|not found|no such host|repository name not known' <<<"$1"
}

hours_since() {
    # hours_since <rfc3339-timestamp> -> whole hours, or empty if unparseable
    local ts parsed now
    ts="$1"
    [[ -z "${ts}" ]] && return 0
    parsed="$(date -u -d "${ts}" +%s 2>/dev/null)" || return 0
    now="$(date -u +%s)"
    echo $(((now - parsed) / 3600))
}

# ---------------------------------------------------------------------------
# Upstream base image
# ---------------------------------------------------------------------------
upstream_err=""
if ! upstream="$(skopeo inspect --no-tags "docker://${BASE_REF}" 2>&1)"; then
    upstream_err="$(tr -s '[:space:]' ' ' <<<"${upstream}")"
    upstream=""
fi

base_digest=""
base_created=""
if [[ -n "${upstream}" ]]; then
    base_digest="$(jq -r '.Digest // ""' <<<"${upstream}" 2>/dev/null)"
    base_created="$(jq -r '.Labels["org.opencontainers.image.created"] // .Created // ""' <<<"${upstream}" 2>/dev/null)"
fi

if [[ -z "${base_digest}" ]] && is_not_found "${upstream_err}"; then
    # Upstream does not publish this tag (e.g. bazzite-dx-nvidia has no :testing).
    # There is nothing to build from, so the caller should drop this target.
    emit false "upstream ${BASE_REF} does not exist" "" true
fi

# A transient upstream failure leaves base_digest empty. We deliberately keep
# going: the commit and max-age signals below are still meaningful, and the
# build will fall back to the floating tag rather than a bogus pin.

# ---------------------------------------------------------------------------
# Unconditional triggers
# ---------------------------------------------------------------------------
if [[ "${FORCE}" == "true" ]]; then
    emit true "${FORCE_REASON}" "${base_digest}"
fi

# ---------------------------------------------------------------------------
# What we published last time
# ---------------------------------------------------------------------------
creds=()
[[ -n "${REG_USER}" && -n "${REG_PASS}" ]] && creds=(--creds "${REG_USER}:${REG_PASS}")

if ! published="$(skopeo inspect --no-tags "${creds[@]}" "docker://${PUBLISHED_REF}" 2>&1)"; then
    published_err="$(tr -s '[:space:]' ' ' <<<"${published}")"
    emit true "no readable published image at ${PUBLISHED_REF} (fail-open): ${published_err:0:160}" "${base_digest}"
fi

prev_base="$(jq -r --arg k "${LABEL_NS}.base-digest" '.Labels[$k] // ""' <<<"${published}")"
prev_ref="$(jq -r --arg k "${LABEL_NS}.base-ref" '.Labels[$k] // ""' <<<"${published}")"
prev_sha="$(jq -r --arg k "${LABEL_NS}.source-commit" '.Labels[$k] // ""' <<<"${published}")"
prev_created="$(jq -r '.Labels["org.opencontainers.image.created"] // .Created // ""' <<<"${published}")"

if [[ -z "${prev_base}" ]]; then
    emit true "published image has no ${LABEL_NS}.base-digest label (fail-open / first gated build)" "${base_digest}"
fi

age_hours="$(hours_since "${prev_created}")"
if [[ -z "${age_hours}" ]]; then
    emit true "cannot parse published image timestamp '${prev_created}' (fail-open)" "${base_digest}"
fi

# ---------------------------------------------------------------------------
# Rate limiter. Overrides the change detection below, but never the fail-open
# paths above -- a stream whose upstream moves several times a day would
# otherwise build more often than the fixed schedule it replaces.
# ---------------------------------------------------------------------------
if ((age_hours < MIN_INTERVAL_HOURS)); then
    emit false "published ${age_hours}h ago, below the ${MIN_INTERVAL_HOURS}h minimum interval" "${base_digest}"
fi

# ---------------------------------------------------------------------------
# Change detection
# ---------------------------------------------------------------------------
if [[ -n "${base_digest}" && "${base_digest}" != "${prev_base}" ]]; then
    emit true "base moved: ${prev_base} -> ${base_digest}" "${base_digest}"
fi

if [[ -n "${prev_ref}" && "${prev_ref}" != "${BASE_REF}" ]]; then
    emit true "base retargeted: ${prev_ref} -> ${BASE_REF}" "${base_digest}"
fi

if [[ -n "${HEAD_SHA}" && -n "${prev_sha}" && "${prev_sha}" != "${HEAD_SHA}" ]]; then
    emit true "source commit changed: ${prev_sha:0:7} -> ${HEAD_SHA:0:7}" "${base_digest}"
fi

if ((age_hours >= MAX_AGE_HOURS)); then
    emit true "published image is ${age_hours}h old (max ${MAX_AGE_HOURS}h)" "${base_digest}"
fi

# Belt for the digest comparison, in case a label ever fails to round-trip.
# Deliberately secondary: it would go quietly dead if upstream ever stamped a
# fixed SOURCE_DATE_EPOCH, whereas a digest mismatch is loud.
if [[ -n "${base_created}" && -n "${prev_created}" ]]; then
    base_epoch="$(date -u -d "${base_created}" +%s 2>/dev/null)" || base_epoch=""
    prev_epoch="$(date -u -d "${prev_created}" +%s 2>/dev/null)" || prev_epoch=""
    if [[ -n "${base_epoch}" && -n "${prev_epoch}" ]] && ((base_epoch > prev_epoch)); then
        emit true "upstream built ${base_created}, newer than our ${prev_created}" "${base_digest}"
    fi
fi

if [[ -z "${base_digest}" ]]; then
    # We never resolved upstream, so "nothing moved" is not something we
    # actually verified. Say so rather than implying a clean comparison.
    emit false "upstream ${BASE_REF} unresolved (${upstream_err:0:120}); no other signal fired, age ${age_hours}h" ""
fi

emit false "nothing moved (base ${base_digest:0:19}..., commit ${HEAD_SHA:0:7}, age ${age_hours}h)" "${base_digest}"
