[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position=0)][ValidateSet('init','attach','detach','doctor','archive','list')][string]$Command = 'list',
    [string]$RepoPath = (Get-Location).Path,
    [string]$Id
)
$ErrorActionPreference = 'Stop'
$hub = Split-Path -Parent $PSScriptRoot
$registryPath = Join-Path $hub 'projects.yaml'
$localPath = Join-Path $hub 'local.json'
function Read-Json($Path, $Default) {
    if (Test-Path -LiteralPath $Path) { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    return $Default
}
function Save-Json($Path, $Value) {
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
}
function Full-Path($Path) { [IO.Path]::GetFullPath($Path).TrimEnd('\') }
function Git-Value($Path, [string[]]$Arguments) {
    $result = & git -C $Path @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: $($Arguments -join ' ')" }
    return ($result -join "`n").Trim()
}
function Link-State($Path, $Target) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'missing' }
    if ($item.LinkType -ne 'Junction') { return 'conflict' }
    if ((Full-Path ([string]$item.Target)) -ne (Full-Path $Target)) { return 'conflict' }
    return 'connected'
}
$registry = Read-Json $registryPath ([pscustomobject]@{ schemaVersion=1; projects=@() })
$local = Read-Json $localPath ([pscustomobject]@{ checkouts=@() })
if ($Command -eq 'list') { $registry.projects | Format-Table id,status,remote; return }
if ($Command -eq 'doctor') {
    $failures = 0
    foreach ($checkout in $local.checkouts) {
        $target = Join-Path $hub "projects\$($checkout.id)"
        $link = Join-Path $checkout.path '.dev'
        $entry = @($registry.projects | Where-Object id -eq $checkout.id)
        $state = Link-State $link $target
        $valid = $entry.Count -eq 1 -and (Test-Path -LiteralPath $target) -and (Test-Path -LiteralPath $checkout.path)
        if ($valid) {
            $root = Git-Value $checkout.path @('rev-parse','--show-toplevel')
            $valid = (Full-Path $root) -eq (Full-Path $checkout.path)
            & git -C $checkout.path check-ignore -q -- .dev
            $valid = $valid -and ($LASTEXITCODE -eq 0)
        }
        if (-not $valid -or $state -ne 'connected') { $failures++ }
        Write-Output "$($checkout.id): $state; valid=$valid; $($checkout.path)"
    }
    if ($failures) { throw "Doctor found $failures problem(s)." }
    return
}
$repo = Full-Path (Git-Value $RepoPath @('rev-parse','--show-toplevel'))
if ((Full-Path $hub) -eq $repo) { throw 'The hub cannot be registered as a development repository.' }
$binding = @($local.checkouts | Where-Object path -eq $repo)
if (-not $Id) {
    if ($binding.Count) { $Id = $binding[0].id } else { $Id = Split-Path -Leaf $repo }
}
if ($Id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { throw 'Invalid project ID.' }
if ($binding.Count -and $binding[0].id -ne $Id) { throw 'Checkout is registered to another project.' }
$entry = @($registry.projects | Where-Object id -eq $Id)
if ($entry.Count -gt 1) { throw 'Duplicate project ID.' }
$target = Join-Path $hub "projects\$Id"
$link = Join-Path $repo '.dev'
$state = Link-State $link $target
if ($state -eq 'conflict') { throw "Refusing to change existing path: $link" }
if ($Command -eq 'init') {
    $remote = Git-Value $repo @('remote','get-url','origin')
    if ($entry.Count -and $entry[0].remote -ne $remote) { throw 'Project ID already belongs to a different remote.' }
    if ($entry.Count -and $entry[0].status -eq 'archived') { throw 'Project is archived. Review its status before reactivation.' }
    if ($PSCmdlet.ShouldProcess($Id, 'Register project')) {
        New-Item -ItemType Directory -Path (Join-Path $target 'docs') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $target 'tasks') -Force | Out-Null
        foreach ($folder in @('docs','tasks')) {
            $keep = Join-Path $target "$folder\.gitkeep"
            if (-not (Test-Path -LiteralPath $keep)) { New-Item -ItemType File -Path $keep | Out-Null }
        }
        $backlog = Join-Path $target 'backlog.md'
        if (-not (Test-Path -LiteralPath $backlog)) {
            "# $Id`n`n運用中。既存リポジトリをhubへ登録。`n`n## 未着手`n`n- [ ] 既存の課題・仕様を確認し、管理対象を整理する。`n`n## 作業中`n`nなし。`n`n## 完了`n`n- hubへの初期登録。" | Set-Content -LiteralPath $backlog -Encoding UTF8
        }
        if (-not $entry.Count) {
            $registry.projects = @($registry.projects) + [pscustomobject]@{ id=$Id; remote=$remote; status='active'; registered=(Get-Date -Format 'yyyy-MM-dd') }
            Save-Json $registryPath $registry
        }
    }
    return
}
if (-not $entry.Count) { throw 'Project is not registered. Run init first.' }
if ($Command -eq 'attach') {
    if ($entry[0].status -ne 'active') { throw 'Project is not active.' }
    if (-not (Test-Path -LiteralPath $target)) { throw 'Project directory is missing.' }
    if ((Git-Value $repo @('remote','get-url','origin')) -ne $entry[0].remote) { throw 'Remote does not match registered project.' }
    $tracked = Git-Value $repo @('ls-files','--','.dev')
    if ($tracked) { throw '.dev is already tracked by Git.' }
    if ($PSCmdlet.ShouldProcess($link, "Attach junction to $target")) {
        $exclude = Git-Value $repo @('rev-parse','--path-format=absolute','--git-path','info/exclude')
        New-Item -ItemType Directory -Path (Split-Path -Parent $exclude) -Force | Out-Null
        $lines = @(Get-Content -LiteralPath $exclude -ErrorAction SilentlyContinue)
        if ($lines -notcontains '/.dev') { Add-Content -LiteralPath $exclude -Value "`n/.dev" -Encoding UTF8 }
        if ($state -eq 'missing') { New-Item -ItemType Junction -Path $link -Target $target | Out-Null }
        if (-not $binding.Count) {
            $local.checkouts = @($local.checkouts) + [pscustomobject]@{id=$Id; path=$repo}
            Save-Json $localPath $local
        }
        Write-Output "Attached: $link -> $target"
    }
} elseif ($Command -eq 'detach') {
    if ($PSCmdlet.ShouldProcess($link, 'Remove managed junction only')) {
        if ($state -eq 'connected') { [IO.Directory]::Delete($link) }
        $local.checkouts = @($local.checkouts | Where-Object path -ne $repo)
        Save-Json $localPath $local
        Write-Output "Detached: $link"
    }
} elseif ($Command -eq 'archive') {
    if (@($local.checkouts | Where-Object id -eq $Id).Count) { throw 'Detach all registered checkouts before archiving.' }
    if ($PSCmdlet.ShouldProcess($Id, 'Archive project without deleting files')) {
        $entry[0].status = 'archived'
        $entry[0] | Add-Member -NotePropertyName finalCodeCommit -NotePropertyValue (Git-Value $repo @('rev-parse','HEAD')) -Force
        Save-Json $registryPath $registry
        Write-Output "Archived: $Id"
    }
}
