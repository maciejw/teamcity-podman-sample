# TeamCity MSSQL Testcontainers sample

This .NET 10 integration-test project demonstrates an isolated TeamCity build:

- TeamCity checks out this Git repository.
- The .NET test step runs in an ephemeral SDK container.
- The build and its SQL Server Testcontainer share a uniquely named per-build network.
- The test attaches SQL Server to that existing network and reaches it by its build-specific container name.

The TeamCity project configuration lives in `.teamcity/settings.kts`. Its settings VCS root must use:

```text
file:///vcs/sample-project.git
```

The build agent requires access to its rootless Podman API socket. The build creates and removes resources labeled with `tc.owner` and `tc.build.id` so cleanup is scoped to the current agent and build.

The Compose stack uses `teamcity-control` only for server-to-agent traffic. Test runners do not join that network; the build configuration creates `tc-build-<build id>` for each run and removes it in an always-run cleanup step.
