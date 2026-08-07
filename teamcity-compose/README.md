# TeamCity rootless Podman demo

This Compose deployment runs one TeamCity server and one custom Linux build agent on the `teamcity-control` network. The agent image is based on `teamcity-minimal-agent:2026.1.3-linux` and contains Git, the Podman 6.0.2 remote client, and standalone Docker Compose 5.3.1. It deliberately contains no Docker CLI.

## Prerequisites

- Podman, with a running rootless Podman machine or Linux service for UID 1000.
- A Compose provider such as `docker-compose`.
- The rootless API socket at `/run/user/1000/podman/podman.sock`.
- This repository checked out on the Windows host. Compose mounts the directory above `teamcity-compose` as `/repo` in TeamCity.

The agent runs as non-root UID 1000. Supplemental container group 0 gives it group access to the mounted rootless socket, which appears as `root:root`. Access to that socket is privileged within the rootless Podman user's container and filesystem domain, so only trusted builds should use this agent.

## Provision agent directories

TeamCity's container wrapper requires the checkout, temporary, tool, plugin, log, and system directories to exist at the same absolute paths on the Podman host and in the agent container. Provision them before starting the stack:

```powershell
podman machine ssh -- "sudo mkdir -p /opt/buildagent/{work,temp,logs,tools,plugins,system} && sudo chown -R 1000:1000 /opt/buildagent && podman unshare chown -R 1000:1000 /opt/buildagent"
```

The final command maps container UID 1000 to its rootless host subordinate UID and prevents recurring write failures. On native Linux, run the equivalent commands directly as the account that owns the rootless Podman service.

## Start or update the stack

From PowerShell:

```powershell
$env:PODMAN_COMPOSE_PROVIDER = (Get-Command docker-compose).Source
podman compose -f C:\setup\teamcity-compose\compose.yaml up -d --build --remove-orphans
```

Open `http://localhost:8111`, finish the TeamCity database/license/administrator setup, and authorize the agent. On a fresh database, make the required one-time decision to import both projects from VCS:

```powershell
./teamcity-compose/Import-VersionedSettings.ps1
```

The script reads the current local super-user token from the TeamCity container logs without printing it; alternatively, pass an access token with `-Token`. It briefly disables each versioned-settings integration to clear any automatic retry, then enables it with TeamCity's supported `importFromVCS` decision. TeamCity subsequently synchronizes the peer manual projects `Sample Testcontainers` and `Sample Compose` normally. Re-run the Compose start command after image or configuration updates.

TeamCity probes its Compose provider as `podman-compose` when Podman is selected. The image supplies that command as a thin compatibility launcher for the same checksum-verified `docker-compose` 5.3.1 binary. This advertises `podman.version`, `podmanCompose.version`, and the `DockerCompose` runner without installing Docker. Both `CONTAINER_HOST` and `DOCKER_HOST` target the mounted rootless socket, and the inherited Root-project parameter `teamcity.default.container.engine=podman` makes the wrapper choice explicit for both samples.

TeamCity images default to the `docker.io` registry. To use a registry mirror, set `CONTAINER_REGISTRY` to its host or prefix without a trailing slash before running Compose, for example `$env:CONTAINER_REGISTRY = "registry.example.com"`. The agent downloads its pinned Podman and Compose binaries from `github.com`; set `GITHUB_HOST` to a compatible GitHub download mirror when direct GitHub access is unavailable.

## Git and TeamCity configuration

Compose mounts the host checkout read-only at `/repo` in both TeamCity containers. It mounts `server-config` read-write as the TeamCity data directory's complete `config` directory. This avoids first-start ownership problems with nested bind-mount targets and exposes these checked-in definitions to TeamCity:

- The root-project VCS root `CurrentRepository`, pointing to `file:///repo/.git`.
- The peer `Sample Testcontainers` and `Sample Compose` projects, each using `CurrentRepository` and a custom settings path under its own sample.

These settings are equivalent to creating the following configuration in the UI:

| Setting | Value |
| --- | --- |
| Fetch URL | `file:///repo/.git` |
| Default branch | `refs/heads/main` |
| Authentication | Anonymous |

The checked-in `server-config/internal.properties` enables local file VCS URLs, which TeamCity 2026.1 disables by default for security. Later internal-property changes made in TeamCity persist to this host file.

TeamCity reads and updates the host-backed configuration directly. Only `internal.properties`, the Root project descriptor, `CurrentRepository.xml`, and the two peer `project-config.xml` files are tracked. Scoped `.gitignore` files exclude database, authentication, encryption, Kotlin-derived build types, configuration backups, counters, plugin data, and other runtime files. The Kotlin DSL under each sample's `.teamcity` directory remains the source of truth for generated build configurations. Never force-add ignored files from `server-config`: they can contain credentials and other installation-specific secrets.

Only use this local-file arrangement for a trusted demonstration repository. Anyone who can modify the mounted repository can modify the versioned TeamCity settings that the server imports.

## Services and mounts

| Service | Ports and mounts | Notes |
| --- | --- | --- |
| `server` | `127.0.0.1:8111:8111`; `server-data`; `server-logs`; `../:/repo:ro`; `./server-config:/data/teamcity_server/datadir/config` | Provides the TeamCity UI, persistent state, local repository access, and writable host-backed server/project configuration. |
| `agent` | `agent-config`; `../:/repo:ro`; Podman socket; `/opt/buildagent/{work,temp,logs,tools,plugins,system}` | Runs as UID 1000, connects to TeamCity, and launches nested build containers through the Podman remote client. |

The repository mount is relative to `compose.yaml`, so this sample does not depend on `C:\setup`. The identical `/repo` path on the server and agent supports both server-side VCS operations and agent-side checkout. The stack's named volumes preserve TeamCity server data, logs, and agent configuration across container replacement. The host-backed agent directories preserve wrapper-visible paths and must not be remapped inside the agent. The initial `podman unshare chown` remains necessary; Podman detection prevents TeamCity from launching its Docker/busybox ownership-restoration container after every wrapped step.
