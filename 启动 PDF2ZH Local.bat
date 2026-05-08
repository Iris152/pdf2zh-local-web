@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch.ps1" -NoBrowser
if errorlevel 1 (
  echo.
  echo PDF2ZH Local failed to start.
  pause
  exit /b 1
)
start "" "http://127.0.0.1:7861/"
