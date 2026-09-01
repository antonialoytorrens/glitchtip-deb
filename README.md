# glitchtip-deb

Experimental `.deb` packaging for [GlitchTip](https://glitchtip.com/). This does **not** follow Debian packaging policy.

**Warning:** do not use in production unless you can troubleshoot it yourself. Prefer the [official install docs](https://glitchtip.com/documentation/install).

## Quick start

```bash
sudo ./build-glitchtip-amd64-deb.sh
sudo dpkg -i glitchtip_$(cat VERSION)-4_amd64.deb
sudo apt-get install -f
```

The build script downloads GlitchTip backend and frontend sources from GitLab tags automatically (see `VERSION`). Downloaded trees are gitignored:

- `glitchtip-backend-v*/`
- `glitchtip-frontend-v*/`

Force a fresh download after bumping `VERSION`:

```bash
FETCH_SOURCES=true sudo -E ./build-glitchtip-amd64-deb.sh
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GLITCHTIP_VERSION` | `VERSION` file | GlitchTip release to package |
| `GLITCHTIP_DOMAIN` | `glitchtip.antonialoytorrens.com` | Hostname baked into config |
| `GLITCHTIP_HTTP_PORT` | `38417` | Granian listen port on `127.0.0.1` (proxy from nginx/apache) |
| `DISABLE_DEBOOTSTRAP_CHROOT` | `false` | `true` = build on host (CI uses this) |
| `KEEP_CHROOT` | `true` | Keep debootstrap chroot after build |
| `FETCH_SOURCES` | `false` | Re-download GitLab tag archives |
| `PKG_REVISION` | `4` | Debian package revision (`glitchtip_VERSION-REV_amd64.deb`) |

## CI

GitHub Actions workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) runs on push to `master` only (no PR builds).

The build job runs inside a **`debian:trixie` container** with `DISABLE_DEBOOTSTRAP_CHROOT=true`, so the embedded venv uses the same Debian Python as the target host (not Ubuntu’s `setup-python`).

Each successful run publishes a GitHub **pre-release** tagged `v{VERSION}-pre.{run}` with the `.deb` and its `.sha256` checksum file attached (e.g. `v6.2.6-pre.42`).

## Version monitoring

[`.github/workflows/check-version.yml`](.github/workflows/check-version.yml) runs weekly (Mondays 08:00 UTC) and queries [release-monitoring.org](https://release-monitoring.org/project/392074/) (Anitya project `392074`). When a newer **stable** version exists, it opens a GitHub issue labelled `new-version`.

Run locally:

```bash
./scripts/check-glitchtip-version.sh
```

Skip the Anitya API and compare against a known upstream version (e.g. when release-monitoring.org is unavailable):

```bash
VERSION=6.2.7 ./scripts/check-glitchtip-version.sh
```

## Patches and trimmed profile

Before building the Python venv, patches under [`patches/`](patches/) are applied to the upstream backend checkout. This package targets **local PostgreSQL + filesystem storage** and omits optional upstream dependencies to save disk space and build time.

- [`patches/0001-trim-optional-deps.patch`](patches/0001-trim-optional-deps.patch) — trims `pyproject.toml` (drops DuckDB, MCP, cloud storage, uWSGI, …).
- [`patches/0002-local-filesystem-profile.patch`](patches/0002-local-filesystem-profile.patch) — adjusts `glitchtip/settings.py` for the trimmed profile: removes the `storages` app from `INSTALLED_APPS`, blocks S3 at startup, and sets `STATIC_ROOT` / `STATICFILES_DIRS` for local paths (configurable via `MEDIA_ROOT` and `STATIC_ROOT` in `/etc/glitchtip/glitchtip.env`).

Removed or changed dependencies (0001): `duckdb`, `mcp`, `uWSGI`, `uwsgi-chunked`, `google-cloud-logging`, `django-storages` (+ boto3/azure/gcs), `arro3-core`, `arro3-io`; `granian[reload,uvloop]` → `granian[uvloop]`.

### Disabled or unavailable features

These GlitchTip capabilities are **not shipped** in this `.deb` (removing the Python packages above). Setting the env var alone is not enough — the code paths need libraries that are not installed.

| Feature | Env var | Effect when missing |
|---------|---------|---------------------|
| Cold storage (Parquet archival) | `GLITCHTIP_ENABLE_DUCKDB` | No long-term event/log archive beyond PostgreSQL retention. Shipped as `false`. |
| MCP (AI agent API) | `GLITCHTIP_ENABLE_MCP` | No `/mcp` OAuth or MCP tools. Shipped as `false`. |
| S3 / Azure / GCS media & uploads | `AWS_*`, `AZURE_*`, `GS_*` | Default storage is local filesystem (`/var/lib/glitchtip/uploads`). Cloud backends will fail at runtime. |
| GCP structured logging | `DJANGO_LOGGING_HANDLER_CLASS=google.cloud...` | Use default `logging.StreamHandler` (journald via systemd). |
| uWSGI deployment | — | Use the bundled Granian ASGI unit (`glitchtip.service`). WSGI is deprecated upstream anyway. |
| Granian auto-reload | — | Production server only; no file-watcher reload extra. |

### Still included

- Error/issue tracking, performance spans (hot storage in PostgreSQL)
- **Logs** (OTLP ingest) — `GLITCHTIP_ENABLE_LOGS` defaults to upstream `true`
- **Uptime monitoring** — `GLITCHTIP_ENABLE_UPTIME` defaults to upstream `true`
- Native symbolication (`symbolic`), minidumps, Rust ingest (`glitchtip-rust`)

Valkey is **required** at runtime: the `.deb` depends on `valkey-server` and ships `VALKEY_URL=redis://127.0.0.1:6379/0` in `/etc/glitchtip/glitchtip.env`.
