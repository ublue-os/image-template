# DNF Cache Rollout Plan

## 1. Cache Directory Preparation
- Introduce a helper (`scripts/cache-prepare.sh`) that ensures `${REPO_ROOT}/cache/dnf` exists, preferably as a Btrfs subvolume when the workspace supports it.
- Do not create the directory automatically; only initialize it when the user runs the cache priming recipe.

## 2. Priming Workflow (`just cache-packages`)
- Add a Just recipe that:
  1. Calls the cache-prep helper.
  2. Starts the local proxy if needed (optional hook).
  3. Invokes `scripts/dnf-cache-helper.sh` inside a helper container, writing metadata and RPM payloads into `cache/dnf`, applying the shared drop-in at `config/dnf/cache.conf`, and copying `/etc/yum.repos.d` into `cache/dnf/yum.repos.d`.
- If the repository includes a `yum.repos.d/` directory, mount it into the helper container so custom `.repo` files are honoured; otherwise fall back to any previously captured definitions under `cache/dnf/yum.repos.d`.
- Keep the cache directory writable during this step so new packages are captured.

## 3. Build Integration
- Update `just build` to detect `cache/dnf`. When the directory exists, append:
  ```
  --volume "$(pwd)/cache/dnf:/var/cache/dnf:Z"
  ```
  to the `podman build` invocation so every `RUN` sees the warmed payloads under `/var/cache/dnf`.
- If `cache/dnf` is absent, skip the volume flag so builds continue to behave exactly as they do today.
- Leave the Containerfile untouched; it already expects to interact with `/var/cache`, but make sure every build mounts `config/dnf/cache.conf` into `/etc/dnf/dnf.conf.d/` so `keepcache=True` applies consistently.
- Keep the base image consistent by editing the `BASE_IMAGE` export (or environment variable); both the Containerfile (`ARG BASE_IMAGE=…`) and cache helpers consume the same value.
- When `cache/dnf/yum.repos.d` exists (or a top-level `yum.repos.d/` is provided), mount it into `/etc/yum.repos.d` during builds so repo fingerprints align with the cached payloads.

## 4. Package List Generation (`just cache-packages-list`)
- Provide a recipe that:
  1. Runs `podman run --rm <built-image> rpm -qa --qf '%{NAME}\n'` and records the output.
  2. Runs the same command against the base image referenced in the Containerfile, storing the result in `cache/baseimage-packages.list`.
  3. Produces a sorted list of additional package names and writes it to `cache/our-packages.list`, diffing against the committed `our-packages.list` so maintainers can copy the updated list when needed. It also captures the upstream package set in `cache/baseimage-packages.list` and a convenience catalog of all available packages in the enabled repos at `cache/available-packages.list`.

## 5. Read/Write Modes
- Default builds use the cache read-only once the package list is established.
- When the cache needs to be refreshed (new package list, base image change), rerun `just cache-packages` with the cache mounted read-write.
- Document the toggle (e.g., environment flag or dedicated recipe) so it’s clear when the cache is mutable.

## 6. Proxy Alignment
- Keep proxy environment fragments in `cache/env.d/` and ensure both `just build` and helper scripts source them before calling Podman. This preserves TLS interception and proxy routing even after the cache directory migration.
- `just proxy-env` should continue to print the current environment fragment for diagnostics.

## 7. Documentation & Follow-Up
- Once the flow works end to end, update the README or dedicated docs to explain:
  - How to warm the cache.
  - How the build reuses it.
  - How to regenerate `our-packages.list`.
  - How to ship the warmed cache (e.g., via Btrfs snapshot or tarball).
- After DNF is solid, replicate the pattern for Flatpak (`cache/flatpak`, `flatpak-refs.list`, etc.).
