using Sample.Data;
using Xunit;

namespace Sample.Data.IntegrationTests;

[Collection(IntegrationCollection.Name)]
public sealed class WidgetRepositoryTests(IntegrationFixture fixture)
{
    [Fact]
    public async Task Inserted_widget_can_be_loaded_from_mssql()
    {
        var repository = new WidgetRepository(fixture.SqlConnectionString);
        await repository.InitializeAsync(TestContext.Current.CancellationToken);
        var id = await repository.AddAsync("Aspire sample", TestContext.Current.CancellationToken);
        var widget = await repository.FindAsync(id, TestContext.Current.CancellationToken);
        Assert.NotNull(widget);
        Assert.Equal("Aspire sample", widget.Name);
    }
}
