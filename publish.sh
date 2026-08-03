set -e

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

# Sync with the remote before bumping the version and committing.
# Otherwise a stale local 'develop' produces a commit that the final push rejects.
if ! git pull --ff-only origin develop; then
  echo "Error: 'develop' has diverged from origin/develop. Resolve manually first."
  exit 1
fi

# Check if a version has already been released today
if git log --since=midnight --pretty=%s | grep -q "version release"; then
  printf "⚠️  %s\n" "A version has already been released today."

  read -p "Do you want to release another version today? (y/N): " CONFIRM

  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Release aborted by user."
    exit 0
  fi
fi

npm version patch --no-git-tag-version

PKG_VERSION=$(npm pkg get version --workspaces=false | tr -d \")

git add .
git commit -m "feat: version release-v${PKG_VERSION}"
git push