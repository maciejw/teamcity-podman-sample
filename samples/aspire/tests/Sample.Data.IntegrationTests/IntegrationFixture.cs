using Aspire.Hosting;
using Aspire.Hosting.Testing;
using Aspire.Hosting.ApplicationModel;
using Xunit;

namespace Sample.Data.IntegrationTests;

public sealed class IntegrationFixture : IAsyncLifetime
{
    private static readonly TimeSpan StartupTimeout = TimeSpan.FromMinutes(5);
    private DistributedApplication? _app;

    public string SqlConnectionString { get; private set; } = string.Empty;
    public string KafkaBootstrapServers { get; private set; } = string.Empty;

    public async ValueTask InitializeAsync()
    {
        Console.WriteLine("[Aspire] Creating and starting AppHost/DCP.");
        using var timeout = new CancellationTokenSource(StartupTimeout);
        var builder = await DistributedApplicationTestingBuilder.CreateAsync<Projects.Sample_AppHost>(cancellationToken: timeout.Token);
        var sqlResource = builder.Resources.Single(resource => resource.Name == "sql") as IResourceWithConnectionString
            ?? throw new InvalidOperationException("Aspire SQL resource was not found.");
        var kafkaResource = builder.Resources.Single(resource => resource.Name == "kafka") as IResourceWithEndpoints
            ?? throw new InvalidOperationException("Aspire Kafka resource was not found.");
        _app = await builder.BuildAsync(timeout.Token);
        await _app.StartAsync(timeout.Token);

        Console.WriteLine("[Aspire] Waiting for SQL Server and Kafka readiness.");
        await _app.ResourceNotifications.WaitForResourceHealthyAsync("sql", timeout.Token);
        await _app.ResourceNotifications.WaitForResourceHealthyAsync("kafka", timeout.Token);

        SqlConnectionString = RewriteContainerHost(await sqlResource.GetConnectionStringAsync(timeout.Token)
            ?? throw new InvalidOperationException("Aspire did not publish a SQL connection string."));
        KafkaBootstrapServers = RewriteContainerHost(await kafkaResource.GetEndpoint("kafka").GetValueAsync(timeout.Token)
            ?? throw new InvalidOperationException("Aspire did not publish a Kafka endpoint."));
        Console.WriteLine($"[Aspire] Resources ready. Kafka endpoint: {KafkaBootstrapServers}");
    }

    public async ValueTask DisposeAsync()
    {
        if (_app is not null)
        {
            Console.WriteLine("[Aspire] Disposing AppHost/DCP and managed resources.");
            await _app.DisposeAsync();
        }
    }

    private static string RewriteContainerHost(string value)
    {
        var host = Environment.GetEnvironmentVariable("ASPIRE_TEST_HOST")?.Trim();
        if (string.IsNullOrEmpty(host) && !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("TEAMCITY_VERSION")))
        {
            host = "host.containers.internal";
        }

        if (string.IsNullOrEmpty(host))
        {
            return value;
        }

        return value.Replace("localhost", host, StringComparison.OrdinalIgnoreCase)
            .Replace("127.0.0.1", host, StringComparison.OrdinalIgnoreCase);
    }
}

[CollectionDefinition(Name)]
public sealed class IntegrationCollection : ICollectionFixture<IntegrationFixture>
{
    public const string Name = "Aspire SQL Server and Kafka";
}
