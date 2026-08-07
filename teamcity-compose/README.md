# TeamCity rootless Podman demo

This Compose deployment runs one TeamCity server and one Linux build agent on the `teamcity-control` network. It is the single-agent demonstration stack; adding production agents requires separate agent configuration volumes and directory trees.

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
podman compose -f C:\setup\teamcity-compose\compose.yaml up -d --remove-orphans
```

Open `http://localhost:8111`, finish the TeamCity database/license/administrator setup, and authorize the agent. The `Sample` project and its `MSSQL Testcontainers` build configuration appear automatically after TeamCity imports `.teamcity/settings.kts`. Re-run the same Compose command after image or configuration updates. `--remove-orphans` also removes the obsolete `teamcity-git` container when updating an earlier version of this sample.

TeamCity images default to the `docker.io` registry. To use a registry mirror, set `CONTAINER_REGISTRY` to its host or prefix without a trailing slash before running Compose, for example `$env:CONTAINER_REGISTRY = "registry.example.com"`.

## Git and TeamCity configuration

Compose mounts the host checkout read-only at `/repo` in both TeamCity containers. It also mounts two checked-in TeamCity configuration directories read-write:

- The root-project VCS root `CurrentRepository`, pointing to `file:///repo/.git`.
- The `Sample` project, with one-way Kotlin versioned settings enabled from `CurrentRepository`.

These settings are equivalent to creating the following configuration in the UI:

| Setting | Value |
| --- | --- |
| Fetch URL | `file:///repo/.git` |
| Default branch | `refs/heads/main` |
| Authentication | Anonymous |

The checked-in `server-config/internal.properties` enables local file VCS URLs, which TeamCity 2026.1 disables by default for security. Compose mounts this file read-write at `/data/teamcity_server/datadir/config/internal.properties`, so no initial Diagnostics-page edit is required and later internal-property changes made in TeamCity persist to the host file.

TeamCity reads and updates the host-backed project directories directly. Only `CurrentRepository.xml` and `Sample/project-config.xml` are tracked; scoped `.gitignore` files exclude Kotlin-derived build types, configuration backups, counters, plugin data, and other runtime files. The Kotlin DSL under `.teamcity` remains the source of truth for generated build configurations.

Only use this local-file arrangement for a trusted demonstration repository. Anyone who can modify the mounted repository can modify the versioned TeamCity settings that the server imports.

## Services and mounts

| Service | Ports and mounts | Notes |
| --- | --- | --- |
| `server` | `127.0.0.1:8111:8111`; `server-data`; `server-logs`; `../:/repo:ro`; host-backed `server-config` mounts | Provides the TeamCity UI, persistent state, local repository access, local-file URL opt-in, and writable project bootstrap configuration. |
| `agent` | `agent-config`; `../:/repo:ro`; Podman socket; `/opt/buildagent/{work,temp,logs,tools,plugins,system}` | Connects to `http://server:8111`, checks out the local repository, and launches nested build containers through Podman. |

The repository mount is relative to `compose.yaml`, so this sample does not depend on `C:\setup`. The identical `/repo` path on the server and agent supports both server-side VCS operations and agent-side checkout. The stack's named volumes preserve TeamCity server data, logs, and agent configuration across container replacement. The host-backed agent directories preserve wrapper-visible paths and must not be remapped to different paths inside the agent. The Compose stack itself creates only `teamcity-control`; versioned TeamCity settings create and retain build-specific networks during builds.
