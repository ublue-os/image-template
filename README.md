# SovereigniteOS

**SovereigniteOS** is an immutable, bootc-based operating system for Kubernetes
nodes, built on [Universal Blue](https://universal-blue.org/). It layers
sovereignite Go/K8s services onto a headless [ucore](https://github.com/ublue-os/ucore)
(Fedora CoreOS + batteries) base image instead of a desktop.

## What it is

- Immutable, container-native OS image (bootc/rpm-ostree) for server/K8s nodes
- Headless `ucore` base — no desktop environment
- Ships sovereignite Go binaries and systemd units as filesystem overlays

## How it's built

- `Containerfile` starts from `ghcr.io/ublue-os/ucore:latest`
- `build_files/build.sh` installs packages and enables services
- `system_files/` is copied verbatim over `/` (config overlays, units, binaries)
- CI builds, rechunks, and signs the image; nodes `bootc switch` / `bootc upgrade` to it

## Repository layout

```
Containerfile                 # build entrypoint (ucore base + /ctx/build.sh + bootc lint)
build_files/build.sh          # customization script (packages, services)
system_files/                 # filesystem overlays copied over /
  usr/local/bin/              # sovereignite Go binaries
  usr/lib/systemd/system/     # sovereignite .service units
  etc/kubernetes/             # k8s configs
  etc/containerd/             # containerd configs
  usr/lib/tmpfiles.d/         # runtime dir provisioning
image-template.env            # image name/org/tag configuration
```

## Status

Skeleton repository forked from
[ublue-os/image-template](https://github.com/ublue-os/image-template) (MIT).
Service integration is a work in progress.

## License

MIT — see [LICENSE](LICENSE).
