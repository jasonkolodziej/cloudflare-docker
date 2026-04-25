# Setting up as WARP connector

If you want to setup a connector using the current Cloudflare Mesh wizard, follow [Get started](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-mesh/get-started/#1-run-the-setup-wizard).

> [!NOTE]
> If you have already started the container, stop it and delete the data directory.

1. In Cloudflare dashboard, go to `Networking > Mesh > Add a node`.
2. Create the node and copy the token from the install command `warp-cli connector new <TOKEN>`.
3. Set `WARP_CONNECTOR_TOKEN` in your compose environment and start the container.

Sample Docker Compose File:

```yaml
services:
  warp:
    image: ghcr.io/jasonkolodziej/cloudflare-docker-warp:${WARP_IMAGE_TAG}
    container_name: warp
    restart: always
    # add removed rule back (https://github.com/opencontainers/runc/pull/3468)
    device_cgroup_rules:
      - 'c 10:200 rwm'
    ports:
      - "1080:1080"
    environment:
      - WARP_SLEEP=2
      - WARP_CONNECTOR_TOKEN=${WARP_CONNECTOR_TOKEN}
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.all.accept_ra=2
    volumes:
      - ./data:/var/lib/cloudflare-warp
```

For a local build instead of the published image, use `compose.build.warp.yml`.
