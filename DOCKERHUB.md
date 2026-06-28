# Vintage Story Server

A Docker image for a [Vintage Story](https://www.vintagestory.at/) dedicated server.
The server and mods are downloaded at startup, so the image stays version-agnostic.

- Pulls the latest server version on start, or a pinned one (`VS_VERSION`).
- Auto-downloads mods and their dependencies from the official
  [ModDB](https://mods.vintagestory.at).
- Configures common `serverconfig.json` values from environment variables.
- Caches the server under `/data`, so restarts don't re-download it.
- One image variant per .NET version to cover different VS versions.

## Supported tags

| Tag | .NET | VS versions |
|-----|------|-------------|
| `latest`, `dotnet10` | 10 | 1.22+ |
| `dotnet8` | 8 | 1.21.x |
| `dotnet7` | 7 | 1.19 – 1.20 |

Also published on GHCR as `ghcr.io/merevge/vintagestory-server`.

## Quick start

```yaml
services:
  vintagestory:
    image: merevge/vintagestory-server:latest
    container_name: vintagestory-server
    restart: unless-stopped
    stop_grace_period: 60s
    stdin_open: true
    tty: true
    ports:
      - "42420:42420/tcp"
      - "42420:42420/udp"
    volumes:
      - ./data:/data
    environment:
      VS_SERVER_NAME: "My Server"
      VS_MODS: |
        carryon
```

```bash
docker compose up -d
docker compose logs -f
```

Everything the server writes — binaries, mods, world saves, config — lives under the
single `/data` volume, so backing up the server is backing up that folder.

## Common configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `VS_VERSION` | _(latest)_ | Pin a server version, e.g. `1.22.3`. |
| `VS_CHANNEL` | `stable` | `stable` or `unstable`. |
| `VS_MODS` | _(empty)_ | Mod ids to auto-download, one per line. |
| `VS_SERVER_NAME` | | Server name shown in the browser. |
| `VS_MAX_CLIENTS` | | Maximum players. |
| `VS_PASSWORD` | | Join password. |
| `VS_PORT` | `42420` | Game port; the healthcheck follows it. |
| `PUID` / `PGID` | `1000` | uid/gid the server runs as. |

A config token from the
[VS-Config-Generator](https://merevge.github.io/VS-Config-Generator/) can configure
world generation, server settings and roles in one go via `VS_CONFIG_TOKEN`.

## Documentation and source

Full configuration reference, mod handling and troubleshooting:
**https://github.com/MErevGe/VintageStory-Server**

## License

MIT. Unofficial project — Vintage Story is © [Anego Studios](https://www.anegostudios.com/);
the game is downloaded at runtime and is not included in the image.
