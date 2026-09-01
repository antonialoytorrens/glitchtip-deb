#!/usr/bin/env bash
#
# check-glitchtip-version.sh — compare packaged VERSION against release-monitoring.org (Anitya).
#
# Set VERSION=<upstream> to skip the Anitya API and compare against that version
# instead (useful when release-monitoring.org is down or blocked).
#
# Exit codes:
#   0 — packaged version is up to date
#   1 — a newer stable version is available (prints version to stdout)
#   2 — API or parse error
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGED_VERSION_FILE="${PACKAGED_VERSION_FILE:-${REPO_ROOT}/VERSION}"
ANITYA_PROJECT_ID="${ANITYA_PROJECT_ID:-392074}"
ANITYA_API_URL="${ANITYA_API_URL:-https://release-monitoring.org/api/v2/versions/?project_id=${ANITYA_PROJECT_ID}}"
ANITYA_USER_AGENT="${ANITYA_USER_AGENT:-glitchtip-deb-packaging/1.0 (+https://github.com/antonialoytorrens/glitchtip-deb)}"
CACHE_DIR="${REPO_ROOT}/.cache"
CACHE_FILE="${CACHE_DIR}/anitya-last-check"

if [ ! -f "${PACKAGED_VERSION_FILE}" ]; then
  echo "!!! Packaged version file not found: ${PACKAGED_VERSION_FILE}" >&2
  exit 2
fi

PACKAGED_VERSION="$(tr -d '[:space:]' < "${PACKAGED_VERSION_FILE}")"

if [ -n "${VERSION:-}" ]; then
  LATEST_STABLE="$(printf '%s' "${VERSION}" | tr -d '[:space:]')"
  echo ">>> Using VERSION=${LATEST_STABLE} (skipping release-monitoring.org)" >&2
else
  if ! command -v python3 &>/dev/null; then
    echo "!!! python3 is required" >&2
    exit 2
  fi

  RESPONSE="$(curl -fsS -A "${ANITYA_USER_AGENT}" "${ANITYA_API_URL}")" || {
    echo "!!! Failed to query Anitya API: ${ANITYA_API_URL}" >&2
    echo "!!! Hint: set VERSION=<upstream> to compare without release-monitoring.org" >&2
    exit 2
  }

  PARSED="$(printf '%s' "${RESPONSE}" | python3 -c '
import json, sys
data = json.load(sys.stdin)
stable = data.get("stable_versions") or []
latest = stable[0] if stable else data.get("version") or data.get("latest_version")
created = data.get("latest_version_created_on") or ""
if not latest:
    raise SystemExit(2)
print(f"{latest}\t{created}")
' 2>/dev/null)" || {
    echo "!!! Failed to parse Anitya API response" >&2
    echo "!!! Hint: set VERSION=<upstream> to compare without release-monitoring.org" >&2
    exit 2
  }

  LATEST_STABLE="${PARSED%%$'\t'*}"
  LATEST_CREATED_ON="${PARSED#*$'\t'}"

  mkdir -p "${CACHE_DIR}"
  cat > "${CACHE_FILE}" << EOF
latest_stable_version=${LATEST_STABLE}
latest_version_created_on=${LATEST_CREATED_ON}
checked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
fi

if [ "${PACKAGED_VERSION}" = "${LATEST_STABLE}" ]; then
  echo "Up to date: ${PACKAGED_VERSION}"
  exit 0
fi

NEWER="$(printf '%s\n%s\n' "${PACKAGED_VERSION}" "${LATEST_STABLE}" | sort -V | tail -1)"
if [ "${NEWER}" = "${LATEST_STABLE}" ]; then
  echo "${LATEST_STABLE}"
  echo "Newer stable version available: packaged ${PACKAGED_VERSION}, upstream ${LATEST_STABLE}" >&2
  exit 1
fi

echo "Up to date: packaged ${PACKAGED_VERSION} (ahead of or equal to upstream stable ${LATEST_STABLE})"
exit 0
