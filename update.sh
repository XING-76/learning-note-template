set -e
# Exit immediately if any command exits with a non-zero status.
# This prevents the script from continuing in a broken state.

# Require a clean working tree before touching branches.
# Two reasons, both hit in practice:
#   1. Every 'git checkout' below aborts on uncommitted changes. The last one
#      runs *after* main is already pushed, leaving the repo half-synced.
#   2. The 'git commit' after the squash merge would sweep in anything already
#      staged by an interrupted log.sh run, mislabelling it as a branch update.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: Working tree is not clean. Commit or stash changes first."
  git status --short
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "develop" ]; then
  if git show-ref --verify --quiet refs/heads/develop; then
    echo "Current branch is '$CURRENT_BRANCH'. Switching to 'develop'..."
    git checkout develop
  else
    echo "Error: 'develop' branch not found. Aborting."
    exit 1
  fi
fi

if [ -f .git/index.lock ]; then
  # Check if a Git lock file exists, which indicates another Git process
  # is running or previously crashed.
  echo "Git index.lock exists. Please resolve first."
  exit 1
  # Abort the script to avoid corrupting the repository state.
fi

# Sync 'develop' with the remote before reading its version.
# --ff-only fast-forwards when behind and is a no-op when merely ahead,
# but fails loudly on a real divergence instead of building on a stale base.
if ! git pull --ff-only origin develop; then
  echo "Error: 'develop' has diverged from origin/develop. Resolve manually first."
  exit 1
fi

PKG_VERSION_DEVELOP=$(npm pkg get version --workspaces=false | tr -d \")

git checkout main

# Same guard for 'main'. This is the step that previously broke the repo:
# without it, a stale local 'main' gets squash-merged and the push below is
# rejected as non-fast-forward, leaving a dangling commit mid-flow.
# Must run before reading the version, or PKG_VERSION_MASTER is stale too.
if ! git pull --ff-only origin main; then
  echo "Error: 'main' has diverged from origin/main. Resolve manually first."
  exit 1
fi

PKG_VERSION_MASTER=$(npm pkg get version --workspaces=false | tr -d \")

if [ "$PKG_VERSION_DEVELOP" != "$PKG_VERSION_MASTER" ]; then
  COMMIT_MSG="feat: version update-v${PKG_VERSION_DEVELOP}"
else
  COMMIT_MSG="feat: update branch"
fi

git merge --squash develop
git commit -m "$COMMIT_MSG"
git push

git checkout develop

# Guard again: origin/develop may have moved while this script was running.
if ! git pull --ff-only origin develop; then
  echo "Error: 'develop' has diverged from origin/develop. Resolve manually first."
  exit 1
fi

git merge main
git push
