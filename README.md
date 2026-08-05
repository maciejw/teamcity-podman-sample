# TeamCity MSSQL Testcontainers sample

This .NET 10 integration-test project demonstrates an isolated TeamCity build:

- TeamCity checks out this Git repository.
- The .NET test step runs in an ephemeral SDK container.
- The build and its SQL Server Testcontainer share a per-build network.
- SQL Server is reachable only through the `mssql` network alias used by the test.

The TeamCity project configuration lives in `.teamcity/settings.kts`. Its settings VCS root must use:

```text
file:///vcs/sample-project.git
```

The build agent requires access to its rootless Podman API socket. The build creates and removes resources labeled with `tc.owner` and `tc.build.id` so cleanup is scoped to the current agent and build.
