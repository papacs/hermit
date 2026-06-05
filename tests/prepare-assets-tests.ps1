$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PrepareScript = Join-Path $RepoRoot "scripts\prepare-assets.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-prepare"
$TempLogFile = Join-Path $TempDir "prepare-assets.log"

if (-not (Test-Path -LiteralPath $PrepareScript)) {
    throw "scripts/prepare-assets.ps1 is missing"
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

try {
    Write-Host "[TEST] prepare-assets dry-run should describe online preparation without downloading"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PrepareScript -DryRun -LogFile $TempLogFile
    if ($LASTEXITCODE -ne 0) {
        throw "Expected prepare-assets dry-run to exit 0, got $LASTEXITCODE"
    }

    $LogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $TempLogFile
    if ($LogText -notmatch "Would download Python installer") {
        throw "Expected dry-run log to include Python installer download plan"
    }
    if ($LogText -notmatch "Would download Hermes installer") {
        throw "Expected dry-run log to include Hermes installer download plan"
    }
    if ($LogText -notmatch "Would download Python wheels") {
        throw "Expected dry-run log to include Python wheel download plan"
    }
    if ($LogText -notmatch "Would generate local manifest and checksum files") {
        throw "Expected dry-run log to include local manifest generation plan"
    }
}
finally {
    if (Test-Path -LiteralPath $TempDir) {
        $ResolvedTempDir = (Resolve-Path -LiteralPath $TempDir).Path
        if (-not $ResolvedTempDir.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean temp directory outside repo: $ResolvedTempDir"
        }
        Remove-Item -LiteralPath $ResolvedTempDir -Recurse -Force
    }
}

Write-Host "[TEST] prepare-assets tests passed"
