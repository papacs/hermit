$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallScript = Join-Path $RepoRoot "scripts\install.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-install"
$TempManifest = Join-Path $TempDir "manifest.ready.json"
$TempChecksums = Join-Path $TempDir "checksums.ready.sha256"

if (-not (Test-Path -LiteralPath $InstallScript)) {
    throw "scripts/install.ps1 is missing"
}

Write-Host "[TEST] Bootstrap manifest should stop install with exit code 2"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile (Join-Path $RepoRoot "assets\manifest.json") -ChecksumFile (Join-Path $RepoRoot "assets\checksums.sha256")
if ($LASTEXITCODE -ne 2) {
    throw "Expected bootstrap install to exit with code 2, got $LASTEXITCODE"
}

Write-Host "[TEST] Ready manifest should reach not-implemented install phases with exit code 3"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
Set-Content -Encoding UTF8 -LiteralPath $TempChecksums -Value "# no active records"
@"
{
  "schemaVersion": 1,
  "packageReady": true,
  "status": "test-ready"
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $TempManifest

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -ManifestFile $TempManifest -ChecksumFile $TempChecksums
    if ($LASTEXITCODE -ne 3) {
        throw "Expected ready manifest to exit with code 3, got $LASTEXITCODE"
    }
}
finally {
    if (Test-Path -LiteralPath $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force
    }
}

Write-Host "[TEST] install bootstrap tests passed"
