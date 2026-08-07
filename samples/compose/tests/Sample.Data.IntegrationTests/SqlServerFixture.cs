using Xunit;

namespace Sample.Data.IntegrationTests;

public sealed class SqlServerFixture : IAsyncLifetime
{
    public string ConnectionString { get; } = ComposeEndpoints.SqlServerConnectionString;

    public ValueTask InitializeAsync() => ValueTask.CompletedTask;

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;
}
