$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('project-hub-test-' + [guid]::NewGuid().ToString('N'))
$hub = Join-Path $root 'hub'
$repo = Join-Path $root 'repo'
New-Item -ItemType Directory -Path "$hub\tools",$repo -Force | Out-Null
$sourceTool = Join-Path (Split-Path -Parent $PSScriptRoot) 'project.ps1'
Copy-Item -LiteralPath $sourceTool -Destination "$hub\tools\project.ps1"
git -C $repo init -q
git -C $repo remote add origin https://example.invalid/test.git
$tool = "$hub\tools\project.ps1"
& $tool init -RepoPath $repo -WhatIf
if (Test-Path "$hub\projects.yaml") { throw 'WhatIf wrote registry.' }
& $tool init -RepoPath $repo
& $tool init -RepoPath $repo
& $tool attach -RepoPath $repo
& $tool attach -RepoPath $repo
$registry = Get-Content "$hub\projects.yaml" -Raw | ConvertFrom-Json
$local = Get-Content "$hub\local.json" -Raw | ConvertFrom-Json
if (@($registry.projects).Count -ne 1 -or @($local.checkouts).Count -ne 1) { throw 'Duplicate registration.' }
& $tool doctor
$blocked = $false
try { & $tool archive -RepoPath $repo } catch { $blocked = $true }
if (-not $blocked) { throw 'Archive accepted connected checkout.' }
& $tool detach -RepoPath $repo -WhatIf
if (-not (Test-Path "$repo\.dev")) { throw 'WhatIf detached link.' }
& $tool detach -RepoPath $repo
if (-not (Test-Path "$hub\projects\repo\backlog.md")) { throw 'Detach removed data.' }
& $tool detach -RepoPath $repo
New-Item -ItemType Directory -Path "$repo\.dev" | Out-Null
'preserve' | Set-Content "$repo\.dev\sentinel.txt"
$blocked = $false
try { & $tool attach -RepoPath $repo } catch { $blocked = $true }
if (-not $blocked -or -not (Test-Path "$repo\.dev\sentinel.txt")) { throw 'Attach did not protect existing directory.' }
Remove-Item -LiteralPath "$repo\.dev\sentinel.txt"
[IO.Directory]::Delete("$repo\.dev")
$other = Join-Path $root 'other'
New-Item -ItemType Directory -Path $other | Out-Null
New-Item -ItemType Junction -Path "$repo\.dev" -Target $other | Out-Null
$blocked = $false
try { & $tool detach -RepoPath $repo } catch { $blocked = $true }
if (-not $blocked -or -not (Test-Path "$repo\.dev")) { throw 'Detach accepted unrelated junction.' }
[IO.Directory]::Delete("$repo\.dev")
git -C $repo -c user.name=HubTest -c user.email=hub-test@example.invalid commit --allow-empty -qm test
$worktree = Join-Path $root 'worktree'
git -C $repo worktree add -qb test-worktree $worktree
& $tool attach -RepoPath $worktree -Id repo
& $tool doctor
& $tool detach -RepoPath $worktree -Id repo
& $tool archive -RepoPath $repo
$registry = Get-Content "$hub\projects.yaml" -Raw | ConvertFrom-Json
if ($registry.projects[0].status -ne 'archived' -or -not $registry.projects[0].finalCodeCommit) { throw 'Archive did not record final state.' }
Write-Output "PASS: WhatIf, idempotency, doctor, safe detach, conflict protection, worktree, archive. Fixtures: $root"
