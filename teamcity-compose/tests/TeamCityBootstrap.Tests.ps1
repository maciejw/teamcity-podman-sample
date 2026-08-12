#requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "6.0.0" }

Describe "TeamCity bootstrap definitions" {
    It "keeps the Root Podman parameter" {
        [xml]$root = Get-Content (Join-Path $PSScriptRoot "..\server-bootstrap/root-project-config.xml") -Raw
        @($root.project.parameters.param | Where-Object name -eq "teamcity.default.container.engine").Count | Should-Be 1
        ($root.project.parameters.param | Where-Object name -eq "teamcity.default.container.engine").value | Should-Be "podman"

        $compose = Get-Content (Join-Path $PSScriptRoot "..\compose.yaml") -Raw
        $compose | Should-MatchString 'server-bootstrap/root-project-config\.xml:/data/teamcity_server/datadir/config/projects/_Root/project-config\.xml'
        $compose | Should-MatchString 'server-bootstrap/internal\.properties:/data/teamcity_server/datadir/config/internal\.properties'
        $compose | Should-MatchString 'server-data-init'
        $compose | Should-MatchString 'init-server-data\.sh:/bootstrap/init-server-data\.sh:ro'
        $compose | Should-MatchString 'condition: service_completed_successfully'
        $compose | Should-NotMatchString 'server-config-init'
        $compose | Should-NotMatchString 'server-config:/data/teamcity_server/datadir/config'

        $init = Get-Content (Join-Path $PSScriptRoot "..\server-bootstrap/init-server-data.sh") -Raw
        $init | Should-MatchString 'mkdir -p.*projects/_Root'
        $init | Should-MatchString 'chown -R 1000:1000'
    }

    It "starts the stack, waits for TeamCity, and keeps both map entries" {
        $bootstrap = Get-Content (Join-Path $PSScriptRoot "..\Bootstrap-TeamCity.ps1") -Raw
        $bootstrap | Should-MatchString 'podman compose .*up -d --remove-orphans'
        $bootstrap | Should-MatchString 'Wait-TeamCityReady -ServerUrl \$ServerUrl'
        $bootstrap | Should-MatchString '\$session = New-TeamCitySession \$ServerUrl \$AccessToken'
        $bootstrap | Should-MatchString 'system administrator token'
        $bootstrap | Should-MatchString 'Set-TeamCityAgentAuthorized -Session \$session'
        $bootstrap | Should-NotMatchString 'Read-Host|ACCEPT'
        $bootstrap | Should-MatchString 'Import-Module .*TeamCityBootstrap\.psm1.*-Scope Local -Force'
        $bootstrap | Should-MatchString '\$projects\.GetEnumerator\(\) \| Register-Project -Session \$session'
        $bootstrap | Should-MatchString '"Sample Testcontainers"'
        $bootstrap | Should-MatchString '"Sample Compose"'
        $bootstrap | Should-MatchString 'samples/testcontainers/\.teamcity'
        $bootstrap | Should-MatchString 'samples/compose/\.teamcity'
        $bootstrap | Should-NotMatchString 'Ensure-Project|Sync-TeamCity'
    }

    It "has no obsolete state manifest or request files" {
        @(Get-Item (Join-Path $PSScriptRoot "..\state-manifest.json"),
            (Join-Path $PSScriptRoot "..\project-request.json") -ErrorAction SilentlyContinue).Count | Should-Be 0
    }

    It "keeps repository access on the server and consolidates agent build paths" {
        $compose = Get-Content (Join-Path $PSScriptRoot "..\compose.yaml") -Raw
        $compose | Should-MatchString '(?ms)server:\s.*?../:/repo:ro'
        $agent = [regex]::Match($compose, '(?ms)^  agent:\s.*?(?=^  [a-zA-Z0-9_-]+:|^volumes:)').Value
        $agent | Should-NotMatchString '(?m)^[ \t-]*[^\r\n]*:/repo(?::|$)'
        $agent | Should-NotMatchString '(?m)^\s*- /opt/teamcity-agent:/opt/buildagent\s*$'
        foreach ($path in @("work", "temp", "logs", "plugins", "system", "tools")) {
            $agent | Should-MatchString "(?m)^\s*- /opt/teamcity-agent/$($path):/opt/buildagent/$path\s*$"
        }
        $agent | Should-MatchString '(?m)APT_REPOSITORY: \$\{APT_REPOSITORY:-\}'
        $agent | Should-MatchString '(?m)APT_SECURITY_REPOSITORY: \$\{APT_SECURITY_REPOSITORY:-\}'

        $bootstrap = Get-Content (Join-Path $PSScriptRoot "..\Bootstrap-TeamCity.ps1") -Raw
        $bootstrap | Should-MatchString 'podman machine ssh'
        $bootstrap | Should-MatchString 'mkdir -p /opt/teamcity-agent/work /opt/teamcity-agent/temp /opt/teamcity-agent/logs /opt/teamcity-agent/plugins /opt/teamcity-agent/system /opt/teamcity-agent/tools'

        $dockerfile = Get-Content (Join-Path $PSScriptRoot "..\agent\Dockerfile") -Raw
        $dockerfile | Should-NotMatchString 'git config --system --add safe\.directory /repo/\.git'
        $dockerfile | Should-MatchString 'ARG APT_REPOSITORY'
        $dockerfile | Should-MatchString 'ARG APT_SECURITY_REPOSITORY'
        $dockerfile | Should-MatchString 'ubuntu\.sources'
        $dockerfile | Should-MatchString 'VERSION_CODENAME'
        $dockerfile | Should-MatchString 'Components: main restricted universe multiverse'
        $dockerfile | Should-MatchString 'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring\.gpg'
        $dockerfile | Should-MatchString 'RUN <<INSTALL_TOOLS'
        $dockerfile | Should-MatchString '(?ms)RUN <<INSTALL_TOOLS\s+set -eu\s+.*?INSTALL_TOOLS'
        $dockerfile | Should-NotMatchString 'sed -i'
        $dockerfile | Should-NotMatchString '(?m)^if '
    }
}

Import-Module (Join-Path $PSScriptRoot "..\TeamCityBootstrap.psm1") -Scope Local
InModuleScope TeamCityBootstrap {
    Describe "Project initializer request sequence" {
        BeforeEach {
            $session = [pscustomobject]@{
                ServerUrl = "http://teamcity"
                WriteHeaders = @{}
            }
            $projects = [ordered]@{
                "Sample Testcontainers" = @{ settingsPath = "samples/testcontainers/.teamcity"; vcs = @{ url = "file:///repo/.git" } }
                "Sample Compose" = @{ settingsPath = "samples/compose/.teamcity"; vcs = @{ url = "file:///repo/.git" } }
            }
            $global:requestSequence = @()
            Mock Invoke-TeamCityWrite { $global:requestSequence += "$($Method.ToUpperInvariant()) $Path" }
        }

        It "makes exactly three writes per project in documented order" {
            $projects.GetEnumerator() | Register-Project -Session $session

            Should-Invoke Invoke-TeamCityWrite -Times 6 -Exactly
            Should-Invoke Invoke-TeamCityWrite -Times 2 -Exactly -ParameterFilter { $Method -eq "Post" -and $Path -eq "/app/rest/projects" }
            Should-Invoke Invoke-TeamCityWrite -Times 2 -Exactly -ParameterFilter { $Method -eq "Post" -and $Path -eq "/app/rest/vcs-roots" }
            Should-Invoke Invoke-TeamCityWrite -Times 2 -Exactly -ParameterFilter { $Method -eq "Put" -and $Path -like "/app/rest/projects/id:*/versionedSettings/config" }
            ($global:requestSequence -join "`n") | Should-Be ("POST /app/rest/projects`nPOST /app/rest/vcs-roots`nPUT /app/rest/projects/id:SampleTestcontainers/versionedSettings/config`nPOST /app/rest/projects`nPOST /app/rest/vcs-roots`nPUT /app/rest/projects/id:SampleCompose/versionedSettings/config")

            Should-Invoke Invoke-TeamCityWrite -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq "/app/rest/projects" -and $Payload.id -eq "SampleTestcontainers" }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq "/app/rest/vcs-roots" -and $Payload.id -eq "SampleTestcontainers_Repository" }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq "/app/rest/projects/id:SampleTestcontainers/versionedSettings/config" -and $Payload.vcsRootId -eq "SampleTestcontainers_Repository" }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq "/app/rest/projects" -and $Payload.id -eq "SampleCompose" }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq "/app/rest/vcs-roots" -and $Payload.id -eq "SampleCompose_Repository" }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -Exactly -Scope It -ParameterFilter { $Path -eq "/app/rest/projects/id:SampleCompose/versionedSettings/config" -and $Payload.vcsRootId -eq "SampleCompose_Repository" }
        }

        It "sends the project, VCS, and versioned-settings fields" {
            $definition = @{ settingsPath = "samples/testcontainers/.teamcity"; vcs = @{ url = "file:///repo/.git" } }
            $entry = [System.Collections.DictionaryEntry]::new("Sample Testcontainers", $definition)
            Register-Project $session $entry

            Should-Invoke Invoke-TeamCityWrite -Times 1 -ParameterFilter {
                $Path -eq "/app/rest/projects" -and
                $Payload.id -eq "SampleTestcontainers" -and
                $Payload.name -eq "Sample Testcontainers" -and
                $Payload.parentProject.locator -eq "id:_Root" -and
                $Payload.copyAllAssociatedSettings -eq $false
            }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -ParameterFilter {
                $Path -eq "/app/rest/vcs-roots" -and
                $Payload.id -eq "SampleTestcontainers_Repository" -and
                $Payload.project.id -eq "SampleTestcontainers" -and
                $Payload.vcsName -eq "jetbrains.git" -and
                (($Payload.properties.property | Where-Object name -eq "url").value -eq "file:///repo/.git") -and
                (($Payload.properties.property | Where-Object name -eq "branch").value -eq "refs/heads/main") -and
                (($Payload.properties.property | Where-Object name -eq "authMethod").value -eq "ANONYMOUS")
            }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -ParameterFilter {
                $Path -eq "/app/rest/projects/id:SampleTestcontainers/versionedSettings/config" -and
                $Payload.vcsRootId -eq "SampleTestcontainers_Repository" -and
                $Payload.settingsPath -eq "samples/testcontainers/.teamcity" -and
                $Payload.format -eq "kotlin" -and
                $Payload.synchronizationMode -eq "enabled" -and
                $Payload.importDecision -eq "importFromVCS"
            }
        }

        It "omits optional VCS and versioned-settings fields" {
            $definition = @{ settingsPath = "samples/testcontainers/.teamcity"; vcs = @{ url = "file:///repo/.git" } }
            $entry = [System.Collections.DictionaryEntry]::new("Sample Testcontainers", $definition)
            Register-Project $session $entry

            Should-Invoke Invoke-TeamCityWrite -Times 1 -ParameterFilter {
                $Path -eq "/app/rest/vcs-roots" -and
                @($Payload.properties.property).Count -eq 3 -and
                $null -eq ($Payload.properties.property | Where-Object name -in @("agentCleanFilesPolicy", "agentCleanPolicy", "ignoreKnownHosts", "submoduleCheckout", "useAlternates", "usernameStyle"))
            }
            Should-Invoke Invoke-TeamCityWrite -Times 1 -ParameterFilter {
                $Path -like "/app/rest/projects/id:*/versionedSettings/config" -and
                @($Payload.Keys).Count -eq 5 -and
                $null -eq $Payload.allowUIEditing -and
                $null -eq $Payload.applyChangesInDependenciesAndVcsSettings -and
                $null -eq $Payload.buildSettingsMode -and
                $null -eq $Payload.portableDsl -and
                $null -eq $Payload.showSettingsChanges -and
                $null -eq $Payload.storeSecureValuesOutsideVcs
            }
        }

        It "does not contain convergence or repair operations" {
            $module = Get-Content (Get-Module TeamCityBootstrap).Path -Raw
            $module | Should-NotMatchString 'Invoke-TeamCityRead|Invoke-WebRequest|versionedSettings/status|loadSettings|drift|converg'
            $module | Should-MatchString 'healthCheck/ready'
            $module | Should-MatchString '/app/rest/agents'
            $module | Should-MatchString '/authorized'
            $module | Should-MatchString 'Invoke-RestMethod.*SkipHttpErrorCheck.*StatusCodeVariable'
            $module | Should-MatchString 'Write-Warning'
        }
    }
}
