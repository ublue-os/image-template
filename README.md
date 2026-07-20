# freizzite

[![Build container image](https://github.com/freiheit/freizzite/actions/workflows/build.yml/badge.svg)](https://github.com/freiheit/freizzite/actions/workflows/build.yml)
[![pre-commit checks](https://github.com/freiheit/freizzite/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/freiheit/freizzite/actions/workflows/pre-commit.yml)
[![Artifact Hub freizzite-deck](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/freizzite-deck)](https://artifacthub.io/packages/search?repo=freizzite-deck)
[![Artifact Hub freizzite-dx-nvidia](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/freizzite-dx-nvidia)](https://artifacthub.io/packages/search?repo=freizzite-dx-nvidia)

This is a freiheit clone of
[bazzite](https://github.com/ublue-os/bazzite)
using <https://github.com/ublue-os/image-template> to start with.

Go look at those 2 places for useful info/links, etc.

## Variants

| Variant                   | Description                                         |
| ------------------------- | ----------------------------------------------------|
| freizzite-dx-nvidia       | KDE Desktop/Laptop + Dev eXperience with Nvidia GPU |
| freizzite-deck            | KDE SteamDeck or similar                            |
| ~~freizzite~~             | ~~KDE Desktop/Laptop with AMD/Intel/etc GPU~~       |
| ~~freizzite-nvidia-open~~ | ~~KDE Desktop/Laptop with Nvidia GPU~~              |

## Installation

0. **Don't**; you'd have to be crazy to do that
1. Install bazzite (or another ublue flavor) **must be KDE/Kinoite variant**.
2. Run `sudo bootc status` and `sudo rpm-ostree status` and save the info somewhere.
3. Optional: `sudo ostree admin pin 0`
4. Depending which flavor you want, one of these:
   * `sudo bootc switch --enforce-container-sigpolicy ghcr.io/freiheit/freizzite-dx-nvidia`
   * `sudo bootc switch --enforce-container-sigpolicy ghcr.io/freiheit/freizzite-deck`
5. reboot

... maybe that's supposed to be an `rpm-ostree rebase` instead?

### ISOs (available on request; untested)

**Untested** ISOs available on request.

Generating them isn't a problem, but hosting downloads for 7-10GB files is
potentially pricey.

## Recovery

If you want to swap back.

* Temporary: reboot and pick the previous version
* Permanent: `sudo bootc switch ghcr.io/ublue-os/bazzite-something`
  (Refer to saved `rpm-ostree status` info from install)

## Local development

The build pipeline follows upstream
[image-template](https://github.com/ublue-os/image-template)'s just-based
flow. Defaults (image name, base image, variant) come from
`image-template.env`; CI overrides them per matrix entry in
`.github/workflows/build.yml`.

* `just build` — build the primary variant
  (`localhost/freizzite-dx-nvidia:latest`)
* `IMAGE_NAME=freizzite-deck BASE_IMAGE=bazzite-deck BUILD_VARIANT=bazzite-deck just build`
  — build the deck variant
* `sudo just build` then
  `sudo bootc switch --transport containers-storage localhost/freizzite-dx-nvidia:latest`
  — test-boot a local build (build as root so the image lands in root's
  containers-storage)
* `just build-iso` — build the dx-nvidia ISO locally
  (`disk_config/iso.toml`); the deck ISO uses `disk_config/iso-deck.toml`
* `just check` / `just lint` / `pre-commit run --all-files` — lint

Images are tagged by upstream's `just generate-build-tags`: `latest`,
`YYYYMMDD`, `latest-YYYYMMDD`, plus `-<gitsha>` variants of each.
