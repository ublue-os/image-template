# freirora

[![Build container image](https://github.com/freiheit/freirora/actions/workflows/build.yml/badge.svg)](https://github.com/freiheit/freirora/actions/workflows/build.yml)
[![pre-commit checks](https://github.com/freiheit/freirora/actions/workflows/pre-commit.yml/badge.svg)](https://github.com/freiheit/freirora/actions/workflows/pre-commit.yml)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/freirora)](https://artifacthub.io/packages/container/freirora/freirora)

This is a freiheit clone of
[aurora-dx](https://github.com/ublue-os/aurora)
using <https://github.com/ublue-os/image-template> to start with, and
heavily pulling from <https://github.com/freiheit/freizzite>

Go look at those 2 places for useful info/links, etc.

## Installation

0. **Don't**; you'd have to be crazy to do that
1. Install aurora (or another ublue flavor) **must be KDE/Kinoite variant**.
2. Run `sudo bootc status` and `sudo rpm-ostree status` and save the info somewhere.
3. Optional: `sudo ostree admin pin 0`
4. Depending which flavor you want, one of these:
   * `sudo bootc switch --enforce-container-sigpolicy ghcr.io/freiheit/freirora`
5. reboot

... maybe that's supposed to be an `rpm-ostree rebase` instead?

## Recovery

If you want to swap back.

* Temporary: reboot and pick the previous version
* Permanent: `sudo bootc switch ghcr.io/ublue-os/aurora-dx`
  (Refer to saved `rpm-ostree status` info from install)
