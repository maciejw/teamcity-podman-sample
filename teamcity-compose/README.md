# TeamCity rootless Podman demo

This Compose deployment runs one TeamCity server, one Linux build agent, and one Git daemon on the `teamcity-control` network. It is the single-agent demonstration stack; adding production agents requires separate agent configuration volumes and directory trees.

## Prerequisites

- Podman, with a running rootless Podman machine or Linux service for UID 1000.
- A Compose provider such as `docker-compose`.
- The rootless API socket at `/run/user/1000/podman/podman.sock`.
- The bare repository at `C:\setup\git\teamcity-podman-sample.git`.

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
podman compose -f C:\setup\teamcity-compose\compose.yaml up -d
```

Open `http://localhost:8111`, finish the TeamCity server setup, and authorize the agent. Re-run the same Compose command after image or configuration updates.

## Git and TeamCity configuration

The `git-repo` service mounts `C:\setup\git` read-only and exports its bare repositories only on the control network. Configure the TeamCity Git VCS root with:

| Setting | Value |
| --- | --- |
| Fetch URL | `git://git-repo:9418/teamcity-podman-sample.git` |
| Default branch | `refs/heads/main` |
| Authentication | Anonymous |

Then load the versioned project settings from `.teamcity` in that repository.

## Services and mounts

| Service | Ports and mounts | Notes |
| --- | --- | --- |
| `server` | `127.0.0.1:8111:8111`; `server-data`; `server-logs` | TeamCity UI and persistent server state. |
| `git-repo` | `C:/setup/git:/git:ro` | Installs and runs `git daemon`; reachable only inside `teamcity-control`. |
| `agent` | `agent-config`; Podman socket; `/opt/buildagent/{work,temp,logs,tools,plugins,system}` | Connects to `http://server:8111` and launches nested build containers through Podman. |

The stack's named volumes preserve TeamCity server data, logs, and agent configuration across container replacement. The host-backed agent directories preserve wrapper-visible paths and must not be remapped to different paths inside the agent. The Compose stack itself creates only `teamcity-control`; versioned TeamCity settings create and retain build-specific networks during builds.
