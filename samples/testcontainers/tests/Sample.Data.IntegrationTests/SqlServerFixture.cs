using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Containers;
using Microsoft.Data.SqlClient;
using Xunit;

namespace Sample.Data.IntegrationTests;

public sealed class SqlServerFixture : IAsyncLifetime
{
    private const int SqlPort = 1433;
    private const string SqlImage = "mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04";

    private IContainer? _sqlServer;

    public string ConnectionString { get; private set; } = string.Empty;

    public async ValueTask InitializeAsync()
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        var teamCity = TeamCityContextDiscovery.Discover();
        var containerName = $"mssql-{Guid.NewGuid():N}";
        var password = $"Tc!{Guid.NewGuid():N}aA1";

        var builder = new ContainerBuilder(SqlImage)
            .WithName(containerName)
            .WithExposedPort(SqlPort)
            .WithEnvironment("ACCEPT_EULA", "Y")
            .WithEnvironment("MSSQL_SA_PASSWORD", password)
            .WithWaitStrategy(Wait.ForUnixContainer().UntilCommandIsCompleted(
                "/opt/mssql-tools18/bin/sqlcmd", "-C", "-S", "localhost", "-U", "sa", "-P", password, "-Q", "SELECT 1;"));

        if (teamCity is null)
        {
            builder = builder.WithPortBinding(SqlPort, true);
        }
        else
        {
            builder = builder.WithNetwork(teamCity.NetworkName);

        }

        _sqlServer = builder.Build();

        try
        {
            await _sqlServer.StartAsync(timeout.Token);
        }
        catch
        {
            await _sqlServer.DisposeAsync();
            _sqlServer = null;
            throw;
        }

        var dataSource = teamCity is null
            ? $"{_sqlServer.Hostname},{_sqlServer.GetMappedPublicPort(SqlPort)}"
            : $"{containerName},{SqlPort}";

        ConnectionString = new SqlConnectionStringBuilder
        {
            DataSource = dataSource,
            InitialCatalog = "master",
            UserID = "sa",
            Password = password,
            Encrypt = false,
            TrustServerCertificate = true
        }.ConnectionString;
    }

    public async ValueTask DisposeAsync()
    {
        if (_sqlServer is not null)
        {
            await _sqlServer.DisposeAsync();
        }
    }
}
