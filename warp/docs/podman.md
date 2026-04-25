# Podman

[Podman](https://podman.io/) have [more strict security settings than Docker](https://blog.caomingjun.com/linux-capabilities-in-docker-and-podman/en/), so you need to add more capabilities to the container to make it work properly. If your podman is not a rootless installation, you can use the default `docker-compose.yml` file, as the additional capabilities required by the container are already included in the default configuration.

[Rootless Podman have more limitations](https://github.com/containers/podman/issues/7866). You can try to mount `/dev/tun` to avoid permission issues. Here is an example command to run the container with Podman:

```bash
podman run -d \
  --name warp \
  --restart always \
  -p 1080:1080 \
  -e WARP_SLEEP=2 \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -v ./data:/var/lib/cloudflare-warp \
  ghcr.io/jasonkolodziej/cloudflare-docker-warp:${WARP_IMAGE_TAG}
```

> [!NOTE]
> I am not a Podman user, the example command is [written by @tony-sung](https://github.com/cmj2002/warp-docker/issues/30#issuecomment-2371448959).

## Building the image with Podman / Buildah

The [warp/Dockerfile](../Dockerfile) is a multistage build that has been validated against Podman 5.8 / Buildah 1.43 in addition to Docker BuildKit. The `gost` and `scripts` stages run on `$BUILDPLATFORM` (no QEMU emulation) and the final `runtime` stage installs `cloudflare-warp` on the requested distro `BASE_IMAGE`.

Native-arch build (matches what CI does per matrix variant):

```bash
podman build \
  -f warp/Dockerfile \
  --target runtime \
  --build-arg OS_FAMILY=debian \
  --build-arg BASE_IMAGE=debian:12-slim \
  --build-arg GOST_VERSION=2.12.0 \
  --build-arg WARP_VERSION=$(curl -fsSL https://api.github.com/repos/ginuerzh/gost/releases/latest \
                              | jq -r '.tag_name' | cut -c2-) \
  --build-arg COMMIT_SHA=$(git rev-parse HEAD) \
  --format docker \
  -t localhost/warp:debian12 \
  warp
```

Multi-arch build (requires `qemu-user-static` registered with binfmt):

```bash
podman build \
  -f warp/Dockerfile \
  --platform linux/amd64,linux/arm64 \
  --manifest localhost/warp:debian12 \
  --target runtime \
  --build-arg OS_FAMILY=debian \
  --build-arg BASE_IMAGE=debian:12-slim \
  --build-arg GOST_VERSION=2.12.0 \
  --format docker \
  warp
```

### `--format docker` and HEALTHCHECK

Podman defaults to the OCI image format, which does not carry the `HEALTHCHECK` directive. Without `--format docker` you will see this warning during build, and the resulting image will have no embedded healthcheck:

```
WARN HEALTHCHECK is not supported for OCI image format and will be ignored. Must use `docker` format
```

Use `--format docker` (as shown above) when you want `HEALTHCHECK` preserved, or supply the healthcheck at runtime with Podman's flags instead:

```bash
podman run -d \
  --name warp \
  --health-cmd='/healthcheck/index.sh' \
  --health-interval=15s \
  --health-timeout=5s \
  --health-start-period=10s \
  --health-retries=3 \
  ...
  ghcr.io/jasonkolodziej/cloudflare-docker-warp:${WARP_IMAGE_TAG}
```

### Notes on the Dockerfile structure

- Global build args used in `FROM` lines (`BASE_IMAGE`, `GOST_VERSION`) are declared **before the first `FROM`**. Buildah is stricter than BuildKit about ARG scoping; declaring them between stages causes `Error: determining starting point for build: no FROM statement found`.
- The Dockerfile uses `--mount=type=cache` for apt/dnf state, with the cache `id` keyed on `OS_FAMILY` + `BASE_IMAGE` + `TARGETARCH`. That gives each (distro, arch) combo a private cache so local rebuilds are fast and the multi-arch CI matrix doesn't cross-contaminate apt indices (which would otherwise fail with exit 100). Buildah parses but ignores cache mounts, so podman builds still succeed — just without the speedup.
- On RHEL-family images, the Dockerfile now auto-selects `curl-minimal` when available and falls back to `curl` when not (for example `rockylinux:8-minimal`). This avoids `curl`/`curl-minimal` conflict errors on UBI9 while preserving Rocky 8 compatibility.
- The smoke test the CI matrix runs against the Docker build also passes against the Podman build:

  ```bash
  podman run --rm --entrypoint /bin/bash localhost/warp:debian12 -lc '
    set -e
    for c in sudo dbus-daemon warp-cli warp-svc gost nft ip jq ipcalc; do command -v "$c"; done
    test -x /entrypoint.sh
    test -x /healthcheck/index.sh
    bash -n /entrypoint.sh
    bash -n /healthcheck/index.sh
    bash -n /healthcheck/fix-host-connectivity.sh
  '
  ```
