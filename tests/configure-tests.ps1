$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ConfigureScript = Join-Path $RepoRoot "scripts\configure.ps1"
$TempDir = Join-Path $RepoRoot "tests\.tmp-configure"
$TempLocalAppData = Join-Path $TempDir "localappdata"
$TempSourceConfig = Join-Path $TempDir "runtime.local.json"
$TempLegacyConfig = Join-Path $TempDir "legacy.config.json"
$TempLogFile = Join-Path $TempDir "configure.log"
$InstalledConfig = Join-Path $TempLocalAppData "Hermit\config\runtime.secrets.json"
$RepoConfigJson = Join-Path $RepoRoot "assets\config\config.json"
$CreatedRepoConfigJson = $false

if (-not (Test-Path -LiteralPath $ConfigureScript)) {
    throw "scripts/configure.ps1 is missing"
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
$OriginalLocalAppData = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $TempLocalAppData

try {
    Write-Host "[TEST] Preconfigured runtime secrets should be installed without leaking values to logs"
    @"
{
  "schemaVersion": 1,
  "providers": {
    "default": "openai",
    "openai": {
      "apiKey": "sk-test-secret",
      "baseUrl": "https://api.example.test/v1"
    }
  },
  "remoteControl": {
    "hermesGateway": {
      "enabled": true,
      "platform": "weixin",
      "hermesHome": "%LOCALAPPDATA%\\hermes",
      "requirePairingApproval": true
    }
  }
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $TempSourceConfig

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ConfigureScript -ConfigFile $TempSourceConfig -NoPrompt -LogFile $TempLogFile
    if ($LASTEXITCODE -ne 0) {
        throw "Expected preconfigured config to exit 0, got $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $InstalledConfig)) {
        throw "Expected installed runtime secret config at $InstalledConfig"
    }

    $InstalledText = Get-Content -Raw -Encoding UTF8 -LiteralPath $InstalledConfig
    if ($InstalledText -notmatch "sk-test-secret" -or $InstalledText -notmatch "hermesGateway") {
        throw "Expected installed config to contain provided runtime values"
    }

    $LogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $TempLogFile
    if ($LogText -match "sk-test-secret") {
        throw "Configure log leaked a secret value"
    }
    if ($LogText -notmatch "Runtime config written") {
        throw "Expected configure log to include success message"
    }

    Write-Host "[TEST] Legacy config without providers.default should be normalized"
    Remove-Item -LiteralPath $InstalledConfig -Force
    Remove-Item -LiteralPath $TempLogFile -Force
    @"
{
  "schemaVersion": 1,
  "environment": "local",
  "providers": {
    "deepseek": {
      "apiKey": "sk-deepseek-secret",
      "baseUrl": "https://api.deepseek.com/v1"
    },
    "slack": {
      "botToken": "",
      "signingSecret": ""
    }
  }
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $TempLegacyConfig

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ConfigureScript -ConfigFile $TempLegacyConfig -NoPrompt -LogFile $TempLogFile
    if ($LASTEXITCODE -ne 0) {
        throw "Expected legacy config to exit 0, got $LASTEXITCODE"
    }

    $NormalizedConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $InstalledConfig | ConvertFrom-Json
    if ($NormalizedConfig.providers.default -ne "deepseek") {
        throw "Expected legacy config normalization to set providers.default to deepseek"
    }
    if ($NormalizedConfig.providers.deepseek.baseUrl -ne "https://api.deepseek.com/v1") {
        throw "Expected legacy config normalization to preserve provider baseUrl"
    }
    if ($NormalizedConfig.providers.slack.botToken -ne "") {
        throw "Expected legacy config normalization to preserve non-LLM provider settings"
    }

    Write-Host "[TEST] Missing runtime secrets with NoPrompt should exit 2"
    Remove-Item -LiteralPath $InstalledConfig -Force
    Remove-Item -LiteralPath $TempLogFile -Force
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ConfigureScript -NoPrompt -NoDefaultConfig -LogFile $TempLogFile
    if ($LASTEXITCODE -ne 2) {
        throw "Expected missing NoPrompt config to exit 2, got $LASTEXITCODE"
    }
    if (Test-Path -LiteralPath $InstalledConfig) {
        throw "Expected NoPrompt missing config to avoid writing runtime secrets"
    }

    $MissingLogText = Get-Content -Raw -Encoding UTF8 -LiteralPath $TempLogFile
    if ($MissingLogText -notmatch "Runtime config not configured") {
        throw "Expected missing config log to explain runtime config was not configured"
    }

    Write-Host "[TEST] Dry-run should not write runtime secrets"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ConfigureScript -ConfigFile $TempSourceConfig -DryRun -NoPrompt -NoDefaultConfig -LogFile $TempLogFile
    if ($LASTEXITCODE -ne 0) {
        throw "Expected dry-run config to exit 0, got $LASTEXITCODE"
    }
    if (Test-Path -LiteralPath $InstalledConfig) {
        throw "Expected dry-run config to avoid writing runtime secrets"
    }

    if (-not (Test-Path -LiteralPath $RepoConfigJson)) {
        Write-Host "[TEST] assets/config/config.json should be discovered as a preconfigured runtime config"
        Copy-Item -LiteralPath $TempSourceConfig -Destination $RepoConfigJson
        $CreatedRepoConfigJson = $true
        Remove-Item -LiteralPath $TempLogFile -Force
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ConfigureScript -NoPrompt -LogFile $TempLogFile
        if ($LASTEXITCODE -ne 0) {
            throw "Expected default assets/config/config.json to exit 0, got $LASTEXITCODE"
        }
        if (-not (Test-Path -LiteralPath $InstalledConfig)) {
            throw "Expected config.json discovery to write runtime secrets"
        }
    }
    else {
        Write-Host "[TEST] Skipping config.json discovery test because a local config.json already exists"
    }
}
finally {
    $env:LOCALAPPDATA = $OriginalLocalAppData
    if ($CreatedRepoConfigJson -and (Test-Path -LiteralPath $RepoConfigJson)) {
        Remove-Item -LiteralPath $RepoConfigJson -Force
    }
    if (Test-Path -LiteralPath $TempDir) {
        $ResolvedTempDir = (Resolve-Path -LiteralPath $TempDir).Path
        if (-not $ResolvedTempDir.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean temp directory outside repo: $ResolvedTempDir"
        }
        Remove-Item -LiteralPath $ResolvedTempDir -Recurse -Force
    }
}

Write-Host "[TEST] configure tests passed"
