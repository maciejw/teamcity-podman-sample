using System.Text.Json;
using Sample.Data;
using Xunit;

namespace Sample.Data.IntegrationTests;

[Collection(IntegrationCollection.Name)]
public sealed class WidgetEventTests(IntegrationFixture fixture)
{
    [Fact]
    public async Task Stored_widget_can_be_published_and_consumed_as_an_event()
    {
        var repository = new WidgetRepository(fixture.SqlConnectionString);
        await repository.InitializeAsync(TestContext.Current.CancellationToken);
        var id = await repository.AddAsync($"Kafka Widget {Guid.NewGuid():N}", TestContext.Current.CancellationToken);
        var widget = await repository.FindAsync(id, TestContext.Current.CancellationToken);
        Assert.NotNull(widget);
        var expected = new WidgetEvent(widget.Id, widget.Name);
        var topic = KafkaTestClient.UniqueName("widget-events");
        await KafkaTestClient.ProduceAsync(fixture.KafkaBootstrapServers, topic, JsonSerializer.Serialize(expected), TestContext.Current.CancellationToken);
        var actual = JsonSerializer.Deserialize<WidgetEvent>(KafkaTestClient.Consume(fixture.KafkaBootstrapServers, topic, KafkaTestClient.UniqueName("group"), TestContext.Current.CancellationToken));
        Assert.Equal(expected, actual);
    }

    private sealed record WidgetEvent(int Id, string Name);
}
