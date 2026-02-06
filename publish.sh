set -e

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