[CmdletBinding()]
param(
    [ValidateSet("Auto", "Docker", "Podman")]
    [string] $Engine = "Auto",

    [ValidateSet("Up", "Down")]
    [string] $Action = "Up"
)

$ErrorActionPreference = "Stop"

function Test-ComposeCommand([string] $Executable) {
    if (-not (Get-Command $Executable -ErrorAction SilentlyContinue)) {
        return $false
    }

    & $Executable compose version *> $null
    return $LASTEXITCODE -eq 0
}

if ($Engine -eq "Auto") {
    foreach ($candidate in @("Podman", "Docker")) {
        if (Test-ComposeCommand $candidate.ToLowerInvariant()) {
            $Engine = $candidate
            break
        }
    }
}

$executable = $Engine.ToLowerInvariant()
if ($Engine -eq "Auto") {
    throw "Neither Podman Compose nor Docker Compose is available."
}
if (-not (Test-ComposeCommand $executable)) {
    throw "$Engine Compose is not available."
}

$composeArguments = @(
    "compose"
    "-f"
    (Join-Path $PSScriptRoot "compose.yaml")
    "-f"
    (Join-Path $PSScriptRoot "compose.local.yaml")
)

if ($Action -eq "Up") {
    $composeArguments += @("up", "-d", "--wait")
    Write-Host "Starting the Compose sample with $Engine..."
}
else {
    $composeArguments += "down"
    Write-Host "Stopping the Compose sample with $Engine..."
}

& $executable @composeArguments

if ($LASTEXITCODE -ne 0) {
    throw "$Engine Compose failed with exit code $LASTEXITCODE."
}

if ($Action -eq "Up") {
    Write-Host "SQL Server is available at 127.0.0.1:1433."
    Write-Host "Kafka is available at 127.0.0.1:9092."
}
