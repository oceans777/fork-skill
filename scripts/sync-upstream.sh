#!/usr/bin/env bash
# See init-upstream.sh: upstream/<default> is both a local branch and a remote-tracking ref.
set -euo pipefail

REPO_PATH="${1:?usage: sync-upstream.sh <repo-path>}"
DEV_BRANCH="${DEV_BRANCH:-dev}"
RELEASE_BRANCH="${RELEASE_BRANCH:-${MAIN_BRANCH:-main}}"
PUSH_MIRROR="${PUSH_MIRROR:-0}"
PROMOTE_MAIN="${PROMOTE_MAIN:-0}"

cd "$REPO_PATH"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is not clean" >&2; exit 1; }

git remote get-url upstream >/dev/null 2>&1 || { echo "missing upstream remote" >&2; exit 1; }
git fetch upstream --prune --tags
git remote set-head upstream -a
HEAD_REF="$(git symbolic-ref refs/remotes/upstream/HEAD)"
case "$HEAD_REF" in
  refs/remotes/upstream/*) UPSTREAM_DEFAULT="${HEAD_REF#refs/remotes/upstream/}" ;;
  *) echo "unable to determine upstream default branch: $HEAD_REF" >&2; exit 1 ;;
esac
MIRROR_BRANCH="upstream/${UPSTREAM_DEFAULT}"
REMOTE_TIP="refs/remotes/upstream/${UPSTREAM_DEFAULT}"
LOCAL_MIRROR="refs/heads/${MIRROR_BRANCH}"

git show-ref --verify --quiet "$LOCAL_MIRROR" || {
  echo "missing mirror branch $MIRROR_BRANCH" >&2
  exit 1
}

git switch "$MIRROR_BRANCH"
git merge-base --is-ancestor "$LOCAL_MIRROR" "$REMOTE_TIP" || {
  echo "mirror branch is not fast-forwardable to upstream; refusing destructive repair" >&2
  exit 2
}
git merge --ff-only "$REMOTE_TIP"

if [[ "$PUSH_MIRROR" == "1" ]] && git remote get-url origin >/dev/null 2>&1; then
  git push origin "refs/heads/${MIRROR_BRANCH}:refs/heads/${MIRROR_BRANCH}"
fi

git show-ref --verify --quiet "refs/heads/$DEV_BRANCH" || {
  echo "missing dev branch $DEV_BRANCH" >&2
  exit 1
}
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="backup/${DEV_BRANCH}-before-upstream-${STAMP}"
suffix=2
while git show-ref --verify --quiet "refs/heads/$BACKUP"; do
  BACKUP="backup/${DEV_BRANCH}-before-upstream-${STAMP}-${suffix}"
  suffix=$((suffix + 1))
done
git branch "$BACKUP" "$DEV_BRANCH"
git switch "$DEV_BRANCH"
if ! git merge --no-edit "$LOCAL_MIRROR"; then
  echo "merge conflicts detected; backup branch: $BACKUP" >&2
  exit 2
fi

if [[ "$PROMOTE_MAIN" == "1" ]]; then
  git show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH" || {
    echo "missing release branch $RELEASE_BRANCH" >&2
    exit 1
  }
  git switch "$RELEASE_BRANCH"
  if ! git merge --no-edit "$DEV_BRANCH"; then
    echo "promote to $RELEASE_BRANCH failed; dev backup: $BACKUP" >&2
    exit 2
  fi
  echo "promoted $DEV_BRANCH to $RELEASE_BRANCH; backup=$BACKUP; mirror=$MIRROR_BRANCH"
else
  echo "upstream merged into $DEV_BRANCH; backup=$BACKUP; mirror=$MIRROR_BRANCH; not promoted to $RELEASE_BRANCH"
fi
