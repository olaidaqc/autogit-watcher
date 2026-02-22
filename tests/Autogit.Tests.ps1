Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "..\\autogit.ps1")

Describe "Get-RepoNameFromPath" {
  It "returns the leaf folder name" {
    $result = Get-RepoNameFromPath "C:\Users\11918\Desktop\claude\projects\MyProject"
    $result | Should Be "MyProject"
  }
}

Describe "New-AutogitGitignoreContent" {
  It "includes common excludes" {
    $content = New-AutogitGitignoreContent
    $content | Should Match "node_modules/"
    $content | Should Match ".env"
  }
}

Describe "Ensure-ProjectInitialized" {
  It "creates a .git directory when missing" {
    $tmp = Join-Path $env:TEMP ("autogit-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Ensure-ProjectInitialized -ProjectPath $tmp -PrivateRepo $true -SkipRemote
    Test-Path (Join-Path $tmp ".git") | Should Be $True
  }
}

Describe "Get-DebounceDelay" {
  It "returns default delay in milliseconds" {
    (Get-DebounceDelay) | Should Be 20000
  }
}

Describe "Commit-And-Push" {
  It "commits changes with an auto message" {
    $tmp = Join-Path $env:TEMP ("autogit-commit-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null

    Push-Location $tmp
    git init | Out-Null
    git config user.email "autogit@example.local"
    git config user.name "AutoGit"
    "hello" | Set-Content -Encoding UTF8 (Join-Path $tmp "file.txt")

    Commit-And-Push -ProjectPath $tmp

    $msg = git log -1 --pretty=%s
    Pop-Location

    $msg | Should Match "^auto: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
  }
}

Describe "Write-Log" {
  It "writes to the log file" {
    $log = (Get-AutogitPaths).LogPath
    Remove-Item -Force -ErrorAction SilentlyContinue $log
    Write-Log -Message "test"
    (Get-Content $log | Select-Object -Last 1) | Should Match "test"
  }
}

Describe "Start-Watcher" {
  It "returns watchers configured for projects root" {
    $tmp = Join-Path $env:TEMP ("autogit-projects-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null

    $state = Start-Watcher -ProjectsRoot $tmp

    $state.ProjectWatcher.Path | Should Be $tmp
    $state.ProjectWatcher.IncludeSubdirectories | Should Be $False
    $state.FileWatcher.Path | Should Be $tmp
    $state.FileWatcher.IncludeSubdirectories | Should Be $True

    foreach ($sid in $state.Subscriptions) {
      Unregister-Event -SourceIdentifier $sid -ErrorAction SilentlyContinue
    }

    $state.ProjectWatcher.EnableRaisingEvents = $false
    $state.FileWatcher.EnableRaisingEvents = $false
    $state.ProjectWatcher.Dispose()
    $state.FileWatcher.Dispose()
  }
}

Describe "Get-OwnerRepoFromRemoteUrl" {
  It "parses https remote url" {
    $info = Get-OwnerRepoFromRemoteUrl "https://github.com/foo/bar.git"
    $info.Owner | Should Be "foo"
    $info.Repo | Should Be "bar"
  }

  It "parses ssh remote url" {
    $info = Get-OwnerRepoFromRemoteUrl "git@github.com:foo/bar.git"
    $info.Owner | Should Be "foo"
    $info.Repo | Should Be "bar"
  }
}

