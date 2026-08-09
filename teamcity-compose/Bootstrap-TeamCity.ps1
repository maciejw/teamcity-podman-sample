[CmdletBinding()]
param(
    [string] $ServerUrl = "http://localhost:8111",
    [Alias("Token")] [string] $AccessToken
)

$ErrorActionPreference = "Stop"

Write-Host "Provisioning TeamCity agent directories..."
& podman machine ssh -- @"
    sudo mkdir -p /opt/teamcity-agent && \
    sudo chown -R 1000:1000 /opt/teamcity-agent && \
    podman unshare chown -R 1000:1000 /opt/teamcity-agent
"@
if ($LASTEXITCODE -ne 0) {
    throw "Failed to provision the TeamCity agent directories (exit code $LASTEXITCODE)."
}

Write-Host "Starting the TeamCity Compose stack..."
$composeFile = Join-Path $PSScriptRoot "compose.yaml"
& podman compose -f $composeFile up -d --remove-orphans
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
    "Sample Aspire" = @{
        settingsPath = "samples/aspire/.teamcity"
        vcs = @{ url = "file:///repo/.git" }
    }
}

$session = New-TeamCitySession $ServerUrl $AccessToken
if ($session.SuperUserToken) {
    Write-Host "TeamCity system administrator token: $($session.SuperUserToken)"
}

Set-TeamCityAgentAuthorized -Session $session
$projects.GetEnumerator() | Register-Project -Session $session
