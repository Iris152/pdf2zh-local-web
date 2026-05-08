$ErrorActionPreference = "Stop"

$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $appDir "scripts\env.ps1")

if (-not (Test-Path -LiteralPath $Pdf2zhPython)) {
    throw "Python not found: $Pdf2zhPython. Run .\install.ps1 first."
}

if (-not (Test-Path -LiteralPath $Pdf2zhExe)) {
    throw "pdf2zh not found: $Pdf2zhExe. Run .\install.ps1 first."
}

& $Pdf2zhPython -m uvicorn app:app --host 127.0.0.1 --port 7861 --app-dir $appDir
