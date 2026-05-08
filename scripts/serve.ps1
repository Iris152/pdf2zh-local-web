param(
    [int]$Port = 7861
)

$ErrorActionPreference = "Stop"

$AppDir = Split-Path -Parent $PSScriptRoot
. (Join-Path $AppDir "scripts\env.ps1")

if (-not (Test-Path -LiteralPath $Pdf2zhPython)) {
    throw "Python not found: $Pdf2zhPython. Run .\install.ps1 first."
}

if (-not (Test-Path -LiteralPath $Pdf2zhExe)) {
    throw "pdf2zh not found: $Pdf2zhExe. Run .\install.ps1 first."
}

Set-Location -LiteralPath $AppDir
& $Pdf2zhPython -m uvicorn app:app --host 127.0.0.1 --port $Port --app-dir $AppDir
