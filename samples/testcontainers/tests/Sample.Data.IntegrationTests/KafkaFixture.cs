using Testcontainers.Kafka;
using Xunit;

namespace Sample.Data.IntegrationTests;

public sealed class KafkaFixture : IAsyncLifetime
{
    private const string KafkaImage = "docker.io/apache/kafka:4.1.1";
    private const int InternalKafkaPort = 19092;
    private static readonly TimeSpan StartupTimeout = TimeSpan.FromMinutes(5);

    private KafkaContainer? _kafka;

    public string BootstrapServers { get; private set; } = string.Empty;

    public async ValueTask InitializeAsync()
    {
        using var timeout = new CancellationTokenSource(StartupTimeout);
        var teamCity = TeamCityContextDiscovery.Discover();
        var containerName = $"kafka-{Guid.NewGuid():N}";

        var builder = new KafkaBuilder(KafkaImage)
            .WithKRaft()
            .WithName(containerName);

        if (teamCity is not null)
        {
            builder = builder
                .WithNetwork(teamCity.NetworkName)
                .WithListener($"{containerName}:{InternalKafkaPort}");

        }

        _kafka = builder.Build();

        try
        {
            await _kafka.StartAsync(timeout.Token);
        }
        catch (OperationCanceledException exception) when (timeout.IsCancellationRequested)
        {
            await _kafka.DisposeAsync();
            _kafka = null;
            throw new TimeoutException($"Kafka did not start within {StartupTimeout}.", exception);
        }
        catch
        {
            await _kafka.DisposeAsync();
            _kafka = null;
            throw;
        }

        BootstrapServers = teamCity is null
            ? _kafka.GetBootstrapAddress()
            : $"{containerName}:{InternalKafkaPort}";
    }

    public async ValueTask DisposeAsync()
    {
        if (_kafka is not null)
        {
            await _kafka.DisposeAsync();
        }
    }
}
