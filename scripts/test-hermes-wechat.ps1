param(
    [string]$HermesHome,
    [string]$HermesCommand = "hermes",
    [string]$Platform = "weixin",
    [switch]$SkipCommands,
    [string]$LogFile
)

$ErrorActionPreference = "Stop"

$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $LocalAppData ("Hermit\logs\hermes-wechat-test-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

function Write-Line {
    param(
        [string]$Message,
        [string]$Color
    )

    if ([string]::IsNullOrWhiteSpace($Color)) {
        Write-Host $Message
    }
    else {
        Write-Host $Message -ForegroundColor $Color
    }

    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        try {
            $LogParent = Split-Path -Parent $LogFile
            if (-not [string]::IsNullOrWhiteSpace($LogParent)) {
                New-Item -ItemType Directory -Force -Path $LogParent | Out-Null
            }
            Add-Content -Encoding UTF8 -LiteralPath $LogFile -Value $Message
        }
        catch {
            Write-Host "[Hermit][WARN] Unable to write Hermes Weixin diagnostic log file." -ForegroundColor Yellow
        }
    }
}

function Write-Info {
    param([string]$Message)
    Write-Line -Message "[Hermit] $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Line -Message "[Hermit][WARN] $Message" -Color "Yellow"
}

function Write-ErrorLine {
    param([string]$Message)
    Write-Line -Message "[Hermit][ERROR] $Message" -Color "Red"
}

function Resolve-HermesHome {
    if (-not [string]::IsNullOrWhiteSpace($HermesHome)) {
        return [System.IO.Path]::GetFullPath($HermesHome)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:HERMES_HOME)) {
        return [System.IO.Path]::GetFullPath($env:HERMES_HOME)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $LocalAppData "hermes"))
}

function Resolve-HermesCommand {
    if ([string]::IsNullOrWhiteSpace($HermesCommand)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($HermesCommand) -or $HermesCommand.Contains("\") -or $HermesCommand.Contains("/")) {
        $FullPath = [System.IO.Path]::GetFullPath($HermesCommand)
        if (Test-Path -LiteralPath $FullPath) {
            return $FullPath
        }
        return $null
    }

    $Command = Get-Command $HermesCommand -ErrorAction SilentlyContinue
    if ($null -eq $Command) {
        return $null
    }

    return $Command.Source
}

function Get-FilePresenceText {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        try {
            $Item = Get-Item -LiteralPath $Path
            return "found ($($Item.Length) bytes)"
        }
        catch {
            return "found"
        }
    }

    return "missing"
}

function Read-TextFileSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    try {
        return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    }
    catch {
        Write-Warn ("Unable to read file for diagnostics: {0}" -f (Split-Path -Leaf $Path))
        return ""
    }
}

function Get-ConfiguredEnvNames {
    param([string]$EnvPath)

    if (-not (Test-Path -LiteralPath $EnvPath)) {
        return @()
    }

    $Names = New-Object System.Collections.Generic.List[string]
    $Lines = Get-Content -Encoding UTF8 -LiteralPath $EnvPath -ErrorAction SilentlyContinue
    foreach ($Line in $Lines) {
        if ($Line -match "^\s*#" -or $Line -notmatch "=") {
            continue
        }

        $Name = ($Line -split "=", 2)[0].Trim()
        $Value = ($Line -split "=", 2)[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($Name) -and -not [string]::IsNullOrWhiteSpace($Value) -and $Value -notmatch "your-.+-here") {
            $Names.Add($Name)
        }
    }

    return $Names.ToArray()
}

function Test-WeixinConfigured {
    param(
        [string]$ConfigYamlText,
        [string]$GatewayJsonText,
        [string[]]$EnvNames
    )

    $PlatformPattern = [regex]::Escape($Platform)
    if (($ConfigYamlText -match "(?im)^\s*$PlatformPattern\s*:") -or
        (($ConfigYamlText -match "(?im)^\s*platforms\s*:") -and ($ConfigYamlText -match "(?im)^\s{2,}$PlatformPattern\s*:"))) {
        return $true
    }

    if ($GatewayJsonText -match "(?i)$PlatformPattern") {
        return $true
    }

    foreach ($Name in $EnvNames) {
        if ($Name -match "^(WEIXIN|WECHAT)_" -or $Name -eq "WEIXIN_ENABLED" -or $Name -eq "WECHAT_ENABLED") {
            return $true
        }
    }

    return $false
}

function Invoke-HermesCommand {
    param(
        [string]$CommandPath,
        [string[]]$Arguments,
        [string]$Label
    )

    Write-Info ("Running: hermes {0}" -f ($Arguments -join " "))
    try {
        $Output = & $CommandPath @Arguments 2>&1 | Out-String
        $ExitCode = $LASTEXITCODE
        $Output = $Output.Trim()
        if (-not [string]::IsNullOrWhiteSpace($Output)) {
            foreach ($Line in ($Output -split "\r?\n")) {
                Write-Line -Message $Line
            }
        }

        if ($ExitCode -ne 0) {
            Write-Warn ("{0} exited with code {1}" -f $Label, $ExitCode)
        }

        return [pscustomobject]@{
            ExitCode = $ExitCode
            Output = $Output
        }
    }
    catch {
        Write-Warn ("{0} failed: {1}" -f $Label, $_.Exception.Message)
        return [pscustomobject]@{
            ExitCode = 1
            Output = ""
        }
    }
}

function Get-PairingCodes {
    param([string]$Text)

    $Codes = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Codes.ToArray()
    }

    $PlatformPattern = [regex]::Escape($Platform)
    foreach ($Match in [regex]::Matches($Text, "(?im)\b$PlatformPattern\b\s+([A-Z0-9][A-Z0-9_-]{3,})\b")) {
        $Codes.Add($Match.Groups[1].Value)
    }

    foreach ($Match in [regex]::Matches($Text, "(?im)Pairing code:\s*([A-Z0-9][A-Z0-9_-]{3,})")) {
        $Codes.Add($Match.Groups[1].Value)
    }

    return ($Codes.ToArray() | Select-Object -Unique)
}

function Get-RecentLogText {
    param([string]$LogsDir)

    if (-not (Test-Path -LiteralPath $LogsDir)) {
        return ""
    }

    $LogFiles = Get-ChildItem -LiteralPath $LogsDir -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 3

    $TextParts = New-Object System.Collections.Generic.List[string]
    foreach ($LogFileItem in $LogFiles) {
        try {
            $Tail = Get-Content -Encoding UTF8 -LiteralPath $LogFileItem.FullName -Tail 80 -ErrorAction Stop | Out-String
            $TextParts.Add($Tail)
        }
        catch {
            Write-Warn ("Unable to read log tail: {0}" -f $LogFileItem.Name)
        }
    }

    return ($TextParts.ToArray() -join "`n")
}

$ResolvedHermesHome = Resolve-HermesHome
$EnvPath = Join-Path $ResolvedHermesHome ".env"
$ConfigPath = Join-Path $ResolvedHermesHome "config.yaml"
$GatewayPath = Join-Path $ResolvedHermesHome "gateway.json"
$PairingDir = Join-Path $ResolvedHermesHome "pairing"
$LogsDir = Join-Path $ResolvedHermesHome "logs"
$PairingDirStatus = if (Test-Path -LiteralPath $PairingDir) { "found" } else { "missing" }
$LogsDirStatus = if (Test-Path -LiteralPath $LogsDir) { "found" } else { "missing" }

Write-Info ("HermesHome: {0}" -f $ResolvedHermesHome)
Write-Info ("Platform: {0}" -f $Platform)
Write-Info ("Log file: {0}" -f $LogFile)
Write-Info (".env: {0}" -f (Get-FilePresenceText -Path $EnvPath))
Write-Info ("config.yaml: {0}" -f (Get-FilePresenceText -Path $ConfigPath))
Write-Info ("gateway.json: {0}" -f (Get-FilePresenceText -Path $GatewayPath))
Write-Info ("pairing directory: {0}" -f $PairingDirStatus)
Write-Info ("logs directory: {0}" -f $LogsDirStatus)

$EnvNames = Get-ConfiguredEnvNames -EnvPath $EnvPath
if ($EnvNames.Count -gt 0) {
    Write-Info ("Configured .env keys: {0} (values hidden)" -f ($EnvNames -join ", "))
}
else {
    Write-Info "Configured .env keys: none detected"
}

$ConfigYamlText = Read-TextFileSafe -Path $ConfigPath
$GatewayJsonText = Read-TextFileSafe -Path $GatewayPath
$WeixinConfigured = Test-WeixinConfigured -ConfigYamlText $ConfigYamlText -GatewayJsonText $GatewayJsonText -EnvNames $EnvNames
if ($WeixinConfigured) {
    Write-Info "Weixin config: found"
}
else {
    Write-Warn "Weixin config: not detected. Run 'hermes gateway setup' on the machine where Hermes is installed."
}

$AllPairingText = ""
if ($SkipCommands) {
    Write-Info "Skipping Hermes CLI commands because -SkipCommands was provided."
}
else {
    $ResolvedHermesCommand = Resolve-HermesCommand
    if ($null -eq $ResolvedHermesCommand) {
        Write-ErrorLine "Hermes CLI was not found. Install Hermes or pass -HermesCommand with the full path to hermes.exe."
        Write-Warn "If Hermes is only running on the VPS, run this diagnostic on the VPS instead of this PC."
        exit 2
    }

    Write-Info ("HermesCommand: {0}" -f $ResolvedHermesCommand)
    $VersionResult = Invoke-HermesCommand -CommandPath $ResolvedHermesCommand -Arguments @("--version") -Label "hermes --version"
    $GatewayResult = Invoke-HermesCommand -CommandPath $ResolvedHermesCommand -Arguments @("gateway", "status") -Label "hermes gateway status"
    $PairingResult = Invoke-HermesCommand -CommandPath $ResolvedHermesCommand -Arguments @("pairing", "list") -Label "hermes pairing list"
    $AllPairingText = @($VersionResult.Output, $GatewayResult.Output, $PairingResult.Output) -join "`n"
}

$RecentLogText = Get-RecentLogText -LogsDir $LogsDir
$PairingCodes = Get-PairingCodes -Text ($AllPairingText + "`n" + $RecentLogText)
if ($PairingCodes.Count -gt 0) {
    foreach ($PairingCode in $PairingCodes) {
        Write-Info ("Approve pending pairing: hermes pairing approve {0} {1}" -f $Platform, $PairingCode)
    }
}
else {
    Write-Info "No pending Weixin pairing code detected in command output or recent logs."
}

Write-Info "Hermes Weixin diagnostic completed."
exit 0
