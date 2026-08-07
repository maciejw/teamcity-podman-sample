using Sample.Data;
using Xunit;

namespace Sample.Data.IntegrationTests;

[Collection(IntegrationCollection.Name)]
public sealed class WidgetRepositoryTests(SqlServerFixture sqlServer)
{
    [Fact]
    public async Task Inserted_widget_can_be_loaded_from_mssql()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var repository = new WidgetRepository(sqlServer.ConnectionString);
        await repository.InitializeAsync(cancellationToken);
        var id = await repository.AddAsync("Testcontainers sample", cancellationToken);

        var widget = await repository.FindAsync(id, cancellationToken);

        Assert.NotNull(widget);
        Assert.Equal("Testcontainers sample", widget.Name);
    }
}
