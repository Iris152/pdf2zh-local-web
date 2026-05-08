$ErrorActionPreference = "Stop"

$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $appDir "scripts\serve.ps1") -Port 7861
