param(
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$LogDir = Join-Path $LocalAppData "Hermit\logs"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot "diagnostics"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ArchivePath = Join-Path $OutputDirectory "hermit-logs-$Timestamp.zip"

if (-not (Test-Path -LiteralPath $LogDir)) {
    Write-Host "[Hermit][WARN] Log directory does not exist: $LogDir"
    exit 2
}

$LogFiles = Get-ChildItem -LiteralPath $LogDir -File -ErrorAction Stop
if ($LogFiles.Count -eq 0) {
    Write-Host "[Hermit][WARN] No log files found: $LogDir"
    exit 2
}

Compress-Archive -LiteralPath $LogFiles.FullName -DestinationPath $ArchivePath -Force
Write-Host "[Hermit] Log archive created: $ArchivePath"
exit 0

