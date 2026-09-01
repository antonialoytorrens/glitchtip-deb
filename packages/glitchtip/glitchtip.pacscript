pkgname="glitchtip"
pkgver="6.2.6"
pkgrel="5"
arch=('amd64')
url="https://glitchtip.com/"
license=('MIT')
pkgdesc="GlitchTip error tracking (trimmed profile, native systemd, bundled venv)"
maintainer=("Antoni Aloy <https://github.com/antonialoytorrens/glitchtip-deb>")
external_connection=true

_glitchtip_domain="${GLITCHTIP_DOMAIN:-glitchtip.antonialoytorrens.com}"
_glitchtip_db_name="${GLITCHTIP_DB_NAME:-glitchtip}"
_glitchtip_db_user="${GLITCHTIP_DB_USER:-glitchtip}"
_glitchtip_db_host="${GLITCHTIP_DB_HOST:-127.0.0.1}"
_glitchtip_http_port="${GLITCHTIP_HTTP_PORT:-38417}"

_backend="glitchtip-backend-v${pkgver}"
_frontend="glitchtip-frontend-v${pkgver}"
_install_prefix="/opt/glitchtip"
_python="python3.13"

source=(
  "https://gitlab.com/glitchtip/glitchtip-backend/-/archive/v${pkgver}/${_backend}.tar.gz"
  "https://gitlab.com/glitchtip/glitchtip-frontend/-/archive/v${pkgver}/${_frontend}.tar.gz"
  "0001-trim-optional-deps.patch"
  "0002-local-filesystem-profile.patch"
  "0003-deb-database-components.patch"
)

makedepends=(
  "python3.13" "python3.13-venv" "python3.13-dev" "build-essential" "pkg-config" "patch"
  "libpq-dev" "libxml2-dev" "zlib1g-dev" "libssl-dev" "libffi-dev"
  "curl" "ca-certificates" "tzdata" "git" "rustc" "cargo" "nodejs" "npm"
)

depends=(
  "python3.13" "libpq5" "libxml2" "postgresql" "valkey-server"
  "dbconfig-pgsql | dbconfig-no-thanks"
)

recommends=("nginx")
backup=('etc/glitchtip/glitchtip.env')

prepare() {
  cd "${srcdir}/${_backend}"
  for p in "${srcdir}"/000*.patch; do
    patch -p1 --forward -i "${p}"
  done
}

build() {
  if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:/root/.local/bin:${PATH}"
  fi

  cd "${srcdir}/${_frontend}"
  npm ci
  npm run build-prod

  local staging="${srcdir}/staging"
  mkdir -p "${staging}${_install_prefix}/src"
  cp -a "${srcdir}/${_backend}/." "${staging}${_install_prefix}/src/"

  mkdir -p "${staging}${_install_prefix}/src/dist"
  cp -a "${srcdir}/${_frontend}/dist/glitchtip-frontend/browser/." \
    "${staging}${_install_prefix}/src/dist/"

  export UV_PROJECT_ENVIRONMENT="${staging}${_install_prefix}/venv"
  export UV_PYTHON="${_python}"
  "${_python}" -m venv "${staging}${_install_prefix}/venv"
  (
    cd "${staging}${_install_prefix}/src"
    uv lock
    uv sync --frozen --no-dev --python "${_python}"
  )

  sed -i "s|${staging}||g" "${staging}${_install_prefix}/venv/pyvenv.cfg"
  find "${staging}${_install_prefix}/venv/bin" -type f -exec sed -i "s|${staging}||g" {} +

  local venv="${staging}${_install_prefix}/venv"
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel,pkg_resources} 2>/dev/null || true
  rm -rf "${venv}/lib"/python*/site-packages/{pip,setuptools,wheel}-*.dist-info 2>/dev/null || true
  find "${venv}" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
  find "${venv}" -name "*.pyc" -delete 2>/dev/null || true
  find "${venv}" -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
  find "${staging}${_install_prefix}/src" -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
}

package() {
  local staging="${srcdir}/staging"
  mkdir -p "${pkgdir}${_install_prefix}"
  cp -a "${staging}${_install_prefix}/." "${pkgdir}${_install_prefix}/"

  mkdir -p "${pkgdir}/etc/glitchtip"
  cat > "${pkgdir}/etc/glitchtip/glitchtip.env" << ENVFILE
SECRET_KEY=__SECRETKEY_PLACEHOLDER__
EMAIL_URL=consolemail://
DEFAULT_FROM_EMAIL=noreply@${_glitchtip_domain}
GLITCHTIP_DOMAIN=https://${_glitchtip_domain}
ALLOWED_HOSTS=${_glitchtip_domain}
CSRF_TRUSTED_ORIGINS=https://${_glitchtip_domain}
GLITCHTIP_VERSION=${pkgver}
GLITCHTIP_ENABLE_DUCKDB=false
GLITCHTIP_ENABLE_MCP=false
MEDIA_ROOT=/var/lib/glitchtip/uploads
STATIC_ROOT=/var/lib/glitchtip/static
VALKEY_URL=redis://127.0.0.1:6379/0
GLITCHTIP_HTTP_PORT=${_glitchtip_http_port}
DJANGO_SETTINGS_MODULE=glitchtip.settings
LOG_LEVEL=WARNING
ENVFILE

  mkdir -p "${pkgdir}/etc/systemd/system"
  install -Dm644 /dev/stdin "${pkgdir}/etc/systemd/system/glitchtip.service" << 'SVCWEB'
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

  install -Dm644 /dev/stdin "${pkgdir}/etc/systemd/system/glitchtip-worker.service" << 'SVCWORKER'
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

  mkdir -p "${pkgdir}/var/lib/glitchtip/uploads"
  mkdir -p "${pkgdir}/var/lib/glitchtip/static"
  mkdir -p "${pkgdir}/var/log/glitchtip"

  mkdir -p "${pkgdir}/usr/share/dbconfig-common/data/glitchtip/install"
  cat > "${pkgdir}/usr/share/dbconfig-common/data/glitchtip/install/pgsql" << 'DBCSQL'
-- GlitchTip: schema managed by Django migrations (manage.py migrate)
SELECT 1;
DBCSQL

  mkdir -p "${pkgdir}/usr/share/glitchtip"
  cat > "${pkgdir}/usr/share/glitchtip/build-info" << BUILDINFO
GLITCHTIP_DB_NAME=${_glitchtip_db_name}
GLITCHTIP_DB_USER=${_glitchtip_db_user}
GLITCHTIP_DB_HOST=${_glitchtip_db_host}
GLITCHTIP_HTTP_PORT=${_glitchtip_http_port}
BUILDINFO

  mkdir -p "${pkgdir}/DEBIAN"
  install -Dm755 /dev/stdin "${pkgdir}/DEBIAN/config" << DEBCONF
#!/bin/sh
set -e
. /usr/share/debconf/confmodule
if [ -f /usr/share/dbconfig-common/dpkg/config.pgsql ]; then
  dbc_dbname="${_glitchtip_db_name}"
  dbc_dbuser="${_glitchtip_db_user}"
  . /usr/share/dbconfig-common/dpkg/config.pgsql
  dbc_go glitchtip "\$@"
fi
DEBCONF
}

post_install() {
  local src="/opt/glitchtip/src"
  local venv="/opt/glitchtip/venv"
  local env_file="/etc/glitchtip/glitchtip.env"
  # shellcheck disable=SC1091
  . /usr/share/glitchtip/build-info

  if [ -f /usr/share/dbconfig-common/dpkg/postinst.pgsql ]; then
    . /usr/share/debconf/confmodule
    . /usr/share/dbconfig-common/dpkg/postinst.pgsql
    dbc_go glitchtip "$@"
  fi

  case "$1" in
    configure|reconfigure) ;;
    *) return 0 ;;
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
      source "$1"
      set +a
      cd "$2" || exit 1
      shift 2
      exec "$@"
    ' bash "${env_file}" "${src}" "$@"
  }

  if grep -q '__SECRETKEY_PLACEHOLDER__' "${env_file}"; then
    local secret
    secret=$("${venv}/bin/python" -c "import secrets; print(secrets.token_urlsafe(50))")
    sed -i "s|__SECRETKEY_PLACEHOLDER__|${secret}|" "${env_file}"
    echo ">>> Generated SECRET_KEY."
  fi

  if ! systemctl is-active --quiet postgresql; then
    echo "!!! postgresql is not running. Database setup and migrations require PostgreSQL." >&2
    exit 1
  fi

  if [ -f /etc/dbconfig-common/glitchtip.conf ]; then
    # shellcheck disable=SC1091
    . /etc/dbconfig-common/glitchtip.conf
    local db_host="${dbc_dbserver:-127.0.0.1}"
    case "${db_host}" in local|localhost) db_host="127.0.0.1" ;; esac
    grep -vE '^(DATABASE_NAME|DATABASE_USER|DATABASE_PASSWORD|DATABASE_HOST|DATABASE_PORT)=' \
      "${env_file}" > "${env_file}.tmp"
    {
      cat "${env_file}.tmp"
      echo "DATABASE_NAME=${dbc_dbname}"
      echo "DATABASE_USER=${dbc_dbuser}"
      case "${dbc_authmethod_user}:${dbc_dbserver:-local}" in
        ident:local|ident:|ident:localhost|ident:127.0.0.1) ;;
        *)
          echo "DATABASE_PASSWORD=${dbc_dbpass}"
          echo "DATABASE_HOST=${db_host}"
          echo "DATABASE_PORT=${dbc_dbport:-5432}"
          ;;
      esac
    } > "${env_file}"
    rm -f "${env_file}.tmp"
    echo ">>> Database env updated from dbconfig."

    if runuser -u postgres -- psql -tc \
      "SELECT 1 FROM pg_roles WHERE rolname='${dbc_dbuser}'" | grep -q 1; then
      if [ "${dbc_authmethod_user}" != "ident" ] && [ -n "${dbc_dbpass}" ]; then
        runuser -u postgres -- psql -c \
          "ALTER ROLE ${dbc_dbuser} WITH PASSWORD '${dbc_dbpass}';" 2>/dev/null || true
      fi
    elif [ "${dbc_authmethod_user}" = "ident" ]; then
      runuser -u postgres -- psql -c "CREATE ROLE ${dbc_dbuser} WITH LOGIN;"
    else
      runuser -u postgres -- psql -c \
        "CREATE ROLE ${dbc_dbuser} WITH LOGIN PASSWORD '${dbc_dbpass}';"
    fi
    runuser -u postgres -- psql -tc \
      "SELECT 1 FROM pg_database WHERE datname='${dbc_dbname}'" | grep -q 1 \
      || runuser -u postgres -- createdb -O "${dbc_dbuser}" "${dbc_dbname}"
    echo ">>> PostgreSQL role/database ready (${dbc_dbname})."
  else
    echo ">>> dbconfig-no-thanks: setting up PostgreSQL locally."
    local db_pass
    db_pass=$("${venv}/bin/python" -c "import secrets; print(secrets.token_urlsafe(32))")
    grep -vE '^(DATABASE_NAME|DATABASE_USER|DATABASE_PASSWORD|DATABASE_HOST|DATABASE_PORT)=' \
      "${env_file}" > "${env_file}.tmp"
    {
      cat "${env_file}.tmp"
      echo "DATABASE_NAME=${GLITCHTIP_DB_NAME}"
      echo "DATABASE_USER=${GLITCHTIP_DB_USER}"
      echo "DATABASE_PASSWORD=${db_pass}"
      echo "DATABASE_HOST=${GLITCHTIP_DB_HOST}"
      echo "DATABASE_PORT=5432"
    } > "${env_file}"
    rm -f "${env_file}.tmp"

    if runuser -u postgres -- psql -tc \
      "SELECT 1 FROM pg_roles WHERE rolname='${GLITCHTIP_DB_USER}'" | grep -q 1; then
      runuser -u postgres -- psql -c \
        "ALTER ROLE ${GLITCHTIP_DB_USER} WITH PASSWORD '${db_pass}';" 2>/dev/null || true
    else
      runuser -u postgres -- psql -c \
        "CREATE ROLE ${GLITCHTIP_DB_USER} WITH LOGIN PASSWORD '${db_pass}';"
    fi
    runuser -u postgres -- psql -tc \
      "SELECT 1 FROM pg_database WHERE datname='${GLITCHTIP_DB_NAME}'" | grep -q 1 \
      || runuser -u postgres -- createdb -O "${GLITCHTIP_DB_USER}" "${GLITCHTIP_DB_NAME}"
    echo ">>> PostgreSQL database '${GLITCHTIP_DB_NAME}' ready."
  fi

  chmod 640 "${env_file}"
  chown root:glitchtip "${env_file}"

  if ! systemctl is-active --quiet valkey-server; then
    echo "!!! valkey-server is not running. Worker requires Valkey on 127.0.0.1:6379." >&2
    exit 1
  fi

  echo ">>> Verifying database connection..."
  run_as_glitchtip "${venv}/bin/python" -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'glitchtip.settings')
import django
django.setup()
from django.db import connection
connection.ensure_connection()
print('>>> Database connection OK.')
"

  echo ">>> Running migrations..."
  run_as_glitchtip "${venv}/bin/python" "${src}/manage.py" migrate --no-input
  echo ">>> Maintaining partitions..."
  run_as_glitchtip "${venv}/bin/python" "${src}/manage.py" maintain_partitions || true
  echo ">>> Collecting static files..."
  run_as_glitchtip "${venv}/bin/python" "${src}/manage.py" collectstatic --no-input

  if id -u www-data &>/dev/null; then
    usermod -aG glitchtip www-data
  fi

  chmod 750 /var/lib/glitchtip
  chmod -R g+rX /var/lib/glitchtip/static 2>/dev/null || true

  systemctl daemon-reload
  systemctl enable --now glitchtip glitchtip-worker
  echo ">>> Services glitchtip and glitchtip-worker enabled."
  echo ">>> GlitchTip is ready. Proxy to http://127.0.0.1:${GLITCHTIP_HTTP_PORT}"
}

pre_remove() {
  if [ -f /usr/share/dbconfig-common/dpkg/prerm.pgsql ]; then
    . /usr/share/debconf/confmodule
    . /usr/share/dbconfig-common/dpkg/prerm.pgsql
    dbc_go glitchtip "$@"
  fi
  systemctl stop glitchtip glitchtip-worker 2>/dev/null || true
  systemctl disable glitchtip glitchtip-worker 2>/dev/null || true
  gpasswd -d www-data glitchtip 2>/dev/null || true
}

post_remove() {
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
}
