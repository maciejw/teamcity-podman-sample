# TeamCity Podman sample

This workspace demonstrates a complete TeamCity build that runs a .NET integration-test project in an ephemeral SDK container and starts SQL Server with Testcontainers on rootless Podman. A local Git daemon supplies the project to TeamCity, while persistent TeamCity data and agent work directories allow the demonstration to survive stack restarts.

## Workspace map

| Path | Purpose |
| --- | --- |
| `Sample.slnx`, `src/`, and `tests/` | .NET 10 sample library and its SQL Server integration tests. |
| `.teamcity/` | Versioned TeamCity project settings. |
| [`teamcity-compose/`](teamcity-compose/README.md) | Compose deployment for the TeamCity server, one build agent, and the Git daemon. |
| `git/teamcity-podman-sample.git/` | Optional local bare repository exported read-only by the Git daemon to TeamCity; this machine-local directory is not committed. |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Canonical topology, discovery, security, cleanup, and production-scaling guidance. |

## Run the sample locally

A running Docker-compatible container engine is required. Restore dependencies if needed, then run:

```powershell
dotnet test Sample.slnx
```

The shared xUnit fixture creates a uniquely named SQL Server container, publishes `1433` to a random host port, derives the connection string from that mapping, and disposes the container after the tests.

In TeamCity, `.teamcity/settings.kts` creates a persistent build network and configures the SDK runner with the network, `tc.owner`, `tc.agent.name`, and `tc.build.id` labels, the rootless Podman socket, `DOCKER_HOST`, and `TESTCONTAINERS_HOST_OVERRIDE`. `TEAMCITY_VERSION` selects strict CI discovery. `HOSTNAME` must remain the runner's inspectable short container ID, and discovery failures never fall back to a published SQL port.

The SDK image is not force-pulled for every build. Podman uses its cached `mcr.microsoft.com/dotnet/sdk:10.0` image and pulls it when initially absent; update or pin it as part of a deliberate SDK upgrade policy.

## Setup order

1. Install and start Podman (or Podman Machine on Windows), and make a Compose provider available.
2. Optionally create and populate `git/teamcity-podman-sample.git` as a local bare mirror of this repository.
3. Provision the agent directories under `/opt/buildagent` in the Podman host or machine.
4. Start the stack from `teamcity-compose/compose.yaml`.
5. Open TeamCity at `http://localhost:8111`, finish server setup, and authorize the build agent.
6. Configure the Git VCS root as `git://git-repo:9418/teamcity-podman-sample.git`, using `refs/heads/main` and anonymous authentication, then load the versioned settings from `.teamcity`.
7. Run the `MSSQL Testcontainers` build configuration.

For exact deployment commands and mounts, see the [Compose README](teamcity-compose/README.md). See the [architecture guide](ARCHITECTURE.md) for the full networking, discovery, cleanup, security, and scaling model.
