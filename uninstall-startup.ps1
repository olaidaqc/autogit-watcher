Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$startupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
if (-not $startupDir) {
  $startupDir = Join-Path $env:APPDATA "Microsoft\\Windows\\Start Menu\\Programs\\Startup"
}
$cmdPath = Join-Path $startupDir "AutoGit-Watcher.cmd"

if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
  Remove-Item -LiteralPath $cmdPath -Force
  "Removed: $cmdPath"
} else {
  "Not found: $cmdPath"
}
