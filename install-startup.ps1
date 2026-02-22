Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$autogitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$autogitScript = Join-Path $autogitRoot "autogit.ps1"

if (-not (Test-Path -LiteralPath $autogitScript -PathType Leaf)) {
  throw "autogit.ps1 not found: $autogitScript"
}

$startupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
if (-not $startupDir) {
  $startupDir = Join-Path $env:APPDATA "Microsoft\\Windows\\Start Menu\\Programs\\Startup"
}

$null = New-Item -ItemType Directory -Path $startupDir -Force

$projectsRoot = Join-Path (Split-Path -Parent $autogitRoot) "projects"
$logPath = Join-Path $autogitRoot "autogit.log"

$cmdPath = Join-Path $startupDir "AutoGit-Watcher.cmd"

$cmd = @"
@echo off
setlocal
set AUTOGIT_PROJECTS_ROOT=$projectsRoot
set AUTOGIT_LOG_PATH=$logPath
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$autogitScript"
"@

$cmd | Set-Content -Encoding ASCII -LiteralPath $cmdPath

"Installed: $cmdPath"
