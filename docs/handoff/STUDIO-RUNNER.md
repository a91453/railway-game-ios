# STUDIO-RUNNER：工作室自己的啟動程式（不靠 Orchestra）

工單是遊戲規劃在 #2118 開的 STUDIO-RUNNER（2026-11-16 21:55Z，評分以那則為準，**Mac 本機**）。
這份是給接這張單的 session 與作者的規劃，2026-11-17 改寫：

- 作者 2026-11-17：「那我可以不要靠orchestra嗎 自己做」「其實就跟你說的一樣 安全性」。
  所以**整個工作室改成只用自家的 `studio.py` 加新的啟動程式**，不再升級 Orchestra（原本建議的 0.32 與 Board 不用了）。
- 時機：等 Ultra 週額度重置（**11-17 台灣時間 22:00**）之後再做。改到一半額度斷掉，工作室會卡在一半的狀態。
- 工作室資料夾以下寫成 `$STUDIO`（家目錄裡名稱以 `-Studio` 結尾的那個資料夾，第 0 步會設好）。

## 0. 工作量：不是重寫，大半已經有了

`studio.py`（約 2,100 行）與它的測試（約 1,400 行）本來就是自己的，Orchestra 只負責「開 AI」和「看畫面」。要新寫的只有這兩塊，外加一個約 400–600 行的 `runner.py` 把它們接起來。估計一個實作 session、一到兩個晚上（不含沙盒驗收）。

| 項目 | 狀態 | 規模 | 沿用的現有程式 |
| --- | --- | --- | --- |
| 認領、帳本、交接單、三輪上限、Blender 鎖、git hook | **已有** | 不動 | `studio.py` claim／handoff／hello／blender、hook |
| 背景開一個 AI、記程序、停掉 | **已有** | 不動 | `studio.py agent`、`_supervise`、`stop` |
| 換人接手的開場、待處理的單、列出未 commit 的改動 | **已有** | 不動 | `studio.py takeover`（RUN-C10 已在 Mac 驗收過） |
| 開工一行做完、選誰坐哪個位置 | **已有** | 小改：把「開 Orchestra session」換成呼叫 `runner.py start` | `studio.py start`、`kickoff --preset/--use` |
| 檢查帳號登入 | **已有** | 小改：路徑從 `~/.orchestra/profiles` 改讀 `accounts.json` | `studio.py doctor` 的 `doctor_profiles` |
| 認出卡住的角色 | **已有** | 小改：改看記錄檔 | `studio.py waiting` |
| session 身分（取代 `ORCHESTRA_SESSION_ID`） | 小改 | 約 20 行 | `in_ai_session`、`hello`、`roster` |
| 進度檔（取代 Orchestra Scratchpad） | 小改 | 約 10 行加角色檔各一句 | `takeover` 的開場、`prompts/` |
| 帳號資料夾與登入 | 新做，但只是指令 | 作者今晚 5 個登入（第 6 節） | 官方 `claude auth login`、`codex login` |
| `accounts.json`、`runner.py accounts` | **新寫** | 約 50 行 | — |
| 讀額度、照週平均分配（`quota`） | **新寫** | 約 120 行 | 格式要先量（第 6 節第 4 步） |
| 開 session、看記錄檔、認出額度用完（`start`、主迴圈） | **新寫** | 約 200 行 | 包在 `studio.py agent` 外面 |
| 自動接手：先 commit、`takeover`、換帳號重開 | **新寫** | 約 80 行 | 呼叫現有 `takeover` |
| 狀態表 `board`、通知 | **新寫** | 約 80 行 | 讀 `studio.py status` 已有的資料 |
| 測試 | **新寫** | 約 300 行 | 照 `tests.py` 現有的寫法與沙盒 |
| `conductor.py`（總機） | 不用了 | 留著不刪，順了再拿掉 | — |

## 1. 安全原則（先讀，實作時每一條都要守）

1. **不用第三方工具碰帳號登入。** 只用官方的 `claude`（Claude Code）與 `codex`（Codex CLI）登入、登出、看狀態。不裝任何代管登入或讀額度的工具，Orchestra 也退出帳號這一塊。
2. **憑證只留在各帳號自己的設定資料夾與 macOS 鑰匙圈。** 啟動程式只設 `CLAUDE_CONFIG_DIR`、`CODEX_HOME` 兩個環境變數，讓官方 CLI 自己去讀；程式**不讀、不複製、不印、不記錄**任何 token、`.credentials.json`、`auth.json` 或鑰匙圈項目。
3. **額度只從 CLI 自己吐出的輸出讀**（第 4 節），不拿 token 去打任何網址。讀不到就讓作者手動填，不繞路。
4. **不寫進 repo、不上傳。** 帳號資料夾、記錄檔、`accounts.json` 都在 `$STUDIO` 底下，不在任何 git worktree 裡；記錄檔進 `$STUDIO/runs/`，不 commit。記錄檔若被 CLI 印進 email，`board` 只顯示帳號名（`ultra`、`max`、`pro`），不顯示 email。
5. **權限不全開。** 背景跑的 AI 不用 `--dangerously-skip-permissions`／`--yolo`；照各帳號資料夾裡現有的 `settings.json` 允許與禁止清單（`studio.py doctor` 檢查的那份），Codex 用 `--sandbox workspace-write`。`git push`、`gh`、`sudo`、改 `$STUDIO/accounts` 一律禁止。
6. **作者的決定留給作者。** `answer`（替作者回答）、push、合併、受保護路徑照舊只有作者能做；啟動程式只做「換帳號接手」這件原本要作者跑 `takeover` 的事，而且是作者自己在終端機開的啟動程式才行（第 5.3 節）。

## 2. 原本靠 Orchestra 的地方，各自換成什麼

| Orchestra 提供的 | 換成 | 在哪裡做 |
| --- | --- | --- |
| Profile（每個帳號一個設定資料夾，登入按鈕） | `$STUDIO/accounts/<帳號>/claude`、`.../codex` 自己建，作者用官方 CLI 登入（第 6 節第 1–3 步）；對照表 `$STUDIO/accounts.json` | 新 `runner.py accounts` |
| 在 worktree 開一個 AI session | `claude -p`（`--output-format stream-json --verbose`）或 `codex exec --json`，`cwd` 是那個角色的 worktree；經 `studio.py agent` 包起來，所以 `STUDIO_MANAGED_AGENT=1`、程序紀錄都照舊 | `runner.py start` |
| 選模型與強度 | 命令列直接帶：Claude `--model`（強度用 `--effort`；不支援就寫進那帳號 `settings.json`，實作先查），Codex `-m` 與 `-c model_reasoning_effort=…` | `runner.py start` |
| 接著同一段對話（Resume） | Claude `--resume <session_id>`（從 stream-json 第一行取得）、Codex `codex exec resume <id>` | `runner.py` 內部 |
| Scratchpad（`orchestra scratchpad read`） | `$STUDIO/reports/<任務>/<角色>-progress.md`，角色檔改成寫這個檔；`studio.py takeover` 的開場同步改 | `studio.py`、`prompts/` |
| 收件匣、總機、`conductor.py serve` | 不需要：啟動程式自己看帳本的交接單，輪到誰就開誰 | `runner.py` 主迴圈 |
| 用量頁、狀態列的額度 | `runner.py quota`（第 4 節） | 新 |
| 側欄帳號徽章（0.29）、Board 看板（0.30） | `runner.py board`：每個位置一列 | 新（第 7 節） |
| 「做完了」的通知 | macOS 內建 `osascript -e 'display notification …'`，加一行寫進 `$STUDIO/runs/events.log` | 新 |
| `session_id`（`ORCHESTRA_SESSION_ID`，`hello` 用來登記 roster） | 啟動程式給每個 session 一個 `STUDIO_SESSION_ID`；`studio.py` 的 `in_ai_session`、`hello`、`roster` 改成也認它 | `studio.py` |

`studio.py` 的認領、帳本、交接、Blender 鎖、hook 本來就和 Orchestra 無關，照用。
Antigravity（Gemini）能不能不開視窗在背景跑還不知道（第 9 節），查清楚之前「看圖」位置仍由作者手動開，啟動程式只提醒。

## 3. 帳號

| 帳號名 | Claude | Codex | 週額度重置（台灣時間） | 備註 |
| --- | --- | --- | --- | --- |
| `ultra` | Claude Ultra | Business 帳號 1 | 每週二 22:00 | 週總量約 Max 兩倍，沒有五小時上限 |
| `max` | Claude Max（**新加**） | 不用 | 每週六 08:00 | 規劃所在的帳號（HANDOFF §1.1「模型與額度」） |
| `pro` | Claude Pro | Business 帳號 2 | 作者填 | 額度小，只做「做一次、看一次」 |
| （Antigravity） | — | — | — | 用作者平常的登入，不經啟動程式 |

`accounts.json` 長這樣（不放任何秘密，只有路徑與時間）：

```json
{
  "order": ["ultra", "max", "pro"],
  "accounts": {
    "ultra": {"claude": "~/…-Studio/accounts/ultra/claude", "codex": "~/…-Studio/accounts/ultra/codex", "weekly_reset": "Tue 22:00", "five_hour": false},
    "max":   {"claude": "~/…-Studio/accounts/max/claude", "weekly_reset": "Sat 08:00", "five_hour": true, "reserve_pct": 30},
    "pro":   {"claude": "~/…-Studio/accounts/pro/claude", "codex": "~/…-Studio/accounts/pro/codex", "weekly_reset": null, "five_hour": true}
  }
}
```

`reserve_pct`：主帳號是 Max 時，雲端的規劃與實作也在吃同一份額度，工作室最多用到「照週平均該用的量」再扣 30%。

## 4. 開工前讀每個帳號剩多少

**怎麼讀**（安全原則 3：只看 CLI 自己吐的東西）：

1. Claude：`claude -p … --output-format stream-json --verbose` 的輸出裡有額度事件（`rate_limit_event`，帶狀態、哪一種上限、重置時間）。**UNVERIFIED**：欄位名稱與是否給百分比，第 6 節第 4 步先量一次；啟動程式照量到的格式寫。
2. Codex：`codex exec --json` 的 token 事件帶 `rate_limits`（五小時與一週各一個 `used_percent`）。**UNVERIFIED**，同一步量。
3. 每次 session 跑完或中途有事件，就把最新一筆存進 `$STUDIO/usage/<帳號>.json`（只存百分比、重置時間、讀到的時間）。
4. 讀不到百分比時：`runner.py quota set ultra 40` 讓作者手填（看官方 App 的用量頁），標成「手填、幾點」。
5. 不另外花額度去問：只在真的要開工的那一次 session 順便讀；開工前沒有新資料，就用上一筆，太舊（超過 5 小時）在 `board` 標灰。

**怎麼分**（照 HANDOFF §1.1「照週平均用」）：

- 週平均線：離上次重置過了幾天 ÷ 7 × 100% = 這時候「該用到」的百分比。用量在線以下才算有額度；週重置前最後 24 小時不受這條限制（用完也沒關係）。
- 依 `order` 選：**有額度優先 Ultra**，再 Max，再 Pro。五小時上限滿了的帳號跳過，到它的重置時間再算。
- 重的位置（做、整合）優先放週總量大的帳號；Pro 只坐「驗」或「看圖」。
- Fable：只在 Ultra、Max 上用，看到 Fable 週上限的警告就那個帳號全部改 Opus（HANDOFF §1.1）。
- 每一次分配都在 `events.log` 寫一行：哪個位置、哪個帳號、為什麼（例如「ultra 週 41%／線 43%」）。

## 5. 額度用完自動接手

### 5.1 怎麼認出「額度用完」

- Claude：額度事件狀態是拒絕，或最後的 `result` 是錯誤且訊息是額度上限。
- Codex：錯誤事件是用量上限。
- 程序結束碼非 0 但不是額度：標「出錯」，不換帳號，通知作者。
- 一律從記錄檔判斷，不靠畫面。**這就修好了「額度用完仍顯示工作中」**：程序已結束、最後一筆是額度事件，`board` 就寫「額度用完」，不會是「工作中」。

### 5.2 接手的順序（先 commit 再換）

1. 等舊程序結束（還活著就送 SIGTERM，經 `studio.py stop`）。
2. 在那個 worktree 跑 `git status --porcelain`。有改動就 `git add` 認領範圍內的檔、`git commit -m "接手前自動存檔（<帳號> 額度用完）"`；**不加 `--no-verify`**，讓 hook 照常檢查。範圍外的檔不 add，留在 worktree，寫進接手開場。commit 被 hook 擋就停，不換帳號，通知作者。
3. 跑 `studio.py takeover --task <任務> --role <角色>`，得到接手開場檔。
4. 照第 4 節選下一個有額度的帳號（不選剛用完的那個，也不選和審它的位置同一個 session）。沒有任何帳號有額度：寫「全部用完，最早 <時間> 恢復」，通知作者，排一個到那個時間再試的計時。
5. 用開場檔開新 session（同一個 worktree、新的 `STUDIO_SESSION_ID`），它跑 `hello` 接手。
6. 同一個位置一小時內接手超過 2 次就停，通知作者（避免來回換帳號空轉）。
7. 接手不算失敗：帳本不加一筆、輪數不變（RUN-C10-TAKEOVER 的規則照舊）。

### 5.3 誰可以觸發

`takeover` 現在只給作者的終端機（`owner_only`）。啟動程式是作者在自己的 Terminal 開的，本身不帶任何 AI 的環境變數，所以算作者；它開出去的 AI 都帶 `STUDIO_MANAGED_AGENT=1`，跑不了 `takeover`。實作要加測試：AI session 裡跑 `runner.py` 會被拒。

### 5.4 做完、交件、審查

照原本規劃：帳本有交接單就開審查；審查 needs-fix 就照開場檔開下一輪（三輪上限照 `studio.py`）；做完、卡住、額度用完、出錯都在 `events.log` 留一行並通知。

## 6. 今晚的步驟（Ultra 22:00 重置之後，一次一步，在 Mac 的「終端機」貼）

每一步貼完，把最後幾行貼回給規劃再做下一步。

**第 0 步：設工作室資料夾**

```sh
STUDIO=$(ls -d ~/*-Studio | head -1); echo "$STUDIO"; echo "export STUDIO=\"$STUDIO\"" >> ~/.zshrc
```

預期印出一個以 `-Studio` 結尾的路徑。之後開新的終端機也有 `$STUDIO`。

**第 1 步：建 Max 帳號的資料夾並登入**

```sh
mkdir -p "$STUDIO/accounts/max/claude" && chmod 700 "$STUDIO/accounts" && CLAUDE_CONFIG_DIR="$STUDIO/accounts/max/claude" claude auth login
```

瀏覽器登入 **Max** 帳號（先在瀏覽器登出 claude.ai，否則會沿用別的帳號）。

**第 2 步：Ultra、Pro 也搬到自己的資料夾重新登入**（Orchestra 建的舊資料夾先不刪，第 5 步確認後再處理）

```sh
mkdir -p "$STUDIO/accounts/ultra/claude" && CLAUDE_CONFIG_DIR="$STUDIO/accounts/ultra/claude" claude auth login
```

登入 **Ultra**。再貼：

```sh
mkdir -p "$STUDIO/accounts/pro/claude" && CLAUDE_CONFIG_DIR="$STUDIO/accounts/pro/claude" claude auth login
```

登入 **Pro**。Codex 兩個帳號：

```sh
mkdir -p "$STUDIO/accounts/ultra/codex" && CODEX_HOME="$STUDIO/accounts/ultra/codex" codex login
```

```sh
mkdir -p "$STUDIO/accounts/pro/codex" && CODEX_HOME="$STUDIO/accounts/pro/codex" codex login
```

（第二個前先在瀏覽器登出 chatgpt.com，否則會沿用第一個。）

**第 3 步：確認五個登入各是誰**（只印方案與 email，不印 token）

```sh
for a in ultra max pro; do echo "== $a"; CLAUDE_CONFIG_DIR="$STUDIO/accounts/$a/claude" claude auth status --json; done; for a in ultra pro; do echo "== codex $a"; CODEX_HOME="$STUDIO/accounts/$a/codex" codex login status; done
```

預期三個 Claude 是三個不同的方案。兩個一樣：那個帳號重做第 1 或 2 步。

**第 4 步：量一次 CLI 會不會吐額度**（用最便宜的模型，每個帳號花一點點）

```sh
cd /tmp && for a in ultra max pro; do echo "== $a"; CLAUDE_CONFIG_DIR="$STUDIO/accounts/$a/claude" claude -p "只回 ok" --model claude-haiku-5-5 --output-format stream-json --verbose | grep -i rate_limit; done
```

```sh
cd /tmp && CODEX_HOME="$STUDIO/accounts/ultra/codex" codex exec --skip-git-repo-check --json "只回 ok" | grep -i rate_limit
```

把印出的行貼回來（裡面沒有秘密，只有狀態與時間）。什麼都沒印：第 4 節改用手填。

**第 5 步：開實作 session**

在 Mac 的 Claude Code（主帳號，那時是 Ultra）開新對話，資料夾選 `~/Developer/railway-assets-private`，模型 `claude-opus-5-5`、強度 `high`，貼：

```text
你是工作室 STUDIO-RUNNER 的實作 session。
1. 讀 railway-game-ios 的 docs/handoff/STUDIO-RUNNER.md（整份，安全原則第 1 節每條都要守），以及 railway-assets-private 的 local-studio-2026-11-10/RUN-C10-TAKEOVER.md、studio-kit/studio.py。
2. 第 6 節第 4 步量到的額度輸出如下：<貼上>。
3. 在 studio-kit 寫 runner.py（accounts、quota、start、board、主迴圈與自動接手），改 studio.py 認 STUDIO_SESSION_ID 與 progress 檔，tests.py 補測試（含 AI session 裡跑 runner 會被拒、接手前先 commit、hook 擋住就不換）。
4. 先在沙盒 hello-rail 跑 RUN-C10 那套換人驗收，過了再開 PR；PR 在 railway-assets-private，分支、不合併。
回我一律用繁體中文，短、白話。
```

**第 6 步（實作 PR 合併、驗收過之後）：舊的登入收掉**

先確認新的能用，再在 Orchestra 的 Profiles 把 `ultra`、`pro` 登出，或作者決定 Orchestra 整個不用了就關掉它。`~/.orchestra/profiles` 的資料夾不用手動刪，鑰匙圈裡它們的項目也不要手動刪（登出會清）。

## 7. 狀態：`runner.py board`

一個指令列出每個位置一列（`--follow` 每 30 秒重印）：

| 任務 | 位置 | 狀態 | 帳號 | 模型／強度 | 開始 | 最後寫檔 | 額度（週／五小時） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hkcec-redo | codexa | 工作中 | ultra | gpt-5／high | 22:10 | 22:41 | 41%／— |
| hkcec-redo | ultra | 等交件 | — | — | — | — | — |

狀態只有：工作中、等你（AI 問了作者問題，`studio.py questions` 有未答的）、等交件、審查中、額度用完、出錯、完成。
「工作中」只在程序還活著、最後寫檔 15 分鐘內才顯示；超過寫「沒動靜 N 分鐘」。

## 8. 怎麼試

素材庫 `RUN-REMOTE.md` 排好的盲測（會展 revision-3、6、8 當考題，比 Hydrogen、Opus，建議加 Fable 高強度當第四組）用新啟動程式跑。順了再把做與審的位置全部搬過來。

## 9. 還不知道、要實作 session 先查的

- Claude `-p` 的額度事件欄位、有沒有百分比（第 6 節第 4 步）；Codex 的 `rate_limits` 是否每次都有。
- Claude `-p` 帶不帶得了強度（`--effort` 之類）；帶不了就寫在該帳號 `settings.json`，那帳號同時只跑一個強度。
- Antigravity 能不能不開視窗在背景跑、它的核准怎麼設才不會卡住等人按。
- `claude -p` 在背景時，`settings.json` 沒允許的工具會不會直接失敗（應該是失敗而不是等人按，要確認）。

## 附：原本的缺口（會展那一輪留下的，2026-11-16）

| 缺口 | 以前怎麼繞 | 現在 |
| --- | --- | --- |
| 開 session 選不了帳號 | 每個 Profile 各開一個總機 | `start` 直接帶帳號 |
| 帶不了模型與強度 | 改 Profile 的設定檔 | 命令列帶（第 9 節待查強度） |
| 叫人做事要作者按 Execute | 改寫開場檔再關掉重開 | 主迴圈直接開 |
| 只有 Orchestra 的終端機能開 session | 收件匣加總機 | 不用 |
| 額度用完仍顯示「工作中」 | 協調者自己看記錄檔（會展第 2 輪停了一個半小時才發現） | 第 5.1 節 |
| 做完不通知、交件後審查不會自己開始 | 背景看守、手動重開審查 | 第 5.4 節 |
