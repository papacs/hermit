$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$HermesTestScript = Join-Path $RepoRoot "scripts\test-hermes-wechat.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-hermes-gateway"
$TempHermesHome = Join-Path $TempDir "hermes-home"
$FakeHermes = Join-Path $TempDir "fake-hermes.ps1"

function Invoke-HermesWechatTest {
    param([string[]]$Arguments)

    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HermesTestScript @Arguments 2>&1 | Out-String
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $Output
    }
}

New-Item -ItemType Directory -Force -Path $TempHermesHome | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $TempHermesHome "logs") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $TempHermesHome "pairing") | Out-Null

try {
    if (-not (Test-Path -LiteralPath $HermesTestScript)) {
        throw "scripts/test-hermes-wechat.ps1 is missing"
    }

    @"
OPENAI_API_KEY=sk-should-not-leak
DEEPSEEK_API_KEY=sk-deepseek-should-not-leak
WEIXIN_ENABLED=true
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $TempHermesHome ".env")

    @"
platforms:
  weixin:
    enabled: true
gateway:
  allow_all_users: false
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $TempHermesHome "config.yaml")

    @"
{
  "reset_by_platform": {
    "weixin": {
      "mode": "idle",
      "idle_minutes": 240
    }
  }
}
"@ | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $TempHermesHome "gateway.json")

    "Pairing code: WXCODE123" | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $TempHermesHome "logs\gateway.log")

    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs)

$Joined = $RemainingArgs -join " "
if ($Joined -eq "--version") {
    "Hermes Agent 0.7.0-test"
    exit 0
}
if ($Joined -eq "gateway status") {
    "gateway: running"
    "platforms: weixin"
    exit 0
}
if ($Joined -eq "pairing list") {
    "Pending pairings:"
    "weixin  WXCODE123  expires in 58m"
    exit 0
}

"unexpected args: $Joined"
exit 9
'@ | Set-Content -Encoding UTF8 -LiteralPath $FakeHermes

    Write-Host "[TEST] Hermes Weixin diagnostic should inspect config and pairing without leaking secrets"
    $Result = Invoke-HermesWechatTest -Arguments @(
        "-HermesHome", $TempHermesHome,
        "-HermesCommand", $FakeHermes
    )

    if ($Result.ExitCode -ne 0) {
        throw "Expected Hermes Weixin diagnostic to exit 0, got $($Result.ExitCode). Output: $($Result.Output)"
    }
    if ($Result.Output -notmatch "HermesHome:") {
        throw "Expected output to include Hermes home"
    }
    if ($Result.Output -notmatch "Weixin config: found") {
        throw "Expected output to report Weixin config"
    }
    if ($Result.Output -notmatch "gateway: running") {
        throw "Expected output to include gateway status"
    }
    if ($Result.Output -notmatch "WXCODE123") {
        throw "Expected output to include pending pairing code"
    }
    if ($Result.Output -notmatch "hermes pairing approve weixin WXCODE123") {
        throw "Expected output to include approve command"
    }
    if ($Result.Output -match "sk-should-not-leak" -or $Result.Output -match "sk-deepseek-should-not-leak") {
        throw "Diagnostic output leaked secrets from .env"
    }

    Write-Host "[TEST] Hermes Weixin diagnostic should support file-only mode"
    $FileOnlyResult = Invoke-HermesWechatTest -Arguments @(
        "-HermesHome", $TempHermesHome,
        "-SkipCommands"
    )
    if ($FileOnlyResult.ExitCode -ne 0) {
        throw "Expected file-only Hermes Weixin diagnostic to exit 0, got $($FileOnlyResult.ExitCode). Output: $($FileOnlyResult.Output)"
    }
    if ($FileOnlyResult.Output -notmatch "Skipping Hermes CLI commands") {
        throw "Expected file-only output to explain command checks were skipped"
    }
    if ($FileOnlyResult.Output -match "sk-should-not-leak" -or $FileOnlyResult.Output -match "sk-deepseek-should-not-leak") {
        throw "File-only diagnostic output leaked secrets from .env"
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

Write-Host "[TEST] Hermes gateway tests passed"
