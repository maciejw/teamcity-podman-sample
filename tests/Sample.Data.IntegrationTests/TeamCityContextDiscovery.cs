using Docker.DotNet;
using Docker.DotNet.Models;
using DotNet.Testcontainers.Configurations;

namespace Sample.Data.IntegrationTests;

internal static class TeamCityContextDiscovery
{
    private const string HostnameVariable = "HOSTNAME";
    private const string TeamCityVersionVariable = "TEAMCITY_VERSION";
    private const string OwnerLabel = "tc.owner";
    private const string AgentNameLabel = "tc.agent.name";
    private const string BuildIdLabel = "tc.build.id";

    private static readonly string[] RequiredLabels = [OwnerLabel, AgentNameLabel, BuildIdLabel];

    public static async Task<TeamCityContext?> DiscoverAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(TeamCityVersionVariable)))
        {
            return null;
        }

        var runnerId = Environment.GetEnvironmentVariable(HostnameVariable)?.Trim();

        if (string.IsNullOrWhiteSpace(runnerId))
        {
            throw new InvalidOperationException(
                $"{TeamCityVersionVariable} is set, but {HostnameVariable} is absent or blank; the TeamCity runner container cannot be identified.");
        }

        using var dockerClient = TestcontainersSettings.OS.DockerEndpointAuthConfig
            .GetDockerClientBuilder(Guid.NewGuid())
            .Build();

        ContainerInspectResponse runner;

        try
        {
            runner = await dockerClient.Containers.InspectContainerAsync(runnerId, cancellationToken);
        }
        catch (Exception exception)
        {
            throw new InvalidOperationException(
                $"{TeamCityVersionVariable} is set, but runner container '{runnerId}' could not be inspected.", exception);
        }

        var labels = DiscoverRequiredLabels(runner.Config?.Labels ?? new Dictionary<string, string>(), runnerId);
        var networkName = await DiscoverNetworkAsync(
            dockerClient,
            runner.NetworkSettings?.Networks?.Keys ?? [],
            runnerId,
            labels,
            cancellationToken);

        return new TeamCityContext(networkName, labels);
    }

    private static Dictionary<string, string> DiscoverRequiredLabels(
        IDictionary<string, string> runnerLabels,
        string runnerId)
    {
        var labels = new Dictionary<string, string>(StringComparer.Ordinal);

        foreach (var labelName in RequiredLabels)
        {
            if (!runnerLabels.TryGetValue(labelName, out var value) || string.IsNullOrWhiteSpace(value))
            {
                throw new InvalidOperationException(
                    $"TeamCity runner container '{runnerId}' is missing required label '{labelName}'.");
            }

            labels.Add(labelName, value);
        }

        return labels;
    }

    private static async Task<string> DiscoverNetworkAsync(
        IDockerClient dockerClient,
        IEnumerable<string> attachedNetworks,
        string runnerId,
        IReadOnlyDictionary<string, string> labels,
        CancellationToken cancellationToken)
    {
        var matchingNetworks = new List<string>();

        foreach (var networkName in attachedNetworks)
        {
            var network = await dockerClient.Networks.InspectNetworkAsync(networkName, cancellationToken);
            var networkLabels = network.Labels ?? new Dictionary<string, string>();

            if (networkLabels.TryGetValue(OwnerLabel, out var owner) && owner == labels[OwnerLabel] &&
                networkLabels.TryGetValue(AgentNameLabel, out var agentName) && agentName == labels[AgentNameLabel])
            {
                matchingNetworks.Add(networkName);
            }
        }

        if (matchingNetworks.Count != 1)
        {
            throw new InvalidOperationException(
                $"TeamCity runner container '{runnerId}' must have exactly one network matching its tc.owner and tc.agent.name labels; found {matchingNetworks.Count}.");
        }

        return matchingNetworks[0];
    }
}

internal sealed record TeamCityContext(string NetworkName, IReadOnlyDictionary<string, string> Labels);
