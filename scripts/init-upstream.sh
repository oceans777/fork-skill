#!/usr/bin/env bash
# Local mirror branches are named upstream/<default> and collide with
# refs/remotes/upstream/<default>. Merge and ancestry checks use full refs.
set -euo pipefail

REPO_PATH="${1:?usage: init-upstream.sh <repo-path> <upstream-url> [origin-url]}"
UPSTREAM_URL="${2:?usage: init-upstream.sh <repo-path> <upstream-url> [origin-url]}"
ORIGIN_URL="${3:-}"
DEV_BRANCH="${DEV_BRANCH:-dev}"
RELEASE_BRANCH="${RELEASE_BRANCH:-${MAIN_BRANCH:-main}}"

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }

if [[ ! -d "$REPO_PATH" ]]; then
  [[ -n "$ORIGIN_URL" ]] || { echo "repo path does not exist; provide origin URL" >&2; exit 1; }
  git clone "$ORIGIN_URL" "$REPO_PATH"
fi

cd "$REPO_PATH"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is not clean" >&2; exit 1; }

if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "$UPSTREAM_URL"
else
  git remote add upstream "$UPSTREAM_URL"
fi

if [[ -n "$ORIGIN_URL" ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$ORIGIN_URL"
  else
    git remote add origin "$ORIGIN_URL"
  fi
fi

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

if git show-ref --verify --quiet "$LOCAL_MIRROR"; then
  git switch "$MIRROR_BRANCH"
  git merge-base --is-ancestor "$LOCAL_MIRROR" "$REMOTE_TIP" || {
    echo "local mirror branch diverged; refusing destructive repair" >&2
    exit 2
  }
  git merge --ff-only "$REMOTE_TIP"
else
  git switch -c "$MIRROR_BRANCH" "$REMOTE_TIP"
fi

if git show-ref --verify --quiet "refs/heads/$DEV_BRANCH"; then
  git switch "$DEV_BRANCH"
else
  git switch -c "$DEV_BRANCH" "$LOCAL_MIRROR"
fi

if git show-ref --verify --quiet "refs/heads/$RELEASE_BRANCH"; then
  if ! git merge-base --is-ancestor "refs/heads/$RELEASE_BRANCH" "$LOCAL_MIRROR"; then
    echo "warning: $RELEASE_BRANCH has commits that are not in $MIRROR_BRANCH. Leaving $RELEASE_BRANCH untouched. Move custom work onto $DEV_BRANCH manually; this script will not reset it." >&2
  fi
else
  git branch "$RELEASE_BRANCH" "$LOCAL_MIRROR"
fi

echo "initialized safely: mirror=$MIRROR_BRANCH dev=$DEV_BRANCH release=$RELEASE_BRANCH"
