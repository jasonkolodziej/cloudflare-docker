# warp-docker

Published image: `ghcr.io/jasonkolodziej/cloudflare-warp-docker`

Run official [Cloudflare WARP](https://1.1.1.1/) client in Docker.

> [!NOTE]
> Cannot guarantee that the [GOST](https://github.com/ginuerzh/gost) and WARP client contained in the image are the latest versions. If necessary, please [build your own image](#build).

## Usage

### Start the container

To run the published image from this repository's registry, use `compose.warp.yml` and set `WARP_IMAGE_TAG` to one of the published tags.

```yaml
services:
  warp:
    image: ghcr.io/jasonkolodziej/cloudflare-warp-docker:${WARP_IMAGE_TAG}
    container_name: warp
    restart: always
    # add removed rule back (https://github.com/opencontainers/runc/pull/3468)
    device_cgroup_rules:
      - 'c 10:200 rwm'
    ports:
      - "1080:1080"
    environment:
      - WARP_SLEEP=2
      # - WARP_LICENSE_KEY= # optional
      # - WARP_ENABLE_NAT=1 # enable nat
    cap_add:
      # Docker already have them, these are for podman users
      - MKNOD
      - AUDIT_WRITE
      # additional required cap for warp, both for podman and docker
      - NET_ADMIN
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv4.conf.all.src_valid_mark=1
      # uncomment for nat
      # - net.ipv4.ip_forward=1
      # - net.ipv6.conf.all.forwarding=1
      # - net.ipv6.conf.all.accept_ra=2
    volumes:
      - ./data:/var/lib/cloudflare-warp
```

Example:

```bash
WARP_IMAGE_TAG=v2026.4.146.0-rhel-latest docker-compose -f compose.warp.yml up -d
```

Try it out to see if it works:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
```

If the output contains `warp=on` or `warp=plus`, the container is working properly. If the output contains `warp=off`, it means that the container failed to connect to the WARP service.

### Configuration

You can configure the container through the following environment variables:

- `WARP_SLEEP`: The time to wait for the WARP daemon to start, in seconds. The default is 2 seconds. If the time is too short, it may cause the WARP daemon to not start before using the proxy, resulting in the proxy not working properly. If the time is too long, it may cause the container to take too long to start. If your server has poor performance, you can increase this value appropriately.
- `WARP_CONNECTOR_TOKEN`: Mesh node token from the Cloudflare setup wizard (`Networking > Mesh > Add a node`). If set, startup uses `warp-cli connector new <TOKEN>` for non-interactive node enrollment.
- `WARP_LICENSE_KEY`: The license key of the WARP client, which is optional. If you have subscribed to WARP+ service, you can fill in the key in this environment variable. If you have not subscribed to WARP+ service, you can ignore this environment variable.
- `GOST_ARGS`: The arguments passed to GOST. The default is `-L :1080`, which means to listen on port 1080 in the container at the same time through HTTP and SOCKS5 protocols. If you want to have UDP support or use advanced features provided by other protocols, you can modify this parameter. For more information, refer to [GOST documentation](https://v2.gost.run/en/). If you modify the port number, you may also need to modify the port mapping in the `docker-compose.yml`.
- `REGISTER_WHEN_MDM_EXISTS`: If set, will register consumer account (WARP or WARP+, in contrast to Zero Trust) even when `mdm.xml` exists. You usually don't need this, as `mdm.xml` are usually used for Zero Trust. However, some users may want to adjust advanced settings in `mdm.xml` while still using consumer account.
- `BETA_FIX_HOST_CONNECTIVITY`: If set, will add checks for host connectivity into healthchecks and automatically fix it if necessary. See [host connectivity issue](docs/host-connectivity.md) for more information.
- `WARP_ENABLE_NAT`: If set, will work as warp mode and turn NAT on. You can route L3 traffic through `warp-docker` to Warp. See [nat gateway](docs/nat-gateway.md) for more information.

Data persistence: Use the host volume `./data` to persist the data of the WARP client. You can change the location of this directory or use other types of volumes. If you modify the `WARP_LICENSE_KEY`, please delete the `./data` directory so that the client can detect and register again.

For advanced usage or configurations, see [documentation](docs/README.md).

### Build with RHEL or Ubuntu base

The repository now uses a single `Dockerfile` for both package ecosystems. To build locally, use `compose.build.warp.yml`.

- RHEL/UBI build (default):
  - `OS_FAMILY=rhel`
  - `BASE_IMAGE=redhat/ubi9-minimal:9.5`
- Ubuntu build:
  - `OS_FAMILY=debian`
  - `BASE_IMAGE=ubuntu:22.04`

Example:

```bash
docker-compose -f compose.build.warp.yml build \
  --build-arg OS_FAMILY=debian \
  --build-arg BASE_IMAGE=ubuntu:22.04
```

### Use other versions

Published tags now use this rule:

- OS distro is required.
- OS version is optional.
- WARP version prefix (`v{WARP_VERSION}-`) is optional.

Supported shapes:

- `{DISTRO}-latest`
- `{DISTRO}-{OS_VERSION}`
- `v{WARP_VERSION}-{DISTRO}-latest`
- `v{WARP_VERSION}-{DISTRO}-{OS_VERSION}`

Build variants in this repository follow the package choices shown in Cloudflare's Linux package portal and include:

- `rhel-8`
- `debian-11`, `debian-12`, `debian-13`
- `fedora-34`, `fedora-35`
- `ubuntu-20.04`, `ubuntu-22.04`, `ubuntu-24.04`

Examples:

- `ubuntu-latest` (latest Ubuntu flavor and latest WARP)
- `debian-11` (Debian 11 flavor and latest WARP)
- `rhel-latest`
- `rhel-8`
- `v{WARP_VERSION}-rhel-latest`
- `v{WARP_VERSION}-rhel-8`
- `v{WARP_VERSION}-rhel-8-gost-{GOST_VERSION}`
- `debian-12-gost-{GOST_VERSION}`

> [!NOTE]
> You can access a commit-specific image with either versioned or unversioned tags, for example `v{WARP_VERSION}-rhel-8-gost-{GOST_VERSION}-{COMMIT_SHA}` or `rhel-8-gost-{GOST_VERSION}-{COMMIT_SHA}`.
> [!NOTE]
> Not all version combinations are available. Do check [the GHCR package page](https://github.com/jasonkolodziej/flow-reduce/pkgs/container/cloudflare-warp-docker) before you use one. If the version you want is not available, you can [build your own image](#build).

#### Available distro variants

Current automated variants include `rhel-8`, `debian-11`, `debian-12`, `debian-13`, `fedora-34`, `fedora-35`, `ubuntu-20.04`, `ubuntu-22.04`, and `ubuntu-24.04`.

CI uses slim/minimal base images where available:

- RHEL family: `rockylinux:8-minimal`, `registry.fedoraproject.org/fedora-minimal:{34,35}`
- Debian family: `debian:{11,12,13}-slim`
- Ubuntu variants currently use standard tags (`ubuntu:20.04`, `ubuntu:22.04`, `ubuntu:24.04`) because upstream `-minimal` tags are not published

## Build

You can use GitHub Actions to build the image yourself.

1. Fork this repository.
2. Ensure the workflow has permission to push packages to GHCR (the workflow uses `GITHUB_TOKEN` and `packages: write`).
3. Manually trigger the workflow `Build and Publish WARP Image` in the Actions tab.

This will build the image with the latest version of WARP client and GOST and push it to GHCR. You can also specify the version of GOST by giving input to the workflow. Building image with custom WARP client version is not supported yet.

### CI workflow notes

- The workflow includes an `Action Runtime Smoke Check` job and a `validate_only` input for fast validation of action/runtime upgrades without running full image matrix jobs.
- The `Resolve Build Versions` job also preflights the resolved GOST release asset URLs with retries, so upstream release issues fail early before matrix builds start.
- Build cache is read on all runs, but cache write/export is limited to default-branch push runs in `Build and Publish Image Matrix`. This keeps pull request runs fast while avoiding unnecessary cache growth.
- The variant matrix is defined once with a YAML anchor and reused between `Build and Smoke Test Matrix` and `Build and Publish Image Matrix` to avoid drift.

If you want to build the image locally, you can use [`.github/workflows/build-warp.yml`](.github/workflows/build-warp.yml) as a reference.

## Common problems

### Proxying UDP or even ICMP traffic

The default `GOST_ARGS` is `-L :1080`, which provides HTTP and SOCKS5 proxy. If you want to proxy UDP or even ICMP traffic, you need to change the `GOST_ARGS`. Read the [GOST documentation](https://v2.gost.run/en/) for more information. If you modify the port number, you may also need to modify the port mapping in the `docker-compose.yml`.

### How to connect from another container

You may want to use the proxy from another container and find that you cannot connect to `127.0.0.1:1080` in that container. This is because the `docker-compose.yml` only maps the port to the host, not to other containers. To solve this problem, you can use the service name as the hostname, for example, `warp:1080`. You also need to put the two containers in the same docker network.

### "Operation not permitted" when open tun

Error like `{ err: Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }, context: "open tun" }` is caused by [an update to containerd](https://github.com/containerd/containerd/releases/tag/v1.7.24). You need to pass the tun device to the container following the [instruction](docs/tun-not-permitted.md).

### NFT error on Synology or QNAP NAS

If you are using Synology or QNAP NAS, you may encounter an error like `Failed to run NFT command`. This is because both Synology and QNAP use old iptables, while WARP uses nftables. It can't be easily fixed since nftables need to be added when the kernel is compiled.

Possible solutions:

- If you don't need UDP support, use the WARP's proxy mode by following the instructions in the [documentation](docs/proxy-mode.md).
- If you need UDP support, run a fully virtualized Linux system (KVM) on your NAS or use another device to run the container.

References that might help:

- [Related issue](https://github.com/cmj2002/warp-docker/issues/16)
- [Request of supporting iptables in Cloudflare Community](https://community.cloudflare.com/t/legacy-support-for-docker-containers-running-on-synology-qnap/733983)

### Container runs well but cannot connect from host

This issue often arises when using Zero Trust. You may find that you can run `curl --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace` inside the container, but cannot run this command outside the container (from host or another container). This is because Cloudflare WARP client is grabbing the traffic. See [host connectivity issue](docs/host-connectivity.md) for solutions.

### How to enable MASQUE / use with Zero Trust / set up WARP Connector / change health check parameters

See [documentation](docs/README.md).

### Permission issue when using Podman

See [documentation](docs/podman.md) for explanation and solution.

## Further reading

For how it works, read my [blog post](https://blog.caomingjun.com/run-cloudflare-warp-in-docker/en/#How-it-works).
