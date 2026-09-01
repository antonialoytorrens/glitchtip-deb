# glitchtip-deb

Experimental `.deb` packaging for [GlitchTip](https://glitchtip.com/). This does **not** follow Debian packaging policy.

**Warning:** do not use in production unless you can troubleshoot it yourself. Prefer the [official install docs](https://glitchtip.com/documentation/install).

## Quick start

```bash
sudo ./build-glitchtip-amd64-deb.sh
sudo dpkg -i glitchtip_$(cat VERSION)-1_amd64.deb
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
| `DISABLE_DEBOOTSTRAP_CHROOT` | `false` | `true` = build on host (CI uses this) |
| `KEEP_CHROOT` | `true` | Keep debootstrap chroot after build |
| `FETCH_SOURCES` | `false` | Re-download GitLab tag archives |

## CI

GitHub Actions workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) runs on push to `master` only (no PR builds).

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

## Patches

`patches/` applies changes before the build. By default `0001-drop-duckdb-dependency.patch` removes DuckDB for PostgreSQL-only installs.
