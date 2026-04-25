# syntax=docker/dockerfile:1

ARG BASE_IMAGE=redhat/ubi9-minimal:9.5

FROM ${BASE_IMAGE}

ARG OS_FAMILY=rhel
ARG WARP_VERSION
ARG GOST_VERSION
ARG COMMIT_SHA
ARG TARGETPLATFORM

LABEL org.opencontainers.image.authors="jasonkolodziej"
LABEL org.opencontainers.image.url="https://github.com/jasonkolodziej/cloudflare-warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

RUN --mount=type=cache,target=/var/cache/gost \
  case ${TARGETPLATFORM} in \
      "linux/amd64")   ARCH_NEW="amd64"; ARCH_LEGACY="amd64" ;; \
      "linux/arm64")   ARCH_NEW="arm64"; ARCH_LEGACY="armv8" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    if [ "${OS_FAMILY}" = "debian" ]; then \
      export DEBIAN_FRONTEND=noninteractive && \
      export TZ=UTC && \
      apt-get update && \
      apt-get upgrade -y && \
      apt-get install -y \
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
        procps && \
      curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list && \
      apt-get update && \
      apt-get install -y cloudflare-warp && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* && \
      # Debian's /etc/profile sets a non-root PATH that excludes /usr/sbin.
      # nft (nftables) and ip (iproute2) live in /usr/sbin; add it for all login shells.
      printf '%s\n' 'export PATH="$PATH:/usr/sbin:/sbin"' > /etc/profile.d/usrsbin.sh && \
      chmod 644 /etc/profile.d/usrsbin.sh; \
    elif [ "${OS_FAMILY}" = "rhel" ]; then \
      if command -v dnf >/dev/null 2>&1; then PM=dnf; \
      elif command -v yum >/dev/null 2>&1; then PM=yum; \
      elif command -v microdnf >/dev/null 2>&1; then PM=microdnf; \
      else echo "No supported RPM package manager found" && exit 1; fi && \
      $PM -y update && \
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
        procps-ng && \
      rpm --import https://pkg.cloudflareclient.com/pubkey.gpg && \
      curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo > /etc/yum.repos.d/cloudflare-warp.repo && \
      $PM -y install cloudflare-warp && \
      if [ "$PM" = "microdnf" ]; then microdnf clean all; else $PM clean all || true; fi; \
    else \
      echo "Unsupported OS_FAMILY: ${OS_FAMILY}. Use rhel or debian." && exit 1; \
    fi && \
    printf '%s\n' \
      'net.ipv4.ip_forward = 1' \
      'net.ipv6.conf.all.forwarding = 1' \
      'net.ipv6.conf.all.accept_ra = 2' \
      > /etc/sysctl.d/99-zzz-cloudflare-warp-connector.conf && \
    MAJOR_VERSION=$(echo ${GOST_VERSION} | cut -d. -f1) && \
    MINOR_VERSION=$(echo ${GOST_VERSION} | cut -d. -f2) && \
    if [ "${MAJOR_VERSION}" -ge 3 ] || [ "${MAJOR_VERSION}" -eq 2 -a "${MINOR_VERSION}" -ge 12 ]; then \
      FILE_NAME="gost_${GOST_VERSION}_linux_${ARCH_NEW}.tar.gz"; \
    else \
      FILE_NAME="gost-linux-${ARCH_LEGACY}-${GOST_VERSION}.gz"; \
    fi && \
    if [ ! -f /var/cache/gost/${FILE_NAME} ]; then \
      curl -fL \
        --retry 6 \
        --retry-all-errors \
        --retry-delay 2 \
        --connect-timeout 15 \
        --max-time 300 \
        -o /var/cache/gost/${FILE_NAME} \
        "https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/${FILE_NAME}"; \
    fi && \
    cp /var/cache/gost/${FILE_NAME} /tmp/${FILE_NAME} && \
    if echo "${FILE_NAME}" | grep -q '.tar.gz$'; then \
      tar -xzf /tmp/${FILE_NAME} -C /usr/bin gost; \
    else \
      gunzip /tmp/${FILE_NAME} && \
      mv /tmp/gost-linux-* /usr/bin/gost; \
    fi && \
    chmod +x /usr/bin/gost && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

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