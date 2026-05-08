param(
    [string]$InstallRoot = "",
    [string]$JobRoot = "",
    [string]$DefaultOutput = "",
    [string]$PythonExe = "",
    [switch]$SkipPythonInstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppDir = Split-Path -Parent $ScriptDir
$Requirements = Join-Path $AppDir "requirements.txt"

function Get-DefaultPath {
    param(
        [Parameter(Mandatory = $true)][string]$Preferred,
        [Parameter(Mandatory = $true)][string]$Fallback
    )

    $drive = Split-Path -Qualifier $Preferred
    if ($drive -and (Test-Path -LiteralPath ($drive + "\"))) {
        return $Preferred
    }

    return $Fallback
}

function Invoke-BasePython {
    param(
        [Parameter(Mandatory = $true)][string[]]$PythonCommand,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    if ($PythonCommand.Count -eq 1) {
        & $PythonCommand[0] @Arguments
    }
    else {
        & $PythonCommand[0] $PythonCommand[1] @Arguments
    }
}

function Test-PythonCommand {
    param([Parameter(Mandatory = $true)][string[]]$PythonCommand)

    try {
        Invoke-BasePython $PythonCommand @("-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)")
        return $true
    }
    catch {
        return $false
    }
}

function Resolve-PythonCommand {
    param([string]$RequestedPython)

    if ($RequestedPython) {
        if (-not (Test-Path -LiteralPath $RequestedPython)) {
            throw "Python executable not found: $RequestedPython"
        }
        $candidate = @($RequestedPython)
        if (Test-PythonCommand $candidate) {
            return $candidate
        }
        throw "Python 3.10 or newer is required: $RequestedPython"
    }

    $pyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($pyLauncher) {
        $candidate = @("py", "-3.11")
        if (Test-PythonCommand $candidate) {
            return $candidate
        }
        $candidate = @("py", "-3")
        if (Test-PythonCommand $candidate) {
            return $candidate
        }
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        $candidate = @("python")
        if (Test-PythonCommand $candidate) {
            return $candidate
        }
    }

    if (-not $SkipPythonInstall) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Host "Python 3.11 not found. Installing it with winget..."
            winget install -e --id Python.Python.3.11 --scope user --accept-package-agreements --accept-source-agreements

            $candidate = @("py", "-3.11")
            if (Test-PythonCommand $candidate) {
                return $candidate
            }
        }
    }

    throw "Python 3.10+ was not found. Install Python 3.11, then rerun this script."
}

function ConvertTo-PowerShellLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

if (-not $InstallRoot) {
    $InstallRoot = Get-DefaultPath "G:\CodexTools" (Join-Path $env:USERPROFILE "CodexTools")
}

if (-not $JobRoot) {
    $JobRoot = Get-DefaultPath "G:\CodexOutputs\pdf2zh-web-jobs" (Join-Path $env:USERPROFILE "CodexOutputs\pdf2zh-web-jobs")
}

if (-not $DefaultOutput) {
    $DefaultOutput = Get-DefaultPath "E:\Download\PDF2ZH_Output" (Join-Path $env:USERPROFILE "Downloads\PDF2ZH_Output")
}

$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$JobRoot = [System.IO.Path]::GetFullPath($JobRoot)
$DefaultOutput = [System.IO.Path]::GetFullPath($DefaultOutput)
$VenvDir = Join-Path $InstallRoot "pdf2zh-venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$Pdf2zhExe = Join-Path $VenvDir "Scripts\pdf2zh.exe"

New-Item -ItemType Directory -Force -Path $InstallRoot, $JobRoot, $DefaultOutput | Out-Null

if ((Test-Path -LiteralPath $VenvDir) -and $Force) {
    $resolvedInstallRoot = (Resolve-Path -LiteralPath $InstallRoot).Path
    $resolvedVenv = (Resolve-Path -LiteralPath $VenvDir).Path
    if (-not $resolvedVenv.StartsWith($resolvedInstallRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a venv outside InstallRoot: $resolvedVenv"
    }
    Remove-Item -LiteralPath $VenvDir -Recurse -Force
}

if (-not (Test-Path -LiteralPath $VenvPython)) {
    $BasePython = Resolve-PythonCommand $PythonExe
    Write-Host "Creating virtual environment: $VenvDir"
    Invoke-BasePython $BasePython @("-m", "venv", $VenvDir)
}

Write-Host "Installing Python packages from requirements.txt..."
& $VenvPython -m pip install --upgrade pip
& $VenvPython -m pip install -r $Requirements

if (-not (Test-Path -LiteralPath $Pdf2zhExe)) {
    throw "pdf2zh was not installed correctly: $Pdf2zhExe"
}

$ConfigPath = Join-Path $AppDir "local.config.ps1"
$ConfigLines = New-Object System.Collections.Generic.List[string]
$ConfigLines.Add('$env:PDF2ZH_TOOL_ROOT = ' + (ConvertTo-PowerShellLiteral $InstallRoot))
$ConfigLines.Add('$env:PDF2ZH_PYTHON = ' + (ConvertTo-PowerShellLiteral $VenvPython))
$ConfigLines.Add('$env:PDF2ZH_EXE = ' + (ConvertTo-PowerShellLiteral $Pdf2zhExe))
$ConfigLines.Add('$env:PDF2ZH_JOB_ROOT = ' + (ConvertTo-PowerShellLiteral $JobRoot))
$ConfigLines.Add('$env:PDF2ZH_DEFAULT_OUTPUT = ' + (ConvertTo-PowerShellLiteral $DefaultOutput))
$ConfigLines | Set-Content -Encoding UTF8 -LiteralPath $ConfigPath

Write-Host ""
Write-Host "Setup complete."
Write-Host "Tool root: $InstallRoot"
Write-Host "Job root: $JobRoot"
Write-Host "Default output: $DefaultOutput"
Write-Host "Start by double-clicking the startup BAT file, or run .\launch.ps1"
