$Pdf2zhAppDir = Split-Path -Parent $PSScriptRoot
$Pdf2zhLocalConfig = Join-Path $Pdf2zhAppDir "local.config.ps1"

if (Test-Path -LiteralPath $Pdf2zhLocalConfig) {
    . $Pdf2zhLocalConfig
}

function Get-Pdf2zhDefaultPath {
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

if (-not $env:PDF2ZH_TOOL_ROOT) {
    $env:PDF2ZH_TOOL_ROOT = Get-Pdf2zhDefaultPath "G:\CodexTools" (Join-Path $env:USERPROFILE "CodexTools")
}

if (-not $env:PDF2ZH_JOB_ROOT) {
    $fallbackJobs = Join-Path $env:USERPROFILE "CodexOutputs\pdf2zh-web-jobs"
    $env:PDF2ZH_JOB_ROOT = Get-Pdf2zhDefaultPath "G:\CodexOutputs\pdf2zh-web-jobs" $fallbackJobs
}

if (-not $env:PDF2ZH_DEFAULT_OUTPUT) {
    $fallbackOutput = Join-Path $env:USERPROFILE "Downloads\PDF2ZH_Output"
    $env:PDF2ZH_DEFAULT_OUTPUT = Get-Pdf2zhDefaultPath "E:\Download\PDF2ZH_Output" $fallbackOutput
}

if (-not $env:PDF2ZH_PYTHON) {
    $env:PDF2ZH_PYTHON = Join-Path $env:PDF2ZH_TOOL_ROOT "pdf2zh-venv\Scripts\python.exe"
}

if (-not $env:PDF2ZH_EXE) {
    $env:PDF2ZH_EXE = Join-Path $env:PDF2ZH_TOOL_ROOT "pdf2zh-venv\Scripts\pdf2zh.exe"
}

$Pdf2zhPython = $env:PDF2ZH_PYTHON
$Pdf2zhExe = $env:PDF2ZH_EXE
