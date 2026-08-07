# Testcontainers sample

This self-contained .NET 10 sample runs SQL Server and Kafka integration tests with Testcontainers. The suite covers a SQL repository round trip, a Kafka round trip, and a combined SQL/Kafka scenario.

## Run locally

Start a Docker-compatible container engine and run:

```powershell
dotnet test samples/testcontainers/Sample.slnx
```

SQL Server and Kafka use random host ports. Each test run creates uniquely named containers, and fixture disposal plus Ryuk remove them when the run finishes.

## TeamCity

The manual build starts the inert service in `compose.yaml` through TeamCity's Compose runner. This gives TeamCity a build-scoped network and causes its SDK wrapper to join that network. The wrapper explicitly receives `TEAMCITY_DOCKER_NETWORK`; the fixtures require that variable whenever `TEAMCITY_VERSION` is present and attach SQL Server and Kafka to it.

The wrapper mounts the rootless Podman socket and sets `DOCKER_HOST` and `TESTCONTAINERS_HOST_OVERRIDE`. SQL Server uses container DNS on port 1433, while Kafka advertises its internal listener. TeamCity's Compose teardown removes the anchor and network; fixture disposal and Ryuk remove the test containers.
