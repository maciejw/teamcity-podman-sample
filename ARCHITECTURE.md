# Architecture

## Independent samples

`samples/compose`, `samples/testcontainers`, and `samples/aspire` are deliberately self-contained. They duplicate the small production component and the three SQL, Kafka, and combined tests so that each sample explains one lifecycle model without shared code or runtime configuration.

## Aspire lifecycle

The Aspire sample's test process launches the AppHost with `Aspire.Hosting.Testing`. The AppHost/DCP creates SQL Server and Kafka through the configured container runtime, waits for resource health, and removes both resources when the test fixture is disposed—even when tests fail. Tests read dynamically allocated SQL and Kafka connection details from Aspire, and port randomization remains enabled for parallel runs.

## Compose lifecycle

The base `samples/compose/compose.yaml` defines SQL Server and a single-node KRaft Kafka broker with bounded health checks, no volumes, and no published ports. The SDK wrapper joins the generated default network, so test code detects `TEAMCITY_VERSION` and uses `mssql:1433` and `kafka:9092`. Compose teardown removes the services and build network.

For host development, `compose.local.yaml` publishes SQL Server and Kafka at IPv4 loopback ports 1433 and 9092. Explicit IPv4 avoids an unusable IPv6 forwarding path on Windows/WSL Podman hosts.

## Testcontainers lifecycle

Locally, the Testcontainers fixtures create uniquely named SQL Server and Kafka containers and connect through random host ports. In TeamCity, the typed Compose runner supplies the build network and fixtures use container DNS.

## TeamCity configuration

The TeamCity server bootstrap contains three peer projects defined by an ordered map. Each project owns a VCS root pointing to the repository mounted in the server and a versioned-settings configuration pointing to its sample-specific `.teamcity` directory. TeamCity checks out sources and keeps agent build state under `/opt/buildagent` on the agent. All builds are manual and require Linux, Podman, and Compose capability; Aspire itself uses only a `dotnetTest` step and no Compose runner or network anchor. The Aspire project ID is `SampleAspire` and its VCS root is `SampleAspire_Repository`.

The bootstrap materializes shared REST request templates in memory and performs exactly three writes per map entry: project creation, VCS-root creation, and versioned-settings configuration with `importDecision=importFromVCS`. It is intentionally create-only and does not provide no-op convergence; reset local TeamCity data before rerunning it. Each project's Kotlin DSL remains the source of truth for its build configurations. The Root project seed retains `teamcity.default.container.engine=podman`.

## Podman boundary

The custom agent has a checksum-pinned Podman remote client and standalone Compose binary, with a `podman-compose` compatibility launcher. It deliberately has no Docker CLI. The mounted rootless Podman socket grants control over resources owned by that Podman user. Only mutually trusted builds should share it.
