# Learning Note Template（中文版）

> 這是 [`README.md`](../README.md) 的中文翻譯。專案的正式文件以英文版為準，
> 兩邊內容有出入時請以英文版為準並回報。
> 腳本註解的中文版在 [`work-log.zh-TW.md`](./work-log.zh-TW.md)。

所有流程都收在 `scripts/work-log.sh`，用 `npm start` 進互動選單即可。
三個任務（每日紀錄 / 發版 / 併回 `main`）仍可單獨執行。

### 一般用法

```bash
npm start
```

會先跑前置檢查、印出目前狀態，再讓你用上下鍵挑要做的事：

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

沒有終端機時（管線、CI）自動退回輸入數字的選單。

### 單項指令

| 指令 | 內容 |
|---|---|
| `npm run log` | 只寫每日紀錄 |
| `npm run release` | 只發版（patch +1） |
| `npm run update` | 只把 `develop` 併回 `main` |
| `npm run daily` | `log` → `update` |
| `npm run ship` | `log` → `release` → `update` |

### 演練

跑完所有檢查、印出「會執行什麼」，但不 commit、不 push：

```bash
npm run dry                     # 等同 npm start -- --dry-run，開選單但只演練
```

任何單項指令後面接 `-- --dry-run` 也可以：

```bash
npm run ship -- --dry-run
npm run update -- --dry-run
```

### Git Flow

日常兩條路徑，選單的第 2、3 項就是這兩條：

- **平日**：`log` → `update`
- **發版日**：`log` → `release` → `update`

### 規則

**前置檢查**（每次執行都會跑，任一項失敗就中止）

- 是 git repo、有 `origin`、沒有殘留的 `.git/index.lock`
- 不在 `develop` 上會自動切過去
- `git fetch` 後比對 upstream，落後就擋下要求先 pull
- 進 merge 步驟前，`main` 不能落後 `origin/main`

**每日紀錄** — `log.json` 記錄當天日期與當天的第幾次。同一天遞增，跨日歸 1。

```
feat: update daily log 2026.05.14.3
```

**發版** — `npm version patch --no-git-tag-version`，不打 tag。
當天已發過版會再確認一次。

```
feat: version release-v0.0.4
```

**併回 `main`** — `git merge --squash develop`，所以 `main` 是一版一個 commit 的乾淨歷史；
推完再切回 `develop` 把 `main` merge 回來。
commit message 依 `develop` 與 `main` 的版號是否相同而定：

```
feat: version update-v0.0.4        版號有變（當天發過版）
feat: update branch                版號沒變
```

**中途失敗** — 組合流程任一步失敗就整段中止，分支自動還原回 `develop`。
失敗那一步之後的任務改用上面的單項指令補跑。

### 需求

`bash` 與 `node`（選單與 JSON 讀寫需要，不是 POSIX `sh`）。
Windows 用 Git Bash、macOS / Linux 直接可跑。

### 設定

要調的東西都集中在 `scripts/work-log.sh` 開頭同一個區塊。
改每一行 `:-` 後面的值即可；同名環境變數會蓋過檔案裡填的值。

```bash
# ---------- Config ----------
WORK_LOG_TITLE=${WORK_LOG_TITLE:-}          # 狀態列標題，留空 -> 用 package.json 的 name
DEV_BRANCH=${DEV_BRANCH:-develop}           # 工作分支
MAIN_BRANCH=${MAIN_BRANCH:-main}            # 要併回去的分支
LOG_JSON=${LOG_JSON:-log.json}              # 每日紀錄的狀態檔
```

想要自己的標題就填第一行：

```bash
WORK_LOG_TITLE=${WORK_LOG_TITLE:-My learning notes}
```

留空的話，標題會退回讀 `package.json` 的 `name`。
