using Microsoft.Data.SqlClient;

namespace Sample.Data.IntegrationTests;

internal static class ComposeEndpoints
{
    private const string Password = "Compose_Test!2026";
    private static bool IsTeamCity =>
        !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("TEAMCITY_VERSION"));

    public static string SqlServerConnectionString => new SqlConnectionStringBuilder
    {
        DataSource = IsTeamCity ? "mssql,1433" : "tcp:127.0.0.1,1433",
        InitialCatalog = "master",
        UserID = "sa",
        Password = Password,
        Encrypt = false,
        TrustServerCertificate = true
    }.ConnectionString;

    public static string KafkaBootstrapServers => IsTeamCity ? "kafka:9092" : "127.0.0.1:9092";
}
