param(
    [string]$ManifestFile,
    [string]$ChecksumFile,
    [switch]$DryRun,
    [string[]]$HermesSilentArgs = @("/S")
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir "..")).Path
$LocalAppData = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { $env:TEMP } else { $env:LOCALAPPDATA }
$AppData = if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { Join-Path $LocalAppData "Roaming" } else { $env:APPDATA }
$UserProfile = if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { [Environment]::GetFolderPath("UserProfile") } else { $env:USERPROFILE }
$LogDir = Join-Path $LocalAppData "Hermit\logs"
$BackupRoot = Join-Path $LocalAppData "Hermit\backup"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDir "install-$Timestamp.log"

try {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
}
catch {
    Write-Host "[Hermit][ERROR] Unable to initialize installer log directory."
    exit 1
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        try {
            Add-Content -Encoding UTF8 -LiteralPath $LogFile -Value $Line
            break
        }
        catch {
            if ($Attempt -eq 5) {
                throw
            }
            Start-Sleep -Milliseconds (100 * $Attempt)
        }
    }
    Write-Host $Line
}

function Stop-Install {
    param(
        [string]$Message,
        [int]$ExitCode = 1
    )

    Write-Log -Level "ERROR" -Message $Message
    Write-Log -Level "ERROR" -Message "Install stopped with exit code $ExitCode"
    exit $ExitCode
}

function Resolve-RepoPath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        Stop-Install -Message "Required manifest path is empty" -ExitCode 1
    }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        return [System.IO.Path]::GetFullPath($RelativePath)
    }

    $NormalizedRelativePath = $RelativePath.Replace("/", "\")
    $FullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $NormalizedRelativePath))
    $RootWithSeparator = $RepoRoot.TrimEnd("\") + "\"
    if (-not $FullPath.StartsWith($RootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        Stop-Install -Message "Manifest path points outside project root: $RelativePath" -ExitCode 1
    }
    return $FullPath
}

function Get-ManifestItem {
    param(
        [object[]]$Items,
        [string]$Id
    )

    if ($null -eq $Items) {
        return $null
    }
    return @($Items | Where-Object { $_.id -eq $Id } | Select-Object -First 1)[0]
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

function Get-PythonRuntime {
    $Candidates = @(
        @{ Exe = "py"; Args = @("-3.11") },
        @{ Exe = "python"; Args = @() }
    )

    foreach ($Candidate in $Candidates) {
        $ProbeArgs = @($Candidate.Args + @("-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)"))
        if (Test-CommandSuccess -FilePath $Candidate.Exe -Arguments $ProbeArgs) {
            return [pscustomobject]@{
                Exe = $Candidate.Exe
                Args = $Candidate.Args
            }
        }
    }
    return $null
}

function Invoke-Python {
    param(
        [object]$Python,
        [string[]]$Arguments
    )

    & $Python.Exe @($Python.Args + $Arguments)
    return $LASTEXITCODE
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Install-PythonRuntime {
    param([object]$Manifest)

    $Python = Get-PythonRuntime
    if ($null -ne $Python) {
        $CommandParts = @($Python.Exe) + @($Python.Args)
        $CommandText = ($CommandParts -join " ").Trim()
        Write-Log "Python >= 3.10 detected through '$CommandText'."
        return $Python
    }

    $PythonInstaller = Get-ManifestItem -Items $Manifest.requiredInstallers -Id "python"
    if ($null -eq $PythonInstaller) {
        Stop-Install -Message "Manifest does not define required python installer" -ExitCode 1
    }

    $InstallerPath = Resolve-RepoPath -RelativePath $PythonInstaller.path
    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        Stop-Install -Message "Python installer not found: $($PythonInstaller.path)" -ExitCode 1
    }

    $PythonArgs = @(
        "/quiet",
        "InstallAllUsers=1",
        "PrependPath=1",
        "Include_pip=1",
        "Include_test=0"
    )

    Write-Log "Python >= 3.10 not detected. Installing from local asset."
    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would run: $InstallerPath $($PythonArgs -join ' ')"
        return [pscustomobject]@{ Exe = "py"; Args = @("-3.11") }
    }

    $Process = Start-Process -FilePath $InstallerPath -ArgumentList $PythonArgs -Wait -PassThru -WindowStyle Hidden
    if ($Process.ExitCode -ne 0) {
        Stop-Install -Message "Python installer failed with exit code $($Process.ExitCode)" -ExitCode 1
    }

    $Python = Get-PythonRuntime
    if ($null -eq $Python) {
        Stop-Install -Message "Python installation completed but Python >= 3.10 was not detected" -ExitCode 1
    }
    return $Python
}

function Install-PythonPackages {
    param([object]$Python)

    $WheelsDir = Resolve-RepoPath -RelativePath "assets/wheels"
    if (-not (Test-Path -LiteralPath $WheelsDir)) {
        Stop-Install -Message "Wheel directory not found: assets/wheels" -ExitCode 1
    }

    $PipArgs = @("-m", "pip", "install", "--no-index", "--find-links", $WheelsDir, "python-docx")
    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would run Python package install from local wheels."
        return
    }

    $ExitCode = Invoke-Python -Python $Python -Arguments $PipArgs
    if ($ExitCode -ne 0) {
        Stop-Install -Message "Offline pip install failed with exit code $ExitCode" -ExitCode 1
    }
}

function Install-HermesDesktop {
    param([object]$Manifest)

    $HermesInstaller = Get-ManifestItem -Items $Manifest.requiredInstallers -Id "hermes"
    if ($null -eq $HermesInstaller) {
        Write-Log -Level "WARN" -Message "Manifest does not define Hermes installer. Skipping Hermes installation."
        return
    }

    $InstallerPath = Resolve-RepoPath -RelativePath $HermesInstaller.path
    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        Stop-Install -Message "Hermes installer not found: $($HermesInstaller.path)" -ExitCode 1
    }

    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would run Hermes installer: $InstallerPath $($HermesSilentArgs -join ' ')"
        return
    }

    $Process = Start-Process -FilePath $InstallerPath -ArgumentList $HermesSilentArgs -Wait -PassThru -WindowStyle Hidden
    if ($Process.ExitCode -ne 0) {
        Stop-Install -Message "Hermes installer failed with exit code $($Process.ExitCode)" -ExitCode 1
    }
}

function Backup-Directory {
    param(
        [string]$SourcePath,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        Write-Log "No existing directory to back up: $Name"
        return $null
    }

    $BackupPath = Join-Path $BackupRoot "$Name-$Timestamp"
    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would back up $Name to $BackupPath"
        return $BackupPath
    }

    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    Copy-Item -LiteralPath $SourcePath -Destination $BackupPath -Recurse -Force
    Write-Log "Backed up $Name to $BackupPath"
    return $BackupPath
}

function Install-HermesConfig {
    param([object]$Manifest)

    $ConfigPackage = Get-ManifestItem -Items $Manifest.configPackages -Id "hermes-config-template"
    if ($null -eq $ConfigPackage) {
        Write-Log -Level "WARN" -Message "Manifest does not define Hermes config template. Skipping config injection."
        return
    }

    if ($ConfigPackage.containsSecrets -eq $true) {
        Write-Log -Level "WARN" -Message "Config package is marked as containing secrets. Logs will not print config contents."
    }

    $TemplatePath = Resolve-RepoPath -RelativePath $ConfigPackage.path
    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        Stop-Install -Message "Hermes config template not found: $($ConfigPackage.path)" -ExitCode 1
    }

    $HermesHome = Join-Path $LocalAppData "hermes"
    $LegacyHermesConfig = Join-Path $AppData "Hermes"
    Backup-Directory -SourcePath $HermesHome -Name "hermes"
    if (Test-Path -LiteralPath $LegacyHermesConfig) {
        Backup-Directory -SourcePath $LegacyHermesConfig -Name "Hermes-legacy"
    }

    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would expand config template into $HermesHome"
        return
    }

    New-Item -ItemType Directory -Force -Path $HermesHome | Out-Null
    Expand-Archive -LiteralPath $TemplatePath -DestinationPath $HermesHome -Force
}

function Install-HermitSkills {
    $SourceDir = Join-Path $RepoRoot "hermit_skills"
    $TargetDir = Join-Path $UserProfile "Hermit_Skills"

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        Stop-Install -Message "Skill source directory not found: hermit_skills" -ExitCode 1
    }

    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would copy skills from $SourceDir to $TargetDir"
        return
    }

    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Get-ChildItem -LiteralPath $SourceDir -Filter "*.py" -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $TargetDir -Force
    }
}

function Initialize-HermitWorkspace {
    $Workspace = "C:\HermitWorkspace"
    $BackupDir = Join-Path $Workspace ".backup"

    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would create sandbox workspace $Workspace and $BackupDir"
        return
    }

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    try {
        $IdentityName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $Grant = "${IdentityName}:(OI)(CI)M"
        & icacls.exe $Workspace /grant $Grant /T /C *> $null
        Write-Log "Granted current user modify access to Hermit workspace."
    }
    catch {
        Write-Log -Level "WARN" -Message "Unable to adjust Hermit workspace ACL. Continuing with existing permissions."
    }
}

function Test-InstallHealth {
    param([object]$Python)

    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Would run Python import and skill deployment checks."
        return
    }

    $ExitCode = Invoke-Python -Python $Python -Arguments @("-c", "import docx; import sys; sys.exit(0)")
    if ($ExitCode -ne 0) {
        Stop-Install -Message "Post-install import check failed for python-docx" -ExitCode 1
    }

    $SkillTarget = Join-Path $UserProfile "Hermit_Skills\docx_processor.py"
    if (-not (Test-Path -LiteralPath $SkillTarget)) {
        Stop-Install -Message "Post-install skill copy check failed" -ExitCode 1
    }
}

try {
    Write-Log "Hermit installer started"
    Write-Log "Project root: $RepoRoot"
    Write-Log "Log file: $LogFile"
    if ($DryRun) {
        Write-Log -Level "DRYRUN" -Message "Dry run is enabled. No installers, config writes, or skill copies will be executed."
    }

    $DefaultManifestFile = Join-Path $RepoRoot "assets\manifest.json"
    $LocalManifestFile = Join-Path $RepoRoot "assets\manifest.local.json"
    $DefaultChecksumFile = Join-Path $RepoRoot "assets\checksums.sha256"
    $LocalChecksumFile = Join-Path $RepoRoot "assets\checksums.local.sha256"
    $VerifyScript = Join-Path $RepoRoot "scripts\verify-assets.ps1"

    if ([string]::IsNullOrWhiteSpace($ManifestFile)) {
        if (Test-Path -LiteralPath $LocalManifestFile) {
            $ManifestFile = $LocalManifestFile
        }
        else {
            $ManifestFile = $DefaultManifestFile
        }
    }

    if ([string]::IsNullOrWhiteSpace($ChecksumFile)) {
        if (Test-Path -LiteralPath $LocalChecksumFile) {
            $ChecksumFile = $LocalChecksumFile
        }
        else {
            $ChecksumFile = $DefaultChecksumFile
        }
    }

    if (-not (Test-Path -LiteralPath $ManifestFile)) {
        Stop-Install -Message "Manifest file not found: $ManifestFile" -ExitCode 1
    }

    if (-not (Test-Path -LiteralPath $VerifyScript)) {
        Stop-Install -Message "Asset verification script not found: $VerifyScript" -ExitCode 1
    }

    Write-Log "Running offline asset verification"
    Write-Log "Manifest file: $ManifestFile"
    Write-Log "Checksum file: $ChecksumFile"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifyScript -ChecksumFile $ChecksumFile -LogFile $LogFile
    if ($LASTEXITCODE -ne 0) {
        Stop-Install -Message "Asset verification failed with exit code $LASTEXITCODE" -ExitCode 1
    }

    try {
        $Manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestFile | ConvertFrom-Json
    }
    catch {
        Stop-Install -Message "Manifest JSON parse failed: $($_.Exception.Message)" -ExitCode 1
    }

    if ($Manifest.packageReady -ne $true) {
        Write-Log -Level "WARN" -Message "Offline package is not ready. Set packageReady=true only after installers, wheels, config, and checksums are complete."
        Write-Log -Level "WARN" -Message "No installation actions were performed."
        exit 2
    }

    if (-not $DryRun -and -not (Test-IsAdministrator)) {
        Stop-Install -Message "Administrator privileges are required for real installation. Use the bat entrypoint or rerun PowerShell as administrator." -ExitCode 1
    }

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
        Stop-Install -Message "Hermit installer supports Windows only" -ExitCode 1
    }

    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
    Write-Log "OS architecture: $env:PROCESSOR_ARCHITECTURE"

    if ($env:PROCESSOR_ARCHITECTURE -notin @("AMD64", "ARM64")) {
        Stop-Install -Message "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" -ExitCode 1
    }

    $Python = Install-PythonRuntime -Manifest $Manifest
    Install-PythonPackages -Python $Python
    Install-HermesDesktop -Manifest $Manifest
    Install-HermesConfig -Manifest $Manifest
    Install-HermitSkills
    Initialize-HermitWorkspace
    Test-InstallHealth -Python $Python

    Write-Log "Hermit installer completed successfully"
    exit 0
}
catch {
    $UnhandledMessage = $_.Exception.Message
    try {
        Write-Log -Level "ERROR" -Message "Unhandled installer error: $UnhandledMessage"
        if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
            Write-Log -Level "ERROR" -Message "Script stack: $($_.ScriptStackTrace)"
        }
    }
    catch {
        Write-Host "[Hermit][ERROR] Unhandled installer error: $UnhandledMessage"
    }
    exit 1
}
