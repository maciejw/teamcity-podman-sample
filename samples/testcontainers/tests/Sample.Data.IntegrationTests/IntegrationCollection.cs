using Xunit;

namespace Sample.Data.IntegrationTests;

[CollectionDefinition(Name)]
public sealed class IntegrationCollection :
    ICollectionFixture<SqlServerFixture>,
    ICollectionFixture<KafkaFixture>
{
    public const string Name = "SQL Server and Kafka";
}
