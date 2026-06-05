param(
    [string]$ConfigFile,
    [switch]$NoPrompt,
    [switch]$NoDefaultConfig,
    [switch]$DryRun,
    [string]$LogFile
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$RuntimeConfigDir = Join-Path $LocalAppData "Hermit\config"
$RuntimeConfigFile = Join-Path $RuntimeConfigDir "runtime.secrets.json"
$DefaultLocalConfigFile = Join-Path $RepoRoot "assets\config\runtime.local.json"
$LegacyLocalConfigFile = Join-Path $RepoRoot "assets\config\config.json"

function Write-Line {
    param(
        [string]$Line,
        [string]$Color
    )

    if ([string]::IsNullOrWhiteSpace($Color)) {
        Write-Host $Line
    }
    else {
        Write-Host $Line -ForegroundColor $Color
    }

    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
            try {
                $LogParent = Split-Path -Parent $LogFile
                if (-not [string]::IsNullOrWhiteSpace($LogParent)) {
                    New-Item -ItemType Directory -Force -Path $LogParent | Out-Null
                }
                Add-Content -Encoding UTF8 -LiteralPath $LogFile -Value $Line
                break
            }
            catch {
                if ($Attempt -eq 5) {
                    Write-Host "[Hermit][WARN] Unable to write configure log file." -ForegroundColor Yellow
                    break
                }
                Start-Sleep -Milliseconds (100 * $Attempt)
            }
        }
    }
}

function Write-Info {
    param([string]$Message)
    Write-Line -Line "[Hermit] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Line -Line "[Hermit][WARN] $Message" -Color "Yellow"
}

function Fail {
    param([string]$Message)
    Write-Line -Line "[Hermit][ERROR] $Message" -Color "Red"
    exit 1
}

function Convert-SecureStringToPlainText {
    param([Security.SecureString]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return ""
    }

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    }
}

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $NormalizedPath = $Path.Replace("/", "\")
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $NormalizedPath))
    $RootWithSeparator = $RepoRoot.TrimEnd("\") + "\"
    if (-not $FullPath.StartsWith($RootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Config file path points outside project root"
    }
    return $FullPath
}

function Get-ConfigSourcePath {
    if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
        return Resolve-RepoPath -Path $ConfigFile
    }

    if ($NoDefaultConfig) {
        return $null
    }

    if (Test-Path -LiteralPath $DefaultLocalConfigFile) {
        return $DefaultLocalConfigFile
    }

    if (Test-Path -LiteralPath $LegacyLocalConfigFile) {
        return $LegacyLocalConfigFile
    }

    return $null
}

function Read-OptionalSecret {
    param([string]$Prompt)

    $SecureValue = Read-Host -Prompt $Prompt -AsSecureString
    return Convert-SecureStringToPlainText -Value $SecureValue
}

function New-PromptedConfig {
    Write-Info "Runtime config was not preconfigured. Starting interactive setup."
    $Provider = Read-Host -Prompt "API provider name [openai]"
    if ([string]::IsNullOrWhiteSpace($Provider)) {
        $Provider = "openai"
    }

    $BaseUrl = Read-Host -Prompt "API base URL (optional)"
    $ApiKey = Read-OptionalSecret -Prompt "API key (input hidden, leave empty to skip)"

    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Warn "Runtime config not configured because API key was empty."
        return $null
    }

    $GatewayEnabledInput = Read-Host -Prompt "Configure Hermes Gateway personal Weixin remote control now? [y/N]"
    $GatewayEnabled = $GatewayEnabledInput -match "^(y|yes)$"
    $GatewayPlatform = "weixin"
    $GatewayHome = "%LOCALAPPDATA%\hermes"

    if ($GatewayEnabled) {
        $GatewayPlatformInput = Read-Host -Prompt "Hermes Gateway platform [weixin]"
        if (-not [string]::IsNullOrWhiteSpace($GatewayPlatformInput)) {
            $GatewayPlatform = $GatewayPlatformInput
        }

        $GatewayHomeInput = Read-Host -Prompt "Hermes home [%LOCALAPPDATA%\hermes]"
        if (-not [string]::IsNullOrWhiteSpace($GatewayHomeInput)) {
            $GatewayHome = $GatewayHomeInput
        }
    }

    $ProviderConfig = [ordered]@{
        apiKey = $ApiKey
        baseUrl = $BaseUrl
    }
    $Providers = [ordered]@{
        default = $Provider
    }
    $Providers[$Provider] = $ProviderConfig

    return [ordered]@{
        schemaVersion = 1
        configuredAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source = "prompt"
        providers = $Providers
        remoteControl = [ordered]@{
            hermesGateway = [ordered]@{
                enabled = $GatewayEnabled
                platform = $GatewayPlatform
                hermesHome = $GatewayHome
                requirePairingApproval = $true
            }
        }
    }
}

function Protect-RuntimeConfigFile {
    param([string]$Path)

    try {
        $IdentityName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls.exe $Path /inheritance:r *> $null
        & icacls.exe $Path /grant:r "${IdentityName}:F" *> $null
        & icacls.exe $Path /remove:g "Users" "Authenticated Users" "Everyone" *> $null
        Write-Info "Runtime config ACL restricted to current user."
    }
    catch {
        Write-Warn "Unable to restrict runtime config ACL. Check file permissions manually."
    }
}

function Write-RuntimeConfig {
    param([string]$JsonText)

    if ($DryRun) {
        Write-Info "Dry-run: would write runtime config to user-local config directory."
        return
    }

    New-Item -ItemType Directory -Force -Path $RuntimeConfigDir | Out-Null
    Set-Content -Encoding UTF8 -LiteralPath $RuntimeConfigFile -Value $JsonText
    Protect-RuntimeConfigFile -Path $RuntimeConfigFile
    Write-Info "Runtime config written to user-local config directory."
}

function Test-LlmProviderConfig {
    param([object]$ProviderConfig)

    if ($null -eq $ProviderConfig) {
        return $false
    }

    $ApiKeyProperty = $ProviderConfig.PSObject.Properties["apiKey"]
    $BaseUrlProperty = $ProviderConfig.PSObject.Properties["baseUrl"]
    return ($null -ne $ApiKeyProperty -or $null -ne $BaseUrlProperty)
}

function Get-InferredDefaultProviderName {
    param([object]$Providers)

    if ($null -eq $Providers) {
        return $null
    }

    $ProviderProperties = @(
        $Providers.PSObject.Properties |
            Where-Object { $_.Name -ne "default" -and (Test-LlmProviderConfig -ProviderConfig $_.Value) }
    )

    if ($ProviderProperties.Count -eq 0) {
        return $null
    }

    $PreferredNames = @("openai", "deepseek", "anthropic", "dashscope", "qwen")
    foreach ($PreferredName in $PreferredNames) {
        foreach ($ProviderProperty in $ProviderProperties) {
            if ($ProviderProperty.Name.Equals($PreferredName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $ProviderProperty.Name
            }
        }
    }

    return $ProviderProperties[0].Name
}

function ConvertTo-RuntimeConfigJson {
    param([string]$RawConfig)

    try {
        $ParsedConfig = $RawConfig | ConvertFrom-Json
    }
    catch {
        Fail "Runtime config JSON parse failed"
    }

    $ProvidersProperty = $ParsedConfig.PSObject.Properties["providers"]
    if ($null -eq $ProvidersProperty -or $null -eq $ProvidersProperty.Value) {
        Fail "Runtime config must contain providers object"
    }

    $DefaultProperty = $ProvidersProperty.Value.PSObject.Properties["default"]
    $HasDefaultProvider = $null -ne $DefaultProperty -and -not [string]::IsNullOrWhiteSpace([string]$DefaultProperty.Value)
    if (-not $HasDefaultProvider) {
        $InferredProviderName = Get-InferredDefaultProviderName -Providers $ProvidersProperty.Value
        if ([string]::IsNullOrWhiteSpace($InferredProviderName)) {
            Write-Warn "Runtime config has no default API provider. API calls may fail until providers.default is configured."
        }
        elseif ($null -eq $DefaultProperty) {
            Add-Member -InputObject $ProvidersProperty.Value -MemberType NoteProperty -Name "default" -Value $InferredProviderName
            Write-Info "Runtime config default API provider inferred."
        }
        else {
            $DefaultProperty.Value = $InferredProviderName
            Write-Info "Runtime config default API provider inferred."
        }
    }

    return ($ParsedConfig | ConvertTo-Json -Depth 12)
}

$SourcePath = Get-ConfigSourcePath
if ($null -ne $SourcePath) {
    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Fail "Runtime config file not found"
    }

    $RawConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $SourcePath
    $RuntimeConfigJson = ConvertTo-RuntimeConfigJson -RawConfig $RawConfig

    Write-Info "Runtime config source found. Installing without printing secret values."
    Write-RuntimeConfig -JsonText $RuntimeConfigJson
    exit 0
}

if ($DryRun) {
    Write-Info "Dry-run: would prompt for runtime config because no preconfigured file was found."
    exit 0
}

if ($NoPrompt) {
    Write-Warn "Runtime config not configured. Provide -ConfigFile or rerun without -NoPrompt."
    exit 2
}

$PromptedConfig = New-PromptedConfig
if ($null -eq $PromptedConfig) {
    exit 2
}

$PromptedJson = $PromptedConfig | ConvertTo-Json -Depth 8
Write-RuntimeConfig -JsonText $PromptedJson
exit 0
