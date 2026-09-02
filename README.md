# glitchtip-deb

Experimental `.deb` packaging for [GlitchTip](https://glitchtip.com/). This does **not** follow Debian packaging policy.

**Warning:** do not use in production unless you can troubleshoot it yourself. Prefer the [official install docs](https://glitchtip.com/documentation/install).

## Quick start

`docker build` needs ~10 GB free disk (Rust + venv; frontend comes from GitLab CI assets, not npm).

### Install from Release

Download from [Releases](https://github.com/antonialoytorrens/glitchtip-deb/releases):

```bash
sudo dpkg -i glitchtip_*_amd64.deb
sudo apt-get install -f
```

### Build (Docker)

Frontend is taken from the upstream `build-assets` CI job (`assets.zip` → `dist/glitchtip-frontend/browser/`). No local npm build (Angular 22 needs Node ≥22; Debian Trixie has Node 20).

```bash
make
sudo dpkg -i glitchtip_$(cat VERSION)-pacstall7_amd64.deb
sudo apt-get install -f
```

On install: debconf/dbconfig sets up PostgreSQL (or a local peer-auth DB if you decline), runs migrations, and starts `glitchtip` + `glitchtip-worker`. Put a reverse proxy in front of `http://127.0.0.1:38417` (nginx is recommended).

## After install

| Path | Purpose |
|------|---------|
| `/etc/glitchtip/glitchtip.env` | Config |
| `/opt/glitchtip/` | App (venv + source) |
| `/var/lib/glitchtip/uploads` | Uploads |
| `/var/lib/glitchtip/static` | Static files |

**Requires:** PostgreSQL, Valkey (`valkey-server`), systemd.

## Build options

Docker build-args ([`Dockerfile`](Dockerfile)):

| Variable | Default |
|----------|---------|
| `GLITCHTIP_DOMAIN` | `glitchtip.localhost.local` |
| `GLITCHTIP_HTTP_PORT` | `38417` |
| `GLITCHTIP_DB_NAME` | `glitchtip` |
| `GLITCHTIP_DB_USER` | `glitchtip` |
| `GLITCHTIP_DB_HOST` | `127.0.0.1` |

## Maintainer

Bump [`VERSION`](VERSION) and `pkgver` in [`glitchtip.pacscript`](packages/glitchtip/glitchtip.pacscript). After dependency changes:

```bash
make requirements   # refresh packages/glitchtip/requirements.txt
make
```

Patches ([`packages/glitchtip/`](packages/glitchtip/)): `0001` trim deps, `0002` local storage, `0003` `DATABASE_*` env.

**Out:** DuckDB cold storage, MCP, S3/Azure/GCS, uWSGI. **In:** issues, performance, logs, uptime, symbolication, minidumps, Rust ingest. Python deps pinned in `requirements.txt` (runtime only).

## CI

Push to `master` → pre-release `.deb` via [build.yml](.github/workflows/build.yml). [check-version.yml](.github/workflows/check-version.yml) opens an issue when upstream has a newer release.
