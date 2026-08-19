# Learning Note Template

Every step lives in `scripts/work-log.sh`. Run `npm start` for the interactive menu.
The three tasks (daily log / release / merge back into `main`) can still be run on their own.

繁體中文：[`docs/README.zh-TW.md`](docs/README.zh-TW.md)　·　腳本註解中文對照：[`docs/work-log.zh-TW.md`](docs/work-log.zh-TW.md)

### Normal use

```bash
npm start
```

It runs the pre-flight checks, prints the current state, then lets you pick with the arrow keys:

```
learning-note-template

  Branch      : develop
  Commit      : 8b7db53  Merge branch 'main' into develop
  Daily log   : 2026.05.14.2   ->   2026.05.14.3
  Version     : 0.0.3          ->   0.0.4
  Released    : not yet today
  Changes     : 4 file(s) pending

Select what to do:

  · Daily log                     log
  > Daily log + merge to main     log -> update
  · Release + merge to main       log -> release -> update
  · Merge to main only            update
  · Release only                  release
  · Abort
```

Without a TTY (pipes, CI) it falls back to a numbered menu you type into.

### Single commands

| Command | What it does |
|---|---|
| `npm run log` | Daily log only |
| `npm run release` | Release only (patch +1) |
| `npm run update` | Merge `develop` into `main` only |
| `npm run daily` | `log` → `update` |
| `npm run ship` | `log` → `release` → `update` |

### Dry run

Runs every check and prints what *would* happen, but never commits or pushes:

```bash
npm run dry                     # same as npm start -- --dry-run: menu, rehearsal only
```

Any single command takes `-- --dry-run` too:

```bash
npm run ship -- --dry-run
npm run update -- --dry-run
```

### Git Flow

Two everyday paths — items 2 and 3 in the menu:

- **Normal day**: `log` → `update`
- **Release day**: `log` → `release` → `update`

### Rules

**Pre-flight checks** (run every time; any failure aborts)

- Is a git repo, has an `origin`, no stale `.git/index.lock`
- Switches to `develop` automatically if you are elsewhere
- Compares against upstream after `git fetch`; being behind is blocked, pull first
- `main` must not be behind `origin/main` before the merge step

**Daily log** — `log.json` holds the date and which run of that day it is.
It increments within a day and resets to 1 on a new day.

```
feat: update daily log 2026.05.14.3
```

**Release** — `npm version patch --no-git-tag-version`, no tag.
If a version was already released today it asks for confirmation.

```
feat: version release-v0.0.4
```

**Merge into `main`** — `git merge --squash develop`, so `main` keeps a clean
one-commit-per-version history; after pushing it switches back to `develop` and merges
`main` in. The commit message depends on whether `develop` and `main` are on the same version:

```
feat: version update-v0.0.4        version changed (released today)
feat: update branch                version unchanged
```

**Failure mid-chain** — any failing step aborts the whole chain and the branch is
restored to `develop`. Re-run the remaining steps with the single commands above.

### Requirements

`bash` and `node` (needed for the menu and for reading/writing JSON — not POSIX `sh`).
Use Git Bash on Windows; macOS / Linux work as-is.

### Configuration

Everything adjustable sits in one block at the top of `scripts/work-log.sh`.
Edit the value after `:-` on each line; the matching environment variable overrides it.

```bash
# ---------- Config ----------
WORK_LOG_TITLE=${WORK_LOG_TITLE:-}          # status banner title, empty -> package.json name
DEV_BRANCH=${DEV_BRANCH:-develop}           # working branch
MAIN_BRANCH=${MAIN_BRANCH:-main}            # branch to merge into
LOG_JSON=${LOG_JSON:-log.json}              # daily log state file
```

So a repo that wants its own banner fills in the first line:

```bash
WORK_LOG_TITLE=${WORK_LOG_TITLE:-My learning notes}
```

Leave it empty and the banner falls back to `name` from `package.json`.
