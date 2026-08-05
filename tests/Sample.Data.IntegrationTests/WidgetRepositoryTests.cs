using DotNet.Testcontainers.Builders;
using Microsoft.Data.SqlClient;
using Sample.Data;
using Xunit;

namespace Sample.Data.IntegrationTests;

public sealed class WidgetRepositoryTests
{
    private const string SqlImage = "mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04";

    [Fact]
    public async Task Inserted_widget_can_be_loaded_from_mssql()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var networkName = Environment.GetEnvironmentVariable("TC_BUILD_NETWORK");
        Assert.False(string.IsNullOrWhiteSpace(networkName), "TC_BUILD_NETWORK must identify the pre-created build network.");

        var buildId = Environment.GetEnvironmentVariable("TC_BUILD_ID") ?? "local";
        var agentName = Environment.GetEnvironmentVariable("TC_AGENT_NAME") ?? "local-agent";
        var owner = Environment.GetEnvironmentVariable("TC_RESOURCE_OWNER") ?? "local-build-type";
        var containerName = $"mssql-{buildId.ToLowerInvariant()}";
        var password = $"Tc!{Guid.NewGuid():N}aA1";

        await using var sqlServer = new ContainerBuilder(SqlImage)
            .WithName(containerName)
            .WithExposedPort(1433)
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("MSSQL_SA_PASSWORD", password)
            .WithWaitStrategy(Wait.ForUnixContainer().UntilCommandIsCompleted(
                "/opt/mssql-tools18/bin/sqlcmd", "-C", "-S", "localhost", "-U", "sa", "-P", password, "-Q", "SELECT 1;"))
            .WithLabel("tc.owner", owner)
            .WithLabel("tc.agent.name", agentName)
            .WithLabel("tc.build.id", buildId)
            .Build();

        await sqlServer.StartAsync(cancellationToken);
        await sqlServer.ConnectAsync(networkName, cancellationToken);

        var connectionString = new SqlConnectionStringBuilder
        {
            DataSource = $"{containerName},1433",
            InitialCatalog = "master",
            UserID = "sa",
            Password = password,
            Encrypt = false,
            TrustServerCertificate = true
        }.ConnectionString;

        var repository = new WidgetRepository(connectionString);
        await repository.InitializeAsync(cancellationToken);
        var id = await repository.AddAsync("TeamCity Testcontainers", cancellationToken);

        var widget = await repository.FindAsync(id, cancellationToken);

        Assert.NotNull(widget);
        Assert.Equal("TeamCity Testcontainers", widget.Name);
    }
}
