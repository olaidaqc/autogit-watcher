Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$Owner = "olaidaqc",
  [switch]$Force
)

if (-not $Force) {
  throw "Refusing to delete repos without -Force"
}

$names = @(gh repo list $Owner --limit 200 --json name --jq ".[].name")
$targets = $names | Where-Object { $_ -match '^(demo-autogit-|rename-test-|rename2-)' } | Sort-Object

if (-not $targets -or $targets.Count -eq 0) {
  "No demo repos found."
  exit 0
}

"Deleting repos:"
$targets | ForEach-Object { " - $Owner/$_" }

foreach ($r in $targets) {
  gh repo delete "$Owner/$r" --yes
}

"Done."

