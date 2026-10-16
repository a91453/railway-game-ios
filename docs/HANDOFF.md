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

作者用幾個常駐 session 分工。這些 session 會換人，換的時候照這一節接手。

| 角色 | 現在的 session | 做什麼 | 交接 |
| --- | --- | --- | --- |
| 遊戲規劃（決策） | session_018D6gYU1yiZMtxSmNNU1K17 | 從玩家、開發、美術、音樂四個角度決定優先順序與設計，開實作 session 並派工，寫 TestFlight 的 What to Test，維護 NEXT_PRIORITIES、PLAYER_FEEDBACK 與這份 | 第 1.1 節 |
| 合併協調 | session_016sNs4eeZwga9hz1CCHkpmX | 照批次規則合併、發 GameCore CI 名額、看 main 的 CI 與 full lane、發版前檢查 | 第 1.2 節 |
| 派工（玩家回報與 bug） | session_01AaAj4wvJMxJQuLWAoYu6S8 | 收作者轉來的回報與 bug，開修正 session | 第 1.3 節 |
| 每日 Threads 開發日誌 | 排程「每日 Threads 開發日誌」每天觸發遊戲規劃，由它開寫作 session | 寫當天的串文草稿，用 SendUserFile 交給作者；不 commit、不發布 | 派工單照 2026-10-14、10-15、10-16 的寫作 session |

### 1.1 遊戲規劃

- **做決定的方式**（作者 2026-10-14「我不再做決定，都以這個當預設」，10-15 加音樂）：四個角度各一行理由寫進 PR；其他選項的預覽留在 PR；然後就做。作者自己保留：TestFlight 發版、Apple 帳號與 App Store Connect、secrets、加依賴、用 copyleft 或沒授權的程式碼。
- **排序**：NEXT_PRIORITIES §14 的權重（玩家 30、開發 25、美術 15、鐵道迷＋產品 15、音樂 15）；§15 是參考庫還沒做的項目與 2026-10-16 的順序。
- **一條線一次一個 PR**：前一個合併再開下一個（§14.4）。同時跑全套 Swift CI 的 GameCore PR 最多 2 個，名額由合併協調發。
- **每次發版**：
  - 發版前：改 `.github/testflight-whats-new.md`（它只在上一版之後有改動時才會被用，沒改就是自動列出的 PR 清單）。
  - 發版後：看 `testflight.yml` 的 run 號與 commit，記進 `docs/research/PLAYER_FEEDBACK.md`。版本號是 0.5.0 (run 號.1)。
- **踩過的坑**：
  - 不要憑記憶說版本號，查 `testflight.yml` 的 run。2026-10-16 把 66.1 當成 64.1。
  - 發版前要收工時，叫 session「做完再停」，不要叫它把做一半的東西留給之後（作者 2026-10-16：「記得不要暫停讓他們做完」「不要限制 可以任意開 pr 但就是收工」）。
  - session 停下來，不一定是因為發版。重開之前先問派工 session，或讀那個 session 自己的紀錄。語言選單是作者說「先不要動」才停的（第 3 節）。
  - 給實作 session 的派工單要對照 art-style §7 的現行規則：參考庫的模型「任意組合、成品跟原本不同」，不是「能搬就搬」。

### 1.2 合併協調

（待合併協調 session 寄來，見本 PR 後續 commit。）

### 1.3 派工

（待派工 session 寄來，見本 PR 後續 commit。）

## 2. 正在做的線（2026-10-16）

| 線 | session | branch／PR | 範圍與順序 | 動 GameCore | 備註 |
| --- | --- | --- | --- | :-: | --- |
| 單線對頭永遠卡死 | session_0162V1LTnnJubXXTaNkZUKQx | `claude/single-line-deadlock-fix` | 兩條線共用單線、沒有待避處時，行車控制下兩列車對頭永遠卡死（`CORE_LOOP_2026-10-16.md` §1.2 的種子 1）。先寫會失敗的測試，再修根因。golden、SaveFixtures、ReplayFixtures 不動 | 是 | 決策 255。CI 名額向合併協調拿 |
| 核心玩法：規則、配車、關卡 | session_01Q48iRY9H6EmeUL8NPyfiDW | 開工時登記 | 決策 254 §7 的第 1→2→4→5 個 PR：簡單規則當預設 → 開線自動配車＋自動交會 → 關卡框架與第 1–3 關 → 第 4–10 關 | 否 | 第 2 個要等死結修正合併；第 6 個（關卡判定進 GameCore）先不做，第 5 個合併後由遊戲規劃判斷 |
| 核心玩法：回饋 | session_011Z9h1X1GcZZ3i1EKEEjDZj | 開工時登記 | 決策 254 §7 的第 3 個 PR：站上的「+$12」、目標打勾、城鎮長大的環、目標旋律 | 否 | 照 `motion` skill 與三條音量 |
| 3D 生活感 | session_01EPkWLr5a25LyJvCuvh1U3R | 開工時登記 | 行人與機車 → 騎樓、雨遮、曬衣 → 廟埕與牌樓 → 主地圖拉近就傾斜 | 否 | 目標畫面與交接見第 4 節 |

## 3. 作者說「先不要動」或還在等作者的事

| 事項 | 狀態 | 在哪裡 |
| --- | --- | --- |
| 開始畫面的語言選單（裝置只設一種語言時，換不到英文） | 作者說「語言這件先不要動」（經派工 session 轉達，2026-10-16）。程式已寫好一個 commit，沒開 PR。原本用的決策 247 已被複線化用掉，重開時要另外取號 | branch `claude/in-app-language`（bf0b621），session_01UUcjVERB4CaVtdcbR3BWgJ |
| 航空遊戲手感借到鐵道 | 研究完、沒寫程式，在等作者決定要不要做。提了五項：①停站時的車廂座位圖 ②每趟結果蓋章（空位多、客滿） ③地圖上的到站收入飄字 ④選車型時標「剛好／太大／不夠」 ⑤路線卡兩端站的需求燈。③和核心玩法回饋的「+$12」重疊，做回饋的 session 已經在做。遊戲規劃建議排在核心玩法之後 | session_01NoAXS67jevFRE5XRz37tcF |
| 複線的最短相隔距離要不要再縮 | 作者 2026-10-14 在手機上問的。那個 session 停在權限確認，沒有回答 | session_01Mtv1QDk434KcMtFHWw67SM |

## 4. 3D 地圖

（三份交接待寄來，見本 PR 後續 commit：3D 任務素材庫 session_01DDMNH81xijBkgM2wVnHEyR、夜晚與地形 session_01RuxRaNwRfKKNijYAe4ReU6、畫風示意 session_018sTU6EMMCProJhAkswMiuo。）

**作者 2026-10-16 的目標畫面**：明亮的 low-poly 台灣街景，白天，斜上方約 35° 俯看。
- 左邊是紅牆橘瓦、雙層屋簷的廟，屋脊兩端翹起、綠色屋脊。廟前是淺色鋪面的廟埕，三四十個方塊小人，衣服顏色各異。廟埕前有一座紅色牌樓（兩根柱子加一道橫楣）。
- 中間一條雙向馬路，白色虛線分隔，路上有紅、白轎車與幾台機車（有一台載兩個人），人行道有路燈與行人。
- 右邊是 4–5 層的米白、黃色公寓：每層窗上有藍、綠、紅的遮雨棚，陽台曬著彩色衣服，頂樓有藍色水塔；一樓店面是彩色雨遮，門口堆著貨物與攤架。
- 遠處是高低錯落的公寓群，頂樓有水塔與彩色屋頂；左上是綠地、圓球狀的行道樹與一條藍色的河。
- 整體很亮、陰影柔和，活的東西多。

這就是 F 台灣版＋（`docs/art/3d-style-2026-10-13/`）的「＋」。作者回報 67.1／68.1 的 3D 地圖在 iPhone 17 Pro 上 60 fps，加人車之後同等級機型要維持 60 fps，舊機型降級。

## 5. 已知、還沒派的待辦

| 事項 | 來源 | 狀態 |
| --- | --- | --- |
| 高鐵示範快轉只有約八成速度（一個 tick 123 ms，間隔 100 ms） | 決策 248、#709 | 排在核心玩法之後 |
| 高鐵的長進路／閉塞區間死結、台南—左營交會 | #669，機廠 session session_01YNBmv76sfS8gJUnyRKEqHV（不再接新工作） | 沒有人接。機廠出庫已由 #678 處理；B 方案（`claude/hsr-depot-exit-priority`）量測失敗、放棄，紀錄在 #685 |
| §15.3 的內容：觀光列車、支線劇本、掛機模式、「這版新增」卡片、台灣節慶、各站到站鈴、3D 拉近傾斜與駕駛艙視角、花錢的地方＋新台幣＋分時電價＋車站容量、股票 | NEXT_PRIORITIES §15 | 排在核心玩法之後；各站到站鈴等測試者回報 |
| 3D：擋住列車的建物變透明、深度閃爍、道具穿模、真的台灣車與站房 | F 台灣版＋「定案前要補」 | 3D 生活感那條線之後 |

## 6. 留在遠端、沒有合併的 branch

清理時先看這張表，不要刪掉還有用的。

| branch | 是什麼 | 處理 |
| --- | --- | --- |
| `claude/in-app-language` | 語言選單（第 3 節） | 保留 |
| `claude/hsr-depot-exit-priority` | 機廠出庫優先的 B 方案，量測失敗 | 紀錄在 #685，可以刪 |
| `claude/hud-width-proof`、`claude/claude-key-check`、`claude/basemap-align-repro`、`claude/details-card-repro`、`claude/bughunt3-app-proof` | 只用來證明或重現的暫時 commit（「not for merge」「Repro only」「Proof only」） | 可以刪 |
| `claude/review-u9-u10` | U9、U10，已由 #646 那一輪 cherry-pick 進 main | 可以刪 |
| 2026-10-12 以前的其他 `claude/*` | 這份是用淺層 clone 查的，看不到 10-12 以前的歷史，所以沒有核對這些 branch | 刪之前先用完整 clone 確認內容已在 main |
