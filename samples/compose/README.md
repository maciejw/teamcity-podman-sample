# Compose sample

This self-contained .NET 10 sample runs the same SQL Server, Kafka, and combined integration scenarios against infrastructure managed by Compose. Its test code owns the disposable SQL credential and selects endpoints from TeamCity presence: `mssql:1433` and `kafka:9092` in TeamCity, or the local loopback endpoints `127.0.0.1:1433` and `127.0.0.1:9092` on a developer host.

## Run or debug locally

Start the services and wait for their bounded health checks:

```powershell
./samples/compose/Start-Local.ps1
```

The script automatically uses Podman when its Compose provider is available, otherwise Docker Compose. Pass `-Engine Docker` or `-Engine Podman` to select one explicitly. It resolves both Compose files relative to the script, so it works from any current directory. The equivalent direct command is `docker compose -f samples/compose/compose.yaml -f samples/compose/compose.local.yaml up -d --wait`.

Then run `dotnet test samples/compose/Sample.slnx`, or run/debug the tests normally in Visual Studio Test Explorer. Fixed ports 1433 and 9092 must be free. Stop the services afterward with:

```powershell
./samples/compose/Start-Local.ps1 -Action Down
```

The base file has no published ports. The local override publishes SQL Server and Kafka only on the host loopback interface, using ports 1433 and 9092, and changes Kafka's advertised address to `127.0.0.1:9092`. TeamCity uses the base file without the override, where Kafka advertises `kafka:9092`. Explicit IPv4 loopback avoids Windows/WSL environments that resolve `localhost` to an unusable IPv6 forwarding path.

## TeamCity

The manual TeamCity build starts only the base file through the typed Compose runner. `COMPOSE_PROJECT_NAME` combines the agent name and TeamCity build type ID. Since an agent executes one build at a time, concurrent builds on different agents receive separate Compose resources and networks, while later runs of the same build type on the same agent reuse a deterministic project name. The agent's Compose compatibility launcher normalizes TeamCity's mixed-case build type ID to Compose's lowercase naming rules. TeamCity waits for service health, attaches the following SDK wrapper to that build's generated network, and tears down the services and network after the build. No endpoint environment parameters or Testcontainers resources are used.
