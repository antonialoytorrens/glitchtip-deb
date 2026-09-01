#!/usr/bin/env bash
#
# fetch-glitchtip-sources.sh — download GlitchTip backend/frontend tag archives from GitLab.
#
# Usage (usually invoked automatically by build-glitchtip-amd64-deb.sh):
#   ./scripts/fetch-glitchtip-sources.sh
#   FETCH_SOURCES=true ./scripts/fetch-glitchtip-sources.sh
#   ./scripts/fetch-glitchtip-sources.sh --force
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"

GLITCHTIP_VERSION="${GLITCHTIP_VERSION:-}"
if [ -z "${GLITCHTIP_VERSION}" ] && [ -f "${VERSION_FILE}" ]; then
  GLITCHTIP_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
fi
GLITCHTIP_VERSION="${GLITCHTIP_VERSION:-6.2.6}"

FORCE="${FETCH_SOURCES:-false}"
for arg in "$@"; do
  case "${arg}" in
    --force) FORCE=true ;;
  esac
done

BACKEND_DIR="${REPO_ROOT}/glitchtip-backend-v${GLITCHTIP_VERSION}"
FRONTEND_DIR="${REPO_ROOT}/glitchtip-frontend-v${GLITCHTIP_VERSION}"

BACKEND_URL="https://gitlab.com/glitchtip/glitchtip-backend/-/archive/v${GLITCHTIP_VERSION}/glitchtip-backend-v${GLITCHTIP_VERSION}.tar.gz"
FRONTEND_URL="https://gitlab.com/glitchtip/glitchtip-frontend/-/archive/v${GLITCHTIP_VERSION}/glitchtip-frontend-v${GLITCHTIP_VERSION}.tar.gz"

fetch_tree() {
  local url="$1"
  local dest="$2"
  local label="$3"

  if [ -d "${dest}" ] && [ "${FORCE}" != "true" ]; then
    echo ">>> ${label} already present: ${dest}"
    return 0
  fi

  if ! command -v curl &>/dev/null || ! command -v tar &>/dev/null || ! command -v gzip &>/dev/null; then
    echo "!!! curl and tar and gzip are required to download sources"
    exit 1
  fi

  echo ">>> Downloading ${label} v${GLITCHTIP_VERSION}..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  curl -fsSL -o "${tmpdir}/archive.tar.gz" "${url}"
  tar -xzf "${tmpdir}/archive.tar.gz" -C "${tmpdir}"
  rm -f "${tmpdir}/archive.tar.gz"

  local extracted
  extracted="$(find "${tmpdir}" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ -z "${extracted}" ]; then
    echo "!!! Archive for ${label} did not contain a top-level directory"
    exit 1
  fi

  rm -rf "${dest}"
  mv "${extracted}" "${dest}"
  echo ">>> ${label} ready: ${dest}"
}

fetch_tree "${BACKEND_URL}" "${BACKEND_DIR}" "backend"
fetch_tree "${FRONTEND_URL}" "${FRONTEND_DIR}" "frontend"
