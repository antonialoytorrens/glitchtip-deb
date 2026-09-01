#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

VERSION="$(tr -d '[:space:]' < VERSION)"
PKG_REVISION="${PKG_REVISION:-3}"
TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"
PKG="glitchtip_${VERSION}-${PKG_REVISION}_amd64.deb"
CHECKSUM_FILE="${PKG}.sha256"
TAG="${VERSION}-${TIMESTAMP}"
RELEASE_NAME="${TAG}"

test -f "${PKG}"
dpkg-deb -I "${PKG}" >/dev/null
sha256sum "${PKG}" > "${CHECKSUM_FILE}"
SHA256="$(awk '{print $1}' "${CHECKSUM_FILE}")"

gh release create "${TAG}" "${PKG}" "${CHECKSUM_FILE}" \
  --prerelease \
  --title "${RELEASE_NAME}" \
  --notes "SHA256: \`${SHA256}\` · commit [\`${GITHUB_SHA::7}\`](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA})"
