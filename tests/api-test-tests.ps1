$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ApiTestScript = Join-Path $RepoRoot "scripts\test-api.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-api-test"
$TempLocalAppData = Join-Path $TempDir "localappdata"
$InstalledConfigDir = Join-Path $TempLocalAppData "Hermit\config"
$InstalledConfig = Join-Path $InstalledConfigDir "runtime.secrets.json"

function Write-TestConfig {
    param([string]$JsonText)

    New-Item -ItemType Directory -Force -Path $InstalledConfigDir | Out-Null
    Set-Content -Encoding UTF8 -LiteralPath $InstalledConfig -Value $JsonText
}

function Invoke-ApiTestScript {
    param([string[]]$Arguments)

    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApiTestScript @Arguments 2>&1 | Out-String
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = $Output
    }
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$OriginalLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $TempLocalAppData

try {
    if (-not (Test-Path -LiteralPath $ApiTestScript)) {
        throw "scripts/test-api.ps1 is missing"
    }

    Write-Host "[TEST] API dry-run should load default provider without leaking secrets"
    Write-TestConfig -JsonText @"
{
  "schemaVersion": 1,
  "providers": {
    "default": "deepseek",
    "deepseek": {
      "apiKey": "sk-dry-run-secret",
      "baseUrl": "https://api.deepseek.com/v1"
    }
  }
}
"@

    $Result = Invoke-ApiTestScript -Arguments @("-DryRun")
    if ($Result.ExitCode -ne 0) {
        throw "Expected API dry-run to exit 0, got $($Result.ExitCode). Output: $($Result.Output)"
    }
    if ($Result.Output -notmatch "Provider: deepseek") {
        throw "Expected dry-run output to include selected provider"
    }
    if ($Result.Output -notmatch "Endpoint: https://api.deepseek.com/v1/chat/completions") {
        throw "Expected dry-run output to include chat completions endpoint"
    }
    if ($Result.Output -notmatch "Model: deepseek-v4-flash") {
        throw "Expected dry-run output to include DeepSeek default model"
    }
    if ($Result.Output -match "sk-dry-run-secret") {
        throw "API dry-run output leaked an API key"
    }

    Write-Host "[TEST] API dry-run should support bypassing the system proxy"
    $NoProxyResult = Invoke-ApiTestScript -Arguments @("-DryRun", "-NoProxy")
    if ($NoProxyResult.ExitCode -ne 0) {
        throw "Expected API dry-run with NoProxy to exit 0, got $($NoProxyResult.ExitCode). Output: $($NoProxyResult.Output)"
    }
    if ($NoProxyResult.Output -notmatch "ProxyMode: direct \(-NoProxy\)") {
        throw "Expected NoProxy dry-run output to explain that the system proxy will be bypassed"
    }
    if ($NoProxyResult.Output -match "sk-dry-run-secret") {
        throw "API dry-run with NoProxy output leaked an API key"
    }

    Write-Host "[TEST] API dry-run should infer default provider for legacy config"
    Write-TestConfig -JsonText @"
{
  "schemaVersion": 1,
  "providers": {
    "deepseek": {
      "apiKey": "sk-legacy-secret",
      "baseUrl": "https://api.deepseek.com/v1"
    },
    "slack": {
      "botToken": "",
      "signingSecret": ""
    }
  }
}
"@

    $LegacyResult = Invoke-ApiTestScript -Arguments @("-DryRun")
    if ($LegacyResult.ExitCode -ne 0) {
        throw "Expected legacy API dry-run to exit 0, got $($LegacyResult.ExitCode). Output: $($LegacyResult.Output)"
    }
    if ($LegacyResult.Output -notmatch "Provider: deepseek") {
        throw "Expected legacy dry-run output to infer deepseek provider"
    }
    if ($LegacyResult.Output -match "sk-legacy-secret") {
        throw "Legacy API dry-run output leaked an API key"
    }

    Write-Host "[TEST] API dry-run should fail clearly when API key is empty"
    Write-TestConfig -JsonText @"
{
  "schemaVersion": 1,
  "providers": {
    "default": "deepseek",
    "deepseek": {
      "apiKey": "",
      "baseUrl": "https://api.deepseek.com/v1"
    }
  }
}
"@

    $MissingKeyResult = Invoke-ApiTestScript -Arguments @("-DryRun")
    if ($MissingKeyResult.ExitCode -ne 1) {
        throw "Expected missing API key to exit 1, got $($MissingKeyResult.ExitCode). Output: $($MissingKeyResult.Output)"
    }
    if ($MissingKeyResult.Output -notmatch "API key is empty") {
        throw "Expected missing API key output to explain the problem"
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

Write-Host "[TEST] API test script tests passed"
