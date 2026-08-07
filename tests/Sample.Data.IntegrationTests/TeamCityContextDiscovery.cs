namespace Sample.Data.IntegrationTests;

internal static class TeamCityContextDiscovery
{
    private const string TeamCityVersionVariable = "TEAMCITY_VERSION";
    private const string NetworkVariable = "SAMPLE_TEAMCITY_NETWORK";
    private const string OwnerVariable = "SAMPLE_TEAMCITY_OWNER";
    private const string AgentNameVariable = "SAMPLE_TEAMCITY_AGENT_NAME";
    private const string BuildIdVariable = "SAMPLE_TEAMCITY_BUILD_ID";
    private const string OwnerLabel = "tc.owner";
    private const string AgentNameLabel = "tc.agent.name";
    private const string BuildIdLabel = "tc.build.id";

    public static TeamCityContext? Discover()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(TeamCityVersionVariable)))
        {
            return null;
        }

        var networkName = GetRequiredVariable(NetworkVariable);
        var labels = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [OwnerLabel] = GetRequiredVariable(OwnerVariable),
            [AgentNameLabel] = GetRequiredVariable(AgentNameVariable),
            [BuildIdLabel] = GetRequiredVariable(BuildIdVariable)
        };

        return new TeamCityContext(networkName, labels);
    }

    private static string GetRequiredVariable(string variableName)
    {
        var value = Environment.GetEnvironmentVariable(variableName)?.Trim();

        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException(
                $"{TeamCityVersionVariable} is set, but required variable {variableName} is absent or blank.");
        }

        return value;
    }
}

internal sealed record TeamCityContext(string NetworkName, IReadOnlyDictionary<string, string> Labels);
