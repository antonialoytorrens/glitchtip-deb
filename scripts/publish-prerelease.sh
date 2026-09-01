#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

VERSION="$(tr -d '[:space:]' < VERSION)"
PKG="glitchtip_${VERSION}-1_amd64.deb"
CHECKSUM_FILE="${PKG}.sha256"
TAG="v${VERSION}-pre.${GITHUB_RUN_NUMBER}"

test -f "${PKG}"
dpkg-deb -I "${PKG}" >/dev/null
sha256sum "${PKG}" > "${CHECKSUM_FILE}"
SHA256="$(awk '{print $1}' "${CHECKSUM_FILE}")"

gh release create "${TAG}" "${PKG}" "${CHECKSUM_FILE}" \
  --prerelease \
  --title "GlitchTip ${VERSION} pre-release #${GITHUB_RUN_NUMBER}" \
  --notes "SHA256: \`${SHA256}\` · commit [\`${GITHUB_SHA::7}\`](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA})"
