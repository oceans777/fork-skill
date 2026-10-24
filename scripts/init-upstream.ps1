param(
  [Parameter(Mandatory=$true)][string]$RepoPath,
  [Parameter(Mandatory=$true)][string]$UpstreamUrl,
  [string]$OriginUrl = "",
  [string]$DevBranch = "dev",
  [string]$ReleaseBranch = "main"
)

$ErrorActionPreference = "Stop"

function Run-Git([string[]]$GitArgs) {
  & git @GitArgs
  if ($LASTEXITCODE -ne 0) { throw "git command failed: git $($GitArgs -join ' ')" }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git is not installed or not available in PATH"
}

if (-not (Test-Path $RepoPath)) {
  if ([string]::IsNullOrWhiteSpace($OriginUrl)) {
    throw "RepoPath does not exist. Provide OriginUrl to clone the user's fork safely."
  }
  Run-Git @("clone", $OriginUrl, $RepoPath)
}

Push-Location $RepoPath
try {
  Run-Git @("rev-parse", "--is-inside-work-tree")

  $dirty = (& git status --porcelain)
  if ($LASTEXITCODE -ne 0) { throw "git status failed" }
  if ($dirty) { throw "Working tree is not clean. Commit or intentionally handle local changes first." }

  $remoteNames = @(& git remote)
  if ($OriginUrl) {
    if ($remoteNames -contains "origin") {
      Run-Git @("remote", "set-url", "origin", $OriginUrl)
    } else {
      Run-Git @("remote", "add", "origin", $OriginUrl)
    }
  }

  if ($remoteNames -contains "upstream") {
    Run-Git @("remote", "set-url", "upstream", $UpstreamUrl)
  } else {
    Run-Git @("remote", "add", "upstream", $UpstreamUrl)
  }

  Run-Git @("fetch", "upstream", "--prune", "--tags")
  Run-Git @("remote", "set-head", "upstream", "-a")

  $head = (& git symbolic-ref refs/remotes/upstream/HEAD).Trim()
  $prefix = "refs/remotes/upstream/"
  if ($LASTEXITCODE -ne 0 -or -not $head.StartsWith($prefix)) {
    throw "Unable to determine upstream default branch."
  }
  $upstreamDefault = $head.Substring($prefix.Length)
  $mirrorBranch = "upstream/$upstreamDefault"
  $remoteTip = "refs/remotes/upstream/$upstreamDefault"
  $localMirror = "refs/heads/$mirrorBranch"

  & git show-ref --verify --quiet $localMirror
  if ($LASTEXITCODE -eq 0) {
    Run-Git @("switch", $mirrorBranch)
    & git merge-base --is-ancestor $localMirror $remoteTip
    if ($LASTEXITCODE -ne 0) {
      throw "Local mirror branch contains divergence or commits not safely fast-forwardable to upstream."
    }
    Run-Git @("merge", "--ff-only", $remoteTip)
  } else {
    Run-Git @("switch", "-c", $mirrorBranch, $remoteTip)
  }

  & git show-ref --verify --quiet "refs/heads/$DevBranch"
  if ($LASTEXITCODE -ne 0) {
    Run-Git @("switch", "-c", $DevBranch, $localMirror)
  } else {
    Run-Git @("switch", $DevBranch)
  }

  & git show-ref --verify --quiet "refs/heads/$ReleaseBranch"
  if ($LASTEXITCODE -eq 0) {
    & git merge-base --is-ancestor "refs/heads/$ReleaseBranch" $localMirror
    if ($LASTEXITCODE -ne 0) {
      Write-Output "warning: $ReleaseBranch has commits that are not in $mirrorBranch. Leaving $ReleaseBranch untouched."
    }
  } else {
    Run-Git @("branch", $ReleaseBranch, $localMirror)
  }

  Write-Output "Initialized safely. mirror: $mirrorBranch; dev: $DevBranch; release: $ReleaseBranch"
} finally {
  Pop-Location
}
