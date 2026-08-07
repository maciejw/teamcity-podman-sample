using Xunit;

namespace Sample.Data.IntegrationTests;

public sealed class KafkaFixture : IAsyncLifetime
{
    public string BootstrapServers { get; } = ComposeEndpoints.KafkaBootstrapServers;

    public ValueTask InitializeAsync() => ValueTask.CompletedTask;

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
