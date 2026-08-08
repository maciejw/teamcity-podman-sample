[CmdletBinding()]
param(
    [string] $ServerUrl = "http://localhost:8111",
    [string] $ManifestPath = (Join-Path $PSScriptRoot "teamcity-state.json"),
    [Alias("Token")] [string] $AccessToken
)

$ErrorActionPreference = "Stop"
$ServerUrl = $ServerUrl.TrimEnd("/")

function Invoke-TeamCityRead {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $AllowNotFound,
        [string] $Accept = "application/json"
    )

    try {
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Headers ($script:AuthenticationHeaders + @{ Accept = $Accept }) `
            -Uri "$ServerUrl$Path"
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int] $_.Exception.Response.StatusCode
        }
        if ($AllowNotFound -and $statusCode -eq 404) {
            return $null
        }
        throw
    }

    if ($Accept -eq "application/json") {
        return $response.Content | ConvertFrom-Json
    }
    return $response.Content
}

function Invoke-TeamCityWrite {
    param(
        [Parameter(Mandatory)] [ValidateSet("Post", "Put")] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ContentType,
        [string] $Body = ""
    )

    $headers = @{}
    foreach ($header in $script:WriteHeaders.GetEnumerator()) {
        $headers[$header.Key] = $header.Value
    }
    $headers.Accept = if ($ContentType -eq "text/plain") { "text/plain" } else { "application/json" }

    Invoke-WebRequest `
        -UseBasicParsing `
        -Method $Method `
        -Headers $headers `
        -ContentType $ContentType `
        -Body $Body `
        -Uri "$ServerUrl$Path" | Out-Null
}

function Load-TeamCitySettings {
    param([Parameter(Mandatory)] [string] $ProjectId)

    $statusPath = "/app/rest/projects/id:$ProjectId/versionedSettings/status"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $previousStatus = Invoke-TeamCityRead $statusPath
        Invoke-TeamCityWrite Post "/app/rest/projects/id:$ProjectId/versionedSettings/loadSettings" "application/json"
        Write-Host "Loading '$ProjectId' settings from VCS (attempt $attempt)..."

        $retryRequested = $false
        $deadline = (Get-Date).AddSeconds(120)
        do {
            $status = Invoke-TeamCityRead $statusPath
            $isFresh = $status.timestamp -ne $previousStatus.timestamp -or $status.message -ne $previousStatus.message
            if ($isFresh -and $status.type -eq "info" -and $status.message -like "Changes from VCS are applied*") {
                Write-Host "Loaded '$ProjectId' settings from VCS."
                return
            }
            if ($isFresh -and $status.type -in @("error", "warn")) {
                if ($status.message -like "*Load project settings from VCS*" -and $attempt -lt 3) {
                    $retryRequested = $true
                    break
                }
                throw "TeamCity could not load '$ProjectId' settings from VCS: $($status.message)"
            }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)

        if (-not $retryRequested) {
            throw "Timed out while loading '$ProjectId' settings from VCS."
        }
        Start-Sleep -Seconds 2
    }
}

function ConvertTo-PropertyMap {
    param($Properties)

    $result = @{}
    if ($null -ne $Properties -and $null -ne $Properties.property) {
        foreach ($property in @($Properties.property)) {
            $result[[string] $property.name] = [string] $property.value
        }
    }
    return $result
}

function Test-MapEqual {
    param(
        [hashtable] $Left,
        [hashtable] $Right
    )

    if ($Left.Count -ne $Right.Count) {
        return $false
    }
    foreach ($key in $Left.Keys) {
        if (-not $Right.ContainsKey($key) -or [string] $Left[$key] -ne [string] $Right[$key]) {
            return $false
        }
    }
    return $true
}

function ConvertTo-VcsPropertiesBody {
    param($Properties)

    $items = @()
    foreach ($property in $Properties.PSObject.Properties | Sort-Object Name) {
        $items += @{ name = $property.Name; value = [string] $property.Value }
    }
    return @{ property = $items }
}

function Wait-VersionedSettingsMode {
    param(
        [Parameter(Mandatory)] [string] $ProjectId,
        [Parameter(Mandatory)] [string] $Mode
    )

    $deadline = (Get-Date).AddSeconds(30)
    do {
        $config = Invoke-TeamCityRead "/app/rest/projects/id:$ProjectId/versionedSettings/config"
        if ($config.synchronizationMode -eq $Mode) {
            return
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for project '$ProjectId' versioned settings mode '$Mode'."
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "TeamCity desired-state manifest not found: $ManifestPath"
}
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

$manifestVcsRootIds = @{}
foreach ($vcsRoot in @($manifest.vcsRoots)) {
    if (-not $vcsRoot.id -or -not $vcsRoot.name -or -not $vcsRoot.ownerProjectId -or -not $vcsRoot.vcsName) {
        throw "Every VCS root requires id, name, ownerProjectId, and vcsName."
    }
    if ($manifestVcsRootIds.ContainsKey([string] $vcsRoot.id)) {
        throw "Duplicate VCS root id '$($vcsRoot.id)' in $ManifestPath."
    }
    $manifestVcsRootIds[[string] $vcsRoot.id] = $true
}

$manifestProjectIds = @{}
$repositoryRoot = Split-Path -Parent $PSScriptRoot
foreach ($project in @($manifest.projects)) {
    if (-not $project.id -or -not $project.name -or -not $project.parentId -or -not $project.vcsRootId -or -not $project.settingsPath) {
        throw "Every project requires id, name, parentId, vcsRootId, and settingsPath."
    }
    if ($manifestProjectIds.ContainsKey([string] $project.id)) {
        throw "Duplicate project id '$($project.id)' in $ManifestPath."
    }
    $manifestProjectIds[[string] $project.id] = $true
    if (-not $manifestVcsRootIds.ContainsKey([string] $project.vcsRootId)) {
        throw "Project '$($project.id)' references undeclared VCS root '$($project.vcsRootId)'."
    }
    if ([IO.Path]::IsPathRooted([string] $project.settingsPath) -or @([string] $project.settingsPath -split "[/\\]") -contains "..") {
        throw "Project '$($project.id)' settingsPath must be a repository-relative path without '..'."
    }
    $settingsFile = Join-Path $repositoryRoot (([string] $project.settingsPath -replace "/", [IO.Path]::DirectorySeparatorChar))
    $settingsFile = Join-Path $settingsFile "settings.kts"
    if (-not (Test-Path -LiteralPath $settingsFile -PathType Leaf)) {
        throw "Project '$($project.id)' settings file does not exist: $settingsFile"
    }
}

if (-not $AccessToken) {
    $tokenLine = podman logs teamcity-server 2>&1 |
        Select-String "Super user authentication token" |
        Select-Object -Last 1

    if (-not $tokenLine) {
        $tokenLine = podman exec teamcity-server `
            grep "Super user authentication token" /opt/teamcity/logs/teamcity-server.log 2>&1 |
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
    $script:AuthenticationHeaders = @{ Authorization = "Basic $basicToken" }
}
else {
    $script:AuthenticationHeaders = @{ Authorization = "Bearer $AccessToken" }
}

$csrfToken = (Invoke-WebRequest `
    -UseBasicParsing `
    -Headers $script:AuthenticationHeaders `
    -Uri "$ServerUrl/authenticationTest.html?csrf").Content
$script:WriteHeaders = $script:AuthenticationHeaders + @{ "X-TC-CSRF-Token" = $csrfToken; Accept = "application/json" }

$changes = 0

foreach ($parameter in $manifest.rootParameters.PSObject.Properties | Sort-Object Name) {
    $parameterName = [Uri]::EscapeDataString($parameter.Name)
    $path = "/app/rest/projects/id:_Root/parameters/$parameterName"
    $currentParameter = Invoke-TeamCityRead $path -AllowNotFound
    if ($null -eq $currentParameter) {
        $body = @{ name = $parameter.Name; value = [string] $parameter.Value } | ConvertTo-Json
        Invoke-TeamCityWrite Post "/app/rest/projects/id:_Root/parameters" "application/json" $body
        Write-Host "Created Root parameter '$($parameter.Name)'."
        $changes++
    }
    elseif ([string] $currentParameter.value -ne [string] $parameter.Value) {
        Invoke-TeamCityWrite Put "$path/value" "text/plain" ([string] $parameter.Value)
        Write-Host "Updated Root parameter '$($parameter.Name)'."
        $changes++
    }
}

foreach ($vcsRoot in @($manifest.vcsRoots)) {
    $path = "/app/rest/vcs-roots/id:$($vcsRoot.id)"
    $current = Invoke-TeamCityRead "$path`?fields=id,name,vcsName,project(id),properties(property(name,value))" -AllowNotFound
    $desiredProperties = @{}
    foreach ($property in $vcsRoot.properties.PSObject.Properties) {
        $desiredProperties[$property.Name] = [string] $property.Value
    }

    if ($null -eq $current) {
        $body = @{
            id = $vcsRoot.id
            name = $vcsRoot.name
            vcsName = $vcsRoot.vcsName
            project = @{ id = $vcsRoot.ownerProjectId }
            properties = ConvertTo-VcsPropertiesBody $vcsRoot.properties
        } | ConvertTo-Json -Depth 8
        Invoke-TeamCityWrite Post "/app/rest/vcs-roots" "application/json" $body
        Write-Host "Created VCS root '$($vcsRoot.id)'."
        $changes++
        continue
    }

    if ($current.vcsName -ne $vcsRoot.vcsName -or $current.project.id -ne $vcsRoot.ownerProjectId) {
        throw "VCS root '$($vcsRoot.id)' exists with a different type or owner; refusing to recreate it."
    }
    if ($current.name -ne $vcsRoot.name) {
        Invoke-TeamCityWrite Put "$path/name" "text/plain" ([string] $vcsRoot.name)
        Write-Host "Renamed VCS root '$($vcsRoot.id)'."
        $changes++
    }
    $currentProperties = ConvertTo-PropertyMap $current.properties
    if (-not (Test-MapEqual $desiredProperties $currentProperties)) {
        $body = ConvertTo-VcsPropertiesBody $vcsRoot.properties | ConvertTo-Json -Depth 6
        Invoke-TeamCityWrite Put "$path/properties" "application/json" $body
        Write-Host "Updated VCS root '$($vcsRoot.id)' properties."
        $changes++
    }
}

foreach ($project in @($manifest.projects)) {
    $projectPath = "/app/rest/projects/id:$($project.id)"
    $current = Invoke-TeamCityRead "$projectPath`?fields=id,name,parentProject(id)" -AllowNotFound
    $created = $false
    $configPath = "$projectPath/versionedSettings/config"
    $config = $null

    if ($null -eq $current) {
        $body = @{
            id = $project.id
            name = $project.name
            parentProject = @{ locator = "id:$($project.parentId)" }
            copyAllAssociatedSettings = $false
        } | ConvertTo-Json -Depth 5
        Invoke-TeamCityWrite Post "/app/rest/projects" "application/json" $body
        Write-Host "Created project '$($project.id)'."
        $changes++
        $created = $true
    }
    else {
        if ($current.parentProject.id -ne $project.parentId) {
            throw "Project '$($project.id)' exists under '$($current.parentProject.id)', not '$($project.parentId)'; refusing to move it."
        }
        if ($current.name -ne $project.name) {
            $config = Invoke-TeamCityRead $configPath
            if ($config.synchronizationMode -eq "enabled") {
                $disabledConfig = @{
                    allowUIEditing = [bool] $config.allowUIEditing
                    applyChangesInDependenciesAndVcsSettings = [bool] $config.applyChangesInDependenciesAndVcsSettings
                    buildSettingsMode = $config.buildSettingsMode
                    format = $config.format
                    settingsPath = $config.settingsPath
                    showSettingsChanges = [bool] $config.showSettingsChanges
                    synchronizationMode = "disabled"
                    vcsRootId = $config.vcsRootId
                }
                Invoke-TeamCityWrite Put $configPath "application/json" ($disabledConfig | ConvertTo-Json -Depth 5)
                Wait-VersionedSettingsMode $project.id "disabled"
                $config = Invoke-TeamCityRead $configPath
            }
            Invoke-TeamCityWrite Put "$projectPath/name" "text/plain" ([string] $project.name)
            Write-Host "Renamed project '$($project.id)'."
            $changes++
        }
    }

    if ($null -eq $config) {
        $config = Invoke-TeamCityRead $configPath
    }
    $sourceChanged = $created -or
        $config.synchronizationMode -ne "enabled" -or
        $config.vcsRootId -ne $project.vcsRootId -or
        $config.settingsPath -ne $project.settingsPath -or
        $config.format -ne "kotlin"

    $desiredConfig = @{
        allowUIEditing = $false
        applyChangesInDependenciesAndVcsSettings = $true
        buildSettingsMode = "useFromVCS"
        format = "kotlin"
        portableDsl = $true
        settingsPath = $project.settingsPath
        showSettingsChanges = $false
        storeSecureValuesOutsideVcs = $true
        synchronizationMode = "enabled"
        vcsRootId = $project.vcsRootId
    }

    if ($sourceChanged) {
        if ($config.synchronizationMode -eq "enabled") {
            $disabledConfig = @{}
            foreach ($key in $desiredConfig.Keys) { $disabledConfig[$key] = $desiredConfig[$key] }
            $disabledConfig.synchronizationMode = "disabled"
            $disabledConfig.format = $config.format
            $disabledConfig.settingsPath = $config.settingsPath
            $disabledConfig.vcsRootId = $config.vcsRootId
            $disabledConfig.Remove("portableDsl")
            $disabledConfig.Remove("storeSecureValuesOutsideVcs")
            Invoke-TeamCityWrite Put $configPath "application/json" ($disabledConfig | ConvertTo-Json -Depth 5)
            Wait-VersionedSettingsMode $project.id "disabled"
        }
        $desiredConfig.importDecision = "importFromVCS"
        Invoke-TeamCityWrite Put $configPath "application/json" ($desiredConfig | ConvertTo-Json -Depth 5)
        Wait-VersionedSettingsMode $project.id "enabled"
        Load-TeamCitySettings $project.id
        Write-Host "Imported '$($project.id)' settings from '$($project.settingsPath)'."
        $changes++
        continue
    }

    $status = Invoke-TeamCityRead "$projectPath/versionedSettings/status"
    if ($status.type -eq "warn" -and $status.message -like "*Load project settings from VCS*") {
        Load-TeamCitySettings $project.id
        $changes++
    }

    $mutableDrift =
        [bool] $config.allowUIEditing -ne $false -or
        [bool] $config.applyChangesInDependenciesAndVcsSettings -ne $true -or
        $config.buildSettingsMode -ne "useFromVCS" -or
        [bool] $config.showSettingsChanges -ne $false
    if ($mutableDrift) {
        $mutableConfig = @{}
        foreach ($key in $desiredConfig.Keys) { $mutableConfig[$key] = $desiredConfig[$key] }
        $mutableConfig.Remove("portableDsl")
        $mutableConfig.Remove("storeSecureValuesOutsideVcs")
        Invoke-TeamCityWrite Put $configPath "application/json" ($mutableConfig | ConvertTo-Json -Depth 5)
        Write-Host "Updated '$($project.id)' versioned-settings options."
        $changes++
    }
}

if ($changes -eq 0) {
    Write-Host "TeamCity already matches the desired state."
}
else {
    Write-Host "TeamCity desired state synchronized ($changes change(s))."
}
