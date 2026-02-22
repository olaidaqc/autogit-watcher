Set-StrictMode -Version Latest

function Get-RepoNameFromPath {
  param([Parameter(Mandatory=$true)][string]$Path)
  Split-Path -Path $Path -Leaf
}

function New-AutogitGitignoreContent {
  @"
node_modules/
dist/
build/
.env
.DS_Store
__pycache__/
*.pyc
.venv/
"@
}

function Get-DefaultPrivateRepo {
  $v = $env:AUTOGIT_REPO_VISIBILITY
  if ($v) {
    $v = $v.ToLowerInvariant().Trim()
    if ($v -eq "public") { return $false }
    if ($v -eq "private") { return $true }
  }
  return $true
}

function Get-AutogitPaths {
  $root = $PSScriptRoot

  $projectsRoot = $env:AUTOGIT_PROJECTS_ROOT
  if (-not $projectsRoot) {
    $projectsRoot = Join-Path $root "..\\projects"
  }

  $logPath = $env:AUTOGIT_LOG_PATH
  if (-not $logPath) {
    $logPath = Join-Path $root "autogit.log"
  }

  # PowerShell 5.1 compatible: avoid ?. / ?? operators.
  $resolvedRoot = (Resolve-Path -LiteralPath $root).Path

  $resolvedProjectsRoot = $projectsRoot
  try {
    $resolvedProjectsRoot = (Resolve-Path -LiteralPath $projectsRoot -ErrorAction Stop).Path
  }
  catch { }

  if (-not [System.IO.Path]::IsPathRooted($logPath)) {
    $logPath = Join-Path $resolvedRoot $logPath
  }

  return @{
    Root = $resolvedRoot
    ProjectsRoot = $resolvedProjectsRoot
    LogPath = $logPath
  }
}

function Write-Log {
  param([Parameter(Mandatory=$true)][string]$Message)

  $paths = Get-AutogitPaths
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  "$timestamp $Message" | Add-Content -Encoding UTF8 $paths.LogPath
}

function Ensure-GitIdentity {
  $name = (git config user.name 2>$null)
  if (-not $name) {
    $name = $env:AUTOGIT_GIT_NAME
    if (-not $name) { $name = "AutoGit" }
    git config user.name $name | Out-Null
  }

  $email = (git config user.email 2>$null)
  if (-not $email) {
    $email = $env:AUTOGIT_GIT_EMAIL
    if (-not $email) { $email = "autogit@local" }
    git config user.email $email | Out-Null
  }
}

function Get-GitOriginUrl {
  $old = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  try {
    return (git remote get-url origin 2>$null)
  }
  finally {
    $ErrorActionPreference = $old
  }
}

function Ensure-ProjectInitialized {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [bool]$PrivateRepo = (Get-DefaultPrivateRepo),
    [switch]$SkipRemote
  )

  if (-not (Test-Path $ProjectPath -PathType Container)) {
    throw "Project path not found: $ProjectPath"
  }

  Push-Location $ProjectPath
  try {
    if (-not (Test-Path (Join-Path $ProjectPath ".git") -PathType Container)) {
      git init | Out-Null
    }

    Ensure-GitIdentity

    $gitignorePath = Join-Path $ProjectPath ".gitignore"
    if (-not (Test-Path $gitignorePath)) {
      New-AutogitGitignoreContent | Set-Content -Encoding UTF8 $gitignorePath
    }

    git add -A | Out-Null

    $status = git status --porcelain
    if (-not $status) {
      $readmePath = Join-Path $ProjectPath "README.md"
      if (-not (Test-Path $readmePath)) {
        "AutoGit initialized." | Set-Content -Encoding UTF8 $readmePath
      }
      git add -A | Out-Null
      $status = git status --porcelain
    }

    if ($status) {
      git commit -m "init" | Out-Null
    }

    if (-not $SkipRemote -and -not $env:AUTOGIT_SKIP_REMOTE) {
      try {
        $existingOrigin = Get-GitOriginUrl
        if ($existingOrigin) { return }

        $repoName = Get-RepoNameFromPath $ProjectPath
        if ($PrivateRepo) {
          gh repo create $repoName --private --source . --remote origin --push | Out-Null
        } else {
          gh repo create $repoName --public --source . --remote origin --push | Out-Null
        }
      }
      catch {
        Write-Log -Message "remote create failed for ${ProjectPath}: $($_.Exception.Message)"
      }
    }
  }
  finally {
    Pop-Location
  }
}

function Get-DebounceDelay { 20000 }

$script:ProjectDebounceTimers = @{}

function Commit-And-Push {
  param([Parameter(Mandatory=$true)][string]$ProjectPath)

  if (-not (Test-Path $ProjectPath -PathType Container)) {
    throw "Project path not found: $ProjectPath"
  }

  Push-Location $ProjectPath
  try {
    Ensure-GitIdentity
    git add -A | Out-Null

    $status = git status --porcelain
    if (-not $status) { return }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "auto: $timestamp" | Out-Null

    $originUrl = Get-GitOriginUrl
    if ($originUrl) {
      git push | Out-Null
    }
  }
  finally {
    Pop-Location
  }
}

function Get-OwnerRepoFromRemoteUrl {
  param([Parameter(Mandatory=$true)][string]$Url)

  $u = $Url.Trim()

  if ($u -match '^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$') {
    return @{ Owner = $matches[1]; Repo = $matches[2] }
  }

  if ($u -match '^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$') {
    return @{ Owner = $matches[1]; Repo = $matches[2] }
  }

  if ($u -match '^ssh://git@github\.com/([^/]+)/([^/]+?)(?:\.git)?$') {
    return @{ Owner = $matches[1]; Repo = $matches[2] }
  }

  return $null
}

function Test-IsTopLevelProjectPath {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectsRoot,
    [Parameter(Mandatory=$true)][string]$Path
  )

  if (-not $Path.StartsWith($ProjectsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $false
  }

  $relative = $Path.Substring($ProjectsRoot.Length).TrimStart("\\")
  if (-not $relative) { return $false }

  return ($relative -notmatch '\\')
}

function Handle-ProjectFolderRenamed {
  param(
    [Parameter(Mandatory=$true)][string]$OldProjectPath,
    [Parameter(Mandatory=$true)][string]$NewProjectPath
  )

  if (-not (Test-Path $NewProjectPath -PathType Container)) { return }
  if (-not (Test-Path (Join-Path $NewProjectPath ".git") -PathType Container)) { return }

  Push-Location $NewProjectPath
  try {
    $newName = Split-Path $NewProjectPath -Leaf
    $originUrl = Get-GitOriginUrl
    if (-not $originUrl) {
      Write-Log -Message "rename skipped (no origin): $OldProjectPath -> $NewProjectPath"
      return
    }

    $info = Get-OwnerRepoFromRemoteUrl $originUrl
    if (-not $info) {
      Write-Log -Message "rename skipped (unparsed origin): $originUrl"
      return
    }

    if ($info.Repo -eq $newName) { return }

    if (-not $env:AUTOGIT_SKIP_REMOTE) {
      & gh repo rename -R "$($info.Owner)/$($info.Repo)" $newName -y | Out-Null
    }

    $newRemote = "https://github.com/$($info.Owner)/$newName.git"
    git remote set-url origin $newRemote | Out-Null

    Write-Log -Message "repo renamed: $($info.Owner)/$($info.Repo) -> $($info.Owner)/$newName"
  }
  catch {
    Write-Log -Message "rename failed ($OldProjectPath -> $NewProjectPath): $($_.Exception.Message)"
  }
  finally {
    Pop-Location
  }
}

function Start-Watcher {
  param(
    [string]$ProjectsRoot = (Get-AutogitPaths).ProjectsRoot,
    [string]$InstanceId = ([guid]::NewGuid().ToString("N"))
  )

  if (-not (Test-Path $ProjectsRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $ProjectsRoot -Force | Out-Null
  }

  $ignoredPatterns = @(
    "*\\.git\\*",
    "*\\node_modules\\*",
    "*\\__pycache__\\*",
    "*\\dist\\*",
    "*\\build\\*"
  )

  $projectWatcher = New-Object System.IO.FileSystemWatcher
  $projectWatcher.Path = $ProjectsRoot
  $projectWatcher.Filter = "*"
  $projectWatcher.IncludeSubdirectories = $false
  $projectWatcher.EnableRaisingEvents = $true

  $fileWatcher = New-Object System.IO.FileSystemWatcher
  $fileWatcher.Path = $ProjectsRoot
  $fileWatcher.Filter = "*"
  $fileWatcher.IncludeSubdirectories = $true
  $fileWatcher.EnableRaisingEvents = $true

  $messageData = @{
    ProjectsRoot = $ProjectsRoot
    IgnoredPatterns = $ignoredPatterns
    InstanceId = $InstanceId
  }

  $onProjectCreated = {
    try {
      $fullPath = $Event.SourceEventArgs.FullPath
      foreach ($pattern in $Event.MessageData.IgnoredPatterns) {
        if ($fullPath -like $pattern) { return }
      }

      if (-not (Test-Path $fullPath -PathType Container)) { return }
      if (Test-Path (Join-Path $fullPath ".git") -PathType Container) { return } # likely a rename/move

      Write-Log -Message "New project detected: $fullPath"
      Ensure-ProjectInitialized -ProjectPath $fullPath
    }
    catch {
      Write-Log -Message "init failed for $($Event.SourceEventArgs.FullPath): $($_.Exception.Message)"
    }
  }

  $onFileChanged = {
    $fullPath = $Event.SourceEventArgs.FullPath
    foreach ($pattern in $Event.MessageData.IgnoredPatterns) {
      if ($fullPath -like $pattern) { return }
    }

    $root = $Event.MessageData.ProjectsRoot
    if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
      return
    }

    if ($Event.SourceEventArgs -is [System.IO.RenamedEventArgs]) {
      $oldFullPath = $Event.SourceEventArgs.OldFullPath
      if ((Test-IsTopLevelProjectPath -ProjectsRoot $root -Path $oldFullPath) -and (Test-IsTopLevelProjectPath -ProjectsRoot $root -Path $fullPath)) {
        Handle-ProjectFolderRenamed -OldProjectPath $oldFullPath -NewProjectPath $fullPath
        return
      }
    }

    $relative = $fullPath.Substring($root.Length).TrimStart("\\")
    if (-not $relative) { return }

    $projectName = $relative.Split("\\")[0]
    $projectPath = Join-Path $root $projectName
    if (-not (Test-Path $projectPath -PathType Container)) { return }

    if ($script:ProjectDebounceTimers.ContainsKey($projectPath)) {
      $existing = $script:ProjectDebounceTimers[$projectPath]
      $existing.Timer.Stop()
      $existing.Timer.Dispose()
      Unregister-Event -SourceIdentifier $existing.TimerSourceId -ErrorAction SilentlyContinue
      $script:ProjectDebounceTimers.Remove($projectPath)
    }

    $timer = New-Object System.Timers.Timer
    $timer.Interval = Get-DebounceDelay
    $timer.AutoReset = $false

    $timerSourceId = ("AutoGit.Debounce." + $Event.MessageData.InstanceId + "." + [guid]::NewGuid().ToString("N"))
    Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $timerSourceId -MessageData @{ ProjectPath = $projectPath } -Action {
      try {
        Commit-And-Push -ProjectPath $Event.MessageData.ProjectPath
        Write-Log -Message "push $($Event.MessageData.ProjectPath)"
      } catch {
        Write-Log -Message "commit failed for $($Event.MessageData.ProjectPath): $($_.Exception.Message)"
      }
    } | Out-Null

    $script:ProjectDebounceTimers[$projectPath] = @{ Timer = $timer; TimerSourceId = $timerSourceId }
    $timer.Start()
  }

  $subscriptions = @()

  $sidProjectCreated = ("AutoGit.ProjectCreated." + $InstanceId)
  $sidFileChanged = ("AutoGit.FileChanged." + $InstanceId)
  $sidFileCreated = ("AutoGit.FileCreated." + $InstanceId)
  $sidFileDeleted = ("AutoGit.FileDeleted." + $InstanceId)
  $sidFileRenamed = ("AutoGit.FileRenamed." + $InstanceId)

  Register-ObjectEvent -InputObject $projectWatcher -EventName Created -SourceIdentifier $sidProjectCreated -MessageData $messageData -Action $onProjectCreated | Out-Null
  Register-ObjectEvent -InputObject $fileWatcher -EventName Changed -SourceIdentifier $sidFileChanged -MessageData $messageData -Action $onFileChanged | Out-Null
  Register-ObjectEvent -InputObject $fileWatcher -EventName Created -SourceIdentifier $sidFileCreated -MessageData $messageData -Action $onFileChanged | Out-Null
  Register-ObjectEvent -InputObject $fileWatcher -EventName Deleted -SourceIdentifier $sidFileDeleted -MessageData $messageData -Action $onFileChanged | Out-Null
  Register-ObjectEvent -InputObject $fileWatcher -EventName Renamed -SourceIdentifier $sidFileRenamed -MessageData $messageData -Action $onFileChanged | Out-Null

  $subscriptions += $sidProjectCreated
  $subscriptions += $sidFileChanged
  $subscriptions += $sidFileCreated
  $subscriptions += $sidFileDeleted
  $subscriptions += $sidFileRenamed

  Write-Log -Message "Watcher started for $ProjectsRoot"

  return @{
    ProjectWatcher = $projectWatcher
    FileWatcher = $fileWatcher
    Subscriptions = $subscriptions
  }
}

function Ensure-SingleInstance {
  param([string]$Name = "Local\\AutoGit.Watcher")

  $createdNew = $false
  $mutex = New-Object System.Threading.Mutex($true, $Name, [ref]$createdNew)
  if (-not $createdNew) {
    try { Write-Log -Message "Another AutoGit watcher instance is already running. Exiting." } catch { }
    exit 0
  }

  return $mutex
}

if ($MyInvocation.InvocationName -ne '.') {
  $script:SingleInstanceMutex = Ensure-SingleInstance
  $null = Start-Watcher
  while ($true) {
    Wait-Event -Timeout 5 | Out-Null
  }
}
