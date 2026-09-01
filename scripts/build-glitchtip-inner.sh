#!/usr/bin/env bash
#
# build-glitchtip-inner.sh — package GlitchTip into a .deb (runs inside chroot or on host).
#
# Required environment (set by build-glitchtip-amd64-deb.sh):
#   OUTPUT_DIR, GLITCHTIP_VERSION, GLITCHTIP_DOMAIN, GLITCHTIP_DB_*,
#   GLITCHTIP_HTTP_PORT, SRC_DIR, VENV_DIR, PKG_NAME, PKG_REVISION, ...
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
: "${GLITCHTIP_VERSION:?GLITCHTIP_VERSION is required}"
: "${GLITCHTIP_DOMAIN:?GLITCHTIP_DOMAIN is required}"
: "${GLITCHTIP_DB_NAME:?GLITCHTIP_DB_NAME is required}"
: "${GLITCHTIP_DB_USER:?GLITCHTIP_DB_USER is required}"
: "${GLITCHTIP_DB_HOST:?GLITCHTIP_DB_HOST is required}"
: "${GLITCHTIP_HTTP_PORT:?GLITCHTIP_HTTP_PORT is required}"
: "${SRC_DIR:?SRC_DIR is required}"
: "${VENV_DIR:?VENV_DIR is required}"
: "${PKG_NAME:?PKG_NAME is required}"
: "${PKG_REVISION:?PKG_REVISION is required}"
: "${ARCH:?ARCH is required}"
: "${DESCRIPTION:?DESCRIPTION is required}"
: "${DEB_FILE:?DEB_FILE is required}"

apt-get update -qq
apt-get install -y -qq \
  python3 python3-venv python3-dev python3-pip \
  build-essential pkg-config patch \
  libpq-dev libxml2-dev zlib1g-dev \
  libssl-dev libffi-dev \
  curl ca-certificates tzdata git \
  ruby ruby-dev \
  rustc cargo

if ! command -v fpm &>/dev/null; then
  gem install --no-document fpm
fi

echo ">>> Installing uv..."
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="/root/.local/bin:${HOME}/.local/bin:${PATH}"
UV_BIN="$(command -v uv || true)"
if [ -z "${UV_BIN}" ] || [ ! -x "${UV_BIN}" ]; then
  echo "!!! uv not found after install"
  ls -la /root/.local/bin/ "${HOME}/.local/bin/" 2>/dev/null || true
  exit 1
fi

echo ">>> Installing Node.js/npm for the Angular build..."
if ! (curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
      && apt-get install -y -qq nodejs); then
  echo ">>> NodeSource setup failed, falling back to distro nodejs/npm..."
  rm -f /etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  apt-get install -y -qq nodejs npm
fi

BUILD_ROOT="$(mktemp -d)"
FRONTEND_SRC="${OUTPUT_DIR}/glitchtip-frontend-v${GLITCHTIP_VERSION}"
BACKEND_SRC="${OUTPUT_DIR}/glitchtip-backend-v${GLITCHTIP_VERSION}"

if [ ! -d "${FRONTEND_SRC}" ] || [ ! -d "${BACKEND_SRC}" ]; then
  echo "!!! Expected source trees not found:"
  echo "    ${FRONTEND_SRC}"
  echo "    ${BACKEND_SRC}"
  exit 1
fi

echo ">>> Copying backend source to ${SRC_DIR}..."
mkdir -p "${BUILD_ROOT}${SRC_DIR}"
cp -a "${BACKEND_SRC}/." "${BUILD_ROOT}${SRC_DIR}/"

echo ">>> Applying patches (if any)..."
shopt -s nullglob
for p in "${OUTPUT_DIR}"/patches/*.patch; do
  echo "    ${p}"
  patch -p1 -d "${BUILD_ROOT}${SRC_DIR}" < "${p}"
done
shopt -u nullglob

echo ">>> Building frontend assets (npm ci + npm run build-prod)..."
(
  cd "${FRONTEND_SRC}"
  npm ci
  npm run build-prod
)
mkdir -p "${BUILD_ROOT}${SRC_DIR}/dist"
rm -rf "${BUILD_ROOT}${SRC_DIR}/dist/"*
cp -a "${FRONTEND_SRC}/dist/glitchtip-frontend/browser/." "${BUILD_ROOT}${SRC_DIR}/dist/"
echo "    Frontend dist: $(du -sh "${BUILD_ROOT}${SRC_DIR}/dist" | cut -f1)"

echo ">>> Creating virtualenv and installing Python dependencies (uv sync)..."
mkdir -p "${BUILD_ROOT}${VENV_DIR}"
python3 -m venv "${BUILD_ROOT}${VENV_DIR}"
export UV_PROJECT_ENVIRONMENT="${BUILD_ROOT}${VENV_DIR}"
if [ -n "$(find "${OUTPUT_DIR}/patches" -maxdepth 1 -name '*.patch' -print -quit 2>/dev/null)" ]; then
  echo ">>> Refreshing uv.lock (patches may have changed dependencies)..."
  (cd "${BUILD_ROOT}${SRC_DIR}" && "${UV_BIN}" lock)
fi
(
  cd "${BUILD_ROOT}${SRC_DIR}"
  "${UV_BIN}" sync --frozen --no-dev
)

echo ">>> Patching venv paths..."
sed -i "s|${BUILD_ROOT}||g" "${BUILD_ROOT}${VENV_DIR}/pyvenv.cfg"
find "${BUILD_ROOT}${VENV_DIR}/bin" -type f -exec sed -i "s|${BUILD_ROOT}||g" {} +

echo ">>> Pruning venv..."
rm -rf "${BUILD_ROOT}${VENV_DIR}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources} 2>/dev/null || true
rm -rf "${BUILD_ROOT}${VENV_DIR}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info 2>/dev/null || true
find "${BUILD_ROOT}${VENV_DIR}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "${BUILD_ROOT}${VENV_DIR}" -name "*.pyc" -delete 2>/dev/null || true
find "${BUILD_ROOT}${VENV_DIR}" -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
echo "    Pruned venv: $(du -sh "${BUILD_ROOT}${VENV_DIR}" | cut -f1)"

find "${BUILD_ROOT}${SRC_DIR}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
echo "    Backend source: $(du -sh "${BUILD_ROOT}${SRC_DIR}" | cut -f1)"

mkdir -p "${BUILD_ROOT}/etc/glitchtip"
cat > "${BUILD_ROOT}/etc/glitchtip/glitchtip.env" << ENVFILE
SECRET_KEY=__SECRETKEY_PLACEHOLDER__
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=noreply@${GLITCHTIP_DOMAIN}
GLITCHTIP_DOMAIN=https://${GLITCHTIP_DOMAIN}
ALLOWED_HOSTS=${GLITCHTIP_DOMAIN}
CSRF_TRUSTED_ORIGINS=https://${GLITCHTIP_DOMAIN}
GLITCHTIP_VERSION=${GLITCHTIP_VERSION}
GLITCHTIP_ENABLE_DUCKDB=false
GLITCHTIP_ENABLE_MCP=false
MEDIA_ROOT=/var/lib/glitchtip/uploads
STATIC_ROOT=/var/lib/glitchtip/static
VALKEY_URL=redis://127.0.0.1:6379/0
GLITCHTIP_HTTP_PORT=${GLITCHTIP_HTTP_PORT}
DJANGO_SETTINGS_MODULE=glitchtip.settings
LOG_LEVEL=WARNING
ENVFILE

mkdir -p "${BUILD_ROOT}/etc/systemd/system"

cat > "${BUILD_ROOT}/etc/systemd/system/glitchtip.service" << 'SVCWEB'
[Unit]
Description=GlitchTip web server (granian)
After=network.target postgresql.service valkey-server.service
Wants=postgresql.service valkey-server.service

[Service]
Type=simple
User=glitchtip
Group=glitchtip
EnvironmentFile=/etc/glitchtip/glitchtip.env
WorkingDirectory=/opt/glitchtip/src
ExecStart=/bin/bash -c 'exec /opt/glitchtip/venv/bin/granian \
  --interface asginl \
  glitchtip.asgi:application \
  --host 127.0.0.1 \
  --port "${GLITCHTIP_HTTP_PORT}" \
  --workers 1 \
  --no-ws'
Restart=on-failure
RestartSec=5
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SVCWEB

cat > "${BUILD_ROOT}/etc/systemd/system/glitchtip-worker.service" << 'SVCWORKER'
[Unit]
Description=GlitchTip background worker
After=network.target postgresql.service valkey-server.service glitchtip.service
Wants=postgresql.service valkey-server.service

[Service]
Type=simple
User=glitchtip
Group=glitchtip
EnvironmentFile=/etc/glitchtip/glitchtip.env
Environment=IS_WORKER=true
WorkingDirectory=/opt/glitchtip/src
ExecStart=/opt/glitchtip/venv/bin/python manage.py runworker --scheduler
Restart=on-failure
RestartSec=10
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SVCWORKER

mkdir -p "${BUILD_ROOT}/var/lib/glitchtip/uploads"
mkdir -p "${BUILD_ROOT}/var/lib/glitchtip/static"
mkdir -p "${BUILD_ROOT}/var/log/glitchtip"

mkdir -p "${BUILD_ROOT}/usr/share/dbconfig-common/data/glitchtip/install"
cat > "${BUILD_ROOT}/usr/share/dbconfig-common/data/glitchtip/install/pgsql" << 'DBCSQL'
-- GlitchTip: schema managed by Django migrations (manage.py migrate)
SELECT 1;
DBCSQL

DEB_CONFIG=$(mktemp)
cat > "${DEB_CONFIG}" << 'DEBCONF'
#!/bin/sh
set -e
. /usr/share/debconf/confmodule
if [ -f /usr/share/dbconfig-common/dpkg/config.pgsql ]; then
  dbc_dbname="__DB_NAME__"
  dbc_dbuser="__DB_USER__"
  . /usr/share/dbconfig-common/dpkg/config.pgsql
  dbc_go glitchtip "$@"
fi
DEBCONF
sed -i \
  -e "s|__DB_NAME__|${GLITCHTIP_DB_NAME}|g" \
  -e "s|__DB_USER__|${GLITCHTIP_DB_USER}|g" \
  "${DEB_CONFIG}"
chmod 755 "${DEB_CONFIG}"

AFTER_INSTALL=$(mktemp)
cat > "${AFTER_INSTALL}" << 'POSTINST'
#!/bin/bash
set -e

SRC="/opt/glitchtip/src"
VENV="/opt/glitchtip/venv"
ENV_FILE="/etc/glitchtip/glitchtip.env"

if [ -f /usr/share/dbconfig-common/dpkg/postinst.pgsql ]; then
  . /usr/share/debconf/confmodule
  . /usr/share/dbconfig-common/dpkg/postinst.pgsql
  dbc_go glitchtip "$@"
fi

case "$1" in
  configure|reconfigure) ;;
  *) exit 0 ;;
esac

if ! id -u glitchtip &>/dev/null; then
  adduser --system --group --home /var/lib/glitchtip \
    --no-create-home --shell /bin/bash glitchtip
  echo ">>> Created system user 'glitchtip'."
fi

mkdir -p /var/lib/glitchtip/uploads /var/lib/glitchtip/static
chown -R glitchtip:glitchtip /var/lib/glitchtip /var/log/glitchtip

run_as_glitchtip() {
  runuser -u glitchtip -- bash -c '
    set -a
    # shellcheck disable=SC1090
    source "$1"
    set +a
    cd "$2" || exit 1
    shift 2
    exec "$@"
  ' bash "${ENV_FILE}" "${SRC}" "$@"
}

if grep -q '__SECRETKEY_PLACEHOLDER__' "${ENV_FILE}"; then
  SECRET=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
  sed -i "s|__SECRETKEY_PLACEHOLDER__|${SECRET}|" "${ENV_FILE}"
  echo ">>> Generated SECRET_KEY."
fi

if ! systemctl is-active --quiet postgresql; then
  echo "!!! postgresql is not running. Database setup and migrations require PostgreSQL." >&2
  exit 1
fi

write_db_env_from_dbconfig() {
  # shellcheck disable=SC1091
  . /etc/dbconfig-common/glitchtip.conf
  local db_host="${dbc_dbserver:-127.0.0.1}"
  case "${db_host}" in
    local|localhost) db_host="127.0.0.1" ;;
  esac
  grep -vE '^(DATABASE_NAME|DATABASE_USER|DATABASE_PASSWORD|DATABASE_HOST|DATABASE_PORT)=' \
    "${ENV_FILE}" > "${ENV_FILE}.tmp"
  {
    cat "${ENV_FILE}.tmp"
    echo "DATABASE_NAME=${dbc_dbname}"
    echo "DATABASE_USER=${dbc_dbuser}"
    case "${dbc_authmethod_user}:${dbc_dbserver:-local}" in
      ident:local|ident:|ident:localhost|ident:127.0.0.1)
        ;;
      *)
        echo "DATABASE_PASSWORD=${dbc_dbpass}"
        echo "DATABASE_HOST=${db_host}"
        echo "DATABASE_PORT=${dbc_dbport:-5432}"
        ;;
    esac
  } > "${ENV_FILE}"
  rm -f "${ENV_FILE}.tmp"
  echo ">>> Database env updated from dbconfig."
}

ensure_postgres_from_dbconfig() {
  # shellcheck disable=SC1091
  . /etc/dbconfig-common/glitchtip.conf
  if runuser -u postgres -- psql -tc \
    "SELECT 1 FROM pg_roles WHERE rolname='${dbc_dbuser}'" | grep -q 1; then
    if [ "${dbc_authmethod_user}" != "ident" ] && [ -n "${dbc_dbpass}" ]; then
      runuser -u postgres -- psql -c \
        "ALTER ROLE ${dbc_dbuser} WITH PASSWORD '${dbc_dbpass}';" 2>/dev/null || true
    fi
  elif [ "${dbc_authmethod_user}" = "ident" ]; then
    runuser -u postgres -- psql -c \
      "CREATE ROLE ${dbc_dbuser} WITH LOGIN;"
  else
    runuser -u postgres -- psql -c \
      "CREATE ROLE ${dbc_dbuser} WITH LOGIN PASSWORD '${dbc_dbpass}';"
  fi
  runuser -u postgres -- psql -tc \
    "SELECT 1 FROM pg_database WHERE datname='${dbc_dbname}'" \
    | grep -q 1 \
    || runuser -u postgres -- createdb -O "${dbc_dbuser}" "${dbc_dbname}"
  echo ">>> PostgreSQL role/database ready (${dbc_dbname})."
}

# #region agent log
_debug_log() {
  python3 -c "
import json, time, os
payload = {
    'sessionId': '7268f9',
    'hypothesisId': os.environ.get('_DBG_HID', 'H0'),
    'location': os.environ.get('_DBG_LOC', 'postinst'),
    'message': os.environ.get('_DBG_MSG', ''),
    'data': json.loads(os.environ.get('_DBG_DATA', '{}')),
    'timestamp': int(time.time() * 1000),
}
open('/home/antonialoy/Seafile/Ikaue/CodeProjects/packaging/glitchtip-deb/.cursor/debug-7268f9.log', 'a').write(json.dumps(payload) + '\n')
" 2>/dev/null || true
}
# #endregion

if [ -f /etc/dbconfig-common/glitchtip.conf ]; then
  write_db_env_from_dbconfig
  ensure_postgres_from_dbconfig
  # #region agent log
  _DBG_HID=H1 _DBG_LOC=postinst:dbconfig _DBG_MSG=env_written \
    _DBG_DATA="$(python3 -c "import re; t=open('${ENV_FILE}').read(); print(__import__('json').dumps({k.split('=')[0]:k.split('=')[1] for k in t.splitlines() if k.startswith('DATABASE_') and 'PASSWORD' not in k}))")" \
    _debug_log
  # #endregion
else
  echo ">>> dbconfig-no-thanks: setting up PostgreSQL locally."
  DB_NAME="__DB_NAME__"
  DB_USER="__DB_USER__"
  DB_HOST="__DB_HOST__"
  DB_PASS=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
  grep -vE '^(DATABASE_NAME|DATABASE_USER|DATABASE_PASSWORD|DATABASE_HOST|DATABASE_PORT)=' \
    "${ENV_FILE}" > "${ENV_FILE}.tmp"
  {
    cat "${ENV_FILE}.tmp"
    echo "DATABASE_NAME=${DB_NAME}"
    echo "DATABASE_USER=${DB_USER}"
    echo "DATABASE_PASSWORD=${DB_PASS}"
    echo "DATABASE_HOST=${DB_HOST}"
    echo "DATABASE_PORT=5432"
  } > "${ENV_FILE}"
  rm -f "${ENV_FILE}.tmp"

  if runuser -u postgres -- psql -tc \
    "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
    runuser -u postgres -- psql -c \
      "ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASS}';" 2>/dev/null || true
  else
    runuser -u postgres -- psql -c \
      "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';"
  fi
  echo ">>> PostgreSQL role '${DB_USER}' ready."

  runuser -u postgres -- psql -tc \
    "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" \
    | grep -q 1 \
    || runuser -u postgres -- createdb -O "${DB_USER}" "${DB_NAME}"
  echo ">>> PostgreSQL database '${DB_NAME}' ready."
fi

chmod 640 "${ENV_FILE}"
chown root:glitchtip "${ENV_FILE}"

if ! systemctl is-active --quiet valkey-server; then
  echo "!!! valkey-server is not running. Worker requires Valkey on 127.0.0.1:6379." >&2
  exit 1
fi

echo ">>> Verifying database connection..."
run_as_glitchtip "${VENV}/bin/python" -c "
import os, json, time
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'glitchtip.settings')
import django
django.setup()
from django.conf import settings
db = settings.DATABASES['default']
# #region agent log
log = {
    'sessionId': '7268f9',
    'hypothesisId': 'H2',
    'location': 'postinst:verify_db',
    'message': 'django_databases_default',
    'data': {k: db.get(k) for k in ('NAME', 'USER', 'HOST', 'PORT', 'ENGINE') if k in db},
    'timestamp': int(time.time() * 1000),
}
open('/home/antonialoy/Seafile/Ikaue/CodeProjects/packaging/glitchtip-deb/.cursor/debug-7268f9.log', 'a').write(json.dumps(log) + '\n')
# #endregion
from django.db import connection
connection.ensure_connection()
print('>>> Database connection OK.')
"

echo ">>> Running migrations..."
run_as_glitchtip "${VENV}/bin/python" "${SRC}/manage.py" migrate --no-input

echo ">>> Maintaining partitions..."
run_as_glitchtip "${VENV}/bin/python" "${SRC}/manage.py" maintain_partitions || true

echo ">>> Collecting static files..."
run_as_glitchtip "${VENV}/bin/python" "${SRC}/manage.py" collectstatic --no-input

if id -u www-data &>/dev/null; then
  usermod -aG glitchtip www-data
fi

chmod 750 /var/lib/glitchtip
chmod -R g+rX /var/lib/glitchtip/static 2>/dev/null || true

systemctl daemon-reload
systemctl enable --now glitchtip glitchtip-worker
echo ">>> Services glitchtip and glitchtip-worker enabled."
echo ""
echo ">>> GlitchTip is ready at the URL configured in ${ENV_FILE}"
echo ">>> Configure nginx/apache to proxy https://YOUR_DOMAIN/ to http://127.0.0.1:__HTTP_PORT__"
echo ">>> Set a real EMAIL_URL in ${ENV_FILE} for outbound mail."
POSTINST

sed -i "s|__HTTP_PORT__|${GLITCHTIP_HTTP_PORT}|g" "${AFTER_INSTALL}"
sed -i \
  -e "s|__DB_NAME__|${GLITCHTIP_DB_NAME}|g" \
  -e "s|__DB_USER__|${GLITCHTIP_DB_USER}|g" \
  -e "s|__DB_HOST__|${GLITCHTIP_DB_HOST}|g" \
  "${AFTER_INSTALL}"

BEFORE_REMOVE=$(mktemp)
cat > "${BEFORE_REMOVE}" << 'PRERM'
#!/bin/bash
set -e
if [ -f /usr/share/dbconfig-common/dpkg/prerm.pgsql ]; then
  . /usr/share/debconf/confmodule
  . /usr/share/dbconfig-common/dpkg/prerm.pgsql
  dbc_go glitchtip "$@"
fi
systemctl stop glitchtip glitchtip-worker 2>/dev/null || true
systemctl disable glitchtip glitchtip-worker 2>/dev/null || true
gpasswd -d www-data glitchtip 2>/dev/null || true
PRERM

AFTER_REMOVE=$(mktemp)
cat > "${AFTER_REMOVE}" << 'POSTRM'
#!/bin/bash
case "$1" in
  remove|purge)
    if [ -f /var/lib/dbconfig-common/config/glitchtip ]; then
      . /usr/share/debconf/confmodule
      if [ -f /usr/share/dbconfig-common/dpkg/postrm.pgsql ]; then
        . /usr/share/dbconfig-common/dpkg/postrm.pgsql
        dbc_go glitchtip "$@" || true
      fi
    fi
    ;;
esac

case "$1" in
  purge)
    deluser --remove-home glitchtip 2>/dev/null || true
    rm -rf /var/lib/glitchtip /var/log/glitchtip
    ;;
esac
POSTRM

echo ">>> Building .deb..."
fpm \
  -s dir \
  -t deb \
  -n "${PKG_NAME}" \
  -v "${GLITCHTIP_VERSION}" \
  --iteration "${PKG_REVISION}" \
  --architecture "${ARCH}" \
  --maintainer "GlitchTip package" \
  --description "${DESCRIPTION}" \
  --url "https://glitchtip.com/" \
  --license "MIT" \
  --category "web" \
  --depends "python3 >= 3.12" \
  --depends "libpq5" \
  --depends "libxml2" \
  --depends "postgresql" \
  --depends "valkey-server" \
  --depends "dbconfig-pgsql | dbconfig-no-thanks" \
  --deb-suggests "nginx" \
  --config-files /etc/glitchtip/glitchtip.env \
  --deb-config "${DEB_CONFIG}" \
  --after-install "${AFTER_INSTALL}" \
  --before-remove "${BEFORE_REMOVE}" \
  --after-remove "${AFTER_REMOVE}" \
  --deb-systemd-enable \
  --deb-no-default-config-files \
  --package "${OUTPUT_DIR}/" \
  -C "${BUILD_ROOT}" \
  .

rm -f "${AFTER_INSTALL}" "${BEFORE_REMOVE}" "${AFTER_REMOVE}" "${DEB_CONFIG}"
echo ">>> Package built: ${OUTPUT_DIR}/${DEB_FILE}"
