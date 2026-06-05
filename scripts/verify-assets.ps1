param(
    [string]$ChecksumFile
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path

if ([string]::IsNullOrWhiteSpace($ChecksumFile)) {
    $ChecksumFile = Join-Path $RepoRoot "assets\checksums.sha256"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[Hermit] $Message"
}

function Fail {
    param([string]$Message)
    Write-Host "[Hermit][ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Resolve-RepoPath {
    param([string]$RelativePath)

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        Fail "Checksum records must use relative paths: $RelativePath"
    }

    $NormalizedRelativePath = $RelativePath.Replace("/", "\")
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $NormalizedRelativePath))
    $RootWithSeparator = $RepoRoot.TrimEnd("\") + "\"

    if (-not $FullPath.StartsWith($RootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Checksum record points outside the project root: $RelativePath"
    }

    return $FullPath
}

if (-not (Test-Path -LiteralPath $ChecksumFile)) {
    Fail "Checksum file not found: $ChecksumFile"
}

Write-Info "Verifying offline assets: $ChecksumFile"

$Lines = Get-Content -Encoding UTF8 -LiteralPath $ChecksumFile
$RecordCount = 0
$LineNumber = 0

foreach ($Line in $Lines) {
    $LineNumber++
    $Trimmed = $Line.Trim()

    if ([string]::IsNullOrWhiteSpace($Trimmed) -or $Trimmed.StartsWith("#")) {
        continue
    }

    $Match = [regex]::Match($Trimmed, "^(?<hash>[a-fA-F0-9]{64})\s+(?<path>.+)$")
    if (-not $Match.Success) {
        Fail "Invalid checksum format on line ${LineNumber}. Expected: <sha256>  <relative-path>"
    }

    $ExpectedHash = $Match.Groups["hash"].Value.ToLowerInvariant()
    $RelativePath = $Match.Groups["path"].Value.Trim()
    $FullPath = Resolve-RepoPath -RelativePath $RelativePath

    if (-not (Test-Path -LiteralPath $FullPath)) {
        Fail "Asset file not found: $RelativePath"
    }

    $ActualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $FullPath).Hash.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedHash) {
        Fail "SHA256 mismatch: $RelativePath"
    }

    $RecordCount++
    Write-Info "Verified: $RelativePath"
}

if ($RecordCount -eq 0) {
    Write-Info "No active checksum records found. Bootstrap stage passes."
}
else {
    Write-Info "Offline asset verification completed. Verified ${RecordCount} file(s)."
}

exit 0
