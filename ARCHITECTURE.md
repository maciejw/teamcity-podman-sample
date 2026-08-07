# Architecture

## Independent samples

`samples/compose` and `samples/testcontainers` are deliberately self-contained. They duplicate the small production component and the three SQL, Kafka, and combined tests so that each sample explains one lifecycle model without shared code or runtime configuration.

## Compose lifecycle

The base `samples/compose/compose.yaml` defines SQL Server and a single-node KRaft Kafka broker with bounded health checks, no volumes, and no published ports. TeamCity starts that file with its typed Compose runner. The following SDK wrapper joins the generated default network, so test code detects `TEAMCITY_VERSION` and uses `mssql:1433` and `kafka:9092`. Compose teardown removes the services and build network.

For host development, `compose.local.yaml` publishes SQL Server and Kafka at IPv4 loopback ports 1433 and 9092 and changes Kafka's advertised address to `127.0.0.1:9092`. TeamCity uses only the base file, where Kafka advertises `kafka:9092`. Developers start both local files with `--wait`, then use Test Explorer or `dotnet test`; test code uses the loopback endpoints when TeamCity is absent. Explicit IPv4 avoids an unusable IPv6 forwarding path on Windows/WSL Podman hosts.

The disposable SQL password is intentionally duplicated between the Compose file and the sample's C# endpoint configuration. Fixed local ports are a documented development constraint.

## Testcontainers lifecycle

Locally, the Testcontainers fixtures create uniquely named SQL Server and Kafka containers and connect through random host ports. Kafka runs KRaft without ZooKeeper. Fixture disposal handles normal and partial-startup cleanup, and Ryuk covers unexpectedly terminated runs.

In TeamCity, the typed Compose runner first starts the single inert service in `samples/testcontainers/compose.yaml`. TeamCity derives `TEAMCITY_DOCKER_NETWORK` from that service and automatically joins the SDK wrapper to the default network. The build explicitly passes the variable into the wrapper. When `TEAMCITY_VERSION` exists, fixtures require the variable, join their containers to that network, and use container DNS: SQL Server on port 1433 and Kafka on its additional internal listener.

The SDK wrapper mounts `/run/user/1000/podman/podman.sock` as `/var/run/docker.sock`, sets `DOCKER_HOST`, and uses `TESTCONTAINERS_HOST_OVERRIDE=host.containers.internal` for Ryuk's mapped control connection. Testcontainers and Ryuk remove transient test resources; TeamCity Compose teardown removes the anchor and build-scoped network. There is no persistent build network or manual network maintenance.

## TeamCity configuration

The TeamCity server bootstrap contains one root-owned VCS root and two peer projects. Each project uses the same VCS root with a custom settings path pointing to its sample-specific `.teamcity` directory. Both build configurations are manual and require Linux, Podman, and Compose. The renamed Testcontainers peer retains external project ID `Sample`; its relative `MssqlTestcontainers` DSL ID therefore preserves the existing absolute ID `Sample_MssqlTestcontainers` and build history.

No endpoint parameters or infrastructure-mode variables are defined in TeamCity. The Compose sample derives its fixed endpoints in C#; the Testcontainers sample receives only TeamCity's generated network name.

## Podman boundary

The custom agent has a checksum-pinned Podman remote client and standalone Compose binary, with a `podman-compose` compatibility launcher. It deliberately has no Docker CLI. `podman.version`, `podmanCompose.version`, and `teamcity.default.container.engine=podman` keep TeamCity on its Podman path and avoid a Docker/busybox ownership-restoration step after wrapped builds.

The mounted rootless Podman socket grants control over resources owned by that Podman user. Only mutually trusted builds should share it. Wrapper-visible build-agent paths must exist at identical absolute paths on the Podman host and inside the agent; initial ownership is provisioned with `podman unshare chown`.

For multiple agents, give each separate configuration and `/opt/buildagent` directory trees. Agents can share an image cache and Podman service only when they share a trust boundary; the socket, machine, storage, and network remain common failure domains.
