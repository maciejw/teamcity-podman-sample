using Confluent.Kafka;

namespace Sample.Data.IntegrationTests;

internal static class KafkaTestClient
{
    private static readonly TimeSpan OperationTimeout = TimeSpan.FromSeconds(30);

    public static string UniqueName(string prefix) => $"{prefix}-{Guid.NewGuid():N}";

    public static async Task ProduceAsync(string bootstrapServers, string topic, string value, CancellationToken cancellationToken)
    {
        var config = new ProducerConfig
        {
            BootstrapServers = bootstrapServers,
            Acks = Acks.All,
            MessageTimeoutMs = (int)OperationTimeout.TotalMilliseconds,
            SocketTimeoutMs = (int)OperationTimeout.TotalMilliseconds
        };

        using var producer = new ProducerBuilder<Null, string>(config).Build();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(OperationTimeout);

        try
        {
            await producer.ProduceAsync(topic, new Message<Null, string> { Value = value }, timeout.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException($"Kafka did not acknowledge a message for topic '{topic}' within {OperationTimeout}.");
        }
    }

    public static string Consume(string bootstrapServers, string topic, string group, CancellationToken cancellationToken)
    {
        var config = new ConsumerConfig
        {
            BootstrapServers = bootstrapServers,
            GroupId = group,
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = false,
            SocketTimeoutMs = (int)OperationTimeout.TotalMilliseconds
        };

        using var consumer = new ConsumerBuilder<Ignore, string>(config).Build();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(OperationTimeout);
        consumer.Subscribe(topic);

        try
        {
            return consumer.Consume(timeout.Token).Message.Value;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException($"Kafka did not provide a message from topic '{topic}' within {OperationTimeout}.");
        }
        finally
        {
            consumer.Close();
        }
    }
}
