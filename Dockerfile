# syntax=docker/dockerfile:1
FROM debian:trixie AS builder

ARG TARGETARCH
ARG GLITCHTIP_DOMAIN=glitchtip.antonialoytorrens.com
ENV DEBIAN_FRONTEND=noninteractive
ENV GLITCHTIP_DOMAIN=${GLITCHTIP_DOMAIN}

RUN apt-get update -qq \
  && apt-get install -y -qq --no-install-recommends \
    curl ca-certificates wget sudo \
    python3.13 python3.13-venv python3.13-dev build-essential pkg-config patch \
    libpq-dev libxml2-dev zlib1g-dev libssl-dev libffi-dev \
    git rustc cargo tzdata nodejs npm \
  && curl -fsSL -o /tmp/pacstall.deb \
    https://github.com/pacstall/pacstall/releases/download/6.4.2/pacstall_6.4.2-pacstall1_all.deb \
  && apt-get install -y -qq /tmp/pacstall.deb \
  && rm -f /tmp/pacstall.deb \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

WORKDIR /build
COPY VERSION srclist packagelist /build/
COPY packages/ /build/packages/

RUN pacstall -BPNs -I packages/glitchtip/glitchtip.pacscript \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/pacstall /var/cache/apt/archives/*

FROM scratch AS artifact
COPY --from=builder /build/*.deb /
