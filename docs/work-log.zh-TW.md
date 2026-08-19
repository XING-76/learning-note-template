# `scripts/work-log.sh` 註解中文版

> 腳本本身的註解一律英文，這份是同一批註解的中文對照，依檔案順序排列。
> 改動腳本註解時請一併更新這裡。README 的中文版在 [`README.zh-TW.md`](./README.zh-TW.md)。

## 檔頭

```bash
#!/usr/bin/env bash
```

Work log — 一個入口把「每日紀錄 / 發版 / 併回 main」串起來。

```
npm start                    互動選單
npm run dry                  只演練：跑完所有檢查，但不 commit、不 push

npm run log                  只寫每日紀錄
npm run release              只發版（patch +1）
npm run update               只把 develop 併回 main
```

三個任務仍可單獨執行；選單只是把常走的組合串起來，省得手動照順序打三次。
組合流程中途失敗就整段中止（`set -e`），分支由 trap 還原回 develop，
失敗那一步之後的任務改用上面的單項指令補跑即可。

這支腳本不綁任何特定 repo，要調的東西都在下面的設定區。

## 設定區

```bash
# ---------- Config ----------
WORK_LOG_TITLE=${WORK_LOG_TITLE:-}
DEV_BRANCH=${DEV_BRANCH:-develop}
MAIN_BRANCH=${MAIN_BRANCH:-main}
LOG_JSON=${LOG_JSON:-log.json}
```

每一行 `:-` 後面就是預設值，直接改這裡即可；同名環境變數會蓋過這裡的值。

| 變數 | 用途 |
|---|---|
| `WORK_LOG_TITLE` | 狀態列標題，留空 -> 自動用 `package.json` 的 `name` |
| `DEV_BRANCH` | 工作分支 |
| `MAIN_BRANCH` | 要併回去的分支 |
| `LOG_JSON` | 每日紀錄的狀態檔 |

## 選單

```bash
# ---------- Menu ----------
SELECTED=0
```

有終端機時用上下鍵 ＋ Enter；沒有時（管線、CI、非互動）退回輸入數字。

> ⚠️ 結果放在全域 `SELECTED`（1 起算），**不要用 `$(menu ...)` 取值**——
> 命令替換捕捉的是 stdout，會把整個選單畫面連同控制碼一起吃進變數裡，
> 使用者什麼都看不到，而且 `case` 永遠比不中。

```bash
ESC_HIDE_CURSOR=$'\033[?25l'
ESC_SHOW_CURSOR=$'\033[?25h'
ESC_CLEAR_EOL=$'\033[K'
```

一律用 ANSI 控制碼，不用 `tput`：`tput` 每次呼叫都要 spawn 一個行程，
一次重繪十幾個行程在 Windows 上慢到看得見閃爍。

```bash
menu_plain() {
```

退回版：印編號讓人輸入。管線餵輸入也走這條，腳本才測得起來。

```bash
printf -v frame '%s%s\n' "$prompt" "$ESC_CLEAR_EOL"
```

整張畫面先組成一個字串再一次輸出。分次 `printf` 會讓人看到畫面一格一格長出來，
而「先清空再重印」更會閃——所以這裡是直接覆蓋，每行結尾補 clear-to-EOL
把上一輪較長的殘字擦掉。

```bash
if [ "$i" -eq "$idx" ]; then
```

選中與未選中的標記都是 2 個字寬，文字才會對齊；兩者都貼齊行頭。

```bash
if $rendered; then
  printf '\033[%dA' "$((count + 1))"
fi
```

重繪時把游標移回這張畫面的第一行，直接蓋上去。

```bash
$'\x1b')
  read -rsn2 -t 1 key || true
```

方向鍵是 ESC ＋ 2 碼；只按 ESC 不要卡住，給個逾時。

## 前置檢查

```bash
[ ! -f .git/index.lock ] || die "Git index.lock exists. Please resolve it first."
```

lock 檔存在代表另一個 git 行程還在跑，或上次跑到一半掛了。

```bash
UPSTREAM_NOTE=""
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
```

落後 upstream 就擋掉：接下來每個任務都會 commit 在 HEAD 上再 push，
落後的情況下不是被拒就是製造出不必要的 merge。領先只是還沒推，等一下會一起推上去。

## 目前狀態

```bash
json_get() {
  # $1 file, $2 field
```

`$1` 檔案、`$2` 欄位。

```bash
V_PATCH=${V_PATCH%%[!0-9]*}
NEXT_PKG="$V_MAJOR.$V_MINOR.$(( ${V_PATCH:-0} + 1 ))"
```

預發布版號（`0.0.1-beta.1`）切出來的 patch 會帶後綴，直接做算術會讓 `set -e` 中止。
這裡算的只是「等一下大概會變成幾」的顯示值，真正的版號以 npm 寫回的為準。

```bash
TITLE=${WORK_LOG_TITLE:-$(json_get package.json name)}
```

檔案開頭的設定區沒填標題（也沒給環境變數）才退回 `package.json` 的 `name`。
這段不能搬去設定區：要等 `json_get` 定義好、`package.json` 也確認存在才讀得到。

## 任務

```bash
npm version patch --no-git-tag-version >/dev/null
local released
released=$(json_get package.json version)
```

以 npm 實際寫回的版號為準，不要相信自己算的那個。

```bash
restore_branch() {
```

失敗時把人送回 develop，別讓他停在 main 上。

```bash
if git show-ref --verify --quiet "refs/remotes/origin/$MAIN_BRANCH"; then
```

main 也要跟得上 origin：前置檢查只驗了 `$DEV_BRANCH` 的 upstream。
落後的 main 被 squash 進去之後 push 會被拒，留下一個推不上去的 commit
跟一半同步的 repo。前面已經 fetch 過，這裡比的是新鮮的 remote ref。

```bash
require_clean
```

切分支前必須乾淨，否則未提交的變更會被一起帶到 main。

```bash
local version_main version_develop msg
version_develop=$(json_get package.json version)
version_main=$(git show "$MAIN_BRANCH:package.json" | node -e '...')
```

不切過去就先讀出 main 的版號，commit message 在動任何分支之前就決定好。
