# glitchtip-deb

Experimental `.deb` packaging for [GlitchTip](https://glitchtip.com/). This does **not** follow Debian packaging policy.

**Warning:** do not use in production unless you can troubleshoot it yourself. Prefer the [official install docs](https://glitchtip.com/documentation/install).

## Quick start

**Note:** `docker build` needs ~10 GB free disk (npm + Rust + venv). GitHub Actions runners have enough space.

### Build (Docker)

```bash
docker build --target artifact --output . .
sudo dpkg -i glitchtip_$(cat VERSION)-5_amd64.deb
sudo apt-get install -f
```

### Install from GitHub Release

Download the latest `.deb` from [Releases](https://github.com/antonialoytorrens/glitchtip-deb/releases), then:

```bash
sudo dpkg -i glitchtip_*_amd64.deb
sudo apt-get install -f
```

### Install via Pacstall (builds from source on host)

```bash
pacstall -I glitchtip@github:antonialoytorrens/glitchtip-deb
```

This compiles GlitchTip on your machine (~60–90 min). Prefer the pre-built `.deb` from Releases for faster installs.

## Environment variables (build)

Set when running `docker build` (build-args / `-e` in Dockerfile):

| Variable | Default | Description |
|----------|---------|-------------|
| `GLITCHTIP_DOMAIN` | `glitchtip.antonialoytorrens.com` | Hostname baked into config |
| `GLITCHTIP_HTTP_PORT` | `38417` | Granian listen port on `127.0.0.1` |
| `GLITCHTIP_DB_NAME` | `glitchtip` | PostgreSQL database name (dbconfig) |
| `GLITCHTIP_DB_USER` | `glitchtip` | PostgreSQL role (dbconfig) |
| `GLITCHTIP_DB_HOST` | `127.0.0.1` | PostgreSQL host (dbconfig-no-thanks fallback) |

Bump GlitchTip upstream version in [`VERSION`](VERSION) and `pkgver` in [`packages/glitchtip/glitchtip.pacscript`](packages/glitchtip/glitchtip.pacscript).

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on push to `master`: `docker build` inside `debian:trixie`, then publishes a GitHub **pre-release** with the `.deb` and `.sha256` checksum.

## Version monitoring

[`.github/workflows/check-version.yml`](.github/workflows/check-version.yml) runs weekly and opens an issue when a newer stable GlitchTip exists on [release-monitoring.org](https://release-monitoring.org/project/392074/).

```bash
./scripts/check-glitchtip-version.sh
```

## Patches and trimmed profile

Patches live in [`packages/glitchtip/`](packages/glitchtip/) and are applied in the pacscript `prepare()` step:

- `0001-trim-optional-deps.patch` — trims optional Python deps (DuckDB, MCP, cloud storage, uWSGI, …)
- `0002-local-filesystem-profile.patch` — local filesystem storage profile in `settings.py`
- `0003-deb-database-components.patch` — `DATABASE_*` env vars for dbconfig-pgsql

### Disabled features

| Feature | Effect when missing |
|---------|---------------------|
| Cold storage (DuckDB) | No Parquet archival beyond PostgreSQL retention |
| MCP (AI agent API) | No `/mcp` endpoints |
| S3 / Azure / GCS storage | Local filesystem only (`/var/lib/glitchtip/uploads`) |
| uWSGI | Use bundled Granian ASGI (`glitchtip.service`) |

### Still included

Error/issue tracking, performance spans, logs, uptime monitoring, native symbolication, minidumps, Rust ingest.

Valkey is **required** at runtime (`valkey-server`).

### Database (dbconfig-pgsql)

Depends on `dbconfig-pgsql | dbconfig-no-thanks`. See previous docs in git history for ident vs password auth details.

Reconfigure: `sudo dpkg-reconfigure glitchtip`.
