#!/usr/bin/env bash
#
# build-glitchtip-amd64-deb.sh
#
# Builds a .deb package of GlitchTip with an embedded virtualenv (plus the
# backend source checkout and compiled frontend static assets).
#
# Sources are downloaded automatically from GitLab tags when missing.
#
# Usage:
#   chmod +x build-glitchtip-amd64-deb.sh
#   sudo ./build-glitchtip-amd64-deb.sh
#
# Environment variables (all optional):
#   GLITCHTIP_VERSION            (default: VERSION file, then 6.2.6)
#   GLITCHTIP_DOMAIN             (default: glitchtip.antonialoytorrens.com)
#   GLITCHTIP_DB_NAME            (default: glitchtip)
#   GLITCHTIP_DB_USER            (default: glitchtip)
#   GLITCHTIP_DB_HOST            (default: 127.0.0.1)
#   PKG_REVISION                 (default: 1)
#   INSTALL_PREFIX               (default: /opt/glitchtip)
#   KEEP_CHROOT                  (default: true — chroot mode only)
#   DISABLE_DEBOOTSTRAP_CHROOT   (default: false — set true to build on host)
#   FETCH_SOURCES                (default: false — force re-download of tags)
#
# Trimmed dependency profile (local PostgreSQL + filesystem; see README):
#   - patches/0001-trim-optional-deps.patch removes optional deps (DuckDB, MCP, cloud storage, uWSGI, …)
#   - GLITCHTIP_ENABLE_DUCKDB=false and GLITCHTIP_ENABLE_MCP=false in glitchtip.env
#
# Example:
#   GLITCHTIP_DOMAIN=errors.acme.org sudo -E ./build-glitchtip-amd64-deb.sh
#   DISABLE_DEBOOTSTRAP_CHROOT=true sudo -E ./build-glitchtip-amd64-deb.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}"
VERSION_FILE="${SCRIPT_DIR}/VERSION"

if [ -z "${GLITCHTIP_VERSION:-}" ] && [ -f "${VERSION_FILE}" ]; then
  GLITCHTIP_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
fi
GLITCHTIP_VERSION="${GLITCHTIP_VERSION:-6.2.6}"

PKG_REVISION="${PKG_REVISION:-1}"
KEEP_CHROOT="${KEEP_CHROOT:-true}"
DISABLE_DEBOOTSTRAP_CHROOT="${DISABLE_DEBOOTSTRAP_CHROOT:-false}"
FETCH_SOURCES="${FETCH_SOURCES:-false}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/glitchtip}"
VENV_DIR="${INSTALL_PREFIX}/venv"
SRC_DIR="${INSTALL_PREFIX}/src"
PKG_NAME="${PKG_NAME:-glitchtip}"
ARCH="amd64"

GLITCHTIP_DOMAIN="${GLITCHTIP_DOMAIN:-glitchtip.antonialoytorrens.com}"
GLITCHTIP_DB_NAME="${GLITCHTIP_DB_NAME:-glitchtip}"
GLITCHTIP_DB_USER="${GLITCHTIP_DB_USER:-glitchtip}"
GLITCHTIP_DB_HOST="${GLITCHTIP_DB_HOST:-127.0.0.1}"

DESCRIPTION="GlitchTip ${GLITCHTIP_VERSION} for ${GLITCHTIP_DOMAIN} (bundled venv)"
CHROOT_DIR="${CHROOT_BASE:-/home/$(whoami)/glitchtip-build-$(head -c6 /dev/urandom | xxd -p)}"
DEB_FILE="${PKG_NAME}_${GLITCHTIP_VERSION}-${PKG_REVISION}_${ARCH}.deb"
INNER_SCRIPT="${SCRIPT_DIR}/scripts/build-glitchtip-inner.sh"
FETCH_SCRIPT="${SCRIPT_DIR}/scripts/fetch-glitchtip-sources.sh"

CHROOT_ACTIVE=false

export_build_env() {
  export OUTPUT_DIR="$1"
  export GLITCHTIP_VERSION GLITCHTIP_DOMAIN
  export GLITCHTIP_DB_NAME GLITCHTIP_DB_USER GLITCHTIP_DB_HOST
  export SRC_DIR VENV_DIR PKG_NAME PKG_REVISION ARCH DESCRIPTION DEB_FILE
}

cleanup() {
  if [ "${CHROOT_ACTIVE}" != "true" ]; then
    return 0
  fi
  echo ">>> Unmounting chroot bind mounts..."
  umount "${CHROOT_DIR}/output" 2>/dev/null || true
  umount "${CHROOT_DIR}/proc" 2>/dev/null || true
  umount "${CHROOT_DIR}/sys" 2>/dev/null || true
  umount "${CHROOT_DIR}/dev/pts" 2>/dev/null || true
  umount "${CHROOT_DIR}/dev" 2>/dev/null || true
  if [ "${KEEP_CHROOT}" = "true" ]; then
    echo ">>> KEEP_CHROOT=true, leaving chroot in place for inspection: ${CHROOT_DIR}"
  else
    echo ">>> Removing chroot..."
    rm -rf "${CHROOT_DIR}"
  fi
}
trap cleanup EXIT INT TERM

echo "Building GlitchTip ${GLITCHTIP_VERSION} for ${ARCH}"
echo "  Domain:   ${GLITCHTIP_DOMAIN}"
echo "  DB:       ${GLITCHTIP_DB_USER}@${GLITCHTIP_DB_HOST}/${GLITCHTIP_DB_NAME}"
echo "  Sources:  ${BUILD_DIR}"
echo "  Chroot:   $([ "${DISABLE_DEBOOTSTRAP_CHROOT}" = "true" ] && echo disabled || echo "${CHROOT_DIR}")"
echo ""

if [ ! -x "${FETCH_SCRIPT}" ]; then
  chmod +x "${FETCH_SCRIPT}"
fi
GLITCHTIP_VERSION="${GLITCHTIP_VERSION}" FETCH_SOURCES="${FETCH_SOURCES}" "${FETCH_SCRIPT}"

if [ ! -x "${INNER_SCRIPT}" ]; then
  chmod +x "${INNER_SCRIPT}"
fi

if [ "${DISABLE_DEBOOTSTRAP_CHROOT}" = "true" ]; then
  echo ">>> Building on host (DISABLE_DEBOOTSTRAP_CHROOT=true)..."
  export_build_env "${BUILD_DIR}"
  bash "${INNER_SCRIPT}"
else
  if ! command -v debootstrap &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq debootstrap
  fi

  echo ">>> Bootstrapping Debian Trixie chroot (amd64, native)..."
  debootstrap --arch=amd64 --variant=minbase trixie "${CHROOT_DIR}" http://deb.debian.org/debian

  mount -t proc proc "${CHROOT_DIR}/proc"
  mount -t sysfs sys "${CHROOT_DIR}/sys"
  mount --bind /dev "${CHROOT_DIR}/dev"
  mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"

  mkdir -p "${CHROOT_DIR}/output"
  mount --bind "${BUILD_DIR}" "${CHROOT_DIR}/output"

  cp "${INNER_SCRIPT}" "${CHROOT_DIR}/build-glitchtip-inner.sh"
  chmod +x "${CHROOT_DIR}/build-glitchtip-inner.sh"

  CHROOT_ACTIVE=true

  echo ">>> Entering chroot (this may take a while: npm + uv sync + Rust builds)..."
  chroot "${CHROOT_DIR}" env \
    OUTPUT_DIR=/output \
    GLITCHTIP_VERSION="${GLITCHTIP_VERSION}" \
    GLITCHTIP_DOMAIN="${GLITCHTIP_DOMAIN}" \
    GLITCHTIP_DB_NAME="${GLITCHTIP_DB_NAME}" \
    GLITCHTIP_DB_USER="${GLITCHTIP_DB_USER}" \
    GLITCHTIP_DB_HOST="${GLITCHTIP_DB_HOST}" \
    SRC_DIR="${SRC_DIR}" \
    VENV_DIR="${VENV_DIR}" \
    PKG_NAME="${PKG_NAME}" \
    PKG_REVISION="${PKG_REVISION}" \
    ARCH="${ARCH}" \
    DESCRIPTION="${DESCRIPTION}" \
    DEB_FILE="${DEB_FILE}" \
    /build-glitchtip-inner.sh

  umount "${CHROOT_DIR}/output" 2>/dev/null || true
  CHROOT_ACTIVE=false
fi

DEB_PATH="${SCRIPT_DIR}/${DEB_FILE}"
DEB_SIZE=$(du -h "${DEB_PATH}" 2>/dev/null | cut -f1 || echo "unknown")

echo ""
echo "Package: ${DEB_PATH} (${DEB_SIZE})"
echo "Domain:  ${GLITCHTIP_DOMAIN}"
echo ""
echo "Install on the target host:"
echo "  sudo dpkg -i ${DEB_FILE}"
echo "  sudo apt-get install -f"
