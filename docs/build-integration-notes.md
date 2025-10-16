# Build Integration Notes

These notes capture the design details behind the template’s “batteries included” workflow so you can explain _why_ everything keeps working whether you use the proxy, the cache, both, or neither.

## Networking Expectations

- Podman treats loopback differently for `build` versus `run`. Every helper adds `--add-host host.containers.internal:10.10.10.2 --network=slirp4netns:allow_host_loopback=true,cidr=10.10.10.0/24` so build containers can reach services the proxy exposes on `localhost`.
- When a proxy is active, `scripts/podman-proxy-flags.sh` rewrites `localhost` endpoints to `host.containers.internal`, injects matching `http_proxy` / `https_proxy` / `no_proxy` env vars, and emits the extra Podman flags. No proxy detected? The script prints nothing and the commands run exactly as stock Podman.

## Proxy CA Handling

- `just proxy setup` creates the Squid working directory, generates a CA (`cache/https-proxy-ca.pem`), and writes `cache/env.d/proxy.env` so subsequent commands auto-load the proxy configuration.
- `just proxy-get-ca` captures _all_ certificates presented by the proxy. It writes the CA-authority certificates to `cache/https-proxy-ca.pem` and drops the full chain in `cache/https-proxy-ca.chain.pem` for debugging.
- Build helpers copy the CA bundle into `cache/certs/<registry>/` and set `CONTAINERS_CERT_PATH`, so registry pulls and `dnf` traffic trust the proxy without touching global host trust stores.
- The CA bundle is mounted over every common path inside the container (`/etc/pki/ca-trust/extracted/*`, `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/certs/ca-bundle.crt`), ensuring tools that honor `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` / `CURL_CA_BUNDLE` all succeed.

## Cache & Repo Mounting

- The cache helpers (`just cache-packages*`) and `just build` look for optional directories and mount them when present:
  - `cache/dnf` → `/var/cache/dnf`
  - `cache/dnf/yum.repos.d` → `/etc/yum.repos.d`
  - `config/dnf/cache.conf` → `/etc/dnf/dnf.conf.d/99-cache.conf`
- Flatpak caching follows the same pattern: populate refs in `our-flatpaks.list`, warm them into `cache/flatpak` (exported repo under `cache/flatpak/sideload`) with `just cache-flatpaks`, and mount that path when available. Check the footprint with `just cache-flatpaks-status`.
- Container image caching pre-pulls OCI images listed in `our-containers.list` into `cache/containers` by bind-mounting that path over `/var/lib/containers/storage` while the helper runs. `just cache-containers-status` reports the resulting size and the configured refs (rootless users still need to import images separately if desired).
- Homebrew caching can pull formula tarballs defined in `our-brewfile` into `cache/homebrew`. The helper defaults to `BASE_IMAGE`; if that image lacks Homebrew, set `HOMEBREW_CACHE_IMAGE` to a brew-enabled image (for example `docker.io/homebrew/brew:latest`). `just cache-homebrew-status` reports the cache footprint and referenced formulas.
- `just cache` runs every available cache recipe (RPMs, Flatpaks, container images, and Homebrew). `just cache-status` prints their roll-up summaries.
- If those paths do not exist, the mounts are simply skipped. The same Containerfile continues to build against upstream mirrors without modification.
- `just cache-packages` warms the cache, but you can also run it against upstream mirrors when no proxy is configured—the helper detects the proxy flags dynamically.
- `just cache-packages-list` intentionally exits with status 1 when it spots differences between `our-packages.list` and the newly captured list. That behaviour protects automated flows by forcing you to acknowledge the diff before continuing.

## Optional Layers, Same Containerfile

- Proxy and cache integration are strictly layered on top of Podman at runtime. You can:
  1. Use **neither** cache nor proxy → stock bootc behaviour.
  2. Use **proxy only** → build traffic is intercepted but RPMs are still fetched from upstream each time.
  3. Use **cache only** → RPMs come from your warmed cache, with outbound traffic hitting upstream mirrors directly.
  4. Use **proxy + cache** → fastest builds, outbound HTTPS pinned to the captured CA.
- Because everything is driven by runtime flags instead of edits to the Containerfile, the image definition remains portable and reproducible across all of the above combinations.

## Known Bootc Lint Warning

- `bootc container lint` warns about content under `/var/cache/dnf` and `/var/lib/dnf`. The warning is expected—warming the cache leaves those directories populated in the final layer, and the lint check reminds you that they are not covered by tmpfiles rules. You can safely acknowledge the warning or clear the directories before the final commit if you prefer.
