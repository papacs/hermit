$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$VerifyScript = Join-Path $RepoRoot "scripts\verify-assets.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp"
$TempFile = Join-Path $TempDir "hash-target.txt"
$TempChecksumFile = Join-Path $TempDir "checksums.sha256"
$TempLogFile = Join-Path $TempDir "logs\verify-assets.log"

if (-not (Test-Path -LiteralPath $VerifyScript)) {
    throw "scripts/verify-assets.ps1 is missing"
}

Write-Host "[TEST] Empty checksum file should pass"
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
Set-Content -Encoding UTF8 -LiteralPath $TempChecksumFile -Value "# test checksum file"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifyScript -ChecksumFile $TempChecksumFile
if ($LASTEXITCODE -ne 0) {
    throw "Expected empty checksum file to pass, got exit code $LASTEXITCODE"
}

Write-Host "[TEST] Valid checksum record should pass"
Set-Content -Encoding UTF8 -LiteralPath $TempFile -Value "hermit asset verification"
$Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $TempFile).Hash.ToLowerInvariant()
$RelativePath = "tests/.tmp/hash-target.txt"
Set-Content -Encoding UTF8 -LiteralPath $TempChecksumFile -Value "$Hash  $RelativePath"

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifyScript -ChecksumFile $TempChecksumFile -LogFile $TempLogFile
    if ($LASTEXITCODE -ne 0) {
        throw "Expected valid checksum record to pass, got exit code $LASTEXITCODE"
    }

    $LogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $TempLogFile
    if ($LogText -notmatch "Verified: tests/.tmp/hash-target.txt") {
        throw "Expected verification log file to contain verified asset output"
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

Write-Host "[TEST] verify-assets tests passed"
