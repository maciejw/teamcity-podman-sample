using Xunit;

namespace Sample.Data.IntegrationTests;

[Collection(IntegrationCollection.Name)]
public sealed class KafkaTests(KafkaFixture kafka)
{
    [Fact]
    public async Task Produced_message_can_be_consumed_from_kafka()
    {
        var cancellationToken = TestContext.Current.CancellationToken;
        var topic = KafkaTestClient.UniqueName("round-trip");
        var group = KafkaTestClient.UniqueName("round-trip-group");
        var expected = $"message-{Guid.NewGuid():N}";

        await KafkaTestClient.ProduceAsync(kafka.BootstrapServers, topic, expected, cancellationToken);
        var actual = KafkaTestClient.Consume(kafka.BootstrapServers, topic, group, cancellationToken);

        Assert.Equal(expected, actual);
    }
}
