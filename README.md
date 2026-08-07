# TeamCity Podman samples

This repository contains two independent .NET 10 integration-testing samples. Both exercise the same SQL Server, Kafka, and combined scenarios on rootless Podman, but each demonstrates one infrastructure lifecycle.

| Sample | Lifecycle | Documentation |
| --- | --- | --- |
| `samples/compose` | Compose owns SQL Server and Kafka | [Compose sample](samples/compose/README.md) |
| `samples/testcontainers` | The test fixtures own SQL Server and Kafka | [Testcontainers sample](samples/testcontainers/README.md) |

Each sample owns its solution, SDK and NuGet configuration, source, tests, infrastructure files, README, and TeamCity Kotlin DSL. Nothing under one sample is referenced by the other. The `samples/<approach>` layout leaves room for future approaches without creating a shared runtime abstraction.

## TeamCity demo

[`teamcity-compose`](teamcity-compose/README.md) runs a TeamCity server and one custom Linux agent. The root-owned `CurrentRepository` VCS root feeds two peer, manual projects:

- `Sample Testcontainers`, whose settings path is `samples/testcontainers/.teamcity`
- `Sample Compose`, whose settings path is `samples/compose/.teamcity`

Neither build has a trigger. The Testcontainers peer retains external project ID `Sample`, so its relative DSL ID preserves the existing absolute build-type ID `Sample_MssqlTestcontainers` and its build history.

See [ARCHITECTURE.md](ARCHITECTURE.md) for networking, cleanup, and security details.
