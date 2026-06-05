param(
    [switch]$DryRun,
    [switch]$Force,
    [string]$LogFile,
    [string]$PythonUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe",
    [string]$HermesUrl = "https://hermes-assets.nousresearch.com/Hermes-Setup.exe",
    [string]$PythonPackageSpec = "python-docx>=1.1,<2"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$RuntimeRoot = Join-Path $LocalAppData "Hermit\runtime"
$ManagedPythonDir = Join-Path $RuntimeRoot "Python311"
$ManagedPythonExe = Join-Path $ManagedPythonDir "python.exe"

$PythonInstallerPath = Join-Path $RepoRoot "assets\installers\python-3.11.9-amd64.exe"
$HermesInstallerPath = Join-Path $RepoRoot "assets\installers\hermes-desktop-setup.exe"
$WheelsDir = Join-Path $RepoRoot "assets\wheels"
$ConfigTemplatePath = Join-Path $RepoRoot "assets\config\config_template.zip"
$ConfigExamplePath = Join-Path $RepoRoot "assets\config\config.example.json"
$LocalManifestPath = Join-Path $RepoRoot "assets\manifest.local.json"
$LocalChecksumPath = Join-Path $RepoRoot "assets\checksums.local.sha256"

function Write-Line {
    param([string]$Line)

    Write-Host $Line
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
                    Write-Host "[Hermit][WARN] Unable to write prepare-assets log file." -ForegroundColor Yellow
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

function Fail {
    param([string]$Message)
    Write-Line -Line "[Hermit][ERROR] $Message"
    exit 1
}

function Test-CommandSuccess {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    try {
        & $FilePath @Arguments *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function New-PythonRuntime {
    param(
        [string]$Exe,
        [string[]]$Args = @()
    )

    return [pscustomobject]@{
        Exe = $Exe
        Args = $Args
    }
}

function Get-Python311Runtime {
    $Candidates = @(
        @{ Exe = $ManagedPythonExe; Args = @() },
        @{ Exe = "py"; Args = @("-3.11") },
        @{ Exe = "python"; Args = @() }
    )

    foreach ($Candidate in $Candidates) {
        if ([System.IO.Path]::IsPathRooted($Candidate.Exe) -and -not (Test-Path -LiteralPath $Candidate.Exe)) {
            continue
        }
        $ProbeArgs = @($Candidate.Args + @("-c", "import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)"))
        if (Test-CommandSuccess -FilePath $Candidate.Exe -Arguments $ProbeArgs) {
            return New-PythonRuntime -Exe $Candidate.Exe -Args $Candidate.Args
        }
    }
    return $null
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $Output = & $FilePath @Arguments 2>&1
        $ExitCode = $LASTEXITCODE
    }
    catch {
        Write-Info ("Failed to start command {0}: {1}" -f $FilePath, $_.Exception.Message)
        return 1
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    foreach ($Line in $Output) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Line)) {
            Write-Info ([string]$Line)
        }
    }
    return [int]$ExitCode
}

function Invoke-Python {
    param(
        [object]$Python,
        [string[]]$Arguments
    )

    return Invoke-NativeCommand -FilePath $Python.Exe -Arguments @($Python.Args + $Arguments)
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Name
    )

    if ((Test-Path -LiteralPath $Destination) -and -not $Force) {
        Write-Info "$Name already exists. Skipping download."
        return
    }

    if ($DryRun) {
        Write-Info "Would download $Name from $Url to $Destination"
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Write-Info "Downloading $Name from official source."
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Install-ManagedPython {
    if (Test-Path -LiteralPath $ManagedPythonExe) {
        $Python = Get-Python311Runtime
        if ($null -ne $Python) {
            return $Python
        }
    }

    if ($DryRun) {
        Write-Info "Would install managed Python 3.11 under Hermit runtime."
        return New-PythonRuntime -Exe $ManagedPythonExe
    }

    if (-not (Test-Path -LiteralPath $PythonInstallerPath)) {
        Fail "Python installer is missing after download step"
    }

    New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
    $PythonArgs = @(
        "/quiet",
        "InstallAllUsers=0",
        "TargetDir=`"$ManagedPythonDir`"",
        "PrependPath=0",
        "Include_pip=1",
        "Include_test=0",
        "Include_launcher=0",
        "Shortcuts=0"
    )

    Write-Info "Installing managed Python 3.11 under Hermit runtime."
    $Process = Start-Process -FilePath $PythonInstallerPath -ArgumentList $PythonArgs -Wait -PassThru -WindowStyle Hidden
    if ($Process.ExitCode -ne 0) {
        Fail "Managed Python installer failed with exit code $($Process.ExitCode)"
    }

    $Python = Get-Python311Runtime
    if ($null -eq $Python) {
        Fail "Managed Python installation completed but Python 3.11 was not detected"
    }
    return $Python
}

function Download-Wheels {
    param([object]$Python)

    if ($DryRun) {
        Write-Info "Would download Python wheels into $WheelsDir"
        return
    }

    New-Item -ItemType Directory -Force -Path $WheelsDir | Out-Null
    Write-Info "Downloading Python wheels for CPython 3.11 win_amd64."
    $PipArgs = @(
        "-m",
        "pip",
        "download",
        "--dest",
        $WheelsDir,
        "--only-binary=:all:",
        "--platform",
        "win_amd64",
        "--python-version",
        "3.11",
        "--implementation",
        "cp",
        "--abi",
        "cp311",
        $PythonPackageSpec
    )
    $ExitCode = Invoke-Python -Python $Python -Arguments $PipArgs
    if ($ExitCode -ne 0) {
        Fail "Python wheel download failed with exit code $ExitCode"
    }
}

function Ensure-ConfigTemplate {
    if ((Test-Path -LiteralPath $ConfigTemplatePath) -and -not $Force) {
        Write-Info "Config template already exists. Skipping generation."
        return
    }

    if ($DryRun) {
        Write-Info "Would generate config template zip"
        return
    }

    if (-not (Test-Path -LiteralPath $ConfigExamplePath)) {
        Fail "Config example file is missing: assets/config/config.example.json"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigTemplatePath) | Out-Null
    Compress-Archive -LiteralPath $ConfigExamplePath -DestinationPath $ConfigTemplatePath -Force
    Write-Info "Generated config template zip."
}

function Get-AssetRecord {
    param([string]$RelativePath)

    $FullPath = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $FullPath)) {
        Fail "Required local asset is missing: $RelativePath"
    }

    $File = Get-Item -LiteralPath $FullPath
    $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $FullPath).Hash.ToLowerInvariant()
    return [pscustomobject]@{
        path = $RelativePath.Replace("\", "/")
        sizeBytes = $File.Length
        sha256 = $Hash
    }
}

function Get-RepoRelativePath {
    param([string]$FullPath)

    $ResolvedPath = (Resolve-Path -LiteralPath $FullPath).Path
    $RootWithSeparator = $RepoRoot.TrimEnd("\") + "\"
    if (-not $ResolvedPath.StartsWith($RootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "Asset path points outside project root"
    }
    return $ResolvedPath.Substring($RootWithSeparator.Length).Replace("\", "/")
}

function Write-LocalManifests {
    if ($DryRun) {
        Write-Info "Would generate local manifest and checksum files"
        return
    }

    $WheelFiles = Get-ChildItem -LiteralPath $WheelsDir -Filter "*.whl" -File | Sort-Object Name
    if ($WheelFiles.Count -eq 0) {
        Fail "No Python wheel files were downloaded"
    }

    $AssetRecords = @(
        Get-AssetRecord -RelativePath "assets/installers/python-3.11.9-amd64.exe"
        Get-AssetRecord -RelativePath "assets/installers/hermes-desktop-setup.exe"
    )
    foreach ($Wheel in $WheelFiles) {
        $RelativeWheel = Get-RepoRelativePath -FullPath $Wheel.FullName
        $AssetRecords += Get-AssetRecord -RelativePath $RelativeWheel
    }
    $AssetRecords += Get-AssetRecord -RelativePath "assets/config/config_template.zip"

    $ChecksumLines = $AssetRecords | ForEach-Object { "{0}  {1}" -f $_.sha256, $_.path }
    Set-Content -Encoding UTF8 -LiteralPath $LocalChecksumPath -Value $ChecksumLines

    $PythonPackages = $WheelFiles | ForEach-Object {
        [pscustomobject]@{
            name = $_.BaseName
            path = Get-RepoRelativePath -FullPath $_.FullName
            required = $true
        }
    }

    $Manifest = [ordered]@{
        schemaVersion = 1
        packageReady = $true
        status = "local-ready"
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        sources = [ordered]@{
            python = $PythonUrl
            hermes = $HermesUrl
            pythonPackages = "pip download --platform win_amd64 --python-version 3.11 --implementation cp --abi cp311 $PythonPackageSpec"
        }
        requiredInstallers = @(
            [ordered]@{
                id = "python"
                name = "Python"
                version = "3.11.9"
                path = "assets/installers/python-3.11.9-amd64.exe"
                architecture = "x64"
                required = $true
            },
            [ordered]@{
                id = "hermes"
                name = "Hermes Desktop"
                version = "downloaded-online"
                path = "assets/installers/hermes-desktop-setup.exe"
                architecture = "x64"
                required = $true
            }
        )
        pythonPackages = $PythonPackages
        configPackages = @(
            [ordered]@{
                id = "hermes-config-template"
                path = "assets/config/config_template.zip"
                required = $true
                containsSecrets = $false
            }
        )
        assets = $AssetRecords
        notes = @(
            "This file is local-only and ignored by git.",
            "Do not commit downloaded installers, wheels, or private config templates."
        )
    }

    $Manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $LocalManifestPath
    Write-Info "Generated assets/manifest.local.json and assets/checksums.local.sha256."
}

if ($DryRun) {
    Write-Info "Would download Python installer from $PythonUrl to $PythonInstallerPath"
    Write-Info "Would download Hermes installer from $HermesUrl to $HermesInstallerPath"
    Write-Info "Would download Python wheels into $WheelsDir"
    Write-Info "Would generate local manifest and checksum files"
    exit 0
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
    Write-Info "Unable to force TLS 1.2; continuing with system defaults."
}

Download-File -Url $PythonUrl -Destination $PythonInstallerPath -Name "Python installer"
Download-File -Url $HermesUrl -Destination $HermesInstallerPath -Name "Hermes installer"
$Python = Get-Python311Runtime
if ($null -eq $Python) {
    $Python = Install-ManagedPython
}
Download-Wheels -Python $Python
Ensure-ConfigTemplate
Write-LocalManifests
Write-Info "Local asset preparation completed."
exit 0
