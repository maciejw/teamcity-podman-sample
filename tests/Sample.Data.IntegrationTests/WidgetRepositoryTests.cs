using Microsoft.Data.SqlClient;
using Sample.Data;
using Testcontainers.MsSql;
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
        var owner = Environment.GetEnvironmentVariable("TC_RESOURCE_OWNER") ?? "teamcity-mssql-sample";
        var containerName = $"mssql-{buildId.ToLowerInvariant()}";
        var password = $"Tc!{Guid.NewGuid():N}aA1";

        await using var sqlServer = new MsSqlBuilder(SqlImage)
            .WithName(containerName)
            .WithPassword(password)
            .WithLabel("tc.owner", owner)
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
