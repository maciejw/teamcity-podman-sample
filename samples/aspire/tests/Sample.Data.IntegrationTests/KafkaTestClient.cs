using Confluent.Kafka;

namespace Sample.Data.IntegrationTests;

internal static class KafkaTestClient
{
    private static readonly TimeSpan OperationTimeout = TimeSpan.FromSeconds(30);
    public static string UniqueName(string prefix) => $"{prefix}-{Guid.NewGuid():N}";

    public static async Task ProduceAsync(string bootstrapServers, string topic, string value, CancellationToken cancellationToken)
    {
        var config = new ProducerConfig { BootstrapServers = bootstrapServers, Acks = Acks.All, MessageTimeoutMs = 30000, SocketTimeoutMs = 30000 };
        using var producer = new ProducerBuilder<Null, string>(config).Build();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(OperationTimeout);
        await producer.ProduceAsync(topic, new Message<Null, string> { Value = value }, timeout.Token);
    }

    public static string Consume(string bootstrapServers, string topic, string group, CancellationToken cancellationToken)
    {
        var config = new ConsumerConfig { BootstrapServers = bootstrapServers, GroupId = group, AutoOffsetReset = AutoOffsetReset.Earliest, EnableAutoCommit = false, SocketTimeoutMs = 30000 };
        using var consumer = new ConsumerBuilder<Ignore, string>(config).Build();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(OperationTimeout);
        consumer.Subscribe(topic);
        try { return consumer.Consume(timeout.Token).Message.Value; }
        finally { consumer.Close(); }
    }
}
