# 交接

> 讀者：每一個新開的 session，以及接手某條線的 session。先讀 [OVERVIEW.md](OVERVIEW.md)，再讀這份。
> 這份記錄「誰在做什麼、做到哪、下一步交給誰」。規則細節以 `docs/ARCHITECTURE.md` 的決策為準，優先順序以 `docs/research/NEXT_PRIORITIES_2026-10-12.md` 為準，號碼以工作登記 #231 為準。
> 作者 2026-10-16：「把所有沒交接在 main 的用 PR 在 main 做交接，防止之後新 session 不知道怎麼做。」交接只放在 session 之間的訊息或 PR 說明裡的，都要搬到這裡。

## 怎麼用這份

- **開工前**：讀第 1、2、3 節，確認要做的事沒有人在做，作者也沒有說「先不要動」。然後照 CLAUDE.md 在 #231 登記。
- **收工時**：做到一半、留給之後、交給別人的事，寫進這份的對應一節（或寫進該決策的「下一步」，並在這裡留一行指過去），跟最後一個 PR 一起合併。只寫在 session 訊息、PR 說明或 #231 留言裡的交接，下一個 session 看不到。
- **交接給另一個 session**：用 send_message 傳的內容，也要在這裡留一份。
- 已經做完、沒有人需要照著做的交接，搬進 `docs/archive/`（OVERVIEW 第 6 節的封存表）。

## 1. 常駐的 session 與角色

作者 2026-10-20 把常駐 session 減成一個：遊戲規劃兼派工。合併協調不再常駐，§1.2 留作合併與發版的檢查清單。

**2026-10-21 起遊戲規劃也合併**（作者原話：「你的權限跟我一樣高／開發新功能一次最多3～4個session同步進行／Pr也不要一次開太多 不然會一直解合併衝突／或是等runner 綠了就合併 紅了就修／另外好像很久沒做pr review了 先優先做／再進行新功能依優先順序逐個進行」）：
- PR 綠了遊戲規劃照 §1.2 合併；紅了交回那個 PR 的 session 修。
- 新功能的實作 session 同時最多 3–4 個，照 NEXT_PRIORITIES §19 的順序一件一件開；開著的 PR 也不要多，免得一直解衝突。
- PR 審查比新功能優先。上一輪是 #786–#872（§7.1）。
- 仍是作者的：TestFlight 發版、Apple 帳號與 App Store Connect、secrets、加依賴、copyleft 或沒授權的程式碼，以及 CLAUDE.md 所有的「never」（不跑 `testflight.yml`、不開 auto-merge、不 force-push `main`、不取消 `main` 的 push run）。原因是額度：常駐 session 每一輪都要重讀整段對話，連被 PR 事件或排程叫醒也一樣，對話越長越貴。舊的遊戲規劃 session 開了兩天，用量已經碰到每週額度的警告。舊文件裡寫「派工 session」的地方，現在都是遊戲規劃。

| 角色 | 現在的 session | 做什麼 | 交接 |
| --- | --- | --- | --- |
| 遊戲規劃（兼派工） | session_01NiR5WLMFjMJBktQAMkfmkm（2026-10-21 起，照 §1.1 換手；前任 session_01WW7o3decEv5LY59nYVqnDN（10-20 至 10-21，作者：「接手 角色表中遊戲規劃的工作」）、session_01V1xd3H9vNkuZoSA3czNfGm（10-16 至 10-18）、session_018D6gYU1yiZMtxSmNNU1K17） | 從玩家、鐵道迷、開發、美術、音樂五個角度決定優先順序與設計，開實作 session 並派工，綠了的 PR 照 §1.2 合併（2026-10-21 起），收作者轉來的玩家回報與 bug（§1.3），寫 TestFlight 的 What to Test，維護 NEXT_PRIORITIES、PLAYER_FEEDBACK 與這份 | 第 1.1、1.3 節 |
| 每日 Threads 開發日誌 | 排程「每日 Threads 開發日誌」（台灣時間每天 21:43，2026-10-18 起暫停）觸發遊戲規劃，由它開寫作 session。2026-10-21 前任已建一個綁到現任 session_01NiR5WLMFjMJBktQAMkfmkm 的新排程（暫停中），舊的 `trig_01342WWauXtTPc87kNedEhb9` 已刪。排程的綁定改不了，以後換手時由現任遊戲規劃用同一份 prompt 建一個綁到自己的新排程，再刪掉舊的；作者沒說要開就維持暫停 | 寫當天的串文草稿，用 SendUserFile 交給作者；不 commit、不發布 | 派工單照 2026-10-14、10-15、10-16 的寫作 session |

不再常駐（2026-10-20 停用）：合併協調 session_01QoA24EvFCFbmbcM1EwaZT7（前任 session_016sNs4eeZwga9hz1CCHkpmX）、派工 session_01MJ7sdeid5DAFjSVbTkmdi3（前任 session_01AaAj4wvJMxJQuLWAoYu6S8）。兩個都從 2026-10-17 起沒有動作。

**額度**（作者 2026-10-20 同意的做法）：
- 實作 session 同時 2–4 個。GameCore 的完整 tier 本來就最多 2 個，macOS runner 也只有 5 台，開更多只是排隊。
- 實作 session 做完一件就收工：在 #231 留合併紀錄、把沒做完的寫進這份。不要留著等下一件。
- 常駐 session 的對話太長（大約超過 20–30 萬 token）就照 §1.1 換手，靠這份接手，不靠舊對話。
- 研究、寫文件可以用較低的思考強度；GameCore 的難題用高的。
- 對話到一定長度就自動壓縮：`.claude/settings.json` 的 `autoCompactWindow` 是 400000（2026-10-20，作者：「你四方思考後決定」）。雲端 session 另外帶 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80`，所以實際大約在 32 萬 token 時壓縮（推算，沒有實測）。壓縮會把舊對話摘要，作者的原話、量到的數字要在壓縮前寫進 PR、#231 或這份。不要這個設定時，刪掉那一行就好。
  - Claude Code 只讀 session 根目錄的 `.claude/settings.json`。同時掛好幾個 repo 的雲端 session，根目錄是上一層，讀不到 repo 裡這一行。所以作者也在雲端環境加了環境變數 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`（2026-10-20），它比設定檔優先，不管掛幾個 repo 都生效。
  - 要確認一個 session 有沒有套用，執行 `env | grep COMPACT`。
  - 要改值，兩處一起改。

### 1.1 遊戲規劃

- **做決定的方式**（作者 2026-10-14「我不再做決定，都以這個當預設」，10-15 加音樂，10-20 加鐵道迷）：五個角度（玩家、鐵道迷、開發、美術、音樂）各一行理由寫進 PR；鐵道迷看真實度與資料來源，和真實鐵路無關就寫「鐵道迷：無」；其他選項的預覽留在 PR；然後就做。作者自己保留：TestFlight 發版、Apple 帳號與 App Store Connect、secrets、加依賴、用 copyleft 或沒授權的程式碼。
- **排序**：NEXT_PRIORITIES §19（2026-10-21，鐵道迷單獨成一欄：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。§14 是舊的權重（鐵道迷＋產品），§15 是參考庫還沒做的項目與 2026-10-16 的順序。
- **一條線一次一個 PR**：前一個合併再開下一個（§14.4）。同時跑全套 Swift CI 的 GameCore PR 最多 2 個；開 PR 前先看 #231 與開著的 PR 還有沒有名額。
- **每次發版**：
  - 發版前：改 `.github/testflight-whats-new.md`（它只在上一版之後有改動時才會被用，沒改就是自動列出的 PR 清單）。
  - 發版後：看 `testflight.yml` 的 run 號與 commit，記進 `docs/research/PLAYER_FEEDBACK.md`。版本號是 0.5.0 (run 號.1)。
- **踩過的坑**：
  - 不要憑記憶說版本號，查 `testflight.yml` 的 run。2026-10-16 把 66.1 當成 64.1。
  - 發版前要收工時，叫 session「做完再停」，不要叫它把做一半的東西留給之後（作者 2026-10-16：「記得不要暫停讓他們做完」「不要限制 可以任意開 pr 但就是收工」）。
  - session 停下來，不一定是因為發版。重開之前先讀那個 session 自己的紀錄與 #231。例：語言選單是作者說「先不要動」才停的，不是發版；後來作者本人在那個 session 回「四方決定要不要繼續」，才重開成 #727。
  - 給實作 session 的派工單要對照 art-style §7 的現行規則：參考庫的模型「任意組合、成品跟原本不同」，不是「能搬就搬」。
  - 同時開好幾個 session，它們會在幾分鐘內登記同一個決策號（2026-10-16：三個都登記 256；2026-10-17：#774 與 #776 都用 271，照登記先後 #776 改成 272）。派工單裡直接寫好號碼；或開完之後看一次 #231，照登記先後重排並留言。

- **換手**（2026-10-16，作者：「你太長了接手」）：遊戲規劃的對話太長時，開新 session 接手。新 session 的派工單要寫清楚現在進行到哪、等誰；每日開發日誌的排程改到新 session；在 #231 留言；第 1 節表格的 session 改成新的。

### 1.2 合併與發版的檢查

（合併協調 session 2026-10-16 寄來的交接原文，整理成條列。2026-10-20 起沒有常駐的合併協調。2026-10-21 起遊戲規劃照這一節合併（§1）；作者在別的 session 裡授權它合併，或要發版時開一個短 session 確認，那個 session 也照這一節。）

**權限**：遊戲規劃（作者 2026-10-21 授權），或作者本人在那個 session 裡授權了的 session，才合併（CLAUDE.md 的「never merge a PR」只在這時放寬）。不開 auto-merge、不 force-push、不碰 `testflight.yml`。

**每個 PR 合併前確認**（`pull_request_read` 的 get 與 get_check_runs）：
- 不是 draft，`mergeable_state` 是 `clean`。
- check runs 全部是 success 或 skipped，沒有 in_progress。
  - 決策 265 之後，PR 的 `Swift CI (gate)` 會等同一個 commit 的 `iOS App Build`，iOS 紅了 gate 就紅；所以 gate 綠就代表 iOS 也綠了。
  - iOS 失敗、重跑通過之後，gate 不會自己變綠：對 CI 那一輪按 Re-run failed jobs（`actions_run_trigger` 的 rerun_failed_jobs）。
  - 「Remember that this change passed」顯示 skipped 是正常的：同一個改動前一輪已經跑過。
  - Xcode build 有時跑兩輪，兩輪都要看。
- main 最新一次 push 的 `ci.yml` 是綠的（`actions_list` 的 list_workflow_runs，條件 ci.yml、branch main、event push）。cancelled 是被新的 push 取代，不算紅；要看最新一個跑完的。

**合併**：
- 用 `merge_pull_request`，merge_method 用 `merge`，`expectedHeadSha` 填 head 的完整 40 碼。
- 合完在 #231 留一則：PR 號、head 與合進 main 後的 sha。再用 send_message 通知那個 PR 的 session。

**批次**：
- 一批 3–5 個綠的 PR，兩批之間等 main 的 `ci.yml` 綠。
- 只改 docs，或只改 UI 測試、CI 腳本的 PR，可以隨時合。
- 先合正在等的那一個：有 PR 為了解衝突重跑 CI 時，先不要合另一個也改 OVERVIEW、ARCHITECTURE 或這份的 PR，否則它要再解一次（2026-10-21：先合 #876，#875 第二次衝突）。

**GameCore 名額**：
- 同時最多 2 個要跑完整 tier（18–19 個 job）的 PR 在跑 CI。改 `.github/scripts/swift-shards.sh` 這類 CI 腳本也算完整 tier。
- session 問能不能推：當下在跑的完整 tier 不到 2 個就答可以。
- GameCore PR 的 base 比另一個已經合進去的 GameCore 改動舊時，請它 merge main（不要 rebase），重跑完整 tier 再合。

**決策號與文件衝突**：
- 兩個 PR 撞同一個決策號，或 ARCHITECTURE、OVERVIEW 衝突：請該 session 自己 merge main 解，決策照號碼排。
- 存檔版本與決策號以 main 加上 #231 還沒釋出的登記為準，取最大值加一。

**full lane**（`ios-build.yml` 把 iPhone UI 測試全部跑一次：兩個 iPhone job 加 iPad 教學，約 42–45 分鐘，佔 3 台 macOS）：
- 合併後不用手動跑（決策 265）：`ios-full-lane.yml` 在合了會影響 App 的 PR 之後自己啟動，最多每三小時一次。10-14 到 10-16 的 67 小時裡 full lane 跑了 42 次，只有 7 次是它啟動的，佔全部 macOS 用量的 34%。
- 只在兩種情況用 `actions_run_trigger` 手動跑（run_workflow，workflow `ios-build.yml`，ref main）：
  - 發版前要用的 HEAD；
  - full lane 紅了，要二分的 commit。
- 只改 docs、`Tests/`、`tools/` 的 PR 不影響 App，不用重跑。
- 要發版的 commit 必須自己有一輪綠的 full lane。

**full lane 紅了**：
1. 用 `actions_list` 的 list_workflow_jobs 找出失敗的 job。
2. 用 `get_job_logs`（return_content 設 false）拿到 log 網址，用 curl 下載到 scratchpad。
3. 用 `grep -aE "error: -\[|' failed \(|Executed [0-9]+ tests, with"` 找出失敗的測試與行號。
4. 跟上一輪綠的 full lane 比：`git log --first-parent <綠>..<紅>`，再用 `git diff --name-only <merge>^1 <merge>` 看每個 PR 改了哪些檔。
5. 從 commit 的 `Claude-Session:` trailer 找到做那個 PR 的 session，用 send_message 交給它。附上 run、job、測試名、行號、錯誤訊息和可疑的 PR。
6. 對方可以用 `ios-build.yml` 的 `only_testing` 分段驗證（例如開 `claude/bisect-*` branch）。修正 PR 綠了就合，全部修完再跑一輪 full lane。
7. 發版前紅了：立刻告訴作者「先不要發」，並說明原因。

**發版前**（作者自己跑 `testflight.yml`，這裡只確認）：
- 要發的 commit 就是 main HEAD，它的 `ci.yml` 和它自己的 full lane 都要綠。
- 確認的時候如果 main 又合了改 App 的 PR，要在新的 HEAD 重跑 full lane。這時可以取消舊 commit 用 workflow_dispatch 跑的 full lane，讓出 macOS runner（上限 5 個）。
- 確認後通知遊戲規劃與作者「可以發（commit X）」，並請各 session 發版前別再合改 App 的 PR。
- 作者在收到「可以發（commit X）」之前就發了，要在 PLAYER_FEEDBACK 記下實際發的 commit 與它 full lane 的結果（72.1：作者 10:47 UTC 發 8c305a6，它的 full lane 才剛開始、後來紅；與全綠的 c3a3ec7 只差一個 UI 測試檔，App 相同。審查 #785 第二節）。
- 發版後在 #231 寫「發版凍結解除」。

**巡查**：用 `send_later` 排下一次巡查，訊息寫清楚要查哪個 run、綠了做什麼、紅了做什麼。計畫改了，就用 `delete_trigger` 刪掉舊的巡查。

**工具**：
- GitHub MCP（先用 ToolSearch 載入）：`pull_request_read`、`merge_pull_request`、`actions_list`、`actions_get`、`actions_run_trigger`（run_workflow、cancel_workflow_run）、`get_job_logs`、`add_issue_comment`（#231 只留言）、`list_pull_requests`。
- claude-code-remote：`send_message`、`send_later`、`delete_trigger`。
- scratchpad 裡 clone 一份 repo，查合併範圍、PR 改的檔、session id：`git log --format=%b A^1..A^2 | grep -o 'session_[A-Za-z0-9]*'`。
- GitHub 留言結尾都要加 Claude Code 的 footer；不寫 `@claude`。

**踩過的坑**：
- #701 的景點標記在買地選格時吃掉點擊。PR 自己的 gate 沒測到，到 full lane 才紅。這種情況要請 session 先用 `only_testing` 跑它改到的 UI 測試，再合。
- UI 測試時好時壞：開局鏡頭 2 秒內還在動（#719）、教學第 15、16 步一下就過去（#714）、時刻列要看當下的行車狀況（#712）。不要重跑碰運氣，要叫 session 把測試修穩。
- 作者也會自己合 PR。查之前先看 state，可能已經 merged；也要留意 main 已經往前走了。
- 發的是 main HEAD。full lane 測過的 commit 如果被新合的 App PR 蓋過，HEAD 要自己再跑一輪綠的 full lane。
- #701 拿了 #700 已經用掉的決策 249。合之前要看決策號有沒有撞。
- 刪 bisect branch 會被自動模式擋下，交給作者刪。
- 不要取消 main 的 `ci.yml` push run。只能取消自己用 workflow_dispatch 跑的 full lane，或 PR 的 run。
- #697 把選單從 6 列改成 8 列，SettingsUITests 跟著紅了三支（#706 改回 6 列）。改版面的 PR 要預期 full lane 會連帶紅。

### 1.3 派工（遊戲規劃兼任）

（派工 session 2026-10-16 寄來的交接原文，整理成條列。2026-10-20 起由遊戲規劃兼任。）

**職責**：
- 接作者轉來的 TestFlight 玩家回報與 bug，到最新 main 查證，有問題就用 `create_session` 派修正 session，結果轉告作者。
- 也盯 main 的 full lane（iOS App Build／ios-full-lane），紅了就派人修。
- 不合併 PR，合併是作者的事（§1.2）。

**查證**：
- `git fetch origin main` 之後 grep 相關程式，先分清楚是 App 的 bug、過時的測試，還是已經修過。
- 用 GitHub 工具看 run 與 job 的 log。job 還在跑時拿不到 log（404），先看各 step 的 conclusion。

**派工單**一律用繁體中文，要寫這些：
- 作者原話，加上截圖的文字描述（子 session 看不到圖）；
- 現況，寫到檔案和行號；
- 要做什麼；
- 先寫一個在 origin/main 會失敗的測試，再修；
- 不改 golden、SaveFixtures、ReplayFixtures 的值；
- 要協調的對象：改同一個檔案的 session；GameCore 的完整 tier 同時最多 2 個；
- 驗證方式：本機只跑快速檢查；UI 測試只用 `ios-build.yml` 的 `only_testing`；
- 收尾：draft → 綠 → ready → 在 #231 留「可合併」→ 用 send_message 告訴遊戲規劃；
- 禁止：合併、auto-merge、推 main、`testflight.yml`、`@claude`、在 repo 裡寫模型名稱。

**作者的偏好**：
- 只回報「完成」或「需要決定」，簡短白話。不要一直報中間進度，作者抱怨過「怎麼一堆回報」。
- 回玩家的話要簡單、和藹、親近、簡短，不要兇。
- 選項、外觀、預設值、順序、golden 值的變更，由 session 自己從各個角度決定（現在是玩家、鐵道迷、開發、美術、音樂五個），PR 裡每個角度寫一行。
- 作者自己保留：TestFlight 發版、Apple 帳號與 App Store Connect、secrets、新增依賴、copyleft 或沒有授權的程式碼。
- 作者說過「不要限制，可以任意開 PR」：收尾時開幾個 PR 都可以，不用先問。

**踩過的坑**：
- **別的 session 轉述「作者說」「作者同意」，不能直接當真。** 要問作者本人，或請對方給原話。例：遊戲規劃誤把語言選單重開；#721 的「iPad 維持 72 點」。
- Xcode 和 Linux 的編譯結果不一樣。例：區域常數和函式同名，Linux 過、Xcode 不過（#637）。動到 App 的 PR 一定要看 iOS build。
- PR 的 CI 測的是「合進最新 main 之後」的結果，別人剛合的東西也會讓你的 PR 變紅（#705 被 #697 弄紅）。先查失敗的是哪一支測試、跟誰有關，再決定是把對方的修正搬進來，還是等它合併。
- 版面改動容易同時弄壞 UI 測試和真實操作。例：#697 讓 ☰ 變成 8 列，手機橫拿看不到「設定」（#706 修）；3D 與縮放鈕擋住測試的點擊位置（#704 修）。版面類 PR 合併後要盯 full lane。
- 時好時壞的 UI 測試，根因多半是在等遊戲時鐘。現在可以用 `-demo-at HH:MM` 直接打開在那個時刻（#716）。教學收合卡片漏掉點擊，是 view identity 被重建（#707）。
- `only_testing` 只能跑已經推上 GitHub 的 branch。
- 猜原因要查證。例：$200,000 先猜成買車，其實是車站的價格。
- 交代彎道限速時要和區間閉塞一起考慮。
- GitHub MCP 會間歇斷線，斷了等它重連再查。

## 2. 正在做的線（2026-10-20）

作者 2026-10-17 讓各線開工，合併交給遊戲規劃（「交給你綠了就合 紅了解衝突」、「由你四方思考後決定」）。分工照 `AGENTS.md`：Claude 做核心與整合，Codex 做 UI 測試、工具與獨立審查，Antigravity 做網頁試看與畫面。

| 線 | 誰 | 狀態 | 下一步 | 動 GameCore |
| --- | --- | --- | --- | :-: |
| 核心玩法：規則、配車、關卡、回饋第二批 | session_01Q48iRY9H6EmeUL8NPyfiDW | 第 1–5 個 PR 與決策 264 的後續已合併（決策 258、264、266、271）；收尾 #779（決策 273）；回饋第二批全部做完：#780（決策 274）、#792 每趟蓋章與 #795 長按路線看旅程（決策 276）；#785 延後的三項 #789（決策 275）、#790 | 高鐵示範（NEXT_PRIORITIES §16 第 4 項）：快轉 #801 已合併；#669 的長進路死結與台南—左營交會是決策 278（#804，已合併）：號誌開＋閉塞時白天不再死結、取消 60 → 45 班。北端夜裡的死結是決策 280（`claude/hsr-north-depot-room`：機廠有空股才入庫，機廠的股道算終點站的盡頭；取消 45 → 32 班）；計算時間是 `claude/hsr-traffic-speed`（結果逐位元不變，`docs/research/APP_TICK_COST_2026-10-18.md` §6）。左營出入線是決策 281；南港咽喉與照地形建是決策 283（`claude/hsr-nangang-throat`）。左營咽喉白天的死結是決策 287（`claude/hsr-zuoying-throat`）：看了第一個死結，是調度不是軌道。閉塞分界設在上行線匯入的斜線旁（決策 281 為出入線加的節點），進站的車停在那裡擋住出站的路，和要讓出股道的閒置車互等；分界改成只設在列車停下來不會妨礙別條軌道的地方，取消 86 → 44 班（平地 129 → 46）。照地形建時夜裡出庫的死結是決策 290（`claude/hsr-zuoying-depot-exit`）：有班次的路線，終點站有一股沒有車停、也沒有車正開往才從機廠出庫，並開往那一股；照地形一天取消 44 → 30、每小時結束時都沒有死結（平地 46 → 33）。「剛入庫 16 分鐘又出庫」是另一個機制（班次晚了、在等的車拿不到路時，出庫的判斷把它們當成趕不上），試過讓兩邊一致，量了變差（照地形 30 → 40），不採用。決策 290 之後剩下的取消逐班分類寫在 `docs/research/HSR_SIGNAL_BASELINE_2026-10-15.md` §13：最多的是接班的車晚到（晚點四成多來自快車跟在慢車後面，排定待避一次都沒排出來），其次是左營咽喉被一百多 km 外的進站車整段占著。決策 294（`claude/hsr-overtake-approach`）兩條一起改：時刻表裡的待避照排（慢車停側線等快車，最多多等 5 分），長區間的列車離站 14 km 內才排進站的路；照地形取消 30 → 13、平地 33 → 22。只做其中一條時某一種建法會變差，數字在決策 294 的「試過、不採用」。機廠與終點站之間的來回（作者這輪的第 3 步）由 session_01KFRB53UNrJR1yVGu2fGJog 接手做成決策 296（`claude/hsr-depot-shuttle`）；作者提的車輛運用（原車接下一班、閒得久的才入庫）試過、不採用（照地形取消 13 → 24，數字在決策 296「下一步」第 1 點的「之後」）。平地白天短暫的死結（第 4 步）是決策 297（`claude/hsr-flat-deadlocks`，session_01KFRB53UNrJR1yVGu2fGJog 開工、session_011GLH8sEjxxMsy2VEXa8szu 接手）：台中、左營月台上等下一班的閒置車擋到進站的車，那站沒有一班要開時就入庫；照地形取消 13 → 4、平地 18 → 2，每小時結束時都沒有死結，代價是機廠進出多了 2.5 倍。往前看 30／60 分、換月台不算後面的車、只在中間站生效，四種都量了、不採用（決策 297「試過、不採用」）。決策 297 的「下一步」第 1–3 點是決策 302（`claude/hsr-depot-churn`，session_011GLH8sEjxxMsy2VEXa8szu）：一組正在路上的車預估比出庫的車先到時，算成接得了那站的班，不再從一個半小時外的烏日機廠派車；台中 08:04 不再取消，照地形取消 4 → 2、平地 2 → 1。「擋路的車入庫前先看來回趕不趕得上」量了、逐位元相同；「在路上的車都算接得了」讓沒有閉塞的組合 21 時起卡死，都不採用。晚點的車追回時間是決策 306（`claude/hsr-catch-up`，session_011GLH8sEjxxMsy2VEXa8szu）：號誌與閉塞打開時，晚點的列車照到表定到站剩下的時間跑，最快照車的性能與彎道限速，不超過設計時速；照地形 取消 2 → 1、晚點中位數 7／11／9 → 3／3／9 分、平地取消 1 → 1、晚點中位數 4／10／11 → 2／4／9 分。沒有閉塞時也追回會在夜裡互等（台南的進路宣告、左營咽喉與要入庫的閒置車），量了、不採用。**交接：決策 302 的「下一步」第 1–3 點**（晚到的車停下那一兩分鐘的出庫、南港咽喉的取消、左營月台的互等）**與決策 306 的「下一步」**（沒有閉塞時的兩個互等與追回時間、平地五站停晚 93 分的那一班）。決策 306 之後還能做的五項、估計與順序在 §5；第 1 項（沒有閉塞時的互等）作者 2026-10-21 說「開新session做4」，由 session_0125dMtwyMdz7mzoBCRNa1pn 在做。決策 294「下一步」其餘四點還沒人做：出站的路上停著的車不能跟（決策 212 的 (C)）、咽喉的容量與南港往台北共用上行線（軌道，§10）、計算時間（一天照地形 1,657 秒）、要不要讓示範的號誌與閉塞一起打開。第 6 個 PR（GameCore 的新目標）先不做。UI 測試交給 Codex（決策 266、271、273、274、276 列了要補的） | 是（決策 280、283、287、288、294、297、302、306） |
| 3D 生活感 | Claude session_01EPkWLr5a25LyJvCuvh1U3R | 四步完成：#734（259）、#745（263）、#765（267）、#768（268）、#769（269）、#771（270）；#770 收尾 #752；#772 修 71.1「3D 一放大就跳回 2D」；#776 配色亮度（決策 272）；#788 場景快取；#793 Meshy 試做模型規格與讀檔；#794 雨天的光線與霧（決策 277） | 決策 277 的後兩步：(a) 雨絲，等 72.1 的 fps 沒問題再做；(b) 站前商店街（條紋雨遮、屋頂立牌、下照燈），等 fps 確定有餘裕。店名、站名、招牌配色要換成本專案自己的，不沿用參考原作那五家店與「晴川站」（art-style §7） | 否 |
| 關卡的 UI 測試、full lane、GLB 轉換器 | Codex | 三張卡都已合併（2026-10-18）：#784 關卡 UI 測試（`LessonUITests` 12 個，決策 271 列的五項都有）；#802 full lane 拆工作（`LessonUITests` 自己一個 iPhone job `FULL_LANE_LESSONS_JOB`、`-lesson-stars` 檔名常數改 public、`FlexDispatchPropertyTests` 搬到較短的 shard）；#803 GLB → `.m3dmodel` 轉換器（`tools/glb-to-m3dmodel/`，Meshy 公車 1,543 面、8 色）。之後 #821 Peakline 圖資研究（§4.5） | (1) 公車模型接進 App：3D session 做（`Resources/Models/`、XcodeGen 重新產生 `.xcodeproj`、取決策號；模型在 `docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel`，轉換器已把車頭轉成 +x）；(2) meshopt／量化與 `.gltf` 橋接已實作於 `codex/glb-meshopt-bridge`，使用／接手點見第 7.3 節；App 接入仍由 3D session 做 | 否 |
| 開發工具 | Claude session_011Z9h1X1GcZZ3i1EKEEjDZj | `GameSim` #740（決策 260）、`Policy` #748（決策 261）、文件數字檢查 #760 都已合併 | 第 7.4 節剩下的項目 | 否 |
| 示範地圖照真實的高架與隧道（決策 279、281） | Claude session_01KeynzCwtDyLHTUYBfKxy1c（作者直接交辦） | #805、#807、#808、#809 已合併（瑞芳／平溪示範、宜蘭線示範、沿真實鐵路描線、參考庫新版）；`claude/hsr-real-structures`：左營機廠的出入線；高鐵示範照真實高架與隧道的建法做好，開關先關（決策 281） | Claude platform 做完（`claude/hsr-nangang-throat`，決策 283）：南港咽喉的卡死修好（遲到的車還在終點站的股道上，進站的車改去空的一條；沿路看對向車 20 km；兩列都還沒上共用軌道時遠的等近的），開關打開，號誌關的一天 `HighSpeedDemoDayTests` 全過。號誌開＋閉塞重量的結果：左營咽喉白天就卡住（平地 09 時、照地形 16 時起），下一步見決策 283。決策 287 看了第一個死結：是閉塞分界的位置（調度），不是出入線和進站的車共用咽喉，**軌道這邊不用改**。決策 290 做完夜裡出庫的死結（調度：終點站有空股才出庫），重量一天：照地形每小時結束時都沒有死結，所以**軌道仍不用為了死結改**。軌道這邊之後可以評估的（都不急，是示範的真實度與咽喉容量，不是死結）：出入線分成入庫、出庫兩條；左營咽喉照真實改成雙線加交叉渡線（現在八股只靠下行線上一串轉轍器） | 否（決策 283、287 動 GameCore） |

**main 的 full lane 紅燈（遊戲規劃 2026-10-20 派工）**：main 的 `ios-build.yml` full lane 從 784bb3a（#833，10-19 16:41）起連續 7 次紅，最後一次綠是 ae77ab4（#827，run 39254620337）。每次都紅的是 `LineDraftSummaryUITests` 兩個（#835 新加）、`NextStepChipUITests.testANewGamesNextStepOpensTheGoals`（#842 新加）、`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`。時紅時好的是 `LessonUITests` 第 8、9 課（清單捲不到按鈕）。已派 session_01MV9BgbHcs7XFafNDk76DyD：先分清楚是 App 的 bug 還是測試過時，再修，用 `only_testing` 驗證。修好以前不發版。
  - **修了**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-red-1020`，原因與證據在那個 PR 的說明）：`NextStepChip` 不是按鈕（App）；路線面板加第一站後停在原處、表單在畫面外（App，決策 299）；月台測試點到 #839 的涵蓋捷徑、第二個月台的偏移超過 80 m 月台（測試）；第 8 課的拖曳落在面板的捲軸上（測試）。
  - **還沒查**（修完後的 full lane 再紅才查）：第 9 課 `testTheNinthLessonsSightOpensItsTourismPanel` 只在 784bb3a 紅過一次，那時 #840 還沒合併，和它無關；`CoverageShortcutUITests:16`、`LineDraftSummaryUITests:75` 的 `Failed to get background assertion`（Simulator 逾時）；`StartSaveFlowSmokeTests:499` 的 `menu.backToStart` 沒停穩。各只紅過一次。
  - **2026-10-21，run 39526204987（5040730）兩個紅**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-coverage-ipad`）：兩個都是那個 job 的第一個測試、App 的第一次啟動。
    - **iPad 的 `TutorialJourneyUITests.testTheWholeTutorialOnAnIPad`（測試，已修）**：第一次啟動花了 35 秒（綠的時候 14–22 秒），接著點 Lessons，點在 (270, 688)，不在按鈕上（478–898, 499–580），課程清單沒開。App 的紀錄只有那一下觸控，看起來是畫面還在轉向時就算好了位置。改成等按鈕停穩再點，5 秒內清單沒開就再點一次。和 #870（決策 303）無關：#870 沒改課程清單，這一步在它之前。
    - **`CoverageShortcutUITests`（Simulator，沒改）**：第二次在 `app.launch()` 就失敗（`Failed to get background assertion … Timed out`，啟動後 19.6 秒）。App 那時已經開始畫面了（01:24:37 起每秒 120 幀），是 XCTest 和 Simulator 的交接逾時，測試的步驟一個都還沒跑。上一次是 `LineDraftSummaryUITests:75`（run 39415463138），也是那個 job 的第一次啟動。最近 15 次 full lane 的 iPhone job 中，第一次啟動從按下到 XCTest 接上要 6–32 秒，有時超過這次失敗時的 19.6 秒也沒事，所以不是單純太慢。「暖機」那一步用 `simctl launch`，不經過 XCTest，所以擋不住這個。測試沒辦法重試 `launch()`。**可能的下一步**（沒做，要多跑幾次才看得出效果）：暖機改用 `xcodebuild test-without-building` 跑一個很短的 UI 測試，讓 XCTest 的第一次交接發生在暖機裡。

**決策 284–286 的 iPhone UI 測試（Codex，`codex/feature-ui-284-286`）**：`Feature284To286UITests` 共 5 個測試，檢查新路線草稿的兩種警告、複線月台卡片與確認後的兩個月台項目、兩款觀光列車的型錄說明與選擇按鈕、景點的觀光列車加星文字。只放 full lane 的 `FULL_LANE_LESSONS_JOB`，PR gate 不加測試。Debug 參數 `-ui-testing -ui-test-world <name>` 可開 `separate-tracks`、`missing-platform`、`double-platform`、`catalog`、`sightseeing`；全部先存入每次清空的測試暫存 library，再經一般讀檔入口載入。VERIFIED：Linux Swift 6.4 的 warnings-as-errors build、5 種世界的建立與存讀一致、XcodeGen 2.46.0 產生專案；GitHub Actions／macOS 26.6.2、Xcode 26.6、iOS 26.5、iPhone 17 Pro 的 [only_testing run 39341335419](https://github.com/a91453/railway-game-ios/actions/runs/39341335419)（head `3fd877f0`）5/5 通過、0 failures，測試 298.160 秒，整個 UI 測試步驟 7:36，專案 drift check 與 build-for-testing 也通過。以最近成功的 lessons job 42:56 加上完整 7:36 保守估算是 50:32／75 分鐘；UI 步驟 36:44＋7:36＝44:20／55 分鐘，兩者都留十分鐘以上。UNVERIFIED：加入新類別後的整條 full lane、實體裝置與 Release archive。下一步：審查者從本卡 PR 的 Checks 接，合併後看正常的 full lane；本卡不另手動開整條 full lane。重現只用 `ios-build.yml` 的 `only_testing=RailwayGameUITests/Feature284To286UITests`。2026-10-20 依作者回報續解 PR #840：merge main `c46f5d2d`，唯一衝突是產生的 `project.pbxproj`，已用 XcodeGen 2.46.0 重建（重複產生結果相同），保留 main 新增的 `LineDraftSummaryUITests`、`CoverageShortcutUITests` 與其 App 元件。本卡的 5 個測試、Debug world、App 測試入口與 full lane 分配皆未改，`LinesPanel` 相對 main 仍只有新增 identifier；main 的新 UI 與其他 session 交接完整保留。merge 後 VERIFIED（Linux／官方 Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors -j 3` 乾淨通過（221.86 秒），5 種 Debug 世界重新建立並經 `SaveLibrary` 存讀一致；沒有跑本機全套測試。上述 5/5 Simulator 證據屬 merge 前 head；merge 後未另手動重跑，專案 drift、Xcode build 與 PR gate 看 PR #840 的新 Checks。存檔版本、決策編號、golden schema 不動。

**Kenney 素材（遊戲規劃 2026-10-17 決定）**：Antigravity 的試看 #773（`docs/art/town-scene-preview-2026-10-17/`）證實 Kenney 包是 CC0，可以用；但人物是大頭比例、每人 690–756、每台車 2,000 以上三角形，原生 3D 已有程式做的人、機車、汽車（決策 259），所以**不放進遊戲、不做 GLB 轉檔**。素材留在 `Web/CityView/public/models/town/`（`SOURCES.json`），遇到程式做不好、Kenney 剛好有的東西再改色組合後取用。

**引擎與素材線（遊戲規劃 2026-10-17 決定；作者問「unity + blender + tripo + claude + codex」要不要跟，說「你四方決定後 幫我做決定」）**：
- **不換 Unity，留在 Swift／SwiftUI／Metal。** 玩家：換引擎要停好幾個月的新功能。開發：GameCore（Swift，270 多條決策、golden、存檔與確定性測試）要改寫成 C# 或接原生外掛，CI 與 TestFlight 流程要重建；雲端的 Claude、Codex 跑在 Linux，打不開 Unity 編輯器。美術：別人跨過的坎是做素材的速度，這和引擎無關。音樂：無。
- **素材線照別人那套，但接進現在的架構**：作者已有付費的 Meshy（`tools/meshy/`，商用輸出歸作者，條款見那裡的 README），不另加 Tripo；Blender 是作者電腦上的選項，不是必要步驟（Meshy 的 smart topology 直接給低面數）。缺的只有「GLB 進原生 3D」這一段。
- **順序**：72.1 在實機量到 3D 幀時間之後，先試一個模型（台灣速克達特寫版或市區公車，#773 指出的缺口）：Meshy 生成、遊戲規劃先報點數等作者同意並由作者在 session 裡登入；Codex 寫 `tools/` 的 GLB 轉成遊戲模型的工具；3D session 接進 Metal。好看、幀數夠，才把這條線用到更多模型。
- **試做模型的規格**（3D 生活感，遊戲規劃 2026-10-17 同意）：`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`。先做市區公車（1,500 面以內），機車排第二。不帶貼圖，每個三角形烤成一個顏色、8 色以內，車身用實例的顏色。格式是二進位的 `.m3dmodel`，GamePresentation 讀檔的 `Map3DModelFile` 已經做好（Linux 測試）。GLB 轉換器已由 Codex 做完（#803，`tools/glb-to-m3dmodel/`）。還沒做的：接進 App（加 `Resources/Models/`、用 XcodeGen 重新產生 `.xcodeproj`、取決策號）；公車上街（決策 259 的車流），等 72.1 的實機幀數。點數由作者決定，遊戲規劃建議先做一次（約 35 點）；作者登入前不呼叫 Meshy。

**#785 審查延後的項目，派給誰（遊戲規劃 2026-10-17）**（詳見 `docs/archive/PR755_784_REVIEW_HANDOFF.md` 第四節）：
- 核心玩法 session，排在回饋第二批（二）之前，因為是玩家會碰到的錯：
  - 整平月台時，轉乘中的乘客會被放棄（要動 GameCore，取決策號）；
  - `AutoService.passingLoopsNeeded` 的第二處以後的規劃帶上高度與水域；
  - 兩端需求燈改用路線列車定員的最小值。
- 3D session：做完（#788，決策 269 的「之後的修正」）。3D 場景快取在回到開始畫面、收到記憶體警告時放掉；2D 拉近到門檻 ¾ 到門檻之間停 0.4 秒，才開始預先蓋 3D。
- Codex（作者轉交；**已由 #802 做完**）：`LessonUITests` 讓 full lane 第一個 job 跑到 1 小時，拆到兩個 job 或第三個 iPhone job（第二個 job 已 35–40 分，整個搬過去會超過 45 分上限）；`-lesson-stars` 用的檔名常數改成 public 給 App 讀；`ci.yml` push 超過 30 分的兩次（#759、#770）看 shard 時間。
- 時好時壞的 `MapInteractionTests/testHoldingAStationTracesItsBusiestTrips`：下次紅時讀 #785 加的 trace（refused／station none／什麼都沒有，各指一個原因），再派。

**作者 2026-10-18 暫停（「現在的做完 收工 就不要做了 沒有額度了」）**：遊戲規劃 session 讓各線停在這裡，每日 Threads 日誌的排程也暫停（`trig_01342WWauXtTPc87kNedEhb9`，重新開工時再打開）。沒有開著的 PR。下次開工從這裡接：
- 核心玩法：高鐵示範的快轉在停工前已推上 `claude/hsr-demo-speed`，之後由 #801 合併（一週 `.fast` 97 s → 36 s）。2026-10-18 作者重新派工後做了決策 278（見第 2 節表格）。
- 3D：等 72.1 的 fps 回報，才做決策 277 的雨絲與站前商店街；Meshy 公車（`docs/art/meshy-city-bus-2026-10-18/`）已由 Codex 的轉換器轉好（#803，`city-bus.m3dmodel`，車頭轉成 +x），等 3D session 接進 App。那兩個 PR 順便照 GAME_AI_TOOLS §6.3 加工具：改 3D 畫面的加 pixelmatch 差異圖，接 Meshy 公車的加 glTF-Validator。
- Codex：三張卡都已合併（#802 full lane 拆工作、#784 關卡 UI 測試、#803 GLB 轉換器），見第 2 節表格。

**App 效能（#791 查到，遊戲規劃 2026-10-18 派給核心玩法 session）**：main 98d1f15 的 full lane 兩個 UI 測試紅，根因都是 App 忙到無障礙查詢要 5–46 秒（#791 改了測試的等待；證據在 #791 的說明，run 39070554849、39077241788 的 xcresult）。App 這邊還沒解：
- 新遊戲買 15 列車、600 倍時，錄影裡 9 秒只走了 14 分鐘（應該 90 分）；6000 倍時一次查詢 14.5 秒。
- 時鐘停著時，主執行緒也會有 6 秒沒回應（App 剛啟動、畫面靜止）。
- 做法：先用 `GameSim` 在 Linux 量每個 tick 的 GameCore 與 GamePresentation 時間，分清楚是模擬慢還是 App 每 tick 重算畫面；結果要逐位元不變。都是 CI Simulator 上看到的，實機要對照 72.1 的回報。
- **量完了（#798，`docs/research/APP_TICK_COST_2026-10-18.md`）**：主因是 XCTest 的無障礙快照，玩家不受影響。
  - 模擬很便宜：UI 測試那一局每 tick 0.2 ms。
  - 不打擾 App 時，600 倍跟得上：10.1 s 走了 102 遊戲分鐘，應該 100；畫面 50–60 fps。
  - 卡頓只出在測試查詢時。App 沒有改。
  - **VoiceOver 未量**（未驗證的缺口）：VoiceOver 也讀無障礙樹，時鐘跑時可能一樣卡。下一版的 What to Test 請實機開 VoiceOver 試 600 倍。
- **高鐵示範的快轉（分支 `claude/hsr-demo-speed`，作者暫停時已提交、推上分支，沒開 PR、沒跑 CI）**：模擬本身慢，熱點是每個 tick 重算每條路線的行程，和出庫時每站重算空車。改成跨 tick 記住（`RouteMemo.ServiceKey`），結果逐位元不變，不動存檔、golden、決策號。一週 `.fast` 從 97 s 到 36 s（預算 100.8 s），超過 100 ms 的 tick 從 563 個到 16 個（`docs/research/APP_TICK_COST_2026-10-18.md` §5）。開工時：開 PR（會跑 GameCore 的整套 CI）。之後才做 #669 的長進路死結與台南—左營交會（號誌開），要改規則才取決策號。

已收工（2026-10-17／18）：#787 文件、#791 full lane 的兩個 UI 測試；玩家回報的修正 #759（建造確認卡換行）、#761（有月台的軌道也能整平）；自動待避線放不回路線的列車 #763；N700 審查修正 #764（Antigravity）與 #770；實景開局 UI 測試的同步 #775（Codex）。2026-10-16 以前：單線死結 #736、#750（決策 255）；語言選單 #727（決策 257）；實景城市 #746、#753（決策 262）；審查清理 #728–#743；PR #712–#754 審查 #757；CI 優化 #756、#758（決策 265）；高鐵 N700 #752；貨運開關說明 #754。

## 3. 作者說過的話、還在等作者的事、遊戲規劃代為決定的事

| 事項 | 狀態 | 在哪裡 |
| --- | --- | --- |
| 實景開局的「用我的位置」 | **等作者決定**（決策 312 沒做）。要 CoreLocation 與 Info.plist 的定位用途字串，App Store Connect 的隱私標籤（App Privacy）要加「位置」，那是作者的事。作者同意後：實景選點的搜尋旁加「用我的位置」，取一次位置就把框移過去（`RealWorldStartArea(latitude:longitude:)` 已經會把點限制在地圖內），不在背景追蹤、不存位置以外的東西。同一個決策也沒做「已下載的地點」：存檔摘要沒有錨點，要做得先在 `SaveSummary` 記錨點 | ARCHITECTURE 決策 312 |
| 競爭對手與收購公司 | 作者 2026-10-21：「收購整條線 或公司會讓玩法變有趣嗎」→「好 排進去……然後競爭對手與收購公司再考慮一下」。收購支線已排進 §19 第 9 名；競爭對手與收購公司**作者還在考慮**，三種做法打好分（汽機車分走旅客 2.55、對手鐵路公司 1.90、收購公司 1.45），作者決定前不派工 | NEXT_PRIORITIES §20 |
| 69.1 之後先不開新工作 | 作者 2026-10-16（69.1 發版後）：「不用凍結了 但也先不要開工我要做pr review 跟ci優化」。發版凍結解除，PR 照一般規則合；但核心玩法第 4 個 PR（關卡）、3D 2b、文件數字檢查等都先不開，等作者說開工。現在只跑：PR #712–#754 審查（session_01QVLVMib2sHjahi6BdYdK48）、CI 優化（session_01LQE9Rif1ggbZsT3iYQiN7G）。各線都已通知 | #231 |
| 69.1 的發版 | 作者 2026-10-16：「交給你綠了就合 紅了解衝突 最後是試著發一版TestFlight 但前提是要所有pr都綠 無失敗」「記得要adhoc external」，之後「隨便 我來發69.1了」，作者自己跑了 run 69（e68f237）。#747 的 What to Test 晚兩分鐘合併，沒被帶上（`docs/research/PLAYER_FEEDBACK.md` 69.1）。教訓：What to Test 的 PR 要最先合，不要排在最後 | PLAYER_FEEDBACK |
| 航空遊戲手感借到鐵道 | **遊戲規劃 2026-10-16 決定**：③ 到站收入飄字併進核心玩法的回饋（#724 的「+$12」）；①座位圖、②每趟蓋章、④車型「剛好／太大／不夠」、⑤兩端站需求燈，排在核心玩法第 5 個 PR 之後，當「回饋第二批」，由遊戲規劃開 session。理由——玩家：先讓核心玩法好上手，再加細節；開發：和回饋共用同一套 GamePresentation 事件，晚做不重工；美術：照《沿線》的畫風重畫，不用影片的霓虹；音樂：蓋章可沿用目標旋律的音色 | session_01NoAXS67jevFRE5XRz37tcF（研究） |
| 高鐵示範的誤點 | 作者 2026-10-15：「沒差先誤點再看怎麼調整」。#660 之後誤點中位數約 7 分、最多 27 分，作者接受；調整方向記在 #660 的留言 | #660 |
| iPhone 左欄縮回 56 點後，iPad 建造欄還是 72 點 | 「作者決定的」沒有原話可查。**遊戲規劃 2026-10-16 決定維持 72 點**。理由——玩家：iPad 畫面大，72 點比較好點，也沒擠到地圖；開發：#721 已經合併，不用再動；美術：iPad 的工具欄留在左下，和 iPhone 本來就是不同排版（決策 226）；音樂：無。作者實機看了覺得要縮，再開一個小 PR | #721（已合併） |
| 加依賴：ACE-Step 1.5 當離線配樂工具 | **遊戲規劃 2026-10-16 決定：現在不加**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」）。玩家：現在缺的是好上手，不是配樂的種類；開發：要 Python 與 GPU，雲端 session 沒有 GPU，只能在作者電腦上跑，而且要改決策 219 §2.2；美術：無；音樂：MML Studio 的流程（決策 219）讓配樂和到站鈴同一種音色，生成的配樂音色不一致。配樂需要更多變化（聲音第 3、4 階段）時再評估 | 已決定 |
| 加依賴：`tools/` 用 glTF-Transform 與 meshoptimizer（npm），讓 3D 的 GLB 在電腦上轉檔 | **遊戲規劃 2026-10-16 決定：同意，只在 `tools/` 用**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」；加依賴是作者保留的決定，合併協調 session 再問作者本人，作者回「四方 思考 最後做決定」，#729 才合併）。條件：兩個都是 MIT；寫進 `tools/` 底下一個工具自己的 `package.json`，版本釘死，加上 lockfile；App 與 Swift 套件不讀它們，也不打包進 App；授權寫進該工具的 README。轉出來的模型照 art-style §7 拆零件、重組、換成調色盤顏色；原始 GLB 與對照留在 scratchpad 或私有參考庫。玩家：3D 的人、車、地標可以更快做到目標畫面；開發：Linux 沒有能讀 GLB 的 Swift 套件（第 4.1 節），用現成工具比自己寫解碼器小；美術：只是取零件的手段，成品還是遊戲自己的風格；音樂：無 | 已決定，3D 生活感 session 可以用 |
| CI 優化（決策 265，session_01LQE9Rif1ggbZsT3iYQiN7G） | 作者 2026-10-16：「我要做pr review 跟ci優化」。四項由遊戲規劃以四方決定：把 iOS 列為必要檢查、關掉 auto-merge 都先不改，#756 跑一陣子再評估；PR gate 的 UI 測試名單不動（`docs/research/CI_MEASURE_2026-10-16.md` 第 3 節 E）；分片逾時上限 20 分不改，下次重新分配分片時再看。之後若 macOS 又常排隊，先看研究文件的方案 | 已決定 |
| CI 4C：自架 runner、Xcode Cloud、第三方 macOS runner | **遊戲規劃 2026-10-16 決定：現在不做**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」）。開發：#693 把 full lane 拆成兩個 job 之後，5 台 macOS runner 夠用；這個 repo 是公開的，自架 runner 會讓 PR 的程式跑在作者的機器上，有安全風險；Xcode Cloud 要作者做 Apple 帳號的設定（`docs/XCODE_CLOUD_ONBOARDING.md`）；第三方 runner 要另外付費。玩家：無；美術：無；音樂：無。macOS 的工作經常排隊超過 30 分鐘時再評估 | 已決定 |
| 複線的最短相隔距離要不要再縮 | 作者 2026-10-14 在手機上問，那個 session 停在權限確認，沒有回答。**遊戲規劃 2026-10-16 回答：不縮**。遊戲的軌道中心間距是 `RailwayNetwork.trackSpacing` 256 單位＝4 m，台鐵一般路段的線間距就是 4 m 左右（高鐵更寬）。畫面上看起來太寬或太窄，是 2D 線的畫法（決策 249），不是間距 | session_01Mtv1QDk434KcMtFHWw67SM |

## 4. 3D 地圖

接手的是「3D 生活感」session（第 2 節）。下面三份交接是 2026-10-16 從做過 3D 的三個 session 收來的，數字對照 main `d542952`。標「估」或「未驗證」的，都沒有量過。

**先讀的決策**：
- 229：3D 地圖
- 230：實例化的列車
- 231：軌道抬高
- 232：陰影
- 234：pmtiles 實景地面
- 235：程序化建物
- 238：遠近分級
- 239：真實建物
- 241：地圖配色
- 242：材質
- 244：街道設施

預覽圖在 `docs/art/map3d-*-2026-10-1*/`。畫風在 `docs/art/3d-style-2026-10-13/`，最接近作者要的是 `ftwplus-street.jpg`。

**作者 2026-10-16 的目標畫面**：明亮的 low-poly 台灣街景，白天，斜上方約 35° 俯看。
- 左邊是紅牆橘瓦、雙層屋簷的廟，屋脊兩端翹起、綠色屋脊。廟前是淺色鋪面的廟埕，三四十個方塊小人，衣服顏色各異。廟埕前有一座紅色牌樓（兩根柱子加一道橫楣）。
- 中間一條雙向馬路，白色虛線分隔，路上有紅、白轎車與幾台機車（有一台載兩個人），人行道有路燈與行人。
- 右邊是 4–5 層的米白、黃色公寓：每層窗上有藍、綠、紅的遮雨棚，陽台曬著彩色衣服，頂樓有藍色水塔；一樓店面是彩色雨遮，門口堆著貨物與攤架。
- 遠處是高低錯落的公寓群，頂樓有水塔與彩色屋頂；左上是綠地、圓球狀的行道樹與一條藍色的河。
- 整體很亮、陰影柔和，活的東西多。

這就是 F 台灣版＋（`docs/art/3d-style-2026-10-13/`）的「＋」。作者回報 67.1／68.1 的 3D 地圖在 iPhone 17 Pro 上 60 fps，加人車之後同等級機型要維持 60 fps，舊機型降級。

### 4.1 架構、預算、坑、素材（3D 任務素材庫 session_01DDMNH81xijBkgM2wVnHEyR）

**讀 GameWorld**
- `Map3DScene(world:snapshot:skyline:focus:baseMap:cityTiles:heights:)`（`Sources/GamePresentation/Map3DScene.swift`）是唯讀的衍生資料，不存世界的第二份。
- 由 `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift` 在 `Task.detached` 裡整個重蓋。路網或城市一變就全部重蓋，沒有增量更新。
- 範圍是已建的部分加 `margin` 1,500 m，每邊最多 `reach` 6,000 m（決策 89 的記憶體理由）。
- 座標單位是公尺：x 東、y 上、z 南。
- 列車不在 scene 裡。`Map3DTrains.frame(...)` 每幀讀 `TrainMotion`，接法是 `view.trains = { eye in feed.frame(in: scene, models:, eye:) }`。

**Chunk**
- 每塊 `chunkSize` 512 m。`Map3DScene.Chunk` 有：
  - `mesh`：前 `baseIndexCount` 個 index 是地面、軌道、道路、玩家建物，任何距離都畫；後面是城市建物。
  - `far`：簡化版的城市。
  - `shadows`：接地陰影，最後畫。
  - `props: [Map3DInstance]`：決策 244 的街道設施。
  - `minimum`、`maximum`：包圍盒。

**遠近分級**（決策 238，`Map3DCamera.wantsDetail`）
- 完整畫要同時符合兩個條件：相機距離 ≤ `detailDistance` 1,600 m；chunk 離目標點或眼睛正下方在 `max(detailReach 700, distance×1.2)` 以內。不符合就畫 base 加 `far`。
- 有遲滯，避免來回切換：已完整的放寬到 1.14 倍才退出，未完整的要進到 0.86 倍才進入（照參考庫 street_scene 的 `updateDetail`）。人和車用同一套，才不會閃。
- 列車：離眼睛 `Map3DTrains.modelReach` 900 m 內畫車廂模型，更遠畫方盒。
- 相機：`nearest` 60 m 到 `farthest` 12 km，依距離傾斜（遠處正上方往下看，近處斜看）。主地圖拉近變傾斜的 3D，可以直接用這台相機。

**實例化繪製**（決策 230、244，可以直接畫人和車）
- `Map3DInstance`：`model` index、4×4 `transform`、`stripe` RGB，每個實例 20 個 float。
- 著色器 `map3dInstancedVertex`：頂點 alpha < 1 的地方換成 `stripe` 的顏色。樹冠就是 alpha 0，所以每棵樹的綠不一樣。人的衣服、車的車身可以照這招，一個模型配多種顏色。
- 模型放在 `Map3DModelPack.standard`（`Map3DModels.swift`）：先列車，再 `Map3DProp.allCases`（`Map3DProps.swift`）。新模型往後加；`Map3DModelTests` 釘了模型總數，要跟著改。
- 建模：用 `Map3DMesh` 的 `addBox`、`addCylinder`、`addFacet`（scene 軸），再用 `Map3DModelPack.Model.flat(named:from:)` 轉成模型空間（+x 前、+y 左、+z 上，每個三角形用自己的法線）。
- 擺放：`Map3DInstance.prop(_:at:forward:scale:tint:)`。
- **不動的東西**（店面貨物、水塔、雨遮、牌樓）：放進 `Builder.props`，進 `Chunk.props`。Metal 端每塊、每種模型一次 draw call，只在 chunk 完整畫時才畫（`Map3DMetalView.swift` 約 372 行）。
- **會動的東西**（人、車）：照列車的做法，每幀由一個 closure 回傳 instances，加在 `Map3DMetalView` 列車 instanced 那段旁邊。
  - 列車現在每幀 `makeBuffer` 一個新的 buffer。上千個人或車時，改成 ring buffer（三份輪流）。
  - 移動狀態放在 GamePresentation，是暫時的表現狀態，不進 GameCore。
  - 亂數用 `map3DRandom(_:_:salt:)`，依位置或 id 取，不用 random。

**量過的數字**（#679，Linux 除錯版，空白的實景新局）

| 地圖 | 行道樹 | 路燈 | 電線桿 | 最多的一塊（三角形） |
| --- | --: | --: | --: | --: |
| 台北 | 6,101 | 2,255 | 1,675 | 34,580 |
| 高雄 | 3,229 | 1,615 | 2,742 | 32,712 |

- 近處通常有 4–9 塊完整畫，街道設施約 13–30 萬個三角形、12–27 次 draw call。
- 每件的面數：樹冠是三團各 20 面；路燈、電線桿都是幾十面。

**draw call 怎麼算**
- 靜態：每塊可見的 chunk 1 次（完整）或 2 次（base 加 far）。
- 陰影：每塊 1 次。
- 列車：方盒合成 1 次，加上每種車廂模型 1 次。
- 街道設施：完整的 chunk，每塊每種模型 1 次。

**沒量過的**
- 整幀的總三角形與總 draw call：`Map3DMetalView` 裡的 `drawCalls`、`triangles` 計數可以印出來。
- 作者在 iPhone 17 Pro 上看到 60 fps，但沒有記下當時的三角形數。

**建議預算**（估）
- 一幀 100 萬個三角形、150 次 draw call 以內。
- 人和車每種模型 200 面以下，只在完整畫的 chunk 或眼睛 300–500 m 內出現。
- 舊機（A15 等）要留餘裕。

**坑：深度閃爍**
- `depthRange`：near = max(1, 0.02×距離)，far = 6×距離 + 4,000。
- 地面的各層靠很小的高度差分開，由低到高：
  - cover：0.04×(rawValue+1)
  - 人行道 `sidewalkLift`：0.26
  - 道路：服務道路與小路 0.28，三級到主要道路 0.32，幹道與高速公路 0.36
  - 中線 `centreLineLift`：0.38
  - 陰影 `Map3DShadow.lift`：0.4
  - 軌道 `railLift`：0.85（道床原本會被地面和廣場蓋掉，決策 231）
- 廟埕鋪面、斑馬線等新的地面層，要插進這個順序裡，不要跟既有的層同高。
- 陰影 pass 不寫深度、用 lessEqual，最後才疊上去。
- cull mode 是 `.none`，但法線和 winding 有測試檢查（`Map3DRealBuildingsTests`）。

**坑：道具穿模**
- 決策 244 的樹、燈、桿只避開軌道經過的格（`removeProps(on: cleared)`）和路口 9 m。
- **沒有**檢查建物輪廓，人行道窄的地方，樹冠可能插進真實建物。加人、車、貨物時一起處理。

**坑：列車被遮住**
- 真實建物和程序化城市都會避開軌道經過的格（`addRealBuildings(..., clearOf:)`）。
- 道床抬高 0.85 m，是為了不被地面蓋掉。
- 高架下的車和人要注意橋墩：`pierSpacing` 32 m，墩的大小是 1.6×2.2 m。

**坑：Metal 在 CI 上驗不到**
- Linux 驗不到 `Map3DShaders.metal` 和 `Map3DMetalView`。只有 `ios-build.yml` 的 Xcode build（PR 的 gate）會編譯；幀數只能在實機看。
- 預覽工具 `tools/map3d-preview/`：
  - `Map3DPreviewDump.swift.txt` 要暫時複製進 Tests，用 `MAP3D_WORLD=kaohsiung|taichung`、`MAP3D_CITY=1` 等環境變數跑，跑完刪掉。
  - `render.sh` 用 headless Chromium 的 WebGL 照 Metal 的算式重畫，著色器是手抄的。改 shader 時兩邊要一起改。
  - 材質常數（第一層 18、`detailRepeat`）由 `Map3DSurfaceTests` 釘住。
  - 預覽圖是軟體算的圖，不是 iPhone 的畫面。

**其他**
- 頂點的 layer 編碼是 surface + 64×(detail+1)（決策 242）。`Map3DSurfaces.png` 有 22 層，每層 512 px。
- scene 每次整個重蓋，加很多靜態實例會拉長重蓋的時間。
- 美術規則見 art-style §7：素材都能用，但要混合、改成遊戲的配色與低多邊形再產出，不照搬。公開 repo 只放改過的成品；加工腳本與原檔對照留在 scratchpad 或私有庫。素材庫的圖與模型不上傳到會保留或拿去訓練的外部服務。

**看過、還沒搬的素材**
- 本 repo 的 `Web/CityView/src/world/`（MIT，Yong Su 與本專案的修改）：
  - `traffic.js`：車在道路圖上跑，有紅綠燈、跟車間距、路口讓行，台灣靠右。
  - `props.js`：號誌 `signalGeometry`、公車站 `busStopGeometry`、停放的腳踏車 `bikesGeometry`、販賣機 `vendingGeometry`、雕像 `statueGeometry`、遊樂設施 `playGeometry`。目前只用過 `poleGeometry`、`lightGeometry`、`blobTreeGeometry` 的尺寸。
  - 還有 `signs.js`、`ads.js`、`decals.js`、`lamplight.js`（夜間燈）、`landmarks.js`（地標清單）。
- App 裡的城市 tile（`RailwayGameApp/Resources/BaseMap/city/{kaohsiung,taichung}`，來源是 Overture／OSM，授權 ODbL 與 CC BY，`DataSourceCredits` 已列）：
  - TKY1 v7 的每個 tile 除了建物，還有路面、設施、電線、牆、招牌五段，也就是高雄、台中真實的設施、招牌、電線位置。
  - `CityTile.swift` 現在只讀建物，其他五段跳過（header 的 `skip(5*4)`）。
  - 格式見 `Web/CityView/src/shared/tileformat.js` 的 `decodeTile`。
- 私有參考庫 `a91453/railway-reference-private`（作者授權）：
  - `Railway/street_scene_reference_clean/`（銅鑼灣街景）：
    - `source/models/street-agents.glb`：行人、遠距行人、車輛、街頭道具的範本，共 213 個 mesh，用 EXT_meshopt_compression 壓縮，沒有骨架，動作由 JS 做。
    - `source/assets/scene.js`：行人與車的移動、事件、日夜、遠近分級。
    - `causeway-bay-buildings.gltf`：店面。
    - OSM 的部分是 ODbL，要保留署名。
  - `Railway/procedural_assets_reference_clean/`：**購買的素材包**，條款在 `ASSET_LICENSE.txt`。
    - 可以用在遊戲、可以修改、不必署名。
    - 不能原樣轉散布 pack 檔、元件或調色盤；不能放進競爭的素材庫；不能拿去訓練或評估生成模型。
    - 程序化建模的 JS 在 `source/preview/<pack>/assets/createModel-*.js`，可以照決策 235 的方式翻成 Swift 再改風格。
    - 跟這條線有關的：
      - japan：Temple Gate、Temple Main Hall、Stacked Shop House、Kishi Corner Shop、Shop Building、Storefront Display Rack、Produce Carton Pallet、Rooftop Water Tank、Chochin Lantern、Kei Taxi、Kei Truck、Sedan Taxi、Bus Stop Sign Board
      - suburban：Car suv、Classic car、Pickup truck、Gable Roof Bus Shelter
      - tiny-cubes：Market Stall、City Shop、City Car
      - city：Voxel Corner Store、Illuminated Advertising Kiosk
      - blocky-characters：100 個角色
      - rooms：Laundry Basket、Paint Cloth Drying Rack（可以參考曬衣）
    - 日式山門不是台灣的牌樓，要改成紅柱、燕尾脊。廟的紅脊色已有 `Map3DPalette.templeRidge`；真實建物裡用途 454 是廟（決策 239）。
  - `Railway/commuter_journey_reference_clean/`（香港地鐵）：人潮、排隊、車門、店舖。它用了 `Math.random`，只能搬進表現層。
  - `Railway/island_city_reference_clean/`：居民、工作、程序化模型。它用了 `Math.random`，只搬規則與數值。
  - `Railway/city_world_reference/`：街屋的地塊規則，已經用在決策 235，第三方聲明在 `THIRD_PARTY_NOTICES.md`。
  - `OpenWorld/reference_snapshot/play/src/world/tamkang-bridge.js`、`bridge-blender-visual.js`：淡江大橋的零件。它是 200 m 的斜張**公路**橋，不能當鐵路高架，可以當地標。
  - 台鐵三款 GLB 每個 16–20 萬面，太重。
  - `Railway/night_district_reference_clean/`、`location_modeler_reference_clean/`：只看過目錄，沒細讀。
- 網站的素材：
  - 貼圖是 Poly Haven（CC0），在參考庫 `Website/site/city/textures/`。決策 242 只取了灰階當底紋。
  - N700ST 列車是 Meshy 產生後再加工的。依 Meshy 條款，要能看出是 AI 產生。

**它原本想做的下一步**
1. 讀 tile 的其他五段：用高雄、台中真實的路面、設施、招牌、電線，取代決策 244 依道路等級推估的擺放；也補上電線（決策 244 的缺口）和路口號誌。
2. GLB 在電腦上轉檔，不在 App 裡讀。
   - Linux 上沒有能用的純 Swift 讀取器：SwiftGLTF 在 Linux 失敗，GLTFKit2 只支援 Apple。
   - 做法：在 scratchpad 寫腳本，解 meshopt（meshoptimizer 是 MIT）、減面、換成遊戲的配色，輸出成 `Map3DModelPack` 能讀的頂點資料。不加 runtime 依賴，要加是作者的決定。
   - 對象：street-agents.glb 的人和車，以及地標（淡江大橋、日月潭）。
3. 3D 列車讀 `TrainLivery`（決策 243，#677）的 `body`、`stripe`、`cab`、`nose`，不另外定顏色。
4. 全台的建物圖層：等作者決定 App 容量。目前兩區的 tile 約 2.6 MB，全台沒量過。

### 4.2 夜晚與地形（session_01RuxRaNwRfKKNijYAe4ReU6，#690）

細節在決策 229、234 的「續（2026-10-16）」和 `docs/art/map3d-night-terrain-2026-10-16/`。

**夜晚怎麼做**
- 開燈的程度：`Map3DLighting.lights` = night×1.4，上限 1，黃昏就開始亮。Metal 從 uniform `shade.y` 讀，白天是 0。
- 會發光的頂點：layer 設成 `Map3DVertex.glowing`（−2），用 `Map3DMesh.makeGlowing(from:)` 標。著色器在霧之後加上 `顏色×1.3×lights`。
  - 實例化模型（`Model.flat`）會保留 glowing，instanced vertex shader 也會把 −2 傳下去。
  - 路燈的燈頭就是這樣做的，顏色 `Map3DProp.lampLight` 0xFFE3B0。
- 地上的光圈：`Map3DMesh.addPool` 放在 shadows mesh。陰影頂點是黑色，有顏色的就當成光，alpha 乘上 `shade.y`。
  - 光圈在 `Builder.addLampPools()` 裡加，要在 `removeProps` 之後，照 chunk key 排序（為了決定論）。
- 亮窗：貼圖不動，全在著色器裡算。
  - 玻璃的判定：有窗的圖層裡，mask 為 0（不染色）而且亮度 ≤ 門檻；店面整面都算玻璃。
  - 亮不亮：用 hash12(格子 floor(surfaceAt) ＋ 牆面平面 `[[flat]] plane`)，每晚亮同一批窗，不會閃。
  - 各圖層亮窗的比例在 `Map3DNightWindows.rule`（GamePresentation），經 `Map3DLighting.nightWindowRows`（12 列）傳進 uniform `nightWindows`。新增 `Map3DSurface` 時要加 rule，總層數不能超過 24。
- 改著色器時，`tools/map3d-preview/index.html`（WebGL 版的同一套算式）要一起改。dump 的陰影格式是 7 個 float：xyz、rgb、a。
- 夜晚的環境光是 0.75 加月光。`Map3DNightAndGroundTests` 釘了地面、道路、牆的亮度下限，以及「夜晚仍是藍色」。

**新的人、車、店面怎麼接上夜晚**（建議）
- 車：頭燈、尾燈做成小方塊並標 glowing，頭燈暖白、尾燈紅（0xFF3B30 一類）。
  - 要讓車燈照在路面上，可以沿用 `addPool`。但 pool 是靜態的、放在 shadows mesh 裡，會動的車要每幀另做一份 instanced 的光圈，或乾脆不做地面光。
- 店面招牌的招牌面用 glowing，整面發光，晚上最顯眼。廟埕、牌樓的燈籠與燈串也用 glowing，顏色用紅與暖黃。
- 列車的車窗和頭燈還沒做（#690 列為缺口）：可以把 `Map3DModels` 的車窗頂點標成 glowing。
- 人：晚上少一點，`lights` 越高人越少，例如乘上 (1−0.5×lights)。夜市、廟埕、車站例外，晚上反而多。只用 `lights` 或 `night` 決定，不另外接時鐘，這樣才有決定論。

**地形與地面的坑**
- 世界的地面只在軌道經過的 1,024 m 區塊讀進來（決策 124），沒讀的區塊 `world.groundHeight` 回 nil。
  - 3D 一律用 `Builder.ground(x:y:)` 或 `drawnGround(x:z:)` 取高度：它們會改讀高度檔（`FileGround`），世界邊緣以外取邊上的值。
  - 不要直接用 `groundHeight ?? 0`，那就是原本斷崖的 bug。
- 東西要貼地就用 `drawnGround`（跟 64 m 的三角形一致），不要自己內插。抬升的順序照 `Map3DRealGround`：水 < 人行道 < 道路 < 中心線 < 陰影 0.4 < 軌道底。
- 平坦的實景地圖（決策 198）`groundHeight` 永遠是 0，3D 不套高度檔，這是對的。
- 道具會被 `removeProps(on: cleared)` 從軌道經過的格清掉，任何依附道具的東西（例如光圈）都要在這之後才加。
- 加進 shadows mesh 的東西會影響 `Map3DRealGroundTests` 的地塊計數，那個計數現在只算黑色的三角形。
- `Map3DRealGround.swift` 沒有 import Foundation，要用 sin、cos 就把表放在 Map3DProps（例如 `poolRing`）。
- 預覽工具的大場景會讓瀏覽器記憶體不夠（OOM），`MAP3D_CROP` 半徑約 1,400 以內比較安全。

### 4.3 F 台灣版＋ 的人車與街景（畫風示意 session_018sTU6EMMCProJhAkswMiuo，#520）

示意場景是 2026-10-13 用 three.js 在 scratchpad 做的，沒有進 repo，下面的數字就是它的全部參數。

**參考庫只當量尺**，模型沒有載入或複製。決策 230：作者看過縮面、重上色的白模，說「根本一模一樣」。
- 來源：`Railway/street_scene_reference_clean/source/models/street-agents.glb`，組裝在 `source/assets/scene.js`。
- 量到的尺寸：

| 物件 | 尺寸（m） | 三角形 |
| --- | --- | --: |
| 汽車、計程車 | 4.56×2.08×1.38 | 約 2,076 |
| 小巴 | 7.2×2.5×2.98 | 2,224 |
| 行人近版（27 件） | — | 約 1,616 |
| 行人遠版 `personfar_`（7 件） | — | 378 |

- 它的店招有仿真實品牌的（mcdonolds、watsens、uniqla），不要搬。

**行人**（自己畫，面向 +z，腳底是原點）
- 腿兩支：漸縮的盒子，寬 0.15→0.17、高 0.82、深 0.16，中心 (±0.09, 0.45)。
- 軀幹：漸縮的盒子，寬 0.32→0.38、高 0.6、深 0.24，中心高 1.13。
- 手臂：0.10→0.11×0.54，x ±0.235，中心高 1.12。
- 頸：圓柱 r0.055，高 1.47。頭：icosahedron r0.16 細分一次，高 1.64。
- 頭髮：球冠 r0.175，三種（短髮、鮑伯、棕髮）。
- 手：球 r0.05，高 0.80。鞋：0.11×0.08×0.25。
- 雨傘：cone r0.55、高 0.28，放在 2.1；傘柄 0.9。
- 一種人分三個 InstancedMesh：褲子、上衣（白色幾何，用 instanceColor 每人換色），加上固定部件（2 種膚色 × 3 種髮型 = 6 個模板）。
- 配色：

| 部位 | 顏色 |
| --- | --- |
| 上衣 | E8E4DA 4E78A8 C65A4E 3B3F45 8A9BB0 D9B48A 5E9A78 B04E6A F2F0EA |
| 褲子 | 3B3F45 4E5A6E 6B5A4A 2B2B2B 8A8F96 C9C2B4 |
| 膚色 | E8C9A8、C48E6A |
| 髮色 | 2B2B2B、5A4232 |
| 傘 | 2B2B2B 4E78A8 C65A4E 5E9A78 F2F0EA B04E6A |

- 雷雨時八成的人撐傘。
- 一人約 500–700 個三角形，偏多（球的分段沒有省）。
- 擺放的人數：北月台（列車要進的那一側）70、南月台 22、路兩側人行道 90、廟埕 26、夜市白天 30 晚上 90。

**汽車**
- 用側面輪廓擠出，輪廓點 (z,y)：(-2.28,.32) (2.28,.32) (2.28,.72) (1.35,.86) (.65,1.36) (-1.15,1.38) (-1.95,.95) (-2.28,.9)，寬 2.0。
- 玻璃帶是一個暗色的盒子 2B3440。四個輪子 r0.33、十邊。頭燈 F4F1E0，尾燈 B0302A。

**小巴與公車**
- 小巴 7.2×2.4×2.7。
- 台灣的單層公車 11×2.5×3.2：前方 LED 牌 F0A93C，車頂淺灰。

**車的畫法**
- 一種車分兩個 InstancedMesh：車身（白色幾何，用 instanceColor 換色），加上固定件。夜裡多一個自發光的頭燈。
- 車身色：
  - 汽車：F2F2F0 C9CCCF 3B3F45 9C3B36 5B6E86 E8E4DA 7C8288
  - 公車：3E8C8C 4E78A8 F2F2F0 5E9A78

**機車**
- 車身 0.5×0.45×1.3，加前擋。兩個輪子 r0.26，加座墊、把手。
- 騎士：軀幹、腿、頭，戴白色安全帽。

**機車與汽車的擺放**
- 站前道路靠右 34 台。車道 z：西行 27.6、29.4，東行 30.6、32.4。
- 平交道柵欄放下時兩側排隊 4＋3 台，**機車 10 台停在最前面**（待轉區的感覺）。
- 路上 18 台機車有騎士；透天厝門口停 0–3 台。

**透天厝的街面**

尺寸：寬 4.2–5.6 m、深 13 m、3–5 層，每層 3.3 m。外牆 9 色磁磚：E9E2D3 D9D6CF E2C9B8 CFDCD8 EDEDEA D6CBB8 C9D3DE B9B2A8 E6D9C9。

一樓：
- 騎樓：3 m 高的暗色退縮（5E5852），兩側柱子 0.4×0.4。店面是亮的玻璃或鐵捲門（BFC3C8）。
- 店面陳列擺到騎樓：
  - 櫃台：寬×0.55、高 0.9、深 0.6，顏色 D8D0C2、8E6E52、C9CCCF；
  - 櫃台上放 3 箱貨，每箱 0.5×0.35×0.35，顏色 E86A7A F2D24B 5E9A78 4E78A8 F2F0EA D98A4A；
  - 低遮雨棚：深 1.1 m、往外斜 0.25 rad、高 2.95 m，顏色 3E8C8C C65A4E 4E78A8 F2F0EA。

樓上每層：
- 窗：寬×0.62、高 1.5。鐵窗是 3 根 0.07 的直桿加一根上橫桿。
- 陽台板深 0.7，樓層飾帶 0.12。
- 鐵皮雨遮：寬是窗寬＋0.6、深 0.9、斜 0.35 rad，在窗上 1.05 m，顏色 7A93A6 6F8E7C D5D1C6 9AA3A8。
- 曬衣：45% 的樓層有，4 片 0.45×0.6，掛在陽台外 0.62 m，顏色 F2F0EA 4E78A8 E86A7A 8A9BB0 D9B48A。
- 花台：35% 有，0.9×0.35×0.35，顏色 6A8F4E。
- 冷氣：30% 有。

其他：
- 直立招牌：50% 的店有，0.25×(3–7)×1.0，夜裡自發光。
- 屋頂：
  - 頂樓加蓋：60% 有，寬減 0.4、高 2.6、深×0.6，上面是鐵皮山牆屋頂高 0.7 m，顏色 7A93A6 6F8E7C 9C6B52 8E9AA3。
  - 水塔：75% 有，r0.62、高 1.1，藍色 3F6FA0 或不鏽鋼 C9CCCF。

**廟埕與牌樓**
- 廟埕：石鋪 34×16（D8D0C2）。台基 24×22×0.8。
- 三川殿 18×8×4.6，屋頂高 2.8。正殿 16×9×5.6，屋頂高 3.4。
- 顏色：牆 A8342C、瓦 C2603C、脊飾帶 3E8C8C、脊中央的綠飾 4F9A6A。燕尾是兩端各斜 0.5 rad 的盒子。
- 前簷 4 盞紅燈籠 E0392C，夜裡自發光。香爐 r1。
- 牌樓：柱 0.9×6，在 ±6 m；橫樑 14×0.9，在 5.4 m 高；上面一個小屋頂。
- 廟面向站前道路，牌樓就在路邊。

**光**

| 天氣 | 設定 |
| --- | --- |
| 晴天 | sun FFF6E6×2.5；hemi D4E8FF／B9C99F×1.35；天空漸層 3D8BE0→9CCDF3→EAF5FB；霧 E2EFF8，320–1100 m；Neutral tone mapping，曝光 1.08；AO；建物下貼一張模糊方塊當接地影（黑 32%） |
| 雷雨 | sun C9D3E0×0.55；霧 8F989F，90–520 m；路面粗糙度 0.18，濕亮；窗戶提早亮 |
| 夜 | 窗 FFC98A，輕微泛光 |

**三角形與遠近分級**
- F 台灣版＋一個畫面 72–78 萬個三角形、79–98 次 draw call（人車都用 instanced）；沒有人車的 F 台灣版是 33 萬。
- 示意場景沒有做遠近門檻（全部畫近版），所以這是上限。
- 建議的門檻（未驗證）：
  - 鏡頭距離 ≲150–200 m：完整的人、車、騎樓陳列、曬衣、雨遮。
  - 150–400 m：人換成 7 件的遠版（目標每人 20–40 個三角形）或不畫；車換成兩個盒子。
  - 400 m 以外：人車都不畫，透天厝只剩盒子、屋頂、水塔。決策 238 的 700 m／距離×1.2 分塊遠版可以沿用。

**當時「定案前要補」的三件事，現況**
1. 真的台灣車與站房：列車已經做了（決策 230、243、252）。main 上找不到專屬的台灣站房。
2. 擋住列車的建物變透明：Map3D 沒有透明化或淡出，shader 只有接地影的 alpha。
3. 建造時地面調淡：3D 還是從設定或 ContentView 打開的獨立預覽（`Map3DPreviewScreen`），沒有接到主地圖的建造模式，所以「建造時正上方、地面調淡」還沒有對象。

**main 和 F 台灣版＋ 的差距**
- 沒有人，路上也沒有車（Map3DProps 只有樹、路燈、電線桿；列車以外沒有會動的東西）。這是和作者那張圖最大的差別。
- 透天厝的立面細節是貼圖（`Map3DSurface` 的 homeWindows、homeBalcony、shopfront、shopEatery 等），畫在平的牆上。示意圖裡的雨遮、曬衣、店面貨物、騎樓柱是凸出牆面的幾何，斜看時有影子和厚度，這才是生活感。陽台、冷氣、直立招牌已經是幾何（決策 238），方向是對的。
- 騎樓沒有退縮的空間：一樓是貼圖，沒有陰影深處和柱子，貨物也擺不進去。
- 有廟（決策 235），但沒有廟埕、牌樓、人潮、燈籠。廟固定面向南，不一定面向街。
- 配色：決策 241 改用遊戲 2D 地圖的色系，比示意圖的晴天飽和度低。作者看的是明亮的晴天，要不要調亮，拿 `ftwplus-street.jpg` 並排給作者看再定。
- 拉近就傾斜：相機已經有（`Map3DCamera`，300 m 內傾到 55°），但只在預覽畫面，主地圖還沒有。

**建議先補的三件**
1. 先上人和機車（不是汽車）：
   - 照上面的零件比例做一種行人和一種機車騎士，用 InstancedMesh、每人換色。
   - 一開始就做好遠版與距離門檻。
   - 擺在月台（照遊戲裡真的候車人數）、廟埕、站前人行道、平交道前。
   - 台灣街景的辨識度有一半在機車。
2. 透天厝的一樓做成真的騎樓：
   - 一樓退縮 2–2.5 m 留出陰影，加柱子，店面貨物和低遮雨棚擺進去。
   - 樓上加凸出牆面的鐵皮雨遮和曬衣，只在近版。
   - 貼圖留給遠版。
3. 廟埕、牌樓、人潮做成一個「地標組」：
   - 廟改成面向最近的街，前面留廟埕，街邊放牌樓，燈籠夜裡亮，廟埕擺人。
   - 一個城鎮一兩個就夠，當畫面的焦點。

之後再做：汽車與公車、雷雨撐傘、擋住列車的建物淡出、接到主地圖。

示意圖相關檔案：
- `ftwplus-street.jpg`：最接近作者要的畫面；
- `ftwplus-street-storm.jpg`：撐傘；
- `ftwplus-close.jpg`：列車、月台的人、平交道排隊；
- `ftwplus-phone.jpg`：手機上的實際大小；
- `ftwplus-street-night.jpg`：夜晚；
- `compare-ftw-ftwplus.jpg`：有人車和沒人車的對照。

### 4.4 3D 生活感這條線做到哪（session_01EPkWLr5a25LyJvCuvh1U3R，2026-10-17 更新）

遊戲規劃 session 派的四步，對照作者的目標畫面（本節開頭）。69.1 發版前收工。

**做完的**：
- **第 1 步：行人與車輛**（決策 259，#734）。
  - 方塊人、機車（一人或兩人）、轎車、廂型車，用 instancing 畫，只在拉近時出現。
  - 月台人數照候車，站前照一天的旅次，街上照城鎮人口；晚上店面與人行道的人少一半。
  - 依 GPU 決定份量，掉幀時再降一級；右上角細節顯示人數、車數、份量。
- **第 2a 步：空白地圖的種子道路**（決策 263，#745）。
  - 主要道路、街、巷照種子分配，和實景地圖共用 `addRoads`。
  - 軌道優先：地面上越過的畫平交道，高架下避開橋墩，路堤、路塹、月台旁邊不畫。只有主要道路與一半的街越過鐵路。
  - 透天厝沿街排、正面朝街。
- **第 2b 步：騎樓與生活細節**（決策 267）。
  - 騎樓柱、櫃台與三箱貨、低遮雨棚；樓上一半的樓層有彩色鐵皮雨遮，有陽台的 45% 曬衣；屋頂 75% 是圓水塔（遠處仍是方塊）。
  - 種子道路旁的透天厝，面向主要道路 70%、面向街 40% 一樓開店。
  - 這些小東西在第 4 層 LOD `Chunk.close`：鏡頭 450 m 內、分塊 350 m 內才畫（`Map3DCamera.wantsClose`），每塊多一次 draw call。之後的小細節（廟埕的燈籠、攤架）也放這一層：`Builder` 的 `target = .close`。
  - 斜交平交道的柵欄沿軌道法線離開道床、平台照 1/sinθ 加長；複線 8 m 內的交點合成一個平交道。
- **第 3 步：廟埕與牌樓**（決策 268）。
  - 廟面向格子四邊最熱鬧的種子道路（`templeFront`），台基後退，前面是最深 16 m 的石鋪廟埕，人行道邊立牌樓，簷下 4 盞夜裡發光的燈籠，兩角各一棵榕樹，廟埕 36 人。
  - 兩面臨街的透天厝後院，70% 鋪草地、1–3 棵樹。
  - 沒做：空地仍是素色（決策 241）、三級道路沒有行道樹（`addRoads` 和實景地圖共用，要另外看實景的效能）、實景地圖的廟沒有廟埕。
- **第 4 步的前半：拉近就傾斜**（決策 269）。
  - 2D 雙指拉近到 3D 站在 800 m 的比例時交給 3D，3D 拉遠超過 960 m 交回；縮放按鈕、建造工具、教學不交接（核心玩法 session 同意：引導的點擊在 2D 上）。
  - 3D 傾斜曲線：800 m 以外平視、150–200 m 約 34–40°、最多 42°。
  - 3D 場景放在 `Map3DSceneCache`（App），同一個世界只蓋一次，2D 拉到門檻一半就先蓋。
- **第 4 步的後半：2D 拉近畫種子道路**（決策 270）。
  - `Map3DScene.seededStreets(world:)` 只鋪軌道與月台、照決策 263 的規則選路（不蓋城市），和 3D 場景的 `seededStreets` 一模一樣（測試釘住）。
  - 2D 照實景道路的配色畫，64 m 格子 16–24 點時淡入。沒做：2D 的平交道記號、道路名稱。
- **#752（N700）的收尾**：#764（Antigravity）還原了其他車頭，#770 補 EMU3000 鼻頂，`Map3DModelTests` 釘住四款車頭的鼻頂顏色（決策 230 之後的修正）。

**下一步，照順序，一次一個 PR**：
1. 第 4 步的後半（決策 270）做完後，四步都完成；之後由遊戲規劃排序。決策 269 的缺口仍在：交接後要放開手指再雙指；3D 的方向交回時不保留；3D 裡沒有建造。
- **配色**（決策 272）：白天的光強一成二、公園與樹更綠；地面與道路照決策 241。目標畫面的大片草地沒有做，要做是另一個決策（連 2D 一起）。

**留下的缺口**（決策 259、263 的缺口一節有完整清單）：
- 車流：沒有跟車、紅綠燈、路口轉彎，車到道路端點就縮小消失；底圖沒有 oneway，所以單行道也畫成雙向。
- 人車沒有影子，車燈不照在路面。
- 平交道的柵欄不會隨列車放下，警示燈不閃，也沒有噹噹聲。
- 路在路堤、路塹處斷開，沒有地下道或陸橋；主要道路的路口沒有號誌。
- 第 2b 步沒做的：陳列只有櫃台與貨箱（沒有攤架、騎樓下的機車、花台），雨遮與曬衣沒有影子，實景地圖的建物沒有這些細節。
- 實機都還沒驗證：人車的幀數、舊機型降級、場景建構時間。兩鎮地圖除錯版的近版三角形 26 萬 → 45 萬（決策 263）→ 57 萬（決策 267），一個 170 m 的近景約 8 萬＋最近一層 2 萬 3 千。掉幀時先把 `Map3DCamera.closeReach` 調小，再把圓水塔換回方塊。

**預覽工具**（`tools/map3d-preview/README.md`）：
- `MAP3D_LIFE=x:z:距離` 畫人車；`MAP3D_BUSY=1` 把每站當作很忙；`MAP3D_LIFE_DETAIL=reduced` 畫舊機型的份量。
- 要知道平交道在哪：暫時在 dump 測試裡印 `scene.levelCrossings`，用完刪掉。
- 預覽預設連最近一層一起畫；`MAP3D_DETAIL=near` 不畫它。鏡頭的傾斜跟著距離，40 m 時幾乎往下看，所以騎樓的近照要選順著街的方向。

### 4.5 Peakline 圖資與離線模型研究（Codex，2026-10-19）

研究基準 main `43f6abc95bd4235a07f91480e401231cbf4cfe5f`；報告：[PEAKLINE_MAP_ENGINE_STUDY.md](research/PEAKLINE_MAP_ENGINE_STUDY.md)，附錄保留141筆套件、26個來源與E01解碼器（D26/E01同一上游），含官方查核、GLB與WorldCover小樣本。普通GLB轉換器已完成，本研究沒有重做或改App。

只推薦一個後續工具任務：報告§8的「無貼圖、無skin的靜態meshopt GLB → `.m3dmodel`橋接」，含節點選取與非AI來源紀錄；沿用§3已同意的tools-only glTF-Transform／meshoptimizer、固定版本／lockfile／README授權，不再列成未批准。正式工具尚未實作。WorldCover僅列視覺補漏候選；現有`addArea(.wood)`會影響程序城市展示地塊，不能直接灌分類。本環境香港下載403，但#820補充已有香港實際樣本、材質誤判與參考庫現成WorldCover，見主報告§3／§5；skin整體轉換與iOS／實機仍未驗證，無手機效能數字。初版functions間接LGPL漏查已更正；後續只用core／extensions4.5.1＋meshoptimizer1.3.0的五個MIT包，bridge lock／逐包授權與無functions重跑證據見附件，不把歷史offline lock視為已批准工具。原始參考GLB、加工腳本及原檔對照留scratch／私有交付，不放公開repo。排程仍由NEXT_PRIORITIES與遊戲規劃處理。

## 5. 已知、還沒派的待辦

| 事項 | 來源 | 狀態 |
| --- | --- | --- |
| 高鐵示範快轉只有約八成速度（一個 tick 123 ms，間隔 100 ms） | 決策 248、#709 | 排在核心玩法之後 |
| 高鐵的長進路／閉塞區間死結、台南—左營交會 | #669，機廠 session session_01YNBmv76sfS8gJUnyRKEqHV（不再接新工作） | 沒有人接。機廠出庫已由 #678 處理；B 方案（`claude/hsr-depot-exit-priority`）量測失敗、放棄，紀錄在 #685。決策 255（單線提早折返）**沒有**解這一項：高鐵是單向的班次（決策 133），時刻表不會回到同一站，不會用到折返 |
| 決策 306 之後，號誌開著的高鐵示範還能做的五項（作者 2026-10-21 問「是不是已經優化到極限了」；車速這條路已到頂，最快就是車的性能與彎道限速，剩下的晚點與取消多半不是速度造成的）。照這個順序：(1) **沒有閉塞時的兩個互等與追回時間**（決策 306「下一步」第 1 點：台南的進路宣告、左營咽喉與要入庫的閒置車；沒有閉塞時一天還取消 85 班，效果最大），約 1 天，改 `RouteReservation.swift`、`RunDepot.swift`、死結判斷，可能動 replay；(2) **平地五站停晚 93 分的那一班**（決策 306「下一步」第 2 點），1–2 小時，查完多半併進別項；(3) **五站停跟在慢車後面**：五站停的表定本來就快，追不回來，晚點中位數停在 9 分，要從待避的排法下手（決策 294），約 1 天，結果不確定；(4) **南港咽喉**（照地形剩的南港 08:30 取消，決策 302「下一步」第 2 點），半天到 1 天，和下一行的六家基地都改示範的機廠配置，併成一件做；(5) **晚點時壓縮停站**（真實鐵路的做法，沒試過、沒量），約半天。五項都改同一塊 GameCore、量同一個示範，平行做要互相重量，所以一個 session 照順序做，全部約 3–4 天 | 作者 2026-10-21（session_011GLH8sEjxxMsy2VEXa8szu 估計與排序） | **第 1 項進行中**：作者說「開新session做4」，session_0125dMtwyMdz7mzoBCRNa1pn。其餘排在它之後，也排在 77.1（自動派車，改同一塊派車，影響每個初學者）之後；示範預設是號誌關，這五項只改善號誌開著的組合。順序由遊戲規劃排 |
| 高鐵示範北端的機廠改成真實的配置：南港站東的 2 條盡頭線（約 8 組）加新竹的六家基地（OSM：新竹站東約 500 m、下行線同側，8 股、每股約 420 m，`tools/hsr-depots/hsr_depots.json`），取代決策 221 的「南港機廠 11 股」（台灣高鐵北端沒有機廠，決策 280） | 作者 2026-10-18（session_01KeynzCwtDyLHTUYBfKxy1c，問「建六家機廠有幫助嗎」後說「寫進HANDOFF排著」） | **排在決策 302（`claude/hsr-depot-churn`）合併之後**：原本等的南港咽喉已由決策 283 修好、真實地形已打開，決策 297 後照地形一天只取消 4 班；決策 302 正在改機廠進出的判斷，六家也動機廠進出，同時做會互相干擾量測，所以等它合併、重量一天再做。它解不了南港咽喉的卡死（白天、終點站的調度）和左營夜裡的排隊（南端），只讓北端更真實；代價是南港與新竹之間每天早晚多約 70 km 的空車，可能有新的互等，要重量一天。動 `HighSpeedDemo.swift` 的機廠配置與決策 221，GameCore 不動 |
| §15.3 的內容：觀光列車（第一步在決策 286，後續見 §7.2）、支線劇本、掛機模式、「這版新增」卡片、台灣節慶、各站到站鈴、3D 拉近傾斜與駕駛艙視角、花錢的地方＋新台幣＋分時電價＋車站容量、股票 | NEXT_PRIORITIES §15 | 排在核心玩法之後；各站到站鈴等測試者回報 |
| 台灣以外的實景地圖沒有人口、地點、分區、水域、陡坡、建物覆蓋率與真實鐵路：新車站一律 10,000 人次、住宅區（決策 262 加了 127 個城市，`Ci/` 的 53 座本來就是這樣）。要補就照 `tools/real-world-population/README.md` 的工具，換成各國的 WorldPop 與 OSM 整包檔，一個國家一份資料 | 決策 262 | 沒有人接 |
| 3D：擋住列車的建物變透明、深度閃爍、道具穿模、真的台灣車與站房 | F 台灣版＋「定案前要補」 | 3D 生活感那條線之後 |
| 參考庫 2026-10-18 新增的兩個資料夾，不是新工作，是讓排好的項目省工的素材（照 NEXT_PRIORITIES §16 的順序用，不插隊）。`Railway/taiwan-rail-reference-clean/` 是 `site_archive_clean` 的新版：(1) 高鐵票價表 `source/data/thsr_fare.json`（TDX ODFare，全部站對、票種與車廂；補上 ARCHITECTURE「沒有真實高鐵的票價表」的缺口），給高鐵示範（§16 第 4 項）或「新台幣」那輪（§16 第 5.7 項）；(2) 台鐵時刻表 10-16 版、`thsr_schedule_dense.json`、國土測繪中心的橋隧改判 `rail_structures_official.json` 與較新的 `rail-3d/physical/`（`network.json`、`level-profiles.json` 都和 `site_archive_clean` 不同），給決策 279 的後續與重跑 `tools/real-railways/`、`tools/real-timetables/`；(3) 62 款車型、附出處的編組 `rail-3d/integration/formations.js`、12 個站區模型 `rail-3d/assets/stations/`，給上一行「真的台灣車與站房」。`Railway/world-rail-reference-clean/`：12 個海外城市的路網與班表、120 款車型，可補上上面「台灣以外的實景地圖沒有真實鐵路」那一行；單城班表 26–55 MB，要像平溪線一樣只抽需要的部分，署名照各檔 `source_notes`；`nyc_schedule_dense.lite.json` 的 `source_notes` 寫成 Entur（挪威），用之前先核對 | 參考庫 `058f833`；session_01B2b7QLdd5dVnXNZLmQbcQX 盤點 | 沒有人接；各自跟著它服務的項目做 |
| 從空地畫的複線兩條之間沒有渡線：玩家在兩站點了不同的一條就不相連（70.1 的回報）。決策 284 只讓開新路線的字說出原因與接法；根本的做法是畫複線時兩端自動加渡線，或「月台」工具在複線上一次設兩條的月台，兩個都改建造規則，預覽寫在決策 284「沒選的」 | 決策 284、285、PLAYER_FEEDBACK 70.1 | **做了**（`claude/double-track-platforms`，決策 285）：選了第二種。「月台」工具點在複線的一條上、而旁邊那條和它不相連時，同一個動作兩條都設月台（同一站），兩站點了不同的一條也相連。兩條已經相連（有渡線）時照舊只設點的那條。剩下：從空地畫複線時兩端自動加渡線（第一種）沒有做，預覽在決策 285「沒選的」；待實機確認 |
| 73.1 的「終點無法折返」只從截圖推斷是列車比月台長（決策 284 改了字）。玩家的實際配置沒有存檔：下一版請測試者用「回報問題」附存檔，確認不是別的原因（例如終點的盡頭線放不下整列車） | 決策 284、PLAYER_FEEDBACK 73.1 | 待實機確認 |
| 提早折返（決策 255）後，列車卡的「本趟」仍從沒去的那一站算（74.1 截圖的「扒子岡 13:52 發」）。決策 288 已讓它照一般停站開走、時刻往前移，但卡片與跟隨列還沒說「在龜山提早折返」（決策 255 的「下一步」）。74.1 的玩家配置沒有存檔，下一版請測試者確認不再卡在那一站 | 決策 255、288，PLAYER_FEEDBACK 74.1 | **做了**（`claude/short-turn-card`，決策 255 的第二則「後來」）：卡片與跟隨列的本趟從折返站算，多一行「在龜山提早折返」。剩下：重複的時刻表認不出折返；74.1 待實機確認 |
| NEXT_PRIORITIES §17 的乙線「現實路網」：~~真實車站當建議站點~~（決策 295，`claude/real-station-suggestions`）→ ~~R1 轉乘站~~（決策 298，`claude/r1-transfer-stations`，存檔 64）→ ~~R2 電腦的車照已打包的時刻表在 2D 地圖上跑（只畫）~~（決策 304，`claude/r2-real-trains`）。甲線（M0 之後的 M1–M3、確認路線卡、空窗快轉）由做 M0 的 session 接著做 | 75.1 玩家建議（PLAYER_FEEDBACK 75.1 #1）、競品研究 #832；排序 2026-10-20 | 建議站點：決策 295 已合併（圖釘的大小與好不好點待實機）。R1：決策 298 做完（session_01TePLuBqSCAQxMhhJBTJ8Cq）；待實機：車站卡那一行、新遊戲的開關；決策 298「下一步」列了 R2 要接的地方。R2：決策 304 做完（session_0193ujbBhjzFo37QWceGdzcX）：捷運與輕軌逐班、高鐵一天的班次、台鐵照班距；車站卡列下一班；設定「真實列車」可關。待實機：膠囊的大小與淡度（`RealTrainTraffic.look`）、畫 157 列的時間、iPad 整張地圖。剩下的在決策 304「下一步」：3D 的真實列車、台鐵逐班時刻表（要打包參考庫的 2026-10-16 時刻表）、路線名與站名的英文；R3 照 §19 的順序 |
| 乙線的資料與時段研究（`docs/research/RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md`）：(1) 台中捷運（data.gov.tw 175718，2025 年只有 7 個月、只有出站）與桃園機捷（164957，雲端容器連不上，要作者在台灣下載 2025 年 12 個 CSV）有各站運量，淡海、安坑、三鶯、高雄輕軌、林鐵沒有；(2) 遊戲的一天時段已經接近北捷，差的是潮汐（住宅站早上進站真實 40–46%、遊戲最多 28%），建議三步：量尺報告 → 潮汐開關（GameCore，升一次存檔、量平衡，排在 #851 之後）→ 實景地圖用內政部電信信令的日夜人口（取代 geo-scene 第 4 項）；(3) 北捷路線色維持 App 的值 | 作者問「台中桃園 輕軌 三鶯有網址嗎」「台北捷運有分時段…日間夜間模型」；遊戲規劃派工 2026-10-20 | 研究做完。潮汐第 1 步（量尺）做了（`claude/tide-measure`，研究 §2.5），1.5 步（選資料：電信信令最好，OSM 只當細部）也做了（`claude/tide-data-choice`，研究 §2.6）；第 2、3 步沒有人接，第 2 步的做法在 §7.2「潮汐第 2 步」那一列。**運量（session_01RdsWZvY7RjZeZbiNvn8XP4，`claude/ridership-tmrt-tymc`，PR #869）**：台中捷運（2025 年 7 個月出站）、新北捷運的淡海與安坑輕軌、環狀線（新北捷運網站的每日各站進出站，2025-10 到 2026-09；`trtc_ridership.json` 的環狀線只有台北捷運閘門記到的部分，改用新北的）都已補。桃園機捷（桃捷公司網站每月「各站旅運量統計」PDF，2025 年 12 個月，（進＋出）÷ 2；開放資料 164957 雲端連不上）也已補。**還剩**：(a) 三鶯線現在是通車後 2026-07 到 09 的 3 個月（`--partial`，作者 2026-10-20 要的），2027-07 以後用 `build_ntmc_ridership.py --first 2026-07` 換成一整年；(b) 台中 2027 年初看 2026 是否 12 個月齊了再換；(c) 高雄環狀輕軌沒有各站運量（高雄捷運公司每月的 PDF 只有全線每天的筆數），它的站已改照輕軌的 1 點；高雄捷運公司若哪天公布分站的，再接進 `RealRidership`；(d) 林鐵沒有各站運量：data.gov.tw 林業及自然保育署阿里山林業鐵路及文化資產管理處的 13 個資料集（車站、路線、時刻表、票價等，2026-10-20 查）都沒有運量，afrch.forest.gov.tw 也沒有統計頁；要的話只能由作者照政府資訊公開法向該處申請，拿到前林鐵的站照後備 |
| 真實運量（決策 298：台鐵、高鐵、台北捷運、高雄捷運，#869 加的台中捷運、桃園機捷、新北捷運的淡海與安坑輕軌、環狀線、三鶯線）每年重跑：每年第一季前一年整年的資料出來後，照 `tools/real-ridership/README.md` 重跑（到時平鎮會有數字，廣慈/奉天宮現在是 2026-09 一個月（`--later`）；它 2026-08-30 才通車，重跑 2026 年時除以 365 天會只剩約三分之一，要先讓工具對年中通車的站只除以營運的天數，或繼續用 `--later` 的整月；台中看 2026 年是否 12 個月齊了；新北捷運用最近 12 個 `.ods` 月份，三鶯線現在只有 3 個月，2027-07 起有一年，到時換掉）。**高雄捷運要作者在台灣下載**：data.kcg.gov.tw 擋國外連線，雲端容器抓不到，請作者從 data.gov.tw [159641](https://data.gov.tw/dataset/159641)（入站）與 [159640](https://data.gov.tw/dataset/159640)（出站）下載兩個 CSV、附在對話裡，工具記下 SHA-256 與下載日期，原始 CSV 不進 repository | 決策 298 的「下一步」2、`tools/real-ridership/README.md` | 下一次是 2027 年第一季；台鐵、高鐵、台北捷運、台中捷運、桃園機捷（公司網站的 PDF）、新北捷運雲端自己抓得到 |
| 參考庫 2026-10-20 新增的 `Railway/geo-scene-reference-clean/`（台灣地理資料包）：遊戲的鐵路、車站、地形、居民人口比它準，不換。要融合的：(1) 新車站命名的地名加內政部的聚落（800 m 內有名字的居民 89.0% → 95.6%）、旗津區用官方外框補（`tools/place-names/`）；(2) 3D 的廟放到真實的廟址（`religion/temples.pmtiles`，19,201 座）；(3) 白天人口的比例，和 R1 一起量（先查出處，原包寫「模擬」）；(4) 21 個 `approx` 景點逐個核對、節慶與景點新種類用它的百大宗教活動與古蹟（§16 第 5.5 項）；(5) R2 移植它的 `RailEngine`／`BusEngine`。Ookla 不能商用，不用。之後不只鐵路的「線」（公車接駁 → 離島渡輪 → 航空）的參考也在研究 §6，排在 §17 甲、乙兩線之後 | `docs/research/GEO_SCENE_REFERENCE_2026-10-20.md`、NEXT_PRIORITIES §18；參考庫 `b3af6d8` | (1) 修正 lane、(2) 3D 那條線，都沒有人接；(3)–(5) 跟著它服務的項目做 |
| 刪掉快車停的站被拒絕時，字沒有說要先刪掉哪個停站模式 | 決策 291 的「下一步」、PLAYER_FEEDBACK 75.1 #2 | 沒有人接（GamePresentation 的小 PR） |
| 自動派車時讓玩家調兩列車的發車：兩端對開、或晚前一班幾分鐘（77.1 #1）。現在「加開一列車」把班距設成「來回 ÷ 列車數」，從終點發的車和第一站共用一個派車間隔（`lastDispatch`，決策 23、172、264），所以做不到。要動 GameCore 的派車（每端各自的間隔或發車的錯開分鐘），升存檔 | PLAYER_FEEDBACK 77.1 #1；遊戲規劃 2026-10-20 | **等決策 302（`claude/hsr-depot-churn`，改同一塊派車）合併後由遊戲規劃派**。五方：玩家，初學者第二列車就卡住，影響大；鐵道迷，單線兩列車兩端對開、在中間站交會，最像真的（平溪、集集）；開發，GameCore＋存檔，和 302 同檔，排在它後面；美術，路線卡多一個選項；音樂，無 |

## 6. 留在遠端、沒有合併的 branch

清理時先看這張表，不要刪掉還有用的。

| branch | 是什麼 | 處理 |
| --- | --- | --- |
| `claude/in-app-language` | 語言選單，#727 已合併 | 可以刪 |
| `claude/hsr-depot-exit-priority` | 機廠出庫優先的 B 方案，量測失敗 | 紀錄在 #685，可以刪 |
| `claude/hud-width-proof`、`claude/claude-key-check`、`claude/basemap-align-repro`、`claude/details-card-repro`、`claude/bughunt3-app-proof` | 只用來證明或重現的暫時 commit（「not for merge」「Repro only」「Proof only」） | 可以刪 |
| `claude/review-u9-u10` | U9、U10，已由 #646 那一輪 cherry-pick 進 main | 可以刪 |
| `claude/hsr-train-rostering` | 車輛運用（原車接下一班、閒得久的才入庫）的實驗，量了變差、沒有合併 | 數字在決策 296「下一步」第 1 點的「之後」，可以刪 |
| `claude/real-station-suggestions`、`claude/hsr-overtake-approach`、`claude/hsr-depot-shuttle`、`claude/hsr-rostering-not-adopted` | 決策 295（#844）、294（#845）、296（#846）與 #849，都已合併 | 可以刪 |
| 2026-10-12 以前的其他 `claude/*` | 這份是用淺層 clone 查的，看不到 10-12 以前的歷史，所以沒有核對這些 branch | 刪之前先用完整 clone 確認內容已在 main |

## 7. 舊交接與文件裡還沒做的（2026-10-16 稽核）

2026-10-16 用三個 agent 對照 main `d542952`，把下面這些文件裡寫了「沒修、延後、下一步、等作者」的項目全部查過一遍：
- `docs/archive/` 的 10 份交接，約 90 項；
- ARCHITECTURE 決策 200–254 的後續，約 80 項；
- `docs/research/` 31 份、`docs/art/` 28 份 README、ROADMAP 的平衡待觀察表、PLAYER_FEEDBACK。

已經做完的、已經記在本檔第 2–5 節或 NEXT_PRIORITIES 的，不列。剩下的列在這一節，每一項都有方向和接手的人。查法是讀程式與文件（`git grep`、`git log --grep`），沒有跑測試；「待查」表示原文說可能是刻意的，或要跑起來才看得出來。

同一次也把文件和程式對不上的四處改好：PLAYER_FEEDBACK 59.1 #1–#6 的狀態、54.1 #1 的「拖動」、`docs/art/depot-icons-2026-10-13/README.md` 的定案、OVERVIEW 研究表的 CI 4C。

### 7.1 小 bug 與效能（舊審查交接留下的）

PR #816／#822／#823 的 Codex 獨立審查與待原作者修正：折返後行程準點判斷、秒級存檔窗、車尾清空及舊檔 invariant 工具缺口，見 [PR816_823_REVIEW_HANDOFF.md](archive/PR816_823_REVIEW_HANDOFF.md)；重現程式與四種開關結果都在報告。**R1、R2 已修**（`claude/short-turn-r1-r2`，決策 288 的「後來」）；R3（#822 的作者評估整列車的契約）、R4（`ReferenceWorld` 的作者）還沒有人接。

審查回報清理 session（session_01FUXNvfnNmoSMf58pgakpsF）已經把這 30 項逐項分好類，每一項的去向寫在 `docs/archive/PR685_711_REVIEW_HANDOFF.md` 第十一節的「第二批」：現在修的（#735、#737、#738、#739）、刻意設計已在原決策補「後來」結案的，以及延後等穩定的（附原因、建議做法、影響範圍）。清單只留那一份。

第一批（PR685_711 交接第四節與前兩輪剩下的）的延後項目也在 `docs/archive/PR685_711_REVIEW_HANDOFF.md` 第十一節：狀態列破產倒數、景點計算量、3D 亮窗與反向 Z、3D 開著時的月底報表、#680 清單拖曳、#657 坡道切軌訊息、hook 的 Swift 6.4.1 等，每項附原因與建議做法。

PR #712–#754 那一輪（69.1 收工那一晚）的審查：修了三項，延後的 11 項（自動待避線抬起的列車放不回去、3D 斜交平交道、#752 模型的可追溯性、PR gate 的 UI 時間等）連同原因與建議做法，寫在 `docs/archive/PR712_754_REVIEW_HANDOFF.md` 第四節。3D 平交道那幾項與測試容差已在第 2b 步（決策 267）做完。

PR #786–#872 那一輪（2026-10-21，作者：「很久沒做pr review了 先優先做」）分三組審查，都已合併：
- **A 組 行車控制**（#878，[PR786_872_A_REVIEW_HANDOFF.md](archive/PR786_872_A_REVIEW_HANDOFF.md)）：0 個新發現。延後的在它第五節：
  - **R3**（P2）：#822 的閉塞分界只看車頭。建議 `isClear` 改看車尾，會動閉塞開時的 golden 與 replay。交行車控制的 session 或 #822 的作者，等 302 的後續做完再排。
  - **R4**（P2，測試工具）：`WorldInvariants.violations` 遇到 v28 的自動結構會 trap（`ReferenceVertical.swift:81`）。交 `ReferenceWorld` 的作者；探針的 fixture 數要改成 68。
  - **B4**（P3）：已經誤點的車被折返，時刻表不動，列車卡認不出折返。B 組建議的修法會讓時刻表非遞增、存檔讀不回，不能用。可行的兩條：GameCore 把之後的停靠移到不早於現在（違反決策 288，要重驗 golden 與 replay），或 GamePresentation 從行程紀錄認出折返（較小，建議走這條）。
- **B 組 建造、真實資料、經濟**（#874，[PR786_872_B_REVIEW_HANDOFF.md](archive/PR786_872_B_REVIEW_HANDOFF.md)）：B1–B3 已修，B4 見上。另兩個小項：整平的提示與成功訊息只說點到的那條軌道的長度；#869 之後轉乘的平衡沒有量（`TRANSFER_REPORT=14`，NOT ASSESSED）。
- **C 組 App、介面、3D、工具**（#873，[PR786_872_C_REVIEW_HANDOFF.md](archive/PR786_872_C_REVIEW_HANDOFF.md)）：6 個發現都修了。它第三節有 6 項只讀程式看到、Linux 測不到的，要在 macOS 或實機確認：
  - 3D 場景快取的 key 只數建築與月台（`Map3DPreviewScreen.swift`）；
  - `Map3DSceneCache.clear()` 不會取消建到一半的場景；
  - 路線面板的 `scrollTo` 沒有照「減少動態效果」；
  - 地圖角落按鈕的觸控區只有 44×28；
  - #870 的預覽用 `targets: nil`，建立路線卻用路線自己的目標班距（轉給空窗快轉 session 後沒有在 #877 修：要一張有真實路線的實景地圖才做得出在 main 上紅的測試，又要改 #873 剛改過的 `LineConfirmation.swift`；留給之後，還沒有人接）；
  - diagnosing-bugs skill 的 TICK_REPORT 指令少了 `--skip-build`。

PR #755–#784 那一輪（72.1 那一天）的審查：修了 6 項（路線卡需求燈只數這條線、座位圖換行、關卡「繼續玩」會繼續、3D 場景快取分局、長按的診斷 trace、決策 266 的文字），延後的 10 項（`main` 在 abb306a 的 full lane 紅、`testHoldingAStationTracesItsBusiestTrips` 的根因、整平時的轉乘乘客、72.1 沒有自己的綠 full lane 等）連同原因與建議做法，寫在 `docs/archive/PR755_784_REVIEW_HANDOFF.md` 第四節。

### 7.2 遊戲功能的後續（決策與研究裡寫了「之後」的）

**接手**：遊戲規劃排序後開 session。核心玩法（決策 254）做完以前都不開，除非下表另外寫了。
**方向**：照 NEXT_PRIORITIES §14 的權重排；開工時把這一列搬到第 2 節。

| 項目 | 出處 | 方向 |
| --- | --- | --- |
| 空白地圖「一鍵全開」 | 決策 200 第 6 點 | 併進核心玩法第 4 個 PR 之後的沙盒選項（關卡解鎖後才出現） |
| 颱風一年 1.5 個（氣象署平均 3.6 個），「留給作者決定」 | 決策 208 | **遊戲規劃決定：維持 1.5**。玩家：簡單規則是預設，颱風太頻繁會打斷剛學會的玩家；開發：不用動 golden；美術：無；音樂：無。寫實規則之後可以考慮照 3.6 |
| 劇本節慶（天燈節等）跟著農曆移動（要改存檔） | 決策 211 | 併進 §15.3「台灣節慶」那一項一起做 |
| 彎道限速沒做的：道岔側向限速、節點折角、坡道影響速度、授權終點前照煞車曲線減速、擺式列車過彎加速、交會停站改用 RunCurve、出發時車尾在彎道內、跨呼叫的快取 | 決策 217 第 10 點 | 寫實規則的加深，排在核心玩法之後；簡單規則不受影響 |
| 長按路線看旅程（用車上與候車的乘客）、鏡頭自動縮放、弧線端點記號 | 決策 220 | 併進「回饋第二批」（第 3 節航空手感那一列） |
| 景點新種類：廟宇、夜市、博物館（新圖示、新季節係數） | 決策 250 | 併進 §15.3「台灣節慶」或觀光列車；廟宇可以和 3D 的廟埕一起做 |
| 真正的機客分離：機車掛上、摘下、換端（要改列車模型與存檔） | 決策 252 | 長期；觀光列車（§15.3）之後再評估 |
| 觀光列車的後續：其他具名列車（山嵐號、鳴日號、環島之星、仲夏寶島號）、加價、故事（車種圖鑑）、季節、3D 模型、到站旋律 | 決策 286「下一步」 | 第一步（藍皮解憂號、海風號，停靠景點旁加 0.5★）#819 已合併；山嵐號（`SHANLAN`，數字照海風號）#826 已合併。下一步照決策裡的順序，一個 PR 一項：鳴日號（機車＋5 客車，照藍皮解憂號的做法）→ 環島之星 → 仲夏寶島號，之後才是加價、故事、季節 |
| 2D 車頭形狀多一種「機車頭」（`TrainNose`、`MapArt.drawCars`） | 決策 252 | 小 PR；美術線有空就做 |
| 台鐵示範延長到七堵或蘇澳 | 決策 240 | 併進 §15.3「支線劇本」 |
| 支線情境包：內灣線 → 深澳線 → 六家線、沙崙線（一條一個 PR，只加一筆 `BranchLineChallenge` 的資料、用報告量一次目標；六家、沙崙通到高鐵站，等高鐵示範那條線告一段落） | 決策 289「下一步」 | 第一條集集線在 `claude/branch-line-jiji`；做法、量法照決策 289 |
| 用 `tra_track_sections.json` 每段的 `tracks` 決定描線時預設單線或複線 | 決策 247 | **做了**（`claude/trace-track-count`，決策 247 的「後來」第二則）：整段照多數決一種。剩下：一次描線中途換線（複線段兩條、單線段一條，接頭加渡線），等玩家需要時再做 |
| 坡道上的 X 渡線（四個道岔加中間菱形交叉要同坡度，要動 GameCore 的交叉規則） | 決策 233、247 | GameCore，等玩家回報需要時再做 |
| 拉近才聽得到那一站的鈴聲（`zoomGain()`）＋鈴聲圈 | RAILWAY_SOUND §2.8、§5 | 併進聲音 2b（NEXT_PRIORITIES §14），和各站到站鈴一起做 |
| 玩家建物旋轉；買入城市建物但不拆（P0-D 的另一半） | CITY_BUILDING_STUDY §5、§7 | 城市線，排在核心玩法之後 |
| 拍照模式 | GAP_RESEARCH §3 G | 和 3D 的主地圖整合一起考慮 |
| 平溪線運煤的史實版（O10） | FREIGHT_STUDY §6.4、§8-6 | 缺史料，誰去蒐集還沒定；支線劇本時再看 |
| 空白地圖用種子產生地形、遷葬費、依車種的坡度上限（阿里山要 6%） | TERRAIN_HEIGHT_DESIGN | 阿里山劇本（§15.2 第 7 名）時一起做 |
| 轉乘資料的明確配對沒有匯入（`station_transfers.json` 只在車站資訊裡顯示） | PHASE5、決策 65 | 寫實規則的加深 |
| 收班後車站自動切換營運狀態（`metroComputeStationAutoOperationMode`）沒有移植 | PHASE5 R1 | 寫實規則的加深 |
| 多次調車、無月台倒車、全域最佳解；中途折返的重疊段不拆名義容量 | STAGE_V、決策 63 | gap，維持不做，有玩家需要再說 |
| 預測未來的授權、畫面延遲式的閉塞保持 | STAGE_V、決策 64 | gap，維持不做（手動號誌在 NEXT_PRIORITIES §7 列為不做） |
| 行政區人口；街區與地塊點選、地塊資訊卡 | UI_GAP §7、§8 | 缺資料管線，城市線再評估 |
| 切開「自動」結構的軌道時各段重算（水域晚讀時切不開、明挖段上的建物沒拆） | PR200_290 §4-2，決策 124 | **完成**（決策 282）：兩段沿用原本的區段，只在切點分開。剩下：不是「自動」的結構物（例如地面）切開時照舊依地形與水檢查，之後才讀入的水仍會讓它切不開；沒有玩家回報，沒有改 |
| 滴管（點既有軌道沿用它的構造與高度）等 UX §8 剩下的小項 | UX_REDESIGN_STUDY §8 | 核心玩法的工具欄依解鎖顯示之後再評估 |
| 車站商業沒有逐線帳時，用「需求旅次 × 2」估人次，誤差沒量過 | STATION_COMMERCE §1.2 | 影響小，經濟平衡（economy-balance skill）下次量測時一起看 |
| 平衡待觀察表：飯店回本、觀光景點份量、城市委託份量、加線加站反而少載、車種取捨、公司建物 | ROADMAP 平衡待觀察表 | 核心玩法第 4、5 個 PR 量關卡目標時，用 economy-balance 一起看 |
| City Transport Manager 研究的 M0–M3（只顯示、只動 2D 的 GamePresentation 與 App，不碰 GameCore） | `docs/research/CITY_TRANSPORT_MANAGER_STUDY_2026-10-19.md` 4.0 | **M0、M1 做完**（session_01Vrym4SZSjubXNm9G5XhP3Y，作者 2026-10-20 交辦）：#835 草稿摘要列、#837 財務「今天」卡、#839 一鍵切換涵蓋層（決策 292）。**M2 做完**（決策 293，`claude/m2-next-steps`）：自由遊戲的六個「下一步」（第一條線 → 有一天賺錢 → 第二條線 → 一條線兩列車 → 轉乘站 → 涵蓋一半），地圖上一行、目標面板列全部，做到時打勾與目標旋律，不給錢。待實機確認：地圖上那一行在手機橫拿時擠不擠；TestFlight 問「第一條線花幾分鐘、看不看得懂下一步」（研究 4.0 的 M2 驗收）。**M3 做完**（決策 301，`claude/m3-line-satisfaction`，session_01QC2g3kh7JcDSjwFCDPMfct）：路線卡「乘客感受」三項（候車由班距估算、擁擠＝最擠一班的載客率、準點＝準點率），各 0–100 分與自己畫的三張表情，樣本不夠寫「尚未評分」，最差一項旁放決策 194 的加開列車；車型展示間加一行每營運小時的成本。待實機確認：手機橫拿時路線面板放不放得下分數與按鈕、表情在 20 點看不看得清楚。M3 沒做的（決策 301「沒選的」）：路線清單每列一張臉與照分數排序、乘車時間一項、全公司平均放在頂端。**「確認路線」卡做完**（決策 303，`claude/m4-confirm-line-card`，session_01QC2g3kh7JcDSjwFCDPMfct）：簡單規則下 ✓ 先升起卡片，名稱、顏色、首末班、四個時段各幾列與約每幾分一班、還要買幾列與總價，預設值等於原本的 ✓，開通用決策 264 的一個指令。待實機確認：手機橫拿時 `.medium` 的 sheet 放不放得下四個時段。沒做的（決策 303「沒選的」）：四個時段各自一個數字（要 GameCore 多一個等級）、選來回或環線、一次買超過起訖站停得下的車（要先有「車開出後自動補上」的規則）。**空窗快轉做完**（決策 305，`claude/night-skip`，session_01QC2g3kh7JcDSjwFCDPMfct）：夜裡沒有車時速度下面的「快轉到早上」，跑到第一列車動起來前 10 分，設定可以自動（預設關）。待實機確認：晶片在手機橫拿時和圖層列擠不擠；TestFlight 問自動快轉要不要預設開（研究 4.15）。沒做的（決策 305「沒選的」）：快轉時配樂收小、夜色實驗。M2 的第二階段（點一下領獎金）要 GameCore＋存檔，等 TestFlight 回饋再決定。M1 沒做的：研究 4.1 的潛力熱圖與白天／夜晚 |
| 潮汐第 2 步：住宅站早上進站多、晚上出站多（NEXT_PRIORITIES §19 第 10 名的後半） | 研究 `RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md` §2.4 第 2 列、§2.5；第 1 步的量尺 `Tests/GameCoreTests/TideReportTests.swift`（session_017uh4jMV1KXvMtDi7MVa5Nn，`claude/tide-measure`） | **第 1 步做完**：量尺報告與北捷 2025 整年的數字（`tools/real-ridership/build_trtc_hourly.py`、`trtc_hourly_2025.json`）。遊戲住宅站早上進站佔全天 24.6%，北捷 35–43%；早上進出比 1.6 倍，北捷 6–13 倍；放出比需求表晚約半小時，上班日 00–06 時放出 3.6%，北捷 0.7%。用營運時間（06:00–01:00）當分母，住宅站也只到 25.1%：差距幾乎全是潮汐，不是營運時間。路線收班（01–06）時一天放出 801 人留在站裡等，佔首班車那一小時上車的 41%。**1.5 步做完**（`claude/tide-data-choice`，研究 §2.6，`tools/real-ridership/compare_tide_sources.py`）：用北捷 108 站比較，電信信令的鄉鎮平日日間 ÷ 夜間（162907／162908）最能說中各站的潮汐（早上進站誤差中位數 4.9 個百分點、出站 3.5、早晚比 1.62 倍；遊戲現在的 OSM 類型是 7.8、6.1、1.95 倍，出站比什麼都不知道還差）。加上 OSM 的「地點 ÷ 居民」只在早晚比再好一點（1.52 倍）。所以第 2 步的潮汐強弱用**一個連續的數字**（鄉鎮的日夜比，實景地圖再加 OSM 的地點 ÷ 居民），不要用「挑最多的一種」的類型；研究 §2.6 有配好的式子當起點（兩端被拉向中間，要照目標再調）。空白地圖沒有鄉鎮，用玩家選的類型。**第 2 步的做法**：(1) 先取決策號，把北捷 2025 的範圍寫成目標：住宅站 07–09 進站 35–43%、進出比 6–13 倍、辦公站傍晚 ÷ 早上 5–9 倍、上班日 00–06 時放出 1% 以下。(2) 照決策 68「每週需求」的做法加一個世界的開關，新遊戲開；舊存檔與 golden 關，缺 key＝關。要升一次存檔，加 `SaveFixtures` 的新版本，`SavedGame` 加遷移。(3) 開關打開時：`morningPeak`／`eveningPeak` 的方向性加強（不只高度，另一端也要壓低，研究 §2.2 最後一段）；`dayShape` 的 0–5 時壓到接近 0；也考慮把 `releasePassengers` 的內插改成這一小時與上一小時，消掉晚半小時（這會動 replay 的 checksum，開關關時一定不能變）。週末的 `weekendShape` 早上偏高（10.4% 對 5.7%），可以一起調。也要決定要不要讓路線收班的時段少放旅客（遊戲規劃 2026-10-21：北捷那幾小時是 0）；報告已列出收班時放出、首班車那一小時上車的人數。(4) 改之前、改之後都用 `TIDE_REPORT=14` 量；也跑 economy-balance 的 `BalanceReportTests`（第一條線、兩鎮之間、示範地圖），看回本天數與 `NewGameBalanceTests` 的目標有沒有跑掉。尖峰會更擠、離峰更空。(5) 轉乘（決策 298）與外地連絡站（決策 137）走同一條曲線，會自然跟著變；R3 不受影響。排序：照 NEXT_PRIORITIES §19；遊戲規劃 2026-10-21 排在存檔 65「自動派車錯開發車」之後，一次只有一件升存檔 |
| 匿名的本機操作計時（附在「回報問題」裡） | CORE_LOOP §1.6 第 6 點 | 核心玩法第 4 個 PR（關卡）時一起做，TestFlight 才問得出「第 1 關花幾分鐘」 |

### 7.3 3D 的後續

**接手**：3D 生活感 session 做完第 2 節的四步之後，由遊戲規劃排序。

| 項目 | 出處 |
| --- | --- |
| 移軸（tilt-shift）效果 | 決策 229 |
| 3D 拉近時的另兩個小做法：列車頭上的標籤（線號徽章＋載客／定員，只畫畫面中間附近幾列）、軌道旁的路線色帶（複線、多線共用只畫最上面那條）。第一項指北針已做（決策 269 的「後來」，2026-10-21） | `docs/research/CITY_TRANSPORT_MANAGER_STUDY_2026-10-19.md` 4.14；NEXT_PRIORITIES §19 第 2 名 |
| 路塹被 64 m 的地面格蓋住，地面沒跟著軌道切開 | 決策 229、231 |
| 背面剔除先關著，之後要打開（`Map3DMetalView.swift:299` 還是 `setCullMode(.none)`） | 決策 229 |
| 3D 列車的集電弓、車門把手 | 決策 230 |
| 磁浮、懸吊、單軌、蒸汽沒有 3D 樣式；莒光號四款沒有機車模型，畫成方塊 | 決策 230、252 |
| 影子不跟太陽方向偏移、建物彼此不投影、月台與雨棚底下沒有影子 | 決策 232 |
| 地面的斑馬線、停止線、車道線（新的地面層要插進第 4.1 節的高度順序） | 決策 241 |
| 3D 的「地圖風格」設定（換配色） | 決策 241 |
| `tools/glb-to-m3dmodel` 靜態橋接已實作（`codex/glb-meshopt-bridge`）：`bridge.mjs --manifest` 讀 meshopt／量化 GLB 與 `.gltf`＋外部 `.bin`，用節點白名單、非 AI 來源／SHA 與 `recolorLightPaint: false`；只用固定版本的 core／extensions／meshoptimizer（五包 MIT），不用 functions。拒收貼圖、skin／動畫／morph 等；原 Meshy 入口與 #803 公車成品逐位元相同。接手從工具 README 與自製 `fixtures/static.manifest.json` 開始；App 接入、美術重組／配色、素材授權與實機幀數仍交 3D session，本工具 PR 不代表素材採用。之後另開 WorldCover 只上色圖層（參考庫 `build_worldcover.py` 與圖磚）與香港無貼圖量體任務 | `docs/research/PEAKLINE_MAP_ENGINE_STUDY.md` §8（#821）；補充與修正 `docs/research/PEAKLINE_STUDY_SUPPLEMENT_2026-10-19.md` §1–§4（#820）；轉換器原本是 Codex 的線（第 2 節） |
| Metal 的色調映射與泛光（作者說留待以後） | `docs/art/map3d-night-terrain-2026-10-16/` |
| Fenn 3D 研究的建議，照順序，一次一個 PR，都在現有的 Metal 裡做：(1) 夜晚與黃昏的泛光＋色調映射，就是上一列，作者說留待以後，所以排到作者要時再做；(2) 實景建物依面積與樓層挑台灣的外牆樣式，補屋頂設備與一樓店面（`Map3DRealBuildings.swift`，可寫 Linux 測試）；(3) 假光貼片：車頭燈、廟與店面往上打的光、招牌光暈。不換 MapLibre、Apple Maps 或 wgpu，不搬 Kenney，手機不開 AO 或高解析度陰影 | [FENN_3D_WORLD_STUDY_2026-10-19.md](research/FENN_3D_WORLD_STUDY_2026-10-19.md) §5（#824） |
| 兩批生成素材：generated-2026-10-13（43 張）、micro3d（24 張），沒接進 App，也沒有「採用或放棄」的紀錄 | `docs/art/generated-2026-10-13/`、`docs/art/generated-2026-10-14-micro3d/` |

### 7.4 開發工具

**接手**：遊戲規劃排序。第 1、3 項對核心玩法的量測有用，可以在第 4 個 PR（關卡）之前開一個 session 先做。

| 項目 | 出處 |
| --- | --- |
| 無頭模擬入口 `GameSim`（指令：new-game、load、apply、advance、dump）——決策 260，#740 已合併 | GAME_AI_TOOLS §3.1、MOTION_3D_TOOLS §4 |
| 3D 截圖時一起輸出每幀時間與 draw call 的 JSON | GAME_AI_TOOLS §3.2 |
| 腳本化玩法框架（`Policy`）＋自動試玩，列出異常——決策 261，#748 已合併 | GAME_AI_TOOLS §3.3、MOTION_3D_TOOLS §5 |
| 文件數字一致性檢查：存檔版本、golden schema、golden 個數——#760 已合併，`python3 -I tools/golden-checks/doc_numbers.py --check` | GAME_AI_TOOLS §3.4 |
| 官網與社群說明短片的 skill | MOTION_3D_TOOLS §2.3 B |
| 在 macOS 上跑一部分套件測試，比對 Apple libm 的浮點值 | GAP_RESEARCH §4.2 |
| 測試用的參照模型擴充到全網選路（`ReferenceWorldGoldenTests.swift:130` 還是 `preconditionFailure`） | GAP_RESEARCH §4.2 |
| 跟著相關的 PR 一起加的工具（作者 2026-10-20 交給 session 判斷時機）：pixelmatch 差異圖 → 下一個改 3D 畫面的 PR；glTF-Validator → Meshy 公車接進 App 的 PR；OR-Tools 車輛運用量尺 → 決策 297 合併後、還有說不出原因的取消時；`performAccessibilityAudit()` → 實機 VoiceOver 有問題時。做那件事的 session 照表加，不必再等作者同意依賴 | GAME_AI_TOOLS §6.3 |
| TDX（運輸資料流通服務）查資料：`.github/workflows/tdx-check.yml`——#850 已合併。Actions → Check TDX API → Run workflow，`path` 填 `/api/basic/` 或 `/api/advanced/` 開頭的 API 路徑與查詢（預設台鐵第一個車站），回答在 run 的 artifact `tdx-response`（保留 7 天）。session 用 GitHub 工具觸發（`actions_run_trigger`，`tdx-check.yml`，ref `main`）再下載 artifact。金鑰是 repository secrets `TDX_CLIENT_ID`、`TDX_CLIENT_SECRET`，只有這個 workflow 讀得到；不要貼在對話、不要存進 repository。TDX 有票價、時刻、站表、路線色，沒有各站運量 | #850、決策 298 |

### 7.5 只等實機確認的

這些不擋任何工作，在 TestFlight 的「請測試者看」裡輪流問：
- PLAYER_FEEDBACK 標「待實機確認」的：54.1 的兩位玩家、56.1 的大多數則、59.1 之後美術線的三件事（選取列車的黃框、建物徽章會不會疊、建造面板好不好捲）。
- 61.1–68.1 各版請測試者看的項目。
- 到站鈴的聽感，以及幾個音軌一起循環時會不會漂移（RAILWAY_SOUND §11）。
- 56.1 #5：教學第 5 步的卡片蓋住 HUD，在 Linux 沒重現。教學之後會併進關卡（決策 254），到時一起看。
- 實景地圖的轉乘站（決策 298，#851）：新遊戲選項的「現實路網：轉乘」開關看不看得到、實景地圖是不是預設開；車站卡第一行「從…轉乘：每天約 N 人」在手機橫拿時會不會被截斷；在台北車站等大站旁蓋站，玩起來覺不覺得旅客變多（量出來第 14 天多 3–12%）。
