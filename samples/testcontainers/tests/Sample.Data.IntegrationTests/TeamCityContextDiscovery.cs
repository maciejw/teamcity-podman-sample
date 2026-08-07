namespace Sample.Data.IntegrationTests;

internal static class TeamCityContextDiscovery
{
    private const string TeamCityVersionVariable = "TEAMCITY_VERSION";
    private const string NetworkVariable = "TEAMCITY_DOCKER_NETWORK";

    public static TeamCityContext? Discover()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(TeamCityVersionVariable)))
        {
            return null;
        }

        return new TeamCityContext(GetRequiredVariable(NetworkVariable));
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

internal sealed record TeamCityContext(string NetworkName);
