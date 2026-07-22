# freizzite roadmap

Working list of fork-specific ideas and follow-ups. Fork-only file (upstream
image-template has none). Keep entries short; move deep detail into PRs.

Legend: **[ ]** todo · **[~]** in progress · **[x]** done · **(?)** needs a decision

Convention: active work is ordered top→bottom (top = next). Items that are
finished but not yet validated sit under "Pending validation." Once validated,
move them to "Done" at the very bottom.

---

## Active work (top = next)

### testing-tag builds [~] — implemented (all variants), pending validation

Decision: **all variants**. Implementation details under Pending validation.

### Per-variant `IMAGE_DESC` [x] — DONE

From PR #41 (TODO in `image-template.env`): mention dx-nvidia / deck in each
image's description. Done via a `image_desc` field in the `build.yml` matrix
targets, exported as `IMAGE_DESC` in the `build_push` env (env beats dotenv —
no Justfile change). Local builds still use the `image-template.env` default.

### Upstream survey — remaining candidates (reference)

From scanning `ublue-os/main` + `ublue-os/bazzite` (workflows/Justfiles only):

- **just syntax check:** bazzite `just-syntax-check.yml` (`ublue-os/just-action`)
  on PRs. Likely redundant — `build.yml` already runs `just check` on PRs.
- **Handy Justfile recipes (optional):** `list-images`, `clean-images`,
  `clean-isos` (bazzite); `verify-container` (main). Small local-dev niceties;
  each is divergence — adopt only on clear need.
- **Emergency retag (low value):** bazzite `retag.yml` (manual, "never
  automate"). Only if a bad publish needs rolling back by tag.

### ISO hosting → B2 + Fastly [ ] (bottom)

GitHub Releases can't host the ISOs: **2 GiB/file** cap vs 7–10 GB ISOs.
**Decision:** Backblaze B2 (already have) + **Fastly**. B2's Bandwidth Alliance
gives free egress to Fastly, so only cheap B2 storage remains — and Fastly is
Eric's wheelhouse. Possible bonus: Fastly Fast Forward (free CDN for OSS) —
verify eligibility. **Next:** design upload + Fastly service (origin = B2
bucket, cache, TLS, custom domain). Ties into releases below.

### Releases + ISO automation [ ] (bottom)

Rebuild release automation (old `generate_release.yml` + `changelog.py` were
deleted as broken). Target flow: build ISOs → upload to B2 → publish a GitHub
Release with notes pointing at hosted ISO URLs.
**Trigger (?):** manual to start, and/or auto after a successful container build
that followed an upstream bazzite release.
**Changelog approach (?):** `release-please` (Conventional-Commits driven, fits
Eric's commit style) vs bazzite `changelog.py` (diffs package versions via SBOMs
— richer image-level notes, heavier).

## Deferred

- **CodeQL Python scan:** leave configured as-is and keep the (currently
  failing) badge for now. It errors because the config includes Python but the
  repo has none. If it can be set to treat missing Python as a silent skip
  rather than an error, do that; otherwise remove the Python scan **last**,
  after the other roadmap items (some may add Python).

## Pending validation (watch; act only if they fail)

- **testing-tag builds:** `build.yml` computes its matrix in a preflight
  `matrix` job that probes `ghcr.io/ublue-os/<base>:testing`
  (`docker buildx imagetools inspect`) and adds a `testing` stream per variant
  only when it exists. Testing publishes only `testing`-prefixed tags (avoids a
  bare-date collision with stable); ArtifactHub push runs once per package
  (stable stream); `clean.yml` excludes `testing`. **Validate via a PR first**
  (matrix + both stream builds run, nothing publishes), then let it hit main.
  Heads-up: job display names are now `<image> (<stream>)`, so any branch-
  protection required checks referencing the old "Build and push image" name
  need updating. If testing streams unexpectedly don't appear, check the matrix
  job log — an auth failure on the probe would need a ghcr login added there.
- **Artifact Hub listings:** deck `repositoryID` corrected to
  `aacc915a-…` (was the wrong `eb2d1d48-…`, why deck wasn't verified). Verify
  deck flips to Verified Publisher after the next build's oras push;
  dx-nvidia already verified and both render clean.
- **Old-image cleanup:** first live `clean.yml` run pruning ~1,900 old-pipeline
  images across both packages; confirm it completes without a permission wall.
- **README badges:** added build-disk, CodeQL, and license badges. Confirm all
  render (especially the CodeQL default-setup badge path).

## Done (validated)

- _(move items here once fully validated)_
