Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectTemplate = [ordered]@{
    parentProject             = @{ locator = "id:_Root" }
    copyAllAssociatedSettings = $false
}

$vcsRootTemplate = [ordered]@{
    vcsName = "jetbrains.git"
}

function New-TeamCitySession {
    param(
        [Parameter(Mandatory)] [string] $ServerUrl,
        [string] $AccessToken
    )

    $superUserToken = $null
    if ($AccessToken) {
        $authenticationHeaders = @{ Authorization = "Bearer $AccessToken" }
    }
    else {
        $tokenLine = podman logs teamcity-server 2>&1 |
            Select-String "Super user authentication token" |
            Select-Object -Last 1

        if (-not $tokenLine) {
            $tokenLine = podman exec teamcity-server grep "Super user authentication token" /opt/teamcity/logs/teamcity-server.log 2>&1 |
                Select-String "Super user authentication token" |
                Select-Object -Last 1
        }

        if (-not $tokenLine) {
            throw "No TeamCity super-user token was found. Pass a permanent access token with -AccessToken."
        }

        $superUserToken = [regex]::Match($tokenLine.Line, "token: ([0-9]+)").Groups[1].Value
        if (-not $superUserToken) {
            throw "The TeamCity super-user token could not be parsed."
        }

        $basicToken = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":" + $superUserToken))
        $authenticationHeaders = @{ Authorization = "Basic $basicToken" }
    }

    $normalizedServerUrl = $ServerUrl.TrimEnd("/")
    $csrfToken = Invoke-RestMethod -Headers $authenticationHeaders -Uri "$normalizedServerUrl/authenticationTest.html?csrf"

    [pscustomobject]@{
        ServerUrl       = $normalizedServerUrl
        SuperUserToken  = $superUserToken
        WriteHeaders    = $authenticationHeaders + @{
            "X-TC-CSRF-Token" = $csrfToken
            Accept            = "application/json"
        }
    }
}

function Wait-TeamCityReady {
    param(
        [Parameter(Mandatory)] [string] $ServerUrl,
        [int] $PollIntervalSeconds = 3
    )

    $healthCheckUri = "$($ServerUrl.TrimEnd('/'))/healthCheck/ready"
    do {
        try {
            $healthStatusCode = 0
            Invoke-RestMethod -Uri $healthCheckUri -SkipHttpErrorCheck -StatusCodeVariable healthStatusCode | Out-Null
            if ($healthStatusCode -eq 200) {
                return
            }

            Write-Warning "TeamCity health check returned HTTP $healthStatusCode. Retrying in $PollIntervalSeconds seconds."
        }
        catch {
            Write-Warning "TeamCity health check is not reachable yet: $($_.Exception.Message) Retrying in $PollIntervalSeconds seconds."
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)
}

function Set-TeamCityAgentAuthorized {
    param(
        [Parameter(Mandatory)] $Session,
        [string] $AgentName = "teamcity-agent",
        [int] $PollIntervalSeconds = 3
    )

    $locator = [Uri]::EscapeDataString("authorized:any,name:$AgentName")
    do {
        $statusCode = 0
        $agents = Invoke-RestMethod -Headers $Session.WriteHeaders -Uri "$($Session.ServerUrl)/app/rest/agents?locator=$locator" -SkipHttpErrorCheck -StatusCodeVariable statusCode
        $agent = @($agents.agent) | Where-Object name -eq $AgentName | Select-Object -First 1
        if ($statusCode -eq 200 -and $null -ne $agent) {
            break
        }

        Write-Warning "TeamCity agent '$AgentName' is not available yet. Retrying in $PollIntervalSeconds seconds."
        Start-Sleep -Seconds $PollIntervalSeconds
    } while ($true)

    $authorizedStatusCode = 0
    $authorized = Invoke-RestMethod -Headers $Session.WriteHeaders -Uri "$($Session.ServerUrl)$($agent.href)/authorized" -SkipHttpErrorCheck -StatusCodeVariable authorizedStatusCode
    if ($authorizedStatusCode -eq 200 -and $authorized.ToString().Trim() -eq "true") {
        Write-Host "TeamCity agent '$AgentName' is already authorized."
        return
    }

    $authorizationStatusCode = 0
    $authorizationHeaders = @{}
    foreach ($header in $Session.WriteHeaders.GetEnumerator()) {
        $authorizationHeaders[$header.Key] = $header.Value
    }
    $authorizationHeaders.Accept = "text/plain"
    Invoke-RestMethod -Method Put -Headers $authorizationHeaders -ContentType "text/plain" -Body "true" -Uri "$($Session.ServerUrl)$($agent.href)/authorized" -SkipHttpErrorCheck -StatusCodeVariable authorizationStatusCode | Out-Null
    if ($authorizationStatusCode -lt 200 -or $authorizationStatusCode -ge 300) {
        throw "TeamCity could not authorize agent '$AgentName' (HTTP $authorizationStatusCode)."
    }

    Write-Host "Authorized TeamCity agent '$AgentName'."
}

function Invoke-TeamCityWrite {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory)] [ValidateSet("Post", "Put")] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Payload
    )

    $body = $Payload | ConvertTo-Json -Depth 10
    $statusCode = 0
    $response = Invoke-RestMethod -Method $Method -Headers $Session.WriteHeaders -ContentType "application/json" -Body $body -Uri "$($Session.ServerUrl)$Path" -SkipHttpErrorCheck -StatusCodeVariable statusCode
    if ($statusCode -ge 400) {
        $message = @($response.errors | ForEach-Object message) -join "; "
        if (-not $message) {
            $message = "The server returned an HTTP error."
        }
        Write-Warning "TeamCity $Method $Path returned HTTP $statusCode`: $message"
        return $false
    }

    return $true
}

function ConvertTo-TeamCityProjectId {
    param([Parameter(Mandatory)] [string] $ProjectName)

    $id = $ProjectName -replace "[^a-zA-Z0-9]", ""
    if (-not $id) {
        throw "Project name '$ProjectName' does not produce a valid TeamCity project ID."
    }

    $id
}

function New-TeamCityProjectPayload {
    param([Parameter(Mandatory)] $Definition)

    [ordered]@{
        id                        = $Definition.id
        name                      = $Definition.name
        parentProject             = $projectTemplate.parentProject
        copyAllAssociatedSettings = $projectTemplate.copyAllAssociatedSettings
    }
}

function New-TeamCityVcsRootPayload {
    param([Parameter(Mandatory)] $Definition)

    $properties = @(
        @{ name = "authMethod"; value = "ANONYMOUS" }
        @{ name = "branch"; value = "refs/heads/main" }
        @{ name = "url"; value = $Definition.vcs.url }
    )

    [ordered]@{
        id         = "$($Definition.id)_Repository"
        name       = "$($Definition.name) repository"
        vcsName    = $vcsRootTemplate.vcsName
        project    = @{ id = $Definition.id }
        properties = @{ property = $properties }
    }
}

function New-TeamCityVersionedSettingsPayload {
    param([Parameter(Mandatory)] $Definition)

    [ordered]@{
        settingsPath       = $Definition.settingsPath
        vcsRootId          = "$($Definition.id)_Repository"
        format             = "kotlin"
        synchronizationMode = "enabled"
        importDecision     = "importFromVCS"
    }
}

function Register-Project {
    param(
        [Parameter(Mandatory)] $Session,
        [Parameter(Mandatory, ValueFromPipeline)] [System.Collections.DictionaryEntry] $Project
    )

    process {
        $definition = $Project.Value
        $definition.id = ConvertTo-TeamCityProjectId $Project.Key
        $definition.name = $Project.Key

        Write-Host "Registering project '$($definition.name)' ($($definition.id))..."

        if (Invoke-TeamCityWrite $Session Post "/app/rest/projects" (New-TeamCityProjectPayload $definition)) {
            Write-Host "Created project '$($definition.id)'."
        }

        if (Invoke-TeamCityWrite $Session Post "/app/rest/vcs-roots" (New-TeamCityVcsRootPayload $definition)) {
            Write-Host "Created VCS root '$($definition.id)_Repository'."
        }

        if (Invoke-TeamCityWrite $Session Put "/app/rest/projects/id:$($definition.id)/versionedSettings/config" (New-TeamCityVersionedSettingsPayload $definition)) {
            Write-Host "Configured versioned settings for '$($definition.id)'."
        }
    }
}

Export-ModuleMember -Function New-TeamCitySession, Wait-TeamCityReady, Set-TeamCityAgentAuthorized, Register-Project
