# TeamCity Podman samples

This repository contains two independent .NET 10 integration-testing samples. Both exercise the same SQL Server, Kafka, and combined scenarios on rootless Podman, but each demonstrates one infrastructure lifecycle.

| Sample | Lifecycle | Documentation |
| --- | --- | --- |
| `samples/compose` | Compose owns SQL Server and Kafka | [Compose sample](samples/compose/README.md) |
| `samples/testcontainers` | The test fixtures own SQL Server and Kafka | [Testcontainers sample](samples/testcontainers/README.md) |

Each sample owns its solution, SDK and NuGet configuration, source, tests, infrastructure files, README, and TeamCity Kotlin DSL. Nothing under one sample is referenced by the other. The `samples/<approach>` layout leaves room for future approaches without creating a shared runtime abstraction.

## TeamCity demo

[`teamcity-compose`](teamcity-compose/README.md) runs a TeamCity server and one custom Linux agent. It registers two peer, manual projects, each with its own project-owned VCS root:

- `Sample Testcontainers`, whose settings path is `samples/testcontainers/.teamcity`
- `Sample Compose`, whose settings path is `samples/compose/.teamcity`

Neither build has a trigger. Project IDs are derived from display names, making the Testcontainers project ID `SampleTestcontainers` and its VCS root `SampleTestcontainers_Repository`. This intentional identity migration requires a clean local TeamCity data reset when testing.

See [ARCHITECTURE.md](ARCHITECTURE.md) for networking, cleanup, and security details.
