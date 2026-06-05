param(
    [string]$ManifestFile,
    [string]$ChecksumFile
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$LogDir = Join-Path $LocalAppData "Hermit\logs"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDir "install-$Timestamp.log"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Encoding UTF8 -LiteralPath $LogFile -Value $Line
    Write-Host $Line
}

function Stop-Install {
    param(
        [string]$Message,
        [int]$ExitCode = 1
    )

    Write-Log -Level "ERROR" -Message $Message
    Write-Log -Level "ERROR" -Message "Install stopped with exit code $ExitCode"
    exit $ExitCode
}

Write-Log "Hermit installer bootstrap started"
Write-Log "Project root: $RepoRoot"
Write-Log "Log file: $LogFile"

$DefaultManifestFile = Join-Path $RepoRoot "assets\manifest.json"
$LocalManifestFile = Join-Path $RepoRoot "assets\manifest.local.json"
$DefaultChecksumFile = Join-Path $RepoRoot "assets\checksums.sha256"
$LocalChecksumFile = Join-Path $RepoRoot "assets\checksums.local.sha256"
$VerifyScript = Join-Path $RepoRoot "scripts\verify-assets.ps1"

if ([string]::IsNullOrWhiteSpace($ManifestFile)) {
    if (Test-Path -LiteralPath $LocalManifestFile) {
        $ManifestFile = $LocalManifestFile
    }
    else {
        $ManifestFile = $DefaultManifestFile
    }
}

if ([string]::IsNullOrWhiteSpace($ChecksumFile)) {
    if (Test-Path -LiteralPath $LocalChecksumFile) {
        $ChecksumFile = $LocalChecksumFile
    }
    else {
        $ChecksumFile = $DefaultChecksumFile
    }
}

if (-not (Test-Path -LiteralPath $ManifestFile)) {
    Stop-Install -Message "Manifest file not found: $ManifestFile" -ExitCode 1
}

if (-not (Test-Path -LiteralPath $VerifyScript)) {
    Stop-Install -Message "Asset verification script not found: $VerifyScript" -ExitCode 1
}

Write-Log "Running offline asset verification"
Write-Log "Manifest file: $ManifestFile"
Write-Log "Checksum file: $ChecksumFile"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifyScript -ChecksumFile $ChecksumFile
if ($LASTEXITCODE -ne 0) {
    Stop-Install -Message "Asset verification failed with exit code $LASTEXITCODE" -ExitCode 1
}

try {
    $Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestFile | ConvertFrom-Json
}
catch {
    Stop-Install -Message "Manifest JSON parse failed: $($_.Exception.Message)" -ExitCode 1
}

if ($Manifest.packageReady -ne $true) {
    Write-Log -Level "WARN" -Message "Offline package is not ready. Set packageReady=true only after installers, wheels, config, and checksums are complete."
    Write-Log -Level "WARN" -Message "No installation actions were performed."
    exit 2
}

Write-Log -Level "WARN" -Message "packageReady=true, but full installation phases are not implemented yet."
exit 3
