set -e
# Exit immediately if any command exits with a non-zero status.
# Without this, a failed sed or commit would still fall through to 'git push'.

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "develop" ]; then
  if git show-ref --verify --quiet refs/heads/develop; then
    echo "Current branch is '$CURRENT_BRANCH'. Switching to 'develop'..."
    git checkout develop || { echo "Error: Failed to checkout 'develop'."; exit 1; }
  else
    echo "Error: 'develop' branch not found. Aborting."
    exit 1
  fi
fi

CURRENT_DATE=$(date +'%Y.%m.%d')

LOG_JSON="log.json"
LOG_DATE=$(grep -oP '"date":\s*"\K[0-9.]+(?=")' $LOG_JSON)
LOG_VERSION=$(grep -oP '"version":\s*\K[0-9]+' $LOG_JSON)

if [ "$CURRENT_DATE" != "$LOG_DATE" ]; then
  NEW_VERSION=1
else
  NEW_VERSION=$((LOG_VERSION + 1))
fi

# Auto-detect the operating system and choose the appropriate sed command parameters
OS=$(uname)
if [[ "$OS" == "Darwin" ]]; then
  # macOS uses sed -i ''
  SED_CMD="sed -i ''"
elif [[ "$OS" == "Linux" ]]; then
  # Linux uses sed -i
  SED_CMD="sed -i"
elif [[ "$OS" == "MINGW"* || "$OS" == "CYGWIN"* ]]; then
  # Windows (Git Bash/Cygwin) uses sed -i
  SED_CMD="sed -i"
else
  echo "Unsupported operating system: $OS"
  exit 1
fi

# Use sed to update the date and version in log.json
$SED_CMD "s|\"date\": \"$LOG_DATE\"|\"date\": \"$CURRENT_DATE\"|" $LOG_JSON
$SED_CMD "s|\"version\": $LOG_VERSION|\"version\": $NEW_VERSION|" $LOG_JSON

LOG_VERSION="${CURRENT_DATE}.${NEW_VERSION}"

git add .
git commit -m "feat: update daily log ${LOG_VERSION}"
git push
