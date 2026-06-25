# Vintage Story dedicated server. The server binaries and mods are downloaded at
# runtime, not baked in. The .NET runtime is parametrized so one repo can publish
# variants for the different .NET versions VS requires:
#   VS 1.19-1.20 -> 7   |   VS 1.21 -> 8   |   VS 1.22+ -> 10   (VS skipped 9)
ARG DOTNET_VERSION=10.0
FROM mcr.microsoft.com/dotnet/runtime:${DOTNET_VERSION}

LABEL org.opencontainers.image.title="vintagestory-server" \
      org.opencontainers.image.description="Vintage Story dedicated server with automatic version and mod downloading"

# The Ubuntu base ships a default user at UID/GID 1000; remove it so the service
# user can own 1000 (the entrypoint remaps to PUID/PGID at runtime).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl jq gosu unzip; \
    rm -rf /var/lib/apt/lists/*; \
    userdel -r ubuntu 2>/dev/null || true; \
    groupdel ubuntu 2>/dev/null || true; \
    groupadd -g 1000 vintagestory; \
    useradd -u 1000 -g 1000 -m -d /home/vintagestory vintagestory; \
    mkdir -p /data

COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

ENV VS_CHANNEL=stable \
    VS_VERSION="" \
    DATA_DIR=/data \
    SERVER_DIR=/data/.server \
    PUID=1000 \
    PGID=1000 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

VOLUME ["/data"]
EXPOSE 42420/tcp 42420/udp
ENTRYPOINT ["/app/scripts/entrypoint.sh"]
