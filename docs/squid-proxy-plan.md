# Squid Proxy Helper Plan

## Goals

- Provide a lightweight way to run a local Squid HTTPS proxy that mirrors remote content for faster image builds.
- Automatically integrate with the existing proxy helper flow (`just proxy get-ca`, `scripts/podman-proxy-flags.sh`).
- Keep the repository changes minimal and easy to upstream.

## Expected Workflow

1. `just proxy setup` – Creates the proxy working directory, generates a TLS CA tailored to the image/host, prepares filesystem attributes, and writes minimal proxy settings (resolved host/port) to `cache/env.d/proxy.env`.
2. `just proxy create-ca` – Regenerates the local proxy CA (with optional `--subject`/`--force`) without touching other configuration. `setup` calls this automatically, but exposing the command makes CA refresh explicit. A convenience recipe `just proxy-create-ca subject="..."` mirrors the same functionality for quick `just --list` discoverability.
3. `just proxy start` – Starts the Squid container (based on `satishweb/squid-ssl-proxy`) with SSL bump enabled on a single published port, chaining to an upstream proxy when configured.
4. `just proxy status` – Shows container state and current proxy environment variables.
5. `just proxy stop` – Stops the running Squid container.
6. `just proxy smoke-test` – Runs a quick curl command through the proxy to verify TLS interception and connectivity.
7. `just proxy get-ca` – Captures (or refreshes) the proxy CA for Podman builds; should work automatically once the proxy is running.

## Directory Layout

- `cache/squid/` – Persistent configuration + cache.
  - Created as a Btrfs subvolume when the user has permission; falls back to a normal directory otherwise.
  - Applies SELinux/xattr adjustments (e.g. `chcon -R system_u:object_r:container_file_t:s0`) using `sudo` if available so Podman can mount large caches cleanly.
- `proxy/` scripts are replaced with a single `scripts/proxy-ctl.sh` responsible for setup/start/stop/status and smoke testing.

## CA Generation

- During `just proxy setup`, generate a CA with the proxy hostname embedded (default to the image name or `local-proxy`).
- During `just proxy setup`, generate a CA using a single subject string (default `/CN=$(hostname)/O=$(hostname)/OU=$(basename "$PWD")/C=AQ`, overridable via `PROXY_CA_SUBJECT`). You can pass any custom string (for example `/O=Framey Proxy Authority/OU=Local Intercept CA/CN=Framey Root CA`).
- Store PEM + key under `cache/squid/ca/`.
- Copy the local CA into `cache/https-proxy-ca.pem` so existing tooling (and `just proxy get-ca`) pick it up.
- Provide `just proxy create-ca --subject "/CN=.../O=.../OU=.../C=AQ"` (and `--force`) to regenerate or override the subject without rerunning full setup.
- If chaining to an upstream HTTPS proxy, store its CA certificates under `cache/squid/upstream/` and mount them into the Squid container so the parent connection verifies cleanly.

## Port & Container Runtime

- Default external port: 4128. During `proxy setup/start`, probe for availability; on conflict, increment until a free port is found.
- Persist the chosen port in `cache/squid/config/proxy-port` and record only the resulting `https_proxy` URL in `cache/env.d/proxy.env`.
- When chaining to an upstream proxy, honour optional configuration (e.g. `HTTPS_PROXY_UPSTREAM`, `HTTPS_PROXY_UPSTREAM_CA`) and pass the relevant settings to the Squid container (`PARENT_HOST`, `PARENT_PORT`, `PARENT_CA`).

- Use `podman run` (or `podman compose` if simpler) to launch `satishweb/squid-ssl-proxy`.
- Publish the resolved HTTPS port bound to `127.0.0.1` (or configurable host interface) with SSL bump enabled.
- Mount `cache/squid` subdirectories into the container (`config`, `state/cache`, `state/log`) using `:z` labels.

## Smoke Test

- `scripts/proxy-ctl.sh smoke-test` should:
  - Curl a known HTTPS endpoint using the proxy.
  - Validate that the CONNECT is intercepted (e.g. inspect the served certificate fingerprint).
  - Fail with clear guidance if the proxy is not running or the CA is missing.

## Offline / Re-entrant Use

- `cache/squid` is designed to be portable (copyable onto removable media or another host).
- Document mounting instructions so another VM/USB build environment can reuse the populated cache and CA.

## Implementation Notes

- The legacy `cache-template` flow (`scripts/squid-ctl.sh`, `.env.d` fragments, auto-detection) is a reference, but this implementation will stay lean:
  - No automatic proxy detection; we only manage the proxy started from this repository.
- Only emit essential environment variables (`https_proxy` and matching `no_proxy` entry) via `cache/env.d/proxy.env`.
  - Port discovery is in-process (probe/increment) and recorded once so subsequent commands reuse the same port.
  - Upstream chaining is optional and configured explicitly; when enabled, the upstream CA material lives under `cache/squid/upstream/`.
  - Explicit upstream configuration will be accepted via command flags or environment variables (e.g. `just proxy setup upstream=https://proxy.example:3128 upstream-ca=/path/to/ca.pem`). These values are stored under `cache/squid/config/` and surfaced through `cache/env.d/proxy.env` so the same proxy can be resumed later.
  - CA generation is handled locally via `just proxy create-ca`, mirroring the upstream container entrypoint (private key + `CA.der` + `CA.pem`), so the container simply reuses the prepared material.
  - Two testable modes:
    1. **Local-only:** run `just proxy setup` with no upstream parameters, start the proxy, and confirm `just proxy smoke-test` passes.
    2. **Chained:** run `just proxy setup upstream=https://parent:3128 upstream-ca=/path/to/parent.pem`, verify the upstream CA is copied to `cache/squid/upstream/`, start the proxy, and run `just proxy smoke-test upstream` to ensure requests succeed end-to-end.
  - A single helper (`scripts/proxy-ctl.sh`) handles setup/start/stop/status/smoke-test and keeps the code path short and readable.
  - CA capture reuses the existing `just proxy get-ca` flow so downstream Podman builds stay unchanged.

## Open Questions

- How much logging/config should we expose for advanced tuning?
- Do we need a clean-up command that removes the Btrfs subvolume safely if standard tools fail?
