set -e
# Exit immediately if any command exits with a non-zero status.
# This prevents the script from continuing in a broken state.

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

PKG_VERSION_DEVELOP=$(npm pkg get version --workspaces=false | tr -d \")

git checkout main

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
git merge main
git push
