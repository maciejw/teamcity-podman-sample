[CmdletBinding()]
param(
    [string] $ServerUrl = "http://localhost:8111",
    [string] $Token
)

$ErrorActionPreference = "Stop"
$ServerUrl = $ServerUrl.TrimEnd("/")

if (-not $Token) {
    $tokenLine = podman logs teamcity-server 2>&1 |
        Select-String "Super user authentication token" |
        Select-Object -Last 1

    if (-not $tokenLine) {
        throw "No TeamCity super-user token was found. Pass an access token with -Token."
    }

    $Token = [regex]::Match($tokenLine.Line, "token: ([0-9]+)").Groups[1].Value
}

if (-not $Token) {
    throw "The TeamCity token is empty."
}

$basicToken = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(":" + $Token)
)
$authenticationHeaders = @{
    Authorization = "Basic $basicToken"
}
$csrfToken = (Invoke-WebRequest `
    -Headers $authenticationHeaders `
    -Uri "$ServerUrl/authenticationTest.html?csrf").Content
$writeHeaders = @{
    Authorization     = "Basic $basicToken"
    "X-TC-CSRF-Token" = $csrfToken
}

$projects = @(
    @{ Id = "Sample"; Path = "samples/testcontainers/.teamcity" },
    @{ Id = "SampleCompose"; Path = "samples/compose/.teamcity" }
)

foreach ($project in $projects) {
    $configUrl = "$ServerUrl/app/rest/projects/id:$($project.Id)/versionedSettings/config"
    $commonAttributes = @"
allowUIEditing="false" applyChangesInDependenciesAndVcsSettings="true" buildSettingsMode="useFromVCS" format="kotlin" settingsPath="$($project.Path)" showSettingsChanges="false" vcsRootId="CurrentRepository"
"@.Trim()
    $disabledConfig = "<versionedSettingsConfig $commonAttributes synchronizationMode=`"disabled`"/>"

    Invoke-WebRequest `
        -Method Put `
        -Headers $writeHeaders `
        -ContentType "application/xml" `
        -Body $disabledConfig `
        -Uri $configUrl | Out-Null

    $deadline = (Get-Date).AddSeconds(30)
    do {
        $currentConfig = Invoke-RestMethod `
            -Headers ($authenticationHeaders + @{ Accept = "application/json" }) `
            -Uri $configUrl
        if ($currentConfig.synchronizationMode -eq "disabled") {
            break
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    if ($currentConfig.synchronizationMode -ne "disabled") {
        throw "Timed out while disabling versioned settings for $($project.Id)."
    }

    $importConfig = "<versionedSettingsConfig $commonAttributes importDecision=`"importFromVCS`" synchronizationMode=`"enabled`"/>"
    Invoke-WebRequest `
        -Method Put `
        -Headers $writeHeaders `
        -ContentType "application/xml" `
        -Body $importConfig `
        -Uri $configUrl | Out-Null

    Write-Host "Imported $($project.Id) settings from $($project.Path)."
}
