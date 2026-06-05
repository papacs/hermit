$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallScript = Join-Path $RepoRoot "scripts\install.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-install"
$TempManifest = Join-Path $TempDir "manifest.ready.json"
$TempChecksums = Join-Path $TempDir "checksums.ready.sha256"
$TempLocalAppData = Join-Path $TempDir "localappdata"

if (-not (Test-Path -LiteralPath $InstallScript)) {
    throw "scripts/install.ps1 is missing"
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$OriginalLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $TempLocalAppData

try {
    Write-Host "[TEST] Bootstrap manifest should stop install with exit code 2"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile (Join-Path $RepoRoot "assets\manifest.json") -ChecksumFile (Join-Path $RepoRoot "assets\checksums.sha256")
    if ($LASTEXITCODE -ne 2) {
        throw "Expected bootstrap install to exit with code 2, got $LASTEXITCODE"
    }

    Write-Host "[TEST] Ready manifest should complete dry-run install plan with exit code 0"
    Set-Content -Encoding UTF8 -LiteralPath $TempChecksums -Value "# no active records"
    @"
{
  "schemaVersion": 1,
  "packageReady": true,
  "status": "test-ready"
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $TempManifest

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile $TempManifest -ChecksumFile $TempChecksums -DryRun
    if ($LASTEXITCODE -ne 0) {
        throw "Expected ready manifest dry-run to exit with code 0, got $LASTEXITCODE"
    }

    $LogDir = Join-Path $TempLocalAppData "Hermit\logs"
    $LatestLog = Get-ChildItem -LiteralPath $LogDir -Filter "install-*.log" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $LatestLog) {
        throw "Expected install dry-run to create a log file"
    }

    $LogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $LatestLog.FullName
    if ($LogText -notmatch "No active checksum records found") {
        throw "Expected install log to include asset verification output"
    }
    if ($LogText -notmatch "Hermit installer completed successfully") {
        throw "Expected install log to include completion output"
    }
    if ($LogText -notmatch "Running runtime config setup") {
        throw "Expected install log to include runtime config setup"
    }
    if ($LogText -notmatch "Dry-run: would prompt for runtime config") {
        throw "Expected install dry-run to avoid interactive runtime config prompt"
    }
}
finally {
    $env:LOCALAPPDATA = $OriginalLocalAppData
    if (Test-Path -LiteralPath $TempDir) {
        $ResolvedTempDir = (Resolve-Path -LiteralPath $TempDir).Path
        if (-not $ResolvedTempDir.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean temp directory outside repo: $ResolvedTempDir"
        }
        Remove-Item -LiteralPath $ResolvedTempDir -Recurse -Force
    }
}

Write-Host "[TEST] install bootstrap tests passed"
