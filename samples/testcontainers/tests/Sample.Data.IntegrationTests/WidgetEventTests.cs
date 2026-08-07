using System.Text.Json;
using Sample.Data;
using Xunit;

namespace Sample.Data.IntegrationTests;

[Collection(IntegrationCollection.Name)]
public sealed class WidgetEventTests(SqlServerFixture sqlServer, KafkaFixture kafka)
{
    [Fact]
    public async Task Stored_widget_can_be_published_and_consumed_as_an_event()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var repository = new WidgetRepository(sqlServer.ConnectionString);
        await repository.InitializeAsync(cancellationToken);
        var id = await repository.AddAsync($"Kafka Widget {Guid.NewGuid():N}", cancellationToken);
        var storedWidget = await repository.FindAsync(id, cancellationToken);
        Assert.NotNull(storedWidget);

        var topic = KafkaTestClient.UniqueName("widget-events");
        var group = KafkaTestClient.UniqueName("widget-events-group");
        var expectedEvent = new WidgetEvent(storedWidget.Id, storedWidget.Name);
        var payload = JsonSerializer.Serialize(expectedEvent);

        await KafkaTestClient.ProduceAsync(kafka.BootstrapServers, topic, payload, cancellationToken);
        var consumedPayload = KafkaTestClient.Consume(
            kafka.BootstrapServers,
            topic,
            group,
            cancellationToken);
        var actualEvent = JsonSerializer.Deserialize<WidgetEvent>(consumedPayload);

        Assert.Equal(expectedEvent, actualEvent);
    }

    private sealed record WidgetEvent(int Id, string Name);
}
