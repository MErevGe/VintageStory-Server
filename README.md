<div align="center">

[![GitHub Workflow Status (with branch)](https://img.shields.io/github/actions/workflow/status/merevge/vintagestory-server/docker-publish.yml?branch=main&label=image%20build&style=flat-square)](https://github.com/merevge/vintagestory-server)
[![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/merevge/vintagestory-server?style=flat-square)](https://hub.docker.com/r/merevge/vintagestory-server)
[![Docker Pulls](https://img.shields.io/docker/pulls/merevge/vintagestory-server?style=flat-square)](https://hub.docker.com/r/merevge/vintagestory-server)
[![Docker Stars](https://img.shields.io/docker/stars/merevge/vintagestory-server?style=flat-square)](https://hub.docker.com/r/merevge/vintagestory-server)

</div>


# Vintage Story Server (Docker)

A Docker image for a [Vintage Story](https://www.vintagestory.at/) dedicated server.
The server and mods are downloaded at startup, so the image stays version-agnostic.

- Pulls the latest server version on start, or a pinned one (`VS_VERSION`).
- Auto-downloads mods from the official [ModDB](https://mods.vintagestory.at).
- Configures common `serverconfig.json` values from environment variables.
- Caches the server under `/data`, so restarts don't re-download it.
- Image variants per .NET version to cover different VS versions.

## Images

Published to both registries:

- GHCR — `ghcr.io/merevge/vintagestory-server`
- Docker Hub — [`merevge/vintagestory-server`](https://hub.docker.com/r/merevge/vintagestory-server)

```bash
docker pull ghcr.io/merevge/vintagestory-server:latest
docker pull merevge/vintagestory-server:latest
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `VS_CHANNEL` | `stable` | `stable` or `unstable` |
| `VS_VERSION` | _(empty)_ | pin a version, e.g. `1.22.3`; empty = latest |
| `VS_MODS` | _(empty)_ | mod ids to auto-download (see [Mods](#mods)) |
| `PUID` / `PGID` | `1000` | uid/gid the server runs as |
| `EXTRA_ARGS` | _(empty)_ | extra arguments passed to the server |

### serverconfig.json overrides

Set these in the environment and they are applied at every start.

| Variable | serverconfig field | Notes |
|----------|--------------------|-------|
| `VS_WHITELIST_MODE` | `WhitelistMode` | `0` = default (**on** for dedicated), `1` = off, `2` = on |
| `VS_SERVER_NAME` | `ServerName` | |
| `VS_MAX_CLIENTS` | `MaxClients` | |
| `VS_PASSWORD` | `Password` | join password |
| `VS_MOTD` | `WelcomeMessage` | |

> Whitelisting: `OnlyWhitelisted` is deprecated since VS 1.20; use
> `VS_WHITELIST_MODE`. For a dedicated server `0` means the whitelist is **on**.

## Mods

List the mods in the `VS_MODS` environment variable — one id per line (a YAML
block scalar keeps it readable), optionally pinned as `modid@version`:

```yaml
    environment:
      VS_MODS: |
        carryon
        primitivesurvival@3.7.4
```

The mod id is the text id from the mod page (the "Mod ID" field or the
1-click-install link `vintagestorymodinstall://<id>@...`), **not** the number in
the `mods.vintagestory.at/show/mod/<N>` URL. To verify an id, open
`https://mods.vintagestory.at/api/mod/<id>` and check the returned name.

Mod dependencies are resolved and downloaded automatically (read from each mod's
`modinfo.json`), so you only need to list the mods you actually want.

## Server console

The server console is reachable via `docker attach` (the compose file sets
`stdin_open` + `tty`):

```bash
docker attach vintagestory-server
```

Commands: `/op <name>` (grant admin, persists), `/serverconfig <key> <value>`,
`/help`, `/stop`. Detach without stopping with `Ctrl-P` `Ctrl-Q` (not `Ctrl-C`).

## Image variants

Different VS versions need different .NET runtimes, so there is one image tag per
.NET version. Pick the tag for your target VS version and pin `VS_VERSION`.

| Tag | .NET | VS versions |
|-----|------|-------------|
| `latest` / `dotnet10` | 10 | 1.22+ |
| `dotnet8` | 8 | 1.21.x |
| `dotnet7` | 7 | 1.19 – 1.20 |

```yaml
    image: ghcr.io/merevge/vintagestory-server:dotnet8
    environment:
      VS_VERSION: "1.21.5"
```

(VS skipped .NET 9, so there is no `dotnet9` tag.) The same tags are available on
both GHCR and Docker Hub.

## Notes

- linux/amd64 only.
- The server saves on stop; `stop_grace_period` is set to 60s.
