[CmdletBinding()]
param(
    [string] $ServerUrl = "http://localhost:8111",
    [Alias("Token")] [string] $AccessToken,
    [ValidateRange(1, 100)] [int] $AgentCount = 1
)

$ErrorActionPreference = "Stop"

$agentRoot = $env:TEAMCITY_AGENT_ROOT
if ([string]::IsNullOrWhiteSpace($agentRoot)) {
    $envFile = Join-Path $PSScriptRoot ".env"
    $agentRootSetting = Get-Content $envFile | Where-Object { $_ -match '^TEAMCITY_AGENT_ROOT=' } | Select-Object -Last 1
    if ($agentRootSetting) {
        $agentRoot = $agentRootSetting.Substring($agentRootSetting.IndexOf('=') + 1).Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($agentRoot)) {
    $agentRoot = "/opt/teamcity-agents"
}
if ($agentRoot -notmatch '^/[A-Za-z0-9._/-]+$' -or $agentRoot -match '(^|/)\.\.(/|$)') {
    throw "TEAMCITY_AGENT_ROOT must be a safe absolute Linux path."
}

Write-Host "Provisioning TeamCity agent directories..."
& podman machine ssh -- "sudo mkdir -p $agentRoot && sudo chown -R 1000:1000 $agentRoot"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to provision the TeamCity agent directories (exit code $LASTEXITCODE)."
}

Write-Host "Starting the TeamCity Compose stack..."
$composeFile = Join-Path $PSScriptRoot "compose.yaml"
& podman compose -f $composeFile up -d --remove-orphans --scale "agent=$AgentCount"
if ($LASTEXITCODE -ne 0) {
    throw "Podman Compose failed to start the TeamCity stack (exit code $LASTEXITCODE)."
}

Import-Module (Join-Path $PSScriptRoot "TeamCityBootstrap.psm1") -Scope Local -Force
Write-Host "Waiting for TeamCity to become reachable..."
Wait-TeamCityReady -ServerUrl $ServerUrl

$projects = [ordered]@{
    "Sample Testcontainers" = @{
        settingsPath = "samples/testcontainers/.teamcity"
        vcs = @{ url = "file:///repo/.git" }
    }
    "Sample Compose" = @{
        settingsPath = "samples/compose/.teamcity"
        vcs = @{ url = "file:///repo/.git" }
    }
}

$session = New-TeamCitySession $ServerUrl $AccessToken
if ($session.SuperUserToken) {
    Write-Host "TeamCity system administrator token: $($session.SuperUserToken)"
}

1..$AgentCount | ForEach-Object {
    Set-TeamCityAgentAuthorized -Session $session -AgentName "teamcity-agent-$_"
}
$projects.GetEnumerator() | Register-Project -Session $session
