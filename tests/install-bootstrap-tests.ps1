$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallScript = Join-Path $RepoRoot "scripts\install.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-install"
$TempManifest = Join-Path $TempDir "manifest.ready.json"
$TempNotReadyManifest = Join-Path $TempDir "manifest.not-ready.json"
$TempChecksums = Join-Path $TempDir "checksums.ready.sha256"
$TempLocalAppData = Join-Path $TempDir "localappdata"

if (-not (Test-Path -LiteralPath $InstallScript)) {
    throw "scripts/install.ps1 is missing"
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$OriginalLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $TempLocalAppData

try {
    Write-Host "[TEST] Public manifest should complete offline dry-run install plan"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile (Join-Path $RepoRoot "assets\manifest.json") -ChecksumFile (Join-Path $RepoRoot "assets\checksums.sha256") -DryRun -NoDefaultRuntimeConfig -NoOnlineBootstrap
    if ($LASTEXITCODE -ne 0) {
        throw "Expected public manifest dry-run to exit with code 0, got $LASTEXITCODE"
    }

    $PublicLog = Get-ChildItem -LiteralPath (Join-Path $TempLocalAppData "Hermit\logs") -Filter "install-*.log" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $PublicLog) {
        throw "Expected public manifest dry-run to create a log file"
    }
    $PublicLogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $PublicLog.FullName
    if ($PublicLogText -match "Attempting online asset preparation") {
        throw "Expected public manifest dry-run to stay offline"
    }
    if ($PublicLogText -notmatch "Verified: assets/wheels/lxml") {
        throw "Expected public manifest dry-run to verify committed wheels"
    }
    if ($PublicLogText -notmatch "Would skip Hermes Desktop installer by default") {
        throw "Expected public manifest dry-run to skip Hermes installer by default"
    }
    if ($PublicLogText -match "Would run optional Hermes Desktop installer") {
        throw "Expected public manifest dry-run not to run optional Hermes installer by default"
    }
    if ($PublicLogText -notmatch "Hermit installer completed successfully") {
        throw "Expected public manifest dry-run to complete install plan"
    }

    Write-Host "[TEST] Hermes installer should be opt-in during dry-run"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile (Join-Path $RepoRoot "assets\manifest.json") -ChecksumFile (Join-Path $RepoRoot "assets\checksums.sha256") -DryRun -NoDefaultRuntimeConfig -NoOnlineBootstrap -InstallHermes
    if ($LASTEXITCODE -ne 0) {
        throw "Expected opt-in Hermes dry-run to exit with code 0, got $LASTEXITCODE"
    }
    $HermesOptInLog = Get-ChildItem -LiteralPath (Join-Path $TempLocalAppData "Hermit\logs") -Filter "install-*.log" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $HermesOptInLog) {
        throw "Expected opt-in Hermes dry-run to create a log file"
    }
    $HermesOptInLogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $HermesOptInLog.FullName
    if ($HermesOptInLogText -notmatch "Would run optional Hermes Desktop installer") {
        throw "Expected opt-in Hermes dry-run to describe installer launch"
    }

    Set-Content -Encoding UTF8 -LiteralPath $TempChecksums -Value "# no active records"
    @"
{
  "schemaVersion": 1,
  "packageReady": false,
  "status": "test-not-ready"
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $TempNotReadyManifest

    Write-Host "[TEST] Not-ready manifest should stop install with exit code 2 when online bootstrap is disabled"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile $TempNotReadyManifest -ChecksumFile $TempChecksums -NoOnlineBootstrap
    if ($LASTEXITCODE -ne 2) {
        throw "Expected not-ready install to exit with code 2, got $LASTEXITCODE"
    }

    Write-Host "[TEST] Not-ready dry-run should describe online preparation and still stop with exit code 2"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile $TempNotReadyManifest -ChecksumFile $TempChecksums -DryRun
    if ($LASTEXITCODE -ne 2) {
        throw "Expected not-ready dry-run install to exit with code 2, got $LASTEXITCODE"
    }

    $BootstrapDryRunLog = Get-ChildItem -LiteralPath (Join-Path $TempLocalAppData "Hermit\logs") -Filter "install-*.log" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $BootstrapDryRunLog) {
        throw "Expected bootstrap dry-run to create a log file"
    }
    $BootstrapDryRunLogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $BootstrapDryRunLog.FullName
    if ($BootstrapDryRunLogText -notmatch "Would run online local asset preparation") {
        throw "Expected bootstrap dry-run log to include online preparation plan"
    }
    if ($BootstrapDryRunLogText -notmatch "prepare-assets: .*Would download Python installer") {
        throw "Expected bootstrap dry-run log to include prepare-assets output"
    }

    Write-Host "[TEST] Ready manifest should complete dry-run install plan with exit code 0"
    @"
{
  "schemaVersion": 1,
  "packageReady": true,
  "status": "test-ready"
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $TempManifest

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile $TempManifest -ChecksumFile $TempChecksums -DryRun -NoDefaultRuntimeConfig -NoOnlineBootstrap
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
    if ($LogText -notmatch "Python virtual environment") {
        throw "Expected install dry-run to create or reuse a Hermit Python virtual environment"
    }
    if ($LogText -notmatch "Would install Python packages into virtual environment") {
        throw "Expected install dry-run to install Python packages into the virtual environment"
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
