param(
    [string]$ConfigFile,
    [string]$Provider,
    [string]$Model,
    [string]$Prompt = "Reply in one short sentence: Hermit API configuration works.",
    [int]$MaxTokens = 64,
    [int]$TimeoutSec = 60,
    [string]$Proxy,
    [switch]$NoProxy,
    [switch]$ProxyUseDefaultCredentials,
    [switch]$SkipNetworkDiagnostics,
    [switch]$DryRun,
    [string]$LogFile
)

$ErrorActionPreference = "Stop"

$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$DefaultConfigFile = Join-Path $LocalAppData "Hermit\config\runtime.secrets.json"

if ([string]::IsNullOrWhiteSpace($LogFile)) {
    $LogFile = Join-Path $LocalAppData ("Hermit\logs\api-test-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
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
            Write-Host "[Hermit][WARN] Unable to write API test log file." -ForegroundColor Yellow
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

function Fail {
    param([string]$Message)
    Write-ErrorLine -Message $Message
    exit 1
}

function Resolve-InputPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $DefaultConfigFile
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path))
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

function Get-DefaultModelName {
    param([string]$ProviderName)

    if ($ProviderName.Equals("deepseek", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "deepseek-v4-flash"
    }

    if ($ProviderName.Equals("openai", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "gpt-4o-mini"
    }

    return "deepseek-v4-flash"
}

function Read-ResponseBody {
    param([System.Net.WebResponse]$Response)

    if ($null -eq $Response) {
        return ""
    }

    try {
        $Stream = $Response.GetResponseStream()
        if ($null -eq $Stream) {
            return ""
        }

        $Reader = New-Object System.IO.StreamReader($Stream)
        try {
            return $Reader.ReadToEnd()
        }
        finally {
            $Reader.Dispose()
        }
    }
    catch {
        return ""
    }
}

function Write-ExceptionDetails {
    param([System.Exception]$Exception)

    $Current = $Exception
    $Depth = 0
    while ($null -ne $Current -and $Depth -lt 5) {
        if ($Depth -eq 0) {
            Write-ErrorLine -Message ("Request failed: {0}" -f $Current.Message)
        }
        else {
            Write-ErrorLine -Message ("Inner exception {0}: {1}" -f $Depth, $Current.Message)
        }
        $Current = $Current.InnerException
        $Depth += 1
    }
}

function Set-NetworkDefaults {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        [System.Net.ServicePointManager]::Expect100Continue = $false
    }
    catch {
        Write-Warn -Message ("Unable to set TLS defaults: {0}" -f $_.Exception.Message)
    }
}

function Set-NoProxyMode {
    try {
        [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
    }
    catch {
        Write-Warn -Message ("Unable to disable the default web proxy: {0}" -f $_.Exception.Message)
    }
}

function Test-LoopbackHost {
    param([string]$HostName)

    return (
        $HostName.Equals("localhost", [System.StringComparison]::OrdinalIgnoreCase) -or
        $HostName.Equals("127.0.0.1", [System.StringComparison]::OrdinalIgnoreCase) -or
        $HostName.Equals("::1", [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Write-ProxyTcpDiagnostic {
    param([System.Uri]$ProxyUri)

    if ($null -eq $ProxyUri -or [string]::IsNullOrWhiteSpace($ProxyUri.Host) -or $ProxyUri.Port -le 0) {
        return
    }

    try {
        $ProxyTcpOk = Test-NetConnection -ComputerName $ProxyUri.Host -Port $ProxyUri.Port -InformationLevel Quiet
        Write-Info ("Proxy TCP {0}:{1}: {2}" -f $ProxyUri.Host, $ProxyUri.Port, $ProxyTcpOk)

        if (-not $ProxyTcpOk -and (Test-LoopbackHost -HostName $ProxyUri.Host)) {
            Write-Warn ("System proxy points to {0}, but no local proxy service is accepting connections there." -f $ProxyUri.AbsoluteUri)
            Write-Warn "Start the proxy application, fix the Windows proxy port, disable the system proxy, or rerun this script with -NoProxy if direct access is allowed."
        }
    }
    catch {
        Write-Warn ("Proxy TCP check failed: {0}" -f $_.Exception.Message)
    }
}

function Write-NetworkDiagnostics {
    param([System.Uri]$Endpoint)

    if ($SkipNetworkDiagnostics) {
        return
    }

    try {
        $Addresses = [System.Net.Dns]::GetHostAddresses($Endpoint.Host) |
            ForEach-Object { $_.IPAddressToString }
        Write-Info ("DNS: {0} -> {1}" -f $Endpoint.Host, ($Addresses -join ", "))
    }
    catch {
        Write-Warn ("DNS lookup failed: {0}" -f $_.Exception.Message)
    }

    try {
        $Port = if ($Endpoint.Port -gt 0) { $Endpoint.Port } elseif ($Endpoint.Scheme -eq "https") { 443 } else { 80 }
        $TcpOk = Test-NetConnection -ComputerName $Endpoint.Host -Port $Port -InformationLevel Quiet
        Write-Info ("TCP {0}:{1}: {2}" -f $Endpoint.Host, $Port, $TcpOk)
    }
    catch {
        Write-Warn ("TCP check failed: {0}" -f $_.Exception.Message)
    }

    if ($NoProxy) {
        Write-Info "Proxy: direct (-NoProxy)"
        return
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
            $ExplicitProxyUri = [System.Uri]$Proxy
            Write-Info ("Proxy: {0} (explicit)" -f $ExplicitProxyUri.AbsoluteUri)
            Write-ProxyTcpDiagnostic -ProxyUri $ExplicitProxyUri
            return
        }

        $SystemProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $ProxyUri = $SystemProxy.GetProxy($Endpoint)
        if ($SystemProxy.IsBypassed($Endpoint) -or $ProxyUri.AbsoluteUri -eq $Endpoint.AbsoluteUri) {
            Write-Info "Proxy: direct"
        }
        else {
            Write-Info ("Proxy: {0}" -f $ProxyUri.AbsoluteUri)
            Write-ProxyTcpDiagnostic -ProxyUri $ProxyUri
        }
    }
    catch {
        Write-Warn ("Proxy check failed: {0}" -f $_.Exception.Message)
    }
}

Set-NetworkDefaults

if ($NoProxy -and -not [string]::IsNullOrWhiteSpace($Proxy)) {
    Fail "Use either -NoProxy or -Proxy, not both."
}

$ResolvedConfigFile = Resolve-InputPath -Path $ConfigFile
if (-not (Test-Path -LiteralPath $ResolvedConfigFile)) {
    Fail "Runtime config file not found. Run scripts\configure.ps1 first."
}

try {
    $Config = Get-Content -Raw -Encoding UTF8 -LiteralPath $ResolvedConfigFile | ConvertFrom-Json
}
catch {
    Fail "Runtime config JSON parse failed."
}

$ProvidersProperty = $Config.PSObject.Properties["providers"]
if ($null -eq $ProvidersProperty -or $null -eq $ProvidersProperty.Value) {
    Fail "Runtime config must contain providers object."
}

$ProviderName = $Provider
if ([string]::IsNullOrWhiteSpace($ProviderName)) {
    $DefaultProperty = $ProvidersProperty.Value.PSObject.Properties["default"]
    if ($null -ne $DefaultProperty) {
        $ProviderName = [string]$DefaultProperty.Value
    }
}
if ([string]::IsNullOrWhiteSpace($ProviderName)) {
    $ProviderName = Get-InferredDefaultProviderName -Providers $ProvidersProperty.Value
}
if ([string]::IsNullOrWhiteSpace($ProviderName)) {
    Fail "Runtime config has no usable API provider."
}

$ProviderProperty = $ProvidersProperty.Value.PSObject.Properties[$ProviderName]
if ($null -eq $ProviderProperty) {
    Fail ("Runtime config provider not found: {0}" -f $ProviderName)
}

$ProviderConfig = $ProviderProperty.Value
$ApiKey = [string]$ProviderConfig.apiKey
$BaseUrl = [string]$ProviderConfig.baseUrl

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    Fail ("API key is empty for provider: {0}" -f $ProviderName)
}
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    Fail ("Base URL is empty for provider: {0}" -f $ProviderName)
}

try {
    $BaseUri = [System.Uri]$BaseUrl
}
catch {
    Fail "Base URL is not a valid absolute URI."
}
if (-not $BaseUri.IsAbsoluteUri -or $BaseUri.Scheme -ne "https") {
    Fail "Base URL must be an absolute https URI."
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    $ModelProperty = $ProviderConfig.PSObject.Properties["model"]
    if ($null -ne $ModelProperty -and -not [string]::IsNullOrWhiteSpace([string]$ModelProperty.Value)) {
        $Model = [string]$ModelProperty.Value
    }
    else {
        $Model = Get-DefaultModelName -ProviderName $ProviderName
    }
}

$Endpoint = [System.Uri]($BaseUrl.TrimEnd("/") + "/chat/completions")

Write-Info ("Provider: {0}" -f $ProviderName)
Write-Info ("Endpoint: {0}" -f $Endpoint.AbsoluteUri)
Write-Info ("Model: {0}" -f $Model)
Write-Info ("TimeoutSec: {0}" -f $TimeoutSec)
Write-Info ("Log file: {0}" -f $LogFile)
if ($NoProxy) {
    Write-Info "ProxyMode: direct (-NoProxy)"
}
elseif (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    Write-Info ("ProxyMode: explicit ({0})" -f $Proxy)
}
else {
    Write-Info "ProxyMode: system default"
}

if ($ProviderName.Equals("deepseek", [System.StringComparison]::OrdinalIgnoreCase) -and
    $BaseUrl.TrimEnd("/").Equals("https://api.deepseek.com/v1", [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Warn "DeepSeek official OpenAI-compatible base URL is https://api.deepseek.com. Keep /v1 only if your account/tooling requires it."
}

if ($DryRun) {
    Write-Info "Dry-run: request not sent."
    exit 0
}

if ($NoProxy) {
    Set-NoProxyMode
}

Write-NetworkDiagnostics -Endpoint $Endpoint

$Body = [ordered]@{
    model = $Model
    messages = @(
        [ordered]@{
            role = "user"
            content = $Prompt
        }
    )
    stream = $false
    max_tokens = $MaxTokens
}
$BodyJson = $Body | ConvertTo-Json -Depth 8

$Headers = @{
    Authorization = "Bearer $ApiKey"
    Accept = "application/json"
    "User-Agent" = "HermitApiTest/0.1"
}

$RestParameters = @{
    Uri = $Endpoint.AbsoluteUri
    Method = "Post"
    Headers = $Headers
    ContentType = "application/json; charset=utf-8"
    Body = $BodyJson
    TimeoutSec = $TimeoutSec
}

$RestCommand = Get-Command Invoke-RestMethod
if ($RestCommand.Parameters.ContainsKey("UseBasicParsing")) {
    $RestParameters["UseBasicParsing"] = $true
}
if (-not [string]::IsNullOrWhiteSpace($Proxy) -and $RestCommand.Parameters.ContainsKey("Proxy")) {
    $RestParameters["Proxy"] = $Proxy
}
if ($ProxyUseDefaultCredentials -and $RestCommand.Parameters.ContainsKey("ProxyUseDefaultCredentials")) {
    $RestParameters["ProxyUseDefaultCredentials"] = $true
}

try {
    $Response = Invoke-RestMethod @RestParameters
    Write-Info "API request succeeded."

    $Message = $null
    if ($null -ne $Response.choices -and $Response.choices.Count -gt 0) {
        $Message = $Response.choices[0].message.content
    }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-Line -Message $Message
    }
    else {
        Write-Info "Response did not contain choices[0].message.content."
    }
    exit 0
}
catch {
    $Exception = $_.Exception
    Write-ExceptionDetails -Exception $Exception

    $HttpResponse = $Exception.Response
    if ($null -ne $HttpResponse) {
        try {
            Write-ErrorLine ("HTTP status: {0} {1}" -f ([int]$HttpResponse.StatusCode), $HttpResponse.StatusDescription)
        }
        catch {
            Write-ErrorLine "HTTP response was received but status could not be read."
        }

        $ResponseBody = Read-ResponseBody -Response $HttpResponse
        if (-not [string]::IsNullOrWhiteSpace($ResponseBody)) {
            if ($ResponseBody.Length -gt 2000) {
                $ResponseBody = $ResponseBody.Substring(0, 2000) + "...(truncated)"
            }
            Write-ErrorLine ("Response body: {0}" -f $ResponseBody)
        }

        Write-Warn "HTTP 400 usually means model/baseUrl/body mismatch. HTTP 401 usually means the API key is invalid or revoked."
    }
    else {
        Write-Warn "No HTTP response was received. If TCP is true, this is usually TLS, certificate, proxy, firewall inspection, or a PowerShell/.NET HTTP stack issue."
        Write-Warn ("Try browser or curl diagnostics on this machine: curl.exe -v {0}" -f $Endpoint.AbsoluteUri)
    }

    exit 1
}
