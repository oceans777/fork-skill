param(
  [Parameter(Mandatory=$true)][string]$RepoPath,
  [string]$DevBranch = "dev",
  [string]$ReleaseBranch = "main",
  [switch]$PushMirror,
  [switch]$PromoteMain
)

$ErrorActionPreference = "Stop"

function Run-Git([string[]]$GitArgs) {
  & git @GitArgs
  if ($LASTEXITCODE -ne 0) { throw "git command failed: git $($GitArgs -join ' ')" }
}

Push-Location $RepoPath
try {
  $dirty = (& git status --porcelain)
  if ($LASTEXITCODE -ne 0) { throw "git status failed" }
  if ($dirty) { throw "Working tree is not clean. Stop before upstream sync." }

  $remotes = @(& git remote)
  if (-not ($remotes -contains "upstream")) { throw "Missing upstream remote." }

  Run-Git @("fetch", "upstream", "--prune", "--tags")
  Run-Git @("remote", "set-head", "upstream", "-a")

  $head = (& git symbolic-ref refs/remotes/upstream/HEAD).Trim()
  $prefix = "refs/remotes/upstream/"
  if ($LASTEXITCODE -ne 0 -or -not $head.StartsWith($prefix)) { throw "Unable to determine upstream default branch." }
  $upstreamDefault = $head.Substring($prefix.Length)
  $mirrorBranch = "upstream/$upstreamDefault"
  $remoteTip = "refs/remotes/upstream/$upstreamDefault"
  $localMirror = "refs/heads/$mirrorBranch"

  & git show-ref --verify --quiet $localMirror
  if ($LASTEXITCODE -ne 0) { throw "Missing mirror branch '$mirrorBranch'." }

  Run-Git @("switch", $mirrorBranch)
  & git merge-base --is-ancestor $localMirror $remoteTip
  if ($LASTEXITCODE -ne 0) { throw "Mirror branch is not fast-forwardable to upstream." }
  Run-Git @("merge", "--ff-only", $remoteTip)

  if ($PushMirror -and ($remotes -contains "origin")) {
    Run-Git @("push", "origin", "refs/heads/${mirrorBranch}:refs/heads/${mirrorBranch}")
  }

  & git show-ref --verify --quiet "refs/heads/$DevBranch"
  if ($LASTEXITCODE -ne 0) { throw "Missing dev branch '$DevBranch'." }

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backup = "backup/$DevBranch-before-upstream-$stamp"
  $suffix = 2
  while ($true) {
    & git show-ref --verify --quiet "refs/heads/$backup"
    if ($LASTEXITCODE -ne 0) { break }
    $backup = "backup/$DevBranch-before-upstream-$stamp-$suffix"
    $suffix += 1
  }
  Run-Git @("branch", $backup, $DevBranch)

  Run-Git @("switch", $DevBranch)
  & git merge --no-edit $localMirror
  if ($LASTEXITCODE -ne 0) {
    Write-Output "Merge into $DevBranch has conflicts. Backup branch: $backup"
    exit 2
  }

  if ($PromoteMain) {
    & git show-ref --verify --quiet "refs/heads/$ReleaseBranch"
    if ($LASTEXITCODE -ne 0) { throw "Missing release branch '$ReleaseBranch'." }
    Run-Git @("switch", $ReleaseBranch)
    & git merge --no-edit $DevBranch
    if ($LASTEXITCODE -ne 0) {
      Write-Output "Promote to $ReleaseBranch failed. Backup branch: $backup"
      exit 2
    }
    Write-Output "Promoted $DevBranch to $ReleaseBranch. Backup branch: $backup. Mirror: $mirrorBranch."
  } else {
    Write-Output "Upstream merged into $DevBranch. Backup branch: $backup. Mirror: $mirrorBranch. Not promoted to $ReleaseBranch."
  }
} finally {
  Pop-Location
}
