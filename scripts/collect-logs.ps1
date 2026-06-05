param(
    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$LogDir = Join-Path $LocalAppData "Hermit\logs"
$HermesLogDir = Join-Path $LocalAppData "hermes\logs"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot "diagnostics"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ArchivePath = Join-Path $OutputDirectory "hermit-logs-$Timestamp.zip"

$LogFiles = @()
if (Test-Path -LiteralPath $LogDir) {
    $LogFiles += Get-ChildItem -LiteralPath $LogDir -File -ErrorAction Stop
}
else {
    Write-Host "[Hermit][WARN] Log directory does not exist: $LogDir"
}

if (Test-Path -LiteralPath $HermesLogDir) {
    $LogFiles += Get-ChildItem -LiteralPath $HermesLogDir -File -ErrorAction Stop
}
else {
    Write-Host "[Hermit][WARN] Hermes log directory does not exist: $HermesLogDir"
}

if ($LogFiles.Count -eq 0) {
    Write-Host "[Hermit][WARN] No log files found."
    exit 2
}

Compress-Archive -LiteralPath $LogFiles.FullName -DestinationPath $ArchivePath -Force
Write-Host "[Hermit] Log archive created: $ArchivePath"
exit 0
