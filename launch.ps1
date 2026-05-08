param(
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 7861
$url = "http://127.0.0.1:$port/"
$healthUrl = "http://127.0.0.1:$port/api/health"
. (Join-Path $appDir "scripts\env.ps1")

$logDir = Join-Path $env:PDF2ZH_JOB_ROOT "service-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stdoutLog = Join-Path $logDir "server-$stamp.log"
$stderrLog = Join-Path $logDir "server-$stamp.err.log"
$serveScript = Join-Path $appDir "scripts\serve.ps1"

function Test-Pdf2zhLocalHealth {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        return [bool]$response.ok
    }
    catch {
        return $false
    }
}

function Open-Pdf2zhLocalBrowser {
    $openers = @(
        { Start-Process -FilePath $url },
        { Start-Process -FilePath "rundll32.exe" -ArgumentList @("url.dll,FileProtocolHandler", $url) },
        { Start-Process -FilePath "explorer.exe" -ArgumentList $url }
    )

    foreach ($opener in $openers) {
        try {
            & $opener
            return
        }
        catch {
        }
    }

    $browserPaths = @(
        "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files\Mozilla Firefox\firefox.exe"
    )

    foreach ($browser in $browserPaths) {
        if (Test-Path -LiteralPath $browser) {
            Start-Process -FilePath $browser -ArgumentList $url
            return
        }
    }

    throw "Could not open browser automatically. Open $url manually."
}

if (-not (Test-Path -LiteralPath $Pdf2zhPython)) {
    throw "Python not found: $Pdf2zhPython. Run .\install.ps1 first."
}

if (-not (Test-Path -LiteralPath $Pdf2zhExe)) {
    throw "pdf2zh not found: $Pdf2zhExe. Run .\install.ps1 first."
}

if (-not (Test-Path -LiteralPath $serveScript)) {
    throw "Server launcher not found: $serveScript"
}

if (-not (Test-Pdf2zhLocalHealth)) {
    $existingPort = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($existingPort) {
        throw "Port $port is already in use, but it is not responding as PDF2ZH Local."
    }

    $powershellArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$serveScript`" -Port $port"
    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList $powershellArgs `
        -WorkingDirectory $appDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru | Out-Null

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-Pdf2zhLocalHealth) {
            $ready = $true
            break
        }
    }

    if (-not $ready) {
        throw "PDF2ZH Local did not start in time. Check $stderrLog"
    }
}

if (-not $NoBrowser) {
    Open-Pdf2zhLocalBrowser
}

Write-Host "PDF2ZH Local is running at $url"
