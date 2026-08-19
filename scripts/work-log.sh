#!/usr/bin/env bash
# Work log — one entry point tying together daily log / release / merge back into main.
#
#   npm start                    interactive menu
#   npm run dry                  rehearsal only: run every check, but never commit or push
#
#   npm run log                  daily log only
#   npm run release              release only (patch +1)
#   npm run update               merge develop into main only
#
# The three tasks still run on their own; the menu only chains the common combinations
# so you do not have to type them in order three times by hand.
# A failure anywhere in a chain aborts the whole thing (set -e) and a trap restores the
# branch to develop; re-run whatever came after the failing step with the single commands.
#
# Nothing here is tied to a specific repo — everything adjustable is in the config block below.
#
# 中文註解版：docs/work-log.zh-TW.md

set -euo pipefail

# ---------- Config ----------
# The value after each `:-` is the default; edit it here. The matching environment
# variable overrides whatever is set here.

WORK_LOG_TITLE=${WORK_LOG_TITLE:-}          # status banner title, empty -> package.json name
DEV_BRANCH=${DEV_BRANCH:-develop}           # working branch
MAIN_BRANCH=${MAIN_BRANCH:-main}            # branch to merge into
LOG_JSON=${LOG_JSON:-log.json}              # daily log state file

DRY_RUN=false
ACTION=""

die() { printf '\n  %s\n\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'

  Usage: npm start [-- <action>] [-- --dry-run]
         npm run dry
         bash scripts/work-log.sh [<action>] [--dry-run]

    Actions (omit for the interactive menu):
      log        Daily log only
      release    Release only (patch +1)
      update     Merge develop into main only
      daily      log -> update
      ship       log -> release -> update

    --dry-run    Run every check and show what would happen,
                 but do not commit or push.

EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    log|release|update|daily|ship)
      [ -z "$ACTION" ] || die "Only one action can be given (got '$ACTION' and '$arg')."
      ACTION=$arg
      ;;
    *) usage; die "Unknown option: $arg" ;;
  esac
done

# ---------- Menu ----------
# Arrow keys + Enter when a terminal is attached; falls back to typing a number
# when there is none (pipes, CI, anything non-interactive).
#
# ⚠️ The result lands in the global `SELECTED` (1-based). **Do not read it via
#    $(menu ...)** — command substitution captures stdout, so the whole rendered
#    menu and its control codes get swallowed into the variable: the user sees
#    nothing and the case never matches.

SELECTED=0

# Always ANSI escapes, never tput: every tput call spawns a process, and a dozen
# processes per repaint is slow enough on Windows to show visible flicker.
ESC_HIDE_CURSOR=$'\033[?25l'
ESC_SHOW_CURSOR=$'\033[?25h'
ESC_CLEAR_EOL=$'\033[K'

menu_restore() {
  printf '%s' "$ESC_SHOW_CURSOR"
  trap - INT TERM
}

# Fallback: print numbers and let the user type one. Piped input takes this path too,
# which is what makes the script testable.
menu_plain() {
  local prompt=$1
  shift
  local options=("$@")
  local count=${#options[@]}
  local i reply

  while :; do
    printf '%s\n\n' "$prompt"
    for i in "${!options[@]}"; do
      printf '%d) %s\n' "$((i + 1))" "${options[$i]}"
    done
    printf '\nSelect [1-%d]: ' "$count"

    read -r reply || die "No input."
    if [[ $reply =~ ^[0-9]+$ ]] && [ "$reply" -ge 1 ] && [ "$reply" -le "$count" ]; then
      SELECTED=$reply
      printf '\n'
      return
    fi
    printf '\n  Invalid choice.\n\n'
  done
}

menu_keys() {
  local prompt=$1
  shift
  local options=("$@")
  local count=${#options[@]}
  local idx=0 i key frame line rendered=false

  printf '%s' "$ESC_HIDE_CURSOR"
  trap 'menu_restore; exit 130' INT TERM

  while :; do
    # Build the whole frame as one string and emit it in a single write. Separate
    # printfs make the screen visibly grow row by row, and clear-then-reprint flickers
    # worse — so this overwrites in place, with a clear-to-EOL at the end of every line
    # to wipe leftovers from a longer previous frame.
    printf -v frame '%s%s\n' "$prompt" "$ESC_CLEAR_EOL"
    for i in "${!options[@]}"; do
      # Selected and unselected markers are both 2 columns wide so the labels line up;
      # both sit flush against the start of the line.
      if [ "$i" -eq "$idx" ]; then
        printf -v line '\033[7m> %s \033[0m%s\n' "${options[$i]}" "$ESC_CLEAR_EOL"
      else
        printf -v line '· %s%s\n' "${options[$i]}" "$ESC_CLEAR_EOL"
      fi
      frame+=$line
    done

    # On a repaint, move the cursor back to the first line of this frame and draw over it
    if $rendered; then
      printf '\033[%dA' "$((count + 1))"
    fi
    rendered=true
    printf '%s' "$frame"

    IFS= read -rsn1 key || { menu_restore; die "No input."; }
    case $key in
      # Arrow keys are ESC + 2 more bytes; a bare ESC must not hang, hence the timeout
      $'\x1b')
        read -rsn2 -t 1 key || true
        case $key in
          '[A') idx=$(( (idx - 1 + count) % count )) ;;
          '[B') idx=$(( (idx + 1) % count )) ;;
        esac
        ;;
      '') break ;;                                    # Enter
      k|K) idx=$(( (idx - 1 + count) % count )) ;;
      j|J) idx=$(( (idx + 1) % count )) ;;
    esac
  done

  menu_restore
  printf '\n'
  SELECTED=$((idx + 1))
}

menu() {
  if [ -t 0 ] && [ -t 1 ]; then
    menu_keys "$@"
  else
    menu_plain "$@"
  fi
}

# ---------- Pre-flight checks ----------

git rev-parse --git-dir >/dev/null 2>&1 || die "Not a git repository."
cd "$(git rev-parse --show-toplevel)"

command -v node >/dev/null 2>&1 \
  || die "node not found. It is required to read and write $LOG_JSON and package.json."
git remote get-url origin >/dev/null 2>&1 || die "No 'origin' remote found."

# A lock file means another git process is still running, or the last one died half-way
[ ! -f .git/index.lock ] || die "Git index.lock exists. Please resolve it first."

git show-ref --verify --quiet "refs/heads/$DEV_BRANCH" \
  || die "'$DEV_BRANCH' branch not found. Aborting."

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$DEV_BRANCH" ]; then
  printf '\nCurrent branch is "%s". Switching to "%s"...\n' "$CURRENT_BRANCH" "$DEV_BRANCH"
  git checkout --quiet "$DEV_BRANCH"
fi

printf '\nFetching from origin...\n'
git fetch --quiet origin

# Block when behind upstream: every task below commits onto HEAD and then pushes, and
# from behind that is either rejected or manufactures a pointless merge. Being ahead
# just means it is not pushed yet, and it will go up along with the rest in a moment.
UPSTREAM_NOTE=""
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
  behind=$(git rev-list --count "HEAD..$upstream")
  ahead=$(git rev-list --count "$upstream..HEAD")
  [ "$behind" -eq 0 ] || die "Local $DEV_BRANCH is $behind commit(s) behind $upstream. Pull first."
  [ "$ahead" -eq 0 ] || UPSTREAM_NOTE="   ($ahead unpushed commit(s))"
fi

# ---------- Current state ----------

json_get() {
  # $1 file, $2 field
  node -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(data[process.argv[2]]));
  ' "$1" "$2"
}

[ -f "$LOG_JSON" ] || die "$LOG_JSON not found."
[ -f package.json ] || die "package.json not found."

LOG_DATE=$(json_get "$LOG_JSON" date)
LOG_VERSION=$(json_get "$LOG_JSON" version)
TODAY=$(date +'%Y.%m.%d')

if [ "$TODAY" != "$LOG_DATE" ]; then
  NEXT_LOG_N=1
else
  NEXT_LOG_N=$((LOG_VERSION + 1))
fi
NEXT_LOG="${TODAY}.${NEXT_LOG_N}"

PKG_VERSION=$(json_get package.json version)
IFS=. read -r V_MAJOR V_MINOR V_PATCH <<<"$PKG_VERSION"
# A prerelease version (0.0.1-beta.1) yields a patch field with a suffix attached, and
# doing arithmetic on that is an error that set -e turns into an abort. What is computed
# here is only the "roughly what it will become" display value — the real version is
# whatever npm writes back.
V_PATCH=${V_PATCH%%[!0-9]*}
NEXT_PKG="$V_MAJOR.$V_MINOR.$(( ${V_PATCH:-0} + 1 ))"

# Falls back to package.json name only when the config block at the top of the file left
# the title empty (and no environment variable was given). This cannot move up into that
# block: it needs json_get defined and package.json confirmed to exist.
TITLE=${WORK_LOG_TITLE:-$(json_get package.json name)}

COMMIT=$(git log -1 --format='%h  %s')
RELEASED_TODAY=$(git log --since=midnight --pretty=%s | grep -c 'version release' || true)

DIRTY=$(git status --porcelain)

printf '\n%s\n\n' "$TITLE"
printf '  Branch      : %s%s\n' "$DEV_BRANCH" "$UPSTREAM_NOTE"
printf '  Commit      : %s\n' "$COMMIT"
printf '  Daily log   : %s.%s   ->   %s\n' "$LOG_DATE" "$LOG_VERSION" "$NEXT_LOG"
printf '  Version     : %s        ->   %s\n' "$PKG_VERSION" "$NEXT_PKG"
if [ "$RELEASED_TODAY" -gt 0 ]; then
  printf '  Released    : ⚠️  already released %s time(s) today\n' "$RELEASED_TODAY"
else
  printf '  Released    : not yet today\n'
fi
if [ -n "$DIRTY" ]; then
  printf '  Changes     : %s file(s) pending\n' "$(printf '%s\n' "$DIRTY" | wc -l | tr -d ' ')"
else
  printf '  Changes     : working tree clean\n'
fi
printf '\n'

# ---------- Tasks ----------

show_dirty() {
  if [ -z "$DIRTY" ]; then
    printf '  Working tree is clean — nothing new to record.\n'
    return
  fi
  printf '  Files to be committed:\n\n'
  printf '%s\n' "$DIRTY" | sed 's/^/    /'
  printf '\n'
}

require_clean() {
  if $DRY_RUN; then
    printf '  (dry run — skipping the clean working tree check)\n'
    return
  fi
  [ -z "$(git status --porcelain)" ] \
    || die "Working tree is not clean. Run the daily log first, or commit/stash your changes."
}

task_log() {
  printf '\n── Daily log ──────────────────────────────────\n\n'
  show_dirty

  local msg="feat: update daily log ${NEXT_LOG}"

  if $DRY_RUN; then
    printf '  would write %s : date=%s version=%s\n' "$LOG_JSON" "$TODAY" "$NEXT_LOG_N"
    printf '  would run   : git add .\n'
    printf '  would run   : git commit -m "%s"\n' "$msg"
    printf '  would run   : git push\n'
    return
  fi

  node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    data.date = process.argv[2];
    data.version = Number(process.argv[3]);
    fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
  ' "$LOG_JSON" "$TODAY" "$NEXT_LOG_N"

  git add .
  git commit -m "$msg"
  git push
  printf '\n  Logged %s\n' "$NEXT_LOG"
}

task_release() {
  printf '\n── Release ────────────────────────────────────\n\n'

  if [ "$RELEASED_TODAY" -gt 0 ]; then
    printf '  ⚠️  A version has already been released today (%s time(s)).\n\n' "$RELEASED_TODAY"
    menu "Release another version today?" \
      "Yes, release $NEXT_PKG" \
      "No, abort"
    case "$SELECTED" in
      1) ;;
      2) die "Release aborted by user." ;;
      *) die "Unexpected selection: $SELECTED" ;;
    esac
  fi

  local msg="feat: version release-v${NEXT_PKG}"

  if $DRY_RUN; then
    printf '  would run   : npm version patch --no-git-tag-version   (%s -> %s)\n' \
      "$PKG_VERSION" "$NEXT_PKG"
    printf '  would run   : git add .\n'
    printf '  would run   : git commit -m "%s"\n' "$msg"
    printf '  would run   : git push\n'
    return
  fi

  npm version patch --no-git-tag-version >/dev/null

  # Trust the version npm actually wrote back, not the one computed above
  local released
  released=$(json_get package.json version)
  msg="feat: version release-v${released}"

  git add .
  git commit -m "$msg"
  git push
  printf '\n  Released v%s\n' "$released"
}

# On failure, put the user back on develop instead of stranding them on main
restore_branch() {
  local current
  current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$DEV_BRANCH")
  if [ "$current" != "$DEV_BRANCH" ]; then
    printf '\n  Restoring branch: %s -> %s\n' "$current" "$DEV_BRANCH"
    git checkout --quiet "$DEV_BRANCH" || true
  fi
}

task_update() {
  printf '\n── Merge into %s ────────────────────────────\n\n' "$MAIN_BRANCH"

  git show-ref --verify --quiet "refs/heads/$MAIN_BRANCH" \
    || die "'$MAIN_BRANCH' branch not found. Aborting."

  # main has to keep up with origin too: the pre-flight only verified $DEV_BRANCH's
  # upstream. Squashing into a stale main gets the push rejected, leaving behind a commit
  # that cannot go up and a half-synced repo. The fetch above already ran, so this
  # compares against a fresh remote ref.
  if git show-ref --verify --quiet "refs/remotes/origin/$MAIN_BRANCH"; then
    local behind_main
    behind_main=$(git rev-list --count "$MAIN_BRANCH..origin/$MAIN_BRANCH")
    [ "$behind_main" -eq 0 ] \
      || die "Local $MAIN_BRANCH is $behind_main commit(s) behind origin/$MAIN_BRANCH. Pull first."
  fi

  # The tree must be clean before switching branches, or uncommitted changes ride along to main
  require_clean

  # Read main's version without checking it out, so the commit message is decided
  # before any branch is touched
  local version_main version_develop msg
  version_develop=$(json_get package.json version)
  version_main=$(git show "$MAIN_BRANCH:package.json" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).version))')

  if [ "$version_develop" != "$version_main" ]; then
    msg="feat: version update-v${version_develop}"
  else
    msg="feat: update branch"
  fi

  if $DRY_RUN; then
    printf '  %s is at v%s, %s is at v%s\n\n' \
      "$DEV_BRANCH" "$version_develop" "$MAIN_BRANCH" "$version_main"
    printf '  would run   : git checkout %s\n' "$MAIN_BRANCH"
    printf '  would run   : git merge --squash %s\n' "$DEV_BRANCH"
    printf '  would run   : git commit -m "%s"\n' "$msg"
    printf '  would run   : git push\n'
    printf '  would run   : git checkout %s\n' "$DEV_BRANCH"
    printf '  would run   : git merge %s\n' "$MAIN_BRANCH"
    printf '  would run   : git push\n'
    return
  fi

  trap restore_branch EXIT

  git checkout "$MAIN_BRANCH"
  git merge --squash "$DEV_BRANCH"

  if git diff --cached --quiet; then
    printf '\n  Nothing to merge — %s is already up to date.\n' "$MAIN_BRANCH"
  else
    git commit -m "$msg"
    git push
  fi

  git checkout "$DEV_BRANCH"
  git merge "$MAIN_BRANCH"
  git push

  trap - EXIT
  printf '\n  Merged into %s (%s)\n' "$MAIN_BRANCH" "$msg"
}

# ---------- Decide which tasks to run ----------

CHAIN=()

case "$ACTION" in
  log)     CHAIN=(log) ;;
  release) CHAIN=(release) ;;
  update)  CHAIN=(update) ;;
  daily)   CHAIN=(log update) ;;
  ship)    CHAIN=(log release update) ;;
  "")
    menu "Select what to do:" \
      "Daily log                     log" \
      "Daily log + merge to main     log -> update" \
      "Release + merge to main       log -> release -> update" \
      "Merge to main only            update" \
      "Release only                  release" \
      "Abort"

    case "$SELECTED" in
      1) CHAIN=(log) ;;
      2) CHAIN=(log update) ;;
      3) CHAIN=(log release update) ;;
      4) CHAIN=(update) ;;
      5) CHAIN=(release) ;;
      6) printf '\n  Aborted.\n\n'; exit 0 ;;
      *) die "Unexpected selection: $SELECTED" ;;
    esac

    printf '  Plan : %s\n\n' "${CHAIN[*]}"
    if ! $DRY_RUN; then
      menu "Proceed?" \
        "Yes, run it" \
        "No, abort"
      case "$SELECTED" in
        1) ;;
        2) printf '\n  Aborted. Nothing was committed or pushed.\n\n'; exit 0 ;;
        *) die "Unexpected selection: $SELECTED" ;;
      esac
    fi
    ;;
esac

if $DRY_RUN; then
  printf 'Dry run — nothing will be committed or pushed.\n'
fi

for task in "${CHAIN[@]}"; do
  "task_$task"
done

printf '\n  Done: %s\n\n' "${CHAIN[*]}"
