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
