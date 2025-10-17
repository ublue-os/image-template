# Custom Repo Definitions

Drop `.repo` files into this directory if you want `just cache-packages` to seed the DNF cache using your own repository definitions instead of the ones shipped in the base image.

- Any `.repo` files present here will be bind-mounted into the cache helper container and copied into `cache/dnf/yum.repos.d` on the first run.
- Leave the directory empty (except for this README) if you prefer to inherit the base image's `/etc/yum.repos.d`.
- To refresh after updating these files, delete `cache/dnf/yum.repos.d` and rerun `just cache-packages`.

The README itself is ignored by the helper so you can ship guidance without affecting behavior.
