using Xunit;

namespace Sample.Data.IntegrationTests;

[Collection(IntegrationCollection.Name)]
public sealed class KafkaTests(IntegrationFixture fixture)
{
    [Fact]
    public async Task Produced_message_can_be_consumed_from_kafka()
    {
        var topic = KafkaTestClient.UniqueName("round-trip");
        var expected = $"message-{Guid.NewGuid():N}";
        await KafkaTestClient.ProduceAsync(fixture.KafkaBootstrapServers, topic, expected, TestContext.Current.CancellationToken);
        Assert.Equal(expected, KafkaTestClient.Consume(fixture.KafkaBootstrapServers, topic, KafkaTestClient.UniqueName("group"), TestContext.Current.CancellationToken));
    }
}
