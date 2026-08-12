# TeamCity rootless Podman demo

This Compose deployment runs one TeamCity server and one custom Linux build agent on the `teamcity-control` network. The agent image is based on `teamcity-minimal-agent:2026.1.3-linux` and contains Git, the Podman 6.0.2 remote client, and standalone Docker Compose 5.3.1. It deliberately contains no Docker CLI.

## Prerequisites

- Podman, with a running rootless Podman machine or Linux service for UID 1000.
- A Compose provider usable by `podman compose`, such as `podman-compose` or `docker-compose`.
- The rootless API socket at `/run/user/1000/podman/podman.sock`.
- This repository checked out on the Windows host. Compose mounts the directory above `teamcity-compose` read-only as `/repo` in both the TeamCity server and agent so the local-file VCS root is available during settings import and agent-side checkout.

The agent runs as non-root UID/GID 1000 with `userns_mode: keep-id`. The rootless API socket is owned by the same host UID/GID, so no supplemental container group is required. Access to that socket is privileged within the rootless Podman user's container and filesystem domain, so only trusted builds should use this agent.

## Agent directories

`Bootstrap-TeamCity.ps1` provisions and owns the host-side `TEAMCITY_AGENT_ROOT`, which defaults to `/opt/teamcity-agents`. Compose mounts this common parent at the identical path inside every agent. At startup, each replica resolves its Compose container name through Podman and uses a unique home such as `/opt/teamcity-agents/teamcity-agent-1`. The custom launcher copies the agent distribution from the image's `/opt/buildagent` template on first start and stores that replica's configuration in its own home. Running from a path-identical directory allows TeamCity's Container Wrapper to mount its files through the remote Podman daemon. The agent runs with `userns_mode: keep-id`, so ownership by UID 1000 on the Podman machine is sufficient. An explicitly defined agent service can set `TEAMCITY_AGENT_HOME` to bypass automatic naming.

## Start or update the stack

From PowerShell:

```powershell
./teamcity-compose/Bootstrap-TeamCity.ps1
```

To run four replicas on the same rootless Podman socket and shared agent root:

```powershell
./teamcity-compose/Bootstrap-TeamCity.ps1 -AgentCount 4
```

The script starts the Compose stack and waits for `/healthCheck/ready` to return HTTP 200. This confirms that the server is reachable, not that the database, license, administrator, or EULA setup is complete; finish that setup at `http://localhost:8111` before running the script. Once the server is reachable, it reads the current local super-user token from the container logs and prints it; alternatively, pass a permanent access token with `-AccessToken` (`-Token` remains an alias). The script waits for and authorizes every requested replica (`teamcity-agent-1`, `teamcity-agent-2`, and so on), then performs the three project writes—project creation, VCS-root creation, and versioned-settings configuration—for each entry in the ordered project definition map in `TeamCityBootstrap.psm1`. This is a create-only initializer following TeamCity's documented project-import flow, not a no-op synchronizer. Rerunning it against existing IDs is expected to fail; reset local TeamCity data before a clean rerun. Project IDs are derived by removing non-alphanumeric characters, so the Testcontainers project ID is `SampleTestcontainers`.

Run the bootstrap tests with Pester 6 or later:

```powershell
Import-Module Pester -MinimumVersion 6.0.0 -Force
Invoke-Pester -Path ./teamcity-compose/tests
```

TeamCity probes its Compose provider as `podman-compose` when Podman is selected. The image supplies that command as a thin compatibility launcher for the same checksum-verified `docker-compose` 5.3.1 binary. This advertises `podman.version`, `podmanCompose.version`, and the `DockerCompose` runner without installing Docker. Both `CONTAINER_HOST` and `DOCKER_HOST` target the mounted rootless socket, and the inherited Root-project parameter `teamcity.default.container.engine=podman` makes the wrapper choice explicit for both samples.

TeamCity images default to the `docker.io` registry. To use a registry mirror, set `CONTAINER_REGISTRY` to its host or prefix without a trailing slash before running Compose, for example `$env:CONTAINER_REGISTRY = "registry.example.com"`. The agent downloads its pinned Podman and Compose binaries from `github.com`; set `GITHUB_HOST` to a compatible GitHub download mirror when direct GitHub access is unavailable. The Compose environment file is [`teamcity-compose/.env`](.env); `APT_REPOSITORY` and `APT_SECURITY_REPOSITORY` are required and default to the official Ubuntu endpoints. Set them to the corresponding Artifactory package sources in restricted environments. The Dockerfile always writes a complete Ubuntu Deb822 source definition using the base image's codename.

## Git and TeamCity configuration

Compose mounts the host checkout read-only at `/repo` in both the TeamCity server and agents. The server uses it to import versioned settings, while each agent uses the same local-file VCS root for agent-side checkout and stores build state under its replica-specific home. A one-shot `server-data-init` service prepares the named `server-data` volume, creates the TeamCity config directories, and assigns them to UID 1000 before the server starts. TeamCity's complete data directory, including its generated `config` directory, persists in that volume. The bootstrap files `root-project-config.xml` and `internal.properties` are mapped directly to their TeamCity config paths. The Root descriptor includes the fixed `teamcity.default.container.engine=podman` parameter and satisfies TeamCity's fresh-start requirement. The project definition map registers:

- `Sample Testcontainers`, with its project-owned `SampleTestcontainers_Repository` VCS root and `samples/testcontainers/.teamcity` settings path.
- `Sample Compose`, with its project-owned `SampleCompose_Repository` VCS root and `samples/compose/.teamcity` settings path.

Both VCS roots point to `file:///repo/.git`; duplicating that endpoint keeps each project registration self-contained.

These settings are equivalent to creating the following configuration in the UI:

| Setting | Value |
| --- | --- |
| Fetch URL | `file:///repo/.git` |
| Default branch | `refs/heads/main` |
| Authentication | Anonymous |

The checked-in `server-bootstrap/internal.properties` enables local file VCS URLs, which TeamCity 2026.1 disables by default for security. Later internal-property changes made in TeamCity persist to this host file.

TeamCity writes its generated project XML and other installation state into the `server-data` volume. The Root descriptor and internal properties are deliberately mapped from the bootstrap files for this sample. The Kotlin DSL under each sample's `.teamcity` directory remains the source of truth for generated build configurations.

This demonstrates a simple ownership boundary: the bootstrap registers each static project, its VCS root, and its settings location, while the project's `.teamcity` directory owns its builds. Shared request shapes are templates materialized in memory from the map. In a production installation, run the bootstrap once with a scoped service account token obtained from secret storage instead of relying on local super-user token discovery.

Only use this local-file arrangement for a trusted demonstration repository. Anyone who can modify the mounted repository can modify the versioned TeamCity settings that the server imports.

## Services and mounts

| Service | Ports and mounts | Notes |
| --- | --- | --- |
| `server-data-init` | `server-data`; `./server-bootstrap/init-server-data.sh:/bootstrap/init-server-data.sh:ro` | Creates the config tree and repairs ownership for TeamCity UID 1000. |
| `server` | `127.0.0.1:8111:8111`; `server-data`; `server-logs`; `../:/repo:ro`; Root descriptor and `internal.properties` file mappings | Provides the TeamCity UI, persistent state, local repository access, and generated server/project configuration. |
| `agent` | Podman socket; `../:/repo:ro`; path-identical `TEAMCITY_AGENT_ROOT` bind | Runs as UID 1000 from a replica-specific home and launches nested build containers through the Podman remote client. |

The repository mount is relative to `compose.yaml`, so this sample does not depend on `C:\setup`. The shared read-only `/repo` mount supports server-side settings import and agent-side checkout. The path-identical agent-root bind preserves each complete agent installation and makes every wrapper source path visible in the Podman VM namespace. Named volumes preserve TeamCity server data and logs, while each replica's configuration and build state persist under `TEAMCITY_AGENT_ROOT`. Podman detection prevents TeamCity from launching its Docker/busybox ownership-restoration container after every wrapped step.
