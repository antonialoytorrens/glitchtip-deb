# syntax=docker/dockerfile:1
FROM debian:trixie AS builder

ARG TARGETARCH
ARG PACSTALL_VERSION=6.4.2-pacstall1
ARG SPDX_LICENSES_VERSION=3.27.0+ds-1
ARG GLITCHTIP_DOMAIN=glitchtip.antonialoytorrens.com
ENV DEBIAN_FRONTEND=noninteractive
ENV GLITCHTIP_DOMAIN=${GLITCHTIP_DOMAIN}

RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    ca-certificates sudo \
    python3.13 python3.13-venv python3.13-dev build-essential pkg-config patch \
    libpq-dev libxml2-dev zlib1g-dev libssl-dev libffi-dev \
    git rustc cargo tzdata nodejs npm

ADD https://github.com/pacstall/pacstall/releases/download/6.4.2/pacstall_${PACSTALL_VERSION}_all.deb \
  /var/cache/apt/archives/pacstall_${PACSTALL_VERSION}_all.deb
ADD https://ftp.debian.org/debian/pool/main/s/spdx-licenses/spdx-licenses_${SPDX_LICENSES_VERSION}_all.deb \
  /var/cache/apt/archives/spdx-licenses_${SPDX_LICENSES_VERSION}_all.deb

RUN apt-get install -y -qq -f \
    /var/cache/apt/archives/pacstall_${PACSTALL_VERSION}_all.deb \
    /var/cache/apt/archives/spdx-licenses_${SPDX_LICENSES_VERSION}_all.deb

RUN apt-get clean \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /build
COPY VERSION srclist packagelist /build/
COPY packages/ /build/packages/

RUN pacstall -BPNs -I packages/glitchtip/glitchtip.pacscript \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
