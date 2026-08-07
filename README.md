# TeamCity Podman sample

This workspace demonstrates a complete TeamCity build that runs a .NET integration-test project in an ephemeral SDK container and starts SQL Server with Testcontainers on rootless Podman. TeamCity reads the host checkout through a read-only local-file mount, while persistent TeamCity data and agent work directories allow the demonstration to survive stack restarts.

## Workspace map

| Path | Purpose |
| --- | --- |
| `Sample.slnx`, `src/`, and `tests/` | .NET 10 sample library and its SQL Server integration tests. |
| `.teamcity/` | Versioned TeamCity project settings. |
| `teamcity-compose/server-config/` | Host-backed TeamCity VCS root, `Sample` project link, and local-file URL setting. |
| [`teamcity-compose/`](teamcity-compose/README.md) | Compose deployment for the TeamCity server and one build agent. |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Canonical topology, discovery, security, cleanup, and production-scaling guidance. |

## Run the sample locally

A running Docker-compatible container engine is required. Restore dependencies if needed, then run:

```powershell
dotnet test Sample.slnx
```

The shared xUnit fixture creates a uniquely named SQL Server container, publishes `1433` to a random host port, derives the connection string from that mapping, and disposes the container after the tests.

In TeamCity, `.teamcity/settings.kts` creates a persistent build network and configures the SDK runner with the network, `tc.owner`, `tc.agent.name`, and `tc.build.id` labels, the rootless Podman socket, `DOCKER_HOST`, and `TESTCONTAINERS_HOST_OVERRIDE`. It also passes the network and ownership values as `SAMPLE_TEAMCITY_*` environment variables. `TEAMCITY_VERSION` selects strict CI discovery; missing TeamCity context never falls back to a published SQL port.

The SDK image is not force-pulled for every build. Podman uses its cached `mcr.microsoft.com/dotnet/sdk:10.0` image and pulls it when initially absent; update or pin it as part of a deliberate SDK upgrade policy.

## Setup order

1. Install and start Podman (or Podman Machine on Windows), and make a Compose provider available.
2. Provision the agent directories under `/opt/buildagent` in the Podman host or machine.
3. Start the stack from `teamcity-compose/compose.yaml`.
4. Open TeamCity at `http://localhost:8111`, finish the database/license/administrator setup, and authorize the build agent. Compose has already created the `CurrentRepository` VCS root and connected the `Sample` project to `.teamcity` versioned settings.
5. Run the `MSSQL Testcontainers` build configuration.

For exact deployment commands and mounts, see the [Compose README](teamcity-compose/README.md). See the [architecture guide](ARCHITECTURE.md) for the full networking, discovery, cleanup, security, and scaling model.
