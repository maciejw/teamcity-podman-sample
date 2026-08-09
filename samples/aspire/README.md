# Aspire sample

This self-contained .NET 10 sample runs the same SQL Server, Kafka, and combined integration scenarios through an Aspire AppHost. The tests use `Aspire.Hosting.Testing` to start the AppHost, wait for both resources to become healthy, obtain their dynamically allocated connection details, and dispose the AppHost in fixture cleanup.

## Run locally

```powershell
dotnet test samples/aspire/Sample.slnx
```

Aspire keeps randomized ports enabled, so parallel runs do not require fixed host ports. For Podman, set `ASPIRE_CONTAINER_RUNTIME=podman`.

Aspire 13.4.6 also requires its DCP and dashboard orchestration binaries at runtime. They are supplied by an Aspire-enabled SDK/workload or by the Aspire CLI bundle; the plain SDK image used by the current TeamCity experiment does not include them. The first TeamCity run therefore serves as the explicit packaging/runtime check and needs an image or bootstrap layer that supplies the matching Aspire 13.4.6 bundle before tests can reach Podman.

## TeamCity

The manual build runs one `dotnetTest` step in the existing .NET SDK container pattern. TeamCity does not run a Compose runner or create a build network anchor. The SDK container mounts the agent's rootless Podman socket and sets `DOCKER_HOST` plus `ASPIRE_CONTAINER_RUNTIME=podman`.

The test process launches the AppHost/DCP. Aspire creates SQL Server and Kafka, manages readiness, publishes dynamic endpoints, and disposes the resources after successful or failed tests. The fixture does not read `TEAMCITY_DOCKER_NETWORK` or use fixed TeamCity DNS names. The only container-runtime boundary is `/run/user/1000/podman/podman.sock`.

The fixture has a five-minute AppHost/resource startup timeout. Build logs label AppHost startup, resource readiness, test execution, and AppHost cleanup.
