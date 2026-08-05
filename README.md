# TeamCity MSSQL Testcontainers sample

This .NET 10 integration-test project demonstrates an isolated TeamCity build:

- TeamCity checks out this Git repository.
- The .NET test step runs in an ephemeral SDK container.
- Each agent/build-configuration pair has one persistent network shared by its SDK runner and SQL Server Testcontainer.
- The test attaches SQL Server to that existing network and reaches it by its build-specific container name.

The TeamCity project configuration lives in `.teamcity/settings.kts`. In the demo Compose network, its settings VCS root must use:

```text
git://git-repo:9418/sample-project.git
```

The build agent requires access to its rootless Podman API socket. Transient resources carry owner, agent, build-type, and build labels. Testcontainers' Ryuk resource reaper removes transient containers, including after the test process terminates unexpectedly.

The Compose stack uses `teamcity-control` only for server-to-agent traffic. Test runners do not join that network. The `build.network.name` parameter defaults to `tc-<agent name>-<build-type id>`; the build idempotently creates that network and leaves it in place for later builds. Renamed agents, build configurations, or parameter values can leave obsolete networks that an administrator may remove manually.
