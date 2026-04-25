# syntax=docker/dockerfile:1.7

# Global build args (declared before the first FROM so they're usable in FROM lines).
# Per-stage ARGs are redeclared inside their stage below.
ARG BASE_IMAGE=redhat/ubi9-minimal:9.5
ARG GOST_VERSION

############################
# Stage 1: fetch gost (runs natively on BUILDPLATFORM, cross-arch safe)
############################
FROM --platform=$BUILDPLATFORM alpine:3.20 AS gost
ARG GOST_VERSION
ARG TARGETPLATFORM
RUN apk add --no-cache curl tar gzip ca-certificates

RUN set -eux; \
    case "${TARGETPLATFORM}" in \
      "linux/amd64") ARCH_NEW=amd64; ARCH_LEGACY=amd64 ;; \
      "linux/arm64") ARCH_NEW=arm64; ARCH_LEGACY=armv8 ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" >&2; exit 1 ;; \
    esac; \
    MAJOR=${GOST_VERSION%%.*}; TAIL=${GOST_VERSION#*.}; MINOR=${TAIL%%.*}; \
    if [ "${MAJOR}" -ge 3 ] || { [ "${MAJOR}" -eq 2 ] && [ "${MINOR}" -ge 12 ]; }; then \
      FILE="gost_${GOST_VERSION}_linux_${ARCH_NEW}.tar.gz"; \
    else \
      FILE="gost-linux-${ARCH_LEGACY}-${GOST_VERSION}.gz"; \
    fi; \
    mkdir -p /out; \
    curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
      -o "/tmp/${FILE}" \
      "https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILE}"; \
    case "${FILE}" in \
      *.tar.gz) tar -xzf "/tmp/${FILE}" -C /out gost ;; \
      *.gz)     gunzip "/tmp/${FILE}" && mv /tmp/gost-linux-* /out/gost ;; \
    esac; \
    chmod +x /out/gost

############################
# Stage 2: stage scripts with executable bit set
############################
FROM --platform=$BUILDPLATFORM alpine:3.20 AS scripts
COPY entrypoint.sh /out/entrypoint.sh
COPY healthcheck   /out/healthcheck
RUN chmod +x /out/entrypoint.sh /out/healthcheck/index.sh

############################
# Stage 3: runtime (distro-specific)
############################
FROM ${BASE_IMAGE} AS runtime

ARG OS_FAMILY=rhel
ARG WARP_VERSION
ARG GOST_VERSION
ARG COMMIT_SHA

LABEL org.opencontainers.image.authors="jasonkolodziej"
LABEL org.opencontainers.image.url="https://github.com/jasonkolodziej/cloudflare-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

# Install distro packages + cloudflare-warp.
# Cache mounts speed up local rebuilds; they're ignored by layer hashing so
# they don't interfere with the GHA cache (type=gha) used in CI.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    --mount=type=cache,target=/var/cache/yum,sharing=locked \
    set -eux; \
    if [ "${OS_FAMILY}" = "debian" ]; then \
      export DEBIAN_FRONTEND=noninteractive; \
      export TZ=UTC; \
      apt-get update; \
      apt-get upgrade -y; \
      apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        sudo \
        jq \
        ipcalc \
        iproute2 \
        iputils-ping \
        nftables \
        dbus \
        procps; \
      curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
        | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg; \
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/cloudflare-client.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends cloudflare-warp; \
      # Debian's /etc/profile sets a non-root PATH that excludes /usr/sbin.
      # nft (nftables) and ip (iproute2) live in /usr/sbin; add it for all login shells.
      printf '%s\n' 'export PATH="$PATH:/usr/sbin:/sbin"' > /etc/profile.d/usrsbin.sh; \
      chmod 644 /etc/profile.d/usrsbin.sh; \
    elif [ "${OS_FAMILY}" = "rhel" ]; then \
      if command -v dnf >/dev/null 2>&1; then PM=dnf; \
      elif command -v yum >/dev/null 2>&1; then PM=yum; \
      elif command -v microdnf >/dev/null 2>&1; then PM=microdnf; \
      else echo "No supported RPM package manager found" >&2; exit 1; fi; \
      $PM -y update; \
      $PM -y install \
        ca-certificates \
        curl \
        sudo \
        dbus-daemon \
        jq \
        iproute \
        iputils \
        ipcalc \
        nftables \
        shadow-utils \
        tar \
        gzip \
        procps-ng; \
      rpm --import https://pkg.cloudflareclient.com/pubkey.gpg; \
      curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo \
        > /etc/yum.repos.d/cloudflare-warp.repo; \
      $PM -y install cloudflare-warp; \
      if [ "$PM" = "microdnf" ]; then microdnf clean all; else $PM clean all || true; fi; \
    else \
      echo "Unsupported OS_FAMILY: ${OS_FAMILY}. Use rhel or debian." >&2; exit 1; \
    fi; \
    printf '%s\n' \
      'net.ipv4.ip_forward = 1' \
      'net.ipv6.conf.all.forwarding = 1' \
      'net.ipv6.conf.all.accept_ra = 2' \
      > /etc/sysctl.d/99-zzz-cloudflare-warp-connector.conf; \
    useradd -m -s /bin/bash warp; \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

# Bring in artifacts from builder stages
COPY --from=gost    /out/gost          /usr/bin/gost
COPY --from=scripts /out/entrypoint.sh /entrypoint.sh
COPY --from=scripts /out/healthcheck   /healthcheck

USER warp

RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV GOST_ARGS="-L :1080"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]