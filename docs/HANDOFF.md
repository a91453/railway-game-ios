# 交接

> 讀者：每一個新開的 session，以及接手某條線的 session。先讀 [OVERVIEW.md](OVERVIEW.md)，再讀這份。
> 這份記錄「誰在做什麼、做到哪、下一步交給誰」。規則細節以 `docs/ARCHITECTURE.md` 的決策為準，優先順序以 `docs/research/NEXT_PRIORITIES_2026-10-12.md` 為準，號碼以工作登記 #231 為準。
> 作者 2026-10-16：「把所有沒交接在 main 的用 PR 在 main 做交接，防止之後新 session 不知道怎麼做。」交接只放在 session 之間的訊息或 PR 說明裡的，都要搬到這裡。

## 怎麼用這份

- **開工前**：讀第 1、2、3 節，確認要做的事沒有人在做，作者也沒有說「先不要動」。然後照 CLAUDE.md 在工作登記 #1041 登記。
- **工作登記換了 issue**（2026-10-22）：#231 滿 2,500 則留言，GitHub 不再接受新留言，改用 #1041。這份文件裡其餘寫「#231」的地方，從此都指 #1041；2026-10-22 以前的紀錄留在 #231。#1041 接近 2,400 則時，遊戲規劃開下一個 issue，並改 CLAUDE.md、AGENTS.md、GEMINI.md、`full-lane-watch.yml` 與 `tools/ci-watch/full_lane_watch.py`。
- **收工時**：做到一半、留給之後、交給別人的事，寫進這份的對應一節（或寫進該決策的「下一步」，並在這裡留一行指過去），跟最後一個 PR 一起合併。只寫在 session 訊息、PR 說明或 #231 留言裡的交接，下一個 session 看不到。
- **交接給另一個 session**：用 send_message 傳的內容，也要在這裡留一份。
- 已經做完、沒有人需要照著做的交接，搬進 `docs/archive/`（OVERVIEW 第 6 節的封存表）。

## 1. 常駐的 session 與角色

作者 2026-10-20 把常駐 session 減成一個：遊戲規劃兼派工。合併協調不再常駐，§1.2 留作合併與發版的檢查清單。

**2026-10-21 起遊戲規劃也合併**（作者原話：「你的權限跟我一樣高／開發新功能一次最多3～4個session同步進行／Pr也不要一次開太多 不然會一直解合併衝突／或是等runner 綠了就合併 紅了就修／另外好像很久沒做pr review了 先優先做／再進行新功能依優先順序逐個進行」）：
- PR 綠了遊戲規劃照 §1.2 合併；紅了交回那個 PR 的 session 修。
- 新功能的實作 session 同時最多 3–4 個，照 NEXT_PRIORITIES §22 的順序一件一件開；開著的 PR 也不要多，免得一直解衝突。
- PR 審查比新功能優先。上一輪是 #786–#872（§7.1）。
- **多久審查一次**（2026-10-22，作者：「多少pr要做一次pr review 因為有時候只是加入文件跟codex加模型而已你五方比較」）：**數程式的 PR，滿 30 點開一輪審查**。GameCore 的 PR 算 2 點；GamePresentation、App、CI 腳本、資料工具（`tools/` 會產生打包資料的）、`Web/` 的程式算 1 點；只改文件、只加模型或素材（Codex 的模型包、`Map3D*Kit` 的配方）、只改測試的算 0 點。上一輪是發版前小審查（審查 E），到 #1030，從 #1031 起數。
  - 量的（2026-10-22，main 最近 60 個合併，約 10 小時）：文件 13、只有素材／測試 6、程式 41（其中 GameCore 5）。#962–#1017 共 51 個 PR、37 個程式、41 點：已經超過，下一個空位先開審查 D。
  - 為什麼 30 點：一個審查 session 看 30 個程式 PR（每個 diff 約 5–10 千 token）大約 15–30 萬，在第一次壓縮（約 32 萬）之前看完；上一輪 #873–#944 一次 72 個，A6–A11 到現在還開著。
  - 五方（權重照 NEXT_PRIORITIES §19；選項：A 每 30 個 PR、B 每 50 個 PR、C 每 30 點、D 每天一次、E 每 60 點）：
    | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --- | --: | --: | --: | --: | --: | --: |
    | A 每 30 個 PR | 4 | 3 | 2 | 2 | 1 | 2.70 |
    | B 每 50 個 PR | 3 | 3 | 2 | 2 | 1 | 2.40 |
    | **C 每 30 點** | **4** | **5** | 2 | 3 | 1 | **3.35** |
    | D 每天一次 | 3 | 3 | 2 | 2 | 1 | 2.40 |
    | E 每 60 點 | 2 | 2 | 2 | 2 | 1 | 1.85 |
    - 玩家：bug 早一點被抓到；每 30 點約半天一輪，不會拖到玩家先碰到。
    - 開發：不把審查花在文件與模型上；一輪在一個 session、壓縮前看完；GameCore 算兩倍，因為它有存檔與重播的風險。
    - 美術：模型與素材在自己的 PR 照 art-style 檢查，不進程式審查（各選項差不多）。
    - 鐵道迷：產生真實資料的工具算進來，出處與授權會被看到（C 才有）。
    - 音樂：無。
- **多久做一次 CI 優化**（2026-10-22，作者：「要幾點ci優化 30/60點還是有更好的」）：**不數點數，看數字過線才開**；遊戲規劃每次巡查本來就看 main 的 `ci.yml`，順便對下面的線，任何一條過線就開一個 CI 優化 session；都沒過線的話，每週也量一次。CI 慢不慢跟合了幾個 PR 關係不大，跟加了多少測試、哪個 shard 變長、哪個 UI 測試開始時好時壞有關。
  - 線（2026-10-22 量的現況寫在括號裡）：
    - main 的 `ci.yml` push run 超過 30 分（現在 18–28 分）。
    - 最長的 shard 超過中位數的 1.5 倍（`swift-shards.sh` 的 `classes_of` 該重排）。
    - pull request 的 iOS gate，UI 測試超過約 6 分（CLAUDE.md、決策 199）。
    - full lane 任何一個 job 接近它的時間上限（差不到 10 分）。
    - 同一個測試 7 天內沒有程式原因紅了 2 次（不穩的測試，照 diagnosing-bugs 查）。
    - pull request 的 macOS job 常常排隊超過 20 分。
  - 五方（權重同上；選項：A 每 30 點、B 每 60 點、C 每週一次、D 看數字過線才開、E D 再加每週量一次）：
    | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --- | --: | --: | --: | --: | --: | --: |
    | A 每 30 點 | 2 | 2 | 2 | 2 | 1 | 1.85 |
    | B 每 60 點 | 3 | 2 | 2 | 2 | 1 | 2.15 |
    | C 每週一次 | 3 | 3 | 2 | 2 | 1 | 2.40 |
    | D 過線才開 | 4 | 4 | 2 | 2 | 1 | 2.95 |
    | **E 過線才開＋每週量** | **4** | **5** | 2 | 2 | 1 | **3.20** |
    - 玩家：CI 快，修正和新功能就早一點進 TestFlight；沒問題時不花一個 session 去優化。
    - 開發：照點數開，常常開了沒事做，或該修時還沒到點；看數字才打到真的慢的地方。每週量一次，抓慢慢變長、還沒過線的趨勢。
    - 美術、鐵道迷：無（各選項一樣）。
    - 音樂：無。
- 仍是作者的：TestFlight 發版（發不發、什麼時候發；作者說「發」之後由遊戲規劃替作者按，§1.2）、Apple 帳號與 App Store Connect、secrets、加依賴、copyleft 或沒授權的程式碼，以及 CLAUDE.md 所有的「never」（不自己跑 `testflight.yml`、不開 auto-merge、不 force-push `main`、不取消 `main` 的 push run）。原因是額度：常駐 session 每一輪都要重讀整段對話，連被 PR 事件或排程叫醒也一樣，對話越長越貴。舊的遊戲規劃 session 開了兩天，用量已經碰到每週額度的警告。舊文件裡寫「派工 session」的地方，現在都是遊戲規劃。

| 角色 | 現在的 session | 做什麼 | 交接 |
| --- | --- | --- | --- |
| 遊戲規劃（兼派工） | session_01H5RHAwnA69n8EfAUSUrH52（2026-10-23 00:10 UTC 起，接 session_014nUBHbE9mSK4qXHHgm8xCQ（10-22 22:30–10-23 00:10），再之前 session_01UsF4QYCGrzSeNSFq11i8Wu（18:15–22:30），再之前 session_01Ddr2wiXx1Xhn2m9qNBDnDh、session_01CHQg7B6JqzbScGSjyDwHos（2026-10-22 起，照 §1.1 換手，作者：「要不要全部所有換個session了 都一直在壓縮了」→「好，照表換」；換手時的現況在第 2 節最前面；前任 session_014rYHMtmqA5bEMkBBuKu6PV（10-21 至 10-22，作者：「那你需要先接手嗎太長了」）、session_01NiR5WLMFjMJBktQAMkfmkm（10-21）、session_01WW7o3decEv5LY59nYVqnDN（10-20 至 10-21，作者：「接手 角色表中遊戲規劃的工作」）、session_01V1xd3H9vNkuZoSA3czNfGm（10-16 至 10-18）、session_018D6gYU1yiZMtxSmNNU1K17） | 從玩家、鐵道迷、開發、美術、音樂五個角度決定優先順序與設計，開實作 session 並派工，綠了的 PR 照 §1.2 合併（2026-10-21 起），收作者轉來的玩家回報與 bug（§1.3），寫 TestFlight 的 What to Test，維護 NEXT_PRIORITIES、PLAYER_FEEDBACK 與這份 | 第 1.1、1.3 節 |
| 每日 Threads 開發日誌 | 排程「每日 Threads 開發日誌」（台灣時間每天 21:43，2026-10-18 起暫停）觸發遊戲規劃，由它開寫作 session。2026-10-22 換手時由前任建了綁到 session_01CHQg7B6JqzbScGSjyDwHos 的新排程 `trig_01FZhfBNQCdDW8iDpowANLZS`（暫停中；之後每次換手都重建，現任的 id 寫在 #1041 接手的留言），前任的 `trig_01NfzFV9BcdiyBJpAwnaTuK9`（再之前是 `trig_01SkNFNW6qN6cMUGkGCXZM1v`）已刪。排程的綁定改不了，以後換手時由現任遊戲規劃用同一份 prompt 建一個綁到自己的新排程，再刪掉舊的；作者沒說要開就維持暫停 | 寫當天的串文草稿，用 SendUserFile 交給作者；不 commit、不發布 | 派工單照 2026-10-14、10-15、10-16 的寫作 session |

不再常駐（2026-10-20 停用）：合併協調 session_01QoA24EvFCFbmbcM1EwaZT7（前任 session_016sNs4eeZwga9hz1CCHkpmX）、派工 session_01MJ7sdeid5DAFjSVbTkmdi3（前任 session_01AaAj4wvJMxJQuLWAoYu6S8）。兩個都從 2026-10-17 起沒有動作。

**額度**（作者 2026-10-20 同意的做法）：
- 實作 session 同時 2–4 個。GameCore 的完整 tier 本來就最多 2 個，macOS runner 也只有 5 台，開更多只是排隊。
- 實作 session 做完一件就收工：在 #231 留合併紀錄、把沒做完的寫進這份。不要留著等下一件。
- **做完就封存**（作者 2026-10-23：「以後只要完成開完pr 檢測／有記錄231 與交接手冊 還有後續檢查都通過就能進入封存了防止之後太多session」）：一個 session 的 PR 開了、CI 綠了、#1041 留了「可合併」或合併紀錄、沒做完的寫進這份，後續檢查也過了，就封存（`archive_session`；要回來可以 `unarchive_session`）。session 列表才不會越堆越多。
- **換手時改舊 session 的標題**（作者同日：「記得把舊遊戲規劃session的標題修改 不然每次都點錯」）：被接手的 session（規劃或實作）封存前，標題改成「【舊・已換手】<角色>（日期）→ 改用 <新 session id>」，現任的標題以「★ 現任：」開頭，作者在列表裡才不會點錯。
- 常駐 session 的對話太長（大約超過 20–30 萬 token）就照 §1.1 換手，靠這份接手，不靠舊對話。
- **壓縮前就換、壓縮幾次一定換**（2026-10-22，作者：「壓縮到一定次數後幫我更換新session 指派的也一樣」→「我是設定400k壓縮耶 你再評估一次」；由遊戲規劃五方決定）：
  - 壓縮點：`CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000` 乘上 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80`，約 **32 萬 token** 時壓縮（不是 40 萬）。壓縮後剩一段摘要，原話與量到的數字會丟。
  - 看自己用了多少：`get_session`（不帶 session_id）的 `external_metadata.context_usage.used_tokens`。量得到，所以主要看 token，壓縮次數只當最後一道。
  - **遊戲規劃：讓它壓縮，壓縮 2 次就換**（作者要求五方公正比較次數後定的，比較在下面）。接近壓縮（`used_tokens` 約 30 萬）前，把作者原話、量到的數字寫進這份或 #231；第 2 次壓縮後，把手上的合併做完或寫進 §2.0，照 §1.1 換手。壓縮後發現記錯事、重做已做的事，就提早換。新任只讀第 1 節、§2.0 與第 3 節最上面幾列，其他要用時再讀。
  - **回頭看（2026-10-22 22:55 UTC，作者：「幫我回頭看一下最近幾個session 想問一下現在的壓縮換session 次數還需改嗎」）**：次數不改，改的是規劃怎麼省 token。
    - 量到的（`get_session` 的 `context_usage` 與 `usage`）：前任規劃 session_01UsF4QYCGrzSeNSFq11i8Wu 做了約 4 小時 15 分、壓縮 2 次、約 $19；新任 session_014nUBHbE9mSK4qXHHgm8xCQ 開工 22 分鐘就用到 28.6 萬（壓縮點約 32 萬）、約 $7.9。實作：決策 358（session_01DQGby5PQyfvKAmzTey1zVE）一個 PR 壓縮 1 次、約 $12.7；決策 359（session_0134bAxAfAEENYWu1NaK1RWW）壓縮 1 次、約 $7.8；10-22 下午到晚上的 8 個實作 session 有 5 個在一個 PR 裡壓縮 1 次，沒有一個到 2 次，「1 次後不接新的」都照做，沒有記錯事的例子。
    - 規劃用得快的原因：每次訂閱 PR 會收到兩則約 2–3 千 token 的事件說明，每則「轉 ready」「合併」「CI 完成」也各一則；開工讀 #1041 全部留言約 2.5 萬。
    - 改法：(1) 規劃**不訂閱實作 session 的 PR**，靠它們在 #1041 留「可合併」並 send_message，加上規劃自己的巡查（send_later）；(2) 規劃自己開的文件 PR 不訂閱，推上去後巡查時看一次 check run 就合；(3) 新任讀 #1041 只讀上一則「遊戲規劃接手」之後的留言，更早的照 §2.0；(4) 實作 session 的規則不變。
    - 五方（選項：A 不改；B 規劃改成壓縮 3 次才換；C 次數不改、規劃少收事件；D 實作改成壓縮 2 次前都能接新工作）：
      | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
      | --- | --: | --: | --: | --: | --: | --: |
      | A 不改 | 3 | 2 | 1 | 1 | 1 | 1.85 |
      | B 規劃 3 次 | 2 | 2 | 1 | 1 | 1 | 1.55 |
      | **C 少收事件** | **4** | **4** | 1 | 1 | 1 | **2.65** |
      | D 實作放寬 | 3 | 2 | 1 | 1 | 1 | 1.85 |
      - 玩家：C 讓規劃同樣的額度能合更多 PR、派更多工；B、D 多一代摘要，派錯工、合錯 PR 的機會變大。
      - 開發：規劃的 token 大多花在重讀事件說明，不是做事；C 直接砍掉這部分，次數照舊就不用重算 §1 的表。D 讓實作在摘要後接新工作，續作反而要重讀一半文件。
      - 美術、鐵道迷、音樂：無。
  - **實作 session：壓縮 1 次就不接新的**，只把手上這個 PR 做完；**壓縮 2 次就停**，做到能停的地方（推上去、PR 開好），沒做完的寫進這份，send_message 告訴遊戲規劃，由它開新 session 接手。實作 session 只在推 PR 與 CI 事件時被叫醒，重讀的次數少，壓縮一次的損失比重開一次（重讀文件約 15–20 萬）小。
  - 每個 session 被壓縮後的第一件事：在 #231 留一行「session_…：壓縮第 N 次」（N 從自己在 #231 的上一則數起），次數記在 #231，不靠對話記得。遊戲規劃巡查時看這些留言，到次數還沒停的就提醒。
  - **次數的比較**（2026-10-22）。估算的前提：約 32 萬壓縮；壓縮後的摘要約 5 萬（沒量過）；新的規劃開頭約 20 萬（實測 205,140）、實作約 15 萬（推估）。所以一個 session 能做的量：開頭到第一次壓縮，加上每次壓縮後約 27 萬。換手的固定成本：新任的開頭，加上約 3 萬寫交接（規劃還要一個交接 PR）。
    | 次數 | 規劃能做的量 | 換手成本佔比 | 摘要疊幾代 |
    | --: | --: | --: | --: |
    | 1 | 約 39 萬 | 約 59% | 1 |
    | 2 | 約 66 萬 | 約 35% | 2 |
    | 3 | 約 93 萬 | 約 25% | 3 |
    | 4 | 約 120 萬 | 約 19% | 4 |
    實作 session 的開頭較小，佔比略低，排名相同。摘要疊越多代，記錯的機會越大；實例：前任規劃壓縮多次後，叫 session_018gQPWzopcCfuR9gTAApKTj「汽機車分走旅客第 2 步合併後收工」，其實那件早已合併，它正在做的是第 12 名（2026-10-22）。
    五方各給 1–5 分，權重照 NEXT_PRIORITIES §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）：
    | 次數 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --: | --: | --: | --: | --: | --: | --: |
    | 1 | 3 | 2 | 1 | 1 | 1 | 1.85 |
    | **2** | **4** | **4** | 1 | 1 | 1 | **2.65** |
    | 3 | 3 | 3 | 1 | 1 | 1 | 2.10 |
    | 4 | 2 | 2 | 1 | 1 | 1 | 1.55 |
    - 玩家：派錯工、合錯 PR 最後都變成玩家看到的 bug 或延遲；1 次換太勤，合併等交接；3 次以上記錯的機會變大（上面的實例）。2 次兩邊都輕。
    - 開發：1 次時一半以上的用量花在換手；2 到 3 次省下的約 10 個百分點，抵不過多一代摘要記錯要重做的成本；實作的程式在 git 裡，記錯的是量測與理由，2 次後交接最划算。
    - 美術、鐵道迷、音樂：無，三者對每個次數都一樣，不影響排名。
    - 結論：規劃與實作都是 2 次。實作另加「壓縮 1 次就不接新的」。
  - **壓縮點（`CLAUDE_CODE_AUTO_COMPACT_WINDOW`）100k–900k 的比較**（2026-10-22，作者：「100k～900k與次數下去比較 用這個專案來看最推薦的」）。同樣的估算：壓縮在 80%；每一輪多約 3 千 token，每一輪都重讀整段，所以成本約和平均長度成正比；成本指數是「每做 1 千 token 的事要重讀幾千 token」，只用來互相比，不是金額。表裡是規劃（開頭 20 萬）、壓縮 2 次就換：
    | 窗口 | 壓縮在 | 開頭讀完後還剩 | 每次換手前做的量 | 成本指數 | 換手佔比 | 每做 100 萬壓縮幾次 |
    | --: | --: | --: | --: | --: | --: | --: |
    | 100k | 8 萬 | 讀文件時就壓縮 | — | — | — | — |
    | 200k | 16 萬 | 讀文件時就壓縮 | — | — | — | — |
    | 300k | 24 萬 | 4 萬 | 約 42 萬 | 68 | 35% | 約 5 |
    | **400k** | **32 萬** | **12 萬** | **約 66 萬** | **77** | **26%** | **約 3.7** |
    | 500k | 40 萬 | 20 萬 | 約 90 萬 | 89 | 20% | 約 2.9 |
    | 600k | 48 萬 | 28 萬 | 約 114 萬 | 101 | 17% | 約 2.3 |
    | 700k | 56 萬 | 36 萬 | 約 138 萬 | 114 | 14% | 約 2.0 |
    | 800k | 64 萬 | 44 萬 | 約 162 萬 | 127 | 12% | 約 1.7 |
    | 900k | 72 萬 | 52 萬 | 約 186 萬 | 140 | 11% | 約 1.5 |
    實作 session（開頭約 15 萬）排名相同。五方（權重同上）：
    | 窗口 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --: | --: | --: | --: | --: | --: | --: |
    | 100k、200k | 1 | 1 | 1 | 1 | 1 | 1.00 |
    | 300k | 3 | 3 | 1 | 1 | 1 | 2.10 |
    | **400k** | **4** | **4** | 1 | 1 | 1 | **2.65** |
    | 500k | 4 | 3 | 1 | 1 | 1 | 2.40 |
    | 600k | 3 | 3 | 1 | 1 | 1 | 2.10 |
    | 700k–900k | 2 | 2 | 1 | 1 | 1 | 1.55 |
    - 玩家：太小（300k 以下）壓縮太勤、細節常丟，派錯工的機會大；太大（600k 以上）每一輪要在很長的對話裡找東西，容易漏看，回應也慢。400k–500k 兩邊都輕。
    - 開發：每週額度是真的限制（舊規劃兩天就碰到警告）。成本指數 400k 比 300k 多 13%，但 300k 的規劃讀完文件只剩 4 萬就壓縮；500k 比 400k 多 16%，只少一點換手；700k 以上多五成到八成。
    - 美術、鐵道迷、音樂：無。
    - **結論：維持 400k，規劃與實作都壓縮 2 次就換**。比窗口更有效的是把開頭讀的量變小：新任規劃只讀第 1 節、§2.0、第 3 節最上面幾列與 NEXT_PRIORITIES §22.1、§22.2（推估約 10 萬），同樣 400k 就多出約 10 萬可以做事。
- 研究、寫文件可以用較低的思考強度；GameCore 的難題用高的。
- 對話到一定長度就自動壓縮：`.claude/settings.json` 的 `autoCompactWindow` 是 400000（2026-10-20，作者：「你四方思考後決定」）。雲端 session 另外帶 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80`，所以實際大約在 32 萬 token 時壓縮（推算，沒有實測）。壓縮會把舊對話摘要，作者的原話、量到的數字要在壓縮前寫進 PR、#231 或這份。不要這個設定時，刪掉那一行就好。
  - Claude Code 只讀 session 根目錄的 `.claude/settings.json`。同時掛好幾個 repo 的雲端 session，根目錄是上一層，讀不到 repo 裡這一行。所以作者也在雲端環境加了環境變數 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`（2026-10-20），它比設定檔優先，不管掛幾個 repo 都生效。
  - 要確認一個 session 有沒有套用，執行 `env | grep COMPACT`。
  - 要改值，兩處一起改。

### 1.1 遊戲規劃

- **做決定的方式**（作者 2026-10-14「我不再做決定，都以這個當預設」，10-15 加音樂，10-20 加鐵道迷）：五個角度（玩家、鐵道迷、開發、美術、音樂）各一行理由寫進 PR；鐵道迷看真實度與資料來源，和真實鐵路無關就寫「鐵道迷：無」；其他選項的預覽留在 PR；然後就做。作者自己保留：TestFlight 發版、Apple 帳號與 App Store Connect、secrets、加依賴、用 copyleft 或沒授權的程式碼。
- **排序**：NEXT_PRIORITIES §22（2026-10-22，把還沒做的全部放進一張表，取代 §19、§21 的順序；權重照 §19：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。§14 是舊的權重（鐵道迷＋產品），§15 是參考庫還沒做的項目與 2026-10-16 的順序。
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

**權限**：遊戲規劃（作者 2026-10-21 授權），或作者本人在那個 session 裡授權了的 session，才合併（CLAUDE.md 的「never merge a PR」只在這時放寬）。不開 auto-merge、不 force-push、不碰 `testflight.yml`；只有作者在遊戲規劃 session 裡說「發」時，遊戲規劃替作者按（下面「發版前」）。

**每個 PR 合併前確認**（`pull_request_read` 的 get 與 get_check_runs）：
- 不是 draft，`mergeable_state` 是 `clean`。
- check runs 全部是 success 或 skipped，沒有 in_progress。
  - 決策 265 之後，PR 的 `Swift CI (gate)` 會等同一個 commit 的 `iOS App Build`，iOS 紅了 gate 就紅；所以 gate 綠就代表 iOS 也綠了。
  - iOS 失敗、重跑通過之後，gate 不會自己變綠：對 CI 那一輪按 Re-run failed jobs（`actions_run_trigger` 的 rerun_failed_jobs）。
  - 「Remember that this change passed」顯示 skipped 是正常的：同一個改動前一輪已經跑過。
  - PR 舊 commit 的 `Swift CI (gate)` 是 skipped、旁邊有一個 `Superseded by a newer push?`：那一輪被新的 push 取代了，看 head 那一輪（決策 329）。head 上的 gate 是紅的、訊息寫「cancelled because a newer push replaced」，也是同一回事。
  - 分片 log 裡的「swift build was killed by signal … Building once more」是工具崩潰後自動重建（決策 329），不是測試失敗；同一個 job 再崩潰一次才會紅。
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
- 兩個 PR 撞同一個決策號（329 起是兩個 `docs/decisions/<N>.md` 同名），照 #231 登記的先後，後登記的改號；ARCHITECTURE、OVERVIEW 衝突（改 1–328 的「後來」時還會有）：請該 session 自己 merge main 解。
- 存檔版本與決策號以 main 加上 #231 還沒釋出的登記為準，取最大值加一。

**full lane**（`ios-build.yml` 把 iPhone UI 測試全部跑一次：兩個 iPhone job 加 iPad 教學，約 42–45 分鐘，佔 3 台 macOS）：
- 合併後不用手動跑（決策 265）：`ios-full-lane.yml` 在合了會影響 App 的 PR 之後自己啟動，最多每三小時一次。10-14 到 10-16 的 67 小時裡 full lane 跑了 42 次，只有 7 次是它啟動的，佔全部 macOS 用量的 34%。
- 只在兩種情況用 `actions_run_trigger` 手動跑（run_workflow，workflow `ios-build.yml`，ref main）：
  - 發版前要用的 HEAD；
  - full lane 紅了，要二分的 commit。
- 只改 docs、`Tests/`、`tools/` 的 PR 不影響 App，不用重跑。
- 要發版的 commit 必須自己有一輪綠的 full lane。

**full lane 紅了**（決策 329 起，`full-lane-watch.yml` 會在 #231 自動留言：第一次紅、紅燈裡又有新的 job 紅、綠回來。看到就照下面做）：
1. 用 `actions_list` 的 list_workflow_jobs 找出失敗的 job。
2. 用 `get_job_logs`（return_content 設 false）拿到 log 網址，用 curl 下載到 scratchpad。
3. 用 `grep -aE "error: -\[|' failed \(|Executed [0-9]+ tests, with"` 找出失敗的測試與行號。
4. 跟上一輪綠的 full lane 比：`git log --first-parent <綠>..<紅>`，再用 `git diff --name-only <merge>^1 <merge>` 看每個 PR 改了哪些檔。
5. 從 commit 的 `Claude-Session:` trailer 找到做那個 PR 的 session，用 send_message 交給它。附上 run、job、測試名、行號、錯誤訊息和可疑的 PR。
6. 對方可以用 `ios-build.yml` 的 `only_testing` 分段驗證（例如開 `claude/bisect-*` branch）。修正 PR 綠了就合，全部修完再跑一輪 full lane。
7. 發版前紅了：立刻告訴作者「先不要發」，並說明原因。

**發版前**（作者 2026-10-23：「改成我說可以發你才能替我發」。發不發由作者決定；作者在遊戲規劃 session 裡說「發」之後，遊戲規劃照下面確認，都綠才用 `workflow_dispatch` 在 `main` 跑一次 `testflight.yml`，輸入照作者上一次發版的 run，作者另外指定的話照作者說的。不是綠的就告訴作者哪裡紅，等作者再說一次才發。作者也可以自己按。實作 session 一律不碰。第 84 版（2026-10-23）遊戲規劃去按時被 session 的權限檢查（自動模式，理由「正式發布」）擋下，由作者自己按；要遊戲規劃替作者按，作者須在那個 session 的權限設定允許啟動 `testflight.yml`，否則照舊告訴作者「可以發（commit X）」與輸入，請作者按）：
- **先寫 What to Test**：`.github/testflight-whats-new.md` 寫好這一版給玩家看的說明（照 83.1 的格式：新增的、修好的、沿用的、請幫忙看），合進 main，這個合併的 commit 才是要發的 commit。沒寫就不說「可以發」：`testflight-changes.py` 只在這個檔案自上一版之後改過才用它，否則填 PR 標題，作者不要那個（84.1 漏寫，作者：「每次都改我這個 說了幾次」）。
- 要發的 commit 就是 main HEAD，它的 `ci.yml` 和它自己的 full lane 都要綠。
- 看 #231 最後一則 `full-lane-watch.yml` 的自動留言：最後一則是「紅了」或「又有 job 紅了」、之後還沒有「綠了」，就是 main 的 full lane 還紅著，先不發（決策 329）。
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
- 也盯 main 的 full lane（iOS App Build／ios-full-lane），紅了就派人修。決策 329 起紅了會在 #231 自動留言（`full-lane-watch.yml`），不用自己一直去 Actions 頁面看。
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
- 決策號：派工單寫好號碼（#231 的登記就是預約），PR 只加 `docs/decisions/<N>.md` 一個檔，不改 ARCHITECTURE 的最後、OVERVIEW 的決策列與 §9（決策 329，2026-10-21 晚）。不用再先在 main 放「### N. （預約）」一節，合併後也不用補 §9 的索引。以前每個 PR 都接在 ARCHITECTURE 最後、改 OVERVIEW 同一行；10-21 改成預約一節也擋不住，相鄰的預約節還是同一處（#934 三次衝突；三天 49 個 merge main 的 run，41 個是這兩份，佔 PR 的 Linux 用量四成，`docs/research/CI_MEASURE_2026-10-21.md`）；
- 壓縮：被壓縮後在 #231 留「壓縮第 N 次」；第 1 次後不接新的，第 2 次就做到能停的地方交接（§1 的「壓縮前就換、壓縮幾次一定換」）；
- 收尾：draft → 綠 → ready → 在 #231 留「可合併」→ 用 send_message 告訴遊戲規劃；
- **封存**（作者 2026-10-23：「只要完成開完 PR、檢測、有記錄 231 與交接手冊、還有後續檢查都通過就能進入封存，防止之後太多 session」）：實作 session 做完、PR 開了、CI 綠、登記處（現在是 #1041）留了「可合併」、還有後續的寫進本檔、遊戲規劃要它查的也查完，遊戲規劃就把它封存，不用等合併。合併後才出的問題（衝突、main 變紅）由遊戲規劃另派。換手後停下來的 session，接手的確定在動就封存。
- **舊遊戲規劃的標題**（作者 2026-10-23：「不然每次都點錯」）：遊戲規劃換手時，新的一任把自己的標題開頭寫「★ 現任：」，把上一任改成「【舊・已換手】…→ 改用 session_…」，指向現任。
- 禁止：合併、auto-merge、推 main、`testflight.yml`、`@claude`、在 repo 裡寫模型名稱。

**作者的偏好**：
- 只回報「完成」或「需要決定」，簡短白話。不要一直報中間進度，作者抱怨過「怎麼一堆回報」。
- 回玩家的話要簡單、和藹、親近、簡短，不要兇。
- 選項、外觀、預設值、順序、golden 值的變更，由 session 自己從各個角度決定（現在是玩家、鐵道迷、開發、美術、音樂五個），PR 裡每個角度寫一行。
- 作者自己保留：TestFlight 發版（作者說「發」，遊戲規劃才替作者按，§1.2）、Apple 帳號與 App Store Connect、secrets、新增依賴、copyleft 或沒有授權的程式碼。
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

### 2.0 2026-10-22 遊戲規劃換手時的現況

**TestFlight 第 83 版**（遊戲規劃 2026-10-22 22:45 UTC 決定，作者：「你覺得做到哪部分完工要先發83 由你決定」）：82 是 e6e8f5a9（#1029）。等 #1048（358）、#1052（359 第一步）、決策 360 的第一個 PR（3D 駕駛艙最高 10×）都合併就發；10d（存檔 71）、360 第二步、隧道內部與地下月台、10g、10h 留到 84；仲夏寶島號那時已合併就一起。選定的 commit 在 main 上 `ci.yml` 與 full lane 都綠、寫好 What to Test，才告訴作者「可以發（commit X）」。五方在 #1041 的規劃留言。

**作者 2026-10-22 晚上的問題、規劃的決定**（五方都在 #1041）：地下透視做，開關預設關，排在隧道內部與地下月台之後（§22.2 10c）；只玩 2D、省電檔不做多重取樣、3D 不搬網頁（10g，在 10e 之前派）；五項效能排進 §22.2（10h 2D 大世界掉幀，要作者在大存檔與宜蘭線 6000× 的幀數截圖；25a、25b、41、42）。

**玩家回報的當機與卡頓（2026-10-22 23:30 UTC，遊戲規劃整理；細節在 PLAYER_FEEDBACK 77.1–82.1）**。和下面不同時以這段為準。
- 五位玩家、六則：77.1 #2（iPad（A16），列車多時跨 24:00、06:00 切速度卡頓後結束）、78.1 #11（iPhone 17 Pro 發熱後結束）、79.1 #5（iPhone 17 Pro，6000× 卡住）、80.1 #1（iPad Air M3，按「升級為複線」後卡住）、82.1 #1（iPad（A16），站多、切速度、點建設、買地卡頓）、82.1 #2（環狀線旅客沒被載到）。另有 81.1 #1 的建議（慢車自動待避，§22.2 第 20a 名，2.75，未派）。
- **升級複線卡住**：修在 #1059（session_01NQonNFtpUhUm4Vbo9krCKK；複線預覽的快取以 worldRevision 記，每個 tick 整份重算），放進第 83 版；決策 362 沒用。同樣以 worldRevision 記住的建造草稿寫在 §5。
- **卡頓、發熱、6000×**：session_011kVCxFJEULkYyGGU7emgsx，決策 363，分三個 PR：(a) 三個動作與跨 24:00、06:00 切速度；(b) §22.2 第 25a 名（決策 330 第 3 步，高倍速每次換世界整個畫面重算）；(c) 第 10h 名 2D 每幀，含不操作時降 2D 幀率上限。它壓縮 1 次就停，剩下的寫在 §7.1，下一個規劃再派人接。
- **環狀線沒載到人**：#1065（決策 364，session_01Efb7Sr7mZC2SiNXUtd1ZAa，`claude/loop-line-boarding`）可合併：環線列車停在第一站以外時每一圈都從那站起算，和旅客排的一圈對不上，改成繞過第一站再跑一整圈、之後從第一站起算；一列車的環線只排內環。`ReplayFixtures/long-leg-traffic.json` 重錄 checksum 1–5（作者同意）。還沒做的：作者轉來玩家的路線卡與車站卡截圖時，對照玩家的路線是不是環線、幾列車；兩種都不是就再查（決策 364「下一步」）；實機確認放進下一版的 What to Test。
- 第 83 版：#1057、#1059 合併後，What to Test 在 `claude/testflight-83-notes`；其他修好的進 84。TestFlight 的「當機意見反應」只有文字、沒有當機紀錄（作者 2026-10-23 截圖）。

**第四次換手（2026-10-23 00:10 UTC，session_014nUBHbE9mSK4qXHHgm8xCQ 壓縮 2 次 → session_01H5RHAwnA69n8EfAUSUrH52）**。和下面不同時以這段為準。

- **合併了**（43b5b011 起這一批）：#1058（玩家回報 77.1–82.1）、#1057（決策 360 第一步，3D 跟車最高 10×）、#1059（升級複線卡住，80.1）→ main 4e18ee8b。之前還有 #1056、#1052（決策 359）、#1048（358）。main 的 `ci.yml` 在 719d3d09 綠，4e18ee8b 那次交接時還在跑。
- **第 83 版**：程式到齊。What to Test 在文件 PR #1062（head 4150e4c9，gate 綠）；4e18ee8b 綠了就合，合併後的 commit 就是 83 的 commit，等它的 `ci.yml` 與 full lane 都綠再告訴作者「可以發（commit X）」。
- **做中**（合併後收工，「可合併」留在 #1041 並 send_message 給規劃）：
  - session_014NB8yWZmutMBX3jDsXC3Sm：#1061 隧道本體（決策 359 續一，壓縮 1 次，只做完這個）。地下月台與地下透視開關寫在 359.md「續一之後還沒做」，要再派。
  - session_01KAjPfBFs9fKJcLV9JsgRC4：#1060 自有建築公園與廟（10d，存檔 71、決策 361，GameCore）。
  - session_01Q3q6JL8VvzYZShXTQRTsoz：仲夏寶島號。
  - session_011kVCxFJEULkYyGGU7emgsx：卡頓、發熱、6000×（決策 363，三個 PR，見上一段）。
  - session_01Efb7Sr7mZC2SiNXUtd1ZAa：環狀線旅客沒被載到 → #1065 可合併（決策 364，動 GameCore；見上面「環狀線沒載到人」）。
- **號碼**：決策 362 釋出，下一個 365；存檔下一個 72。
- **排隊**：360 第二步（沿線預載、霧）、10g、10e、10f、20a（慢車自動待避）、§5 的同類預覽（`NetworkSession` 草稿、`PassingLoop`、`DepotYard`、`LevelPlatformTrack` 都以 worldRevision 為鍵）。
- **審查**：從 #1031 起約 21 點（#1057、#1059 各 1），滿 30 開一輪。
- **排程**：每日 Threads 開發日誌 `trig_016U9uyaff5jSPvx4fZNbAp1`（暫停）綁在前任；新任建一個綁到自己的、刪掉舊的，新 id 寫在 #1041 接手的留言。
- **等作者**：環狀線玩家的路線卡與車站卡截圖；大存檔的幀數截圖。

**第三次換手（2026-10-22 22:30 UTC，session_01UsF4QYCGrzSeNSFq11i8Wu 壓縮 2 次 → session_014nUBHbE9mSK4qXHHgm8xCQ）**。和下面不同時以這段為準。

- **合併了**：#1037、#1039、#1040、#1043（決策 356）、#1044（決策 357）、#1045（鳴日號）、#1046（iPad 委託案旗子）、#1047（環島之星，main 24bd3875）、文件 #1049、#1050、#1051。這一批從 b136e84b 起只合了 #1047；等 24bd3875（或之後最新的 push）的 `ci.yml` 綠再合下一批。
- **開著的 PR**：#1048（決策 358，3D 邊開邊載入，session_01DQGby5PQyfvKAmzTey1zVE，壓縮 1 次）、#1052（決策 359，隧道第一步：隧道裡的列車不畫、跟車鏡頭留在地面，session_0134bAxAfAEENYWu1NaK1RWW，壓縮 1 次）。都是 draft，綠了轉 ready 就合併；兩個 session 合併後收工。
- **做中**：session_01KAjPfBFs9fKJcLV9JsgRC4，§22.2 第 10d 名自有建築（公園、廟），存檔 71、決策 361，`claude/owned-building-kits`。
- **號碼**：決策 358、359、361 已登記未合併，360 預約；下一個空的決策號 362，存檔版本 72。
- **排隊派工**：
  1. #1048 合併後：決策 360（3D 駕駛艙速度上限）。兩個 PR：先在 3D 跟車時速度最高 10×（用 600× 開 3D 就改用 10×，離開 3D 回到 2D 原本的速度，2D 不變）；再做沿路線的走廊載入（往前 6 km、軌道兩側各一格，岔路兩邊各蓋一小段）加駕駛艙的霧（1.2 km 起、2 km 全白、天空色，俯瞰不加），停下、10× 以下或看側面時補蓋周圍 3 km；實機量過再調高上限（估 30–40×），跟不上自動降一檔，用現有的「跟不上」提示。作者原話：「邊開邊載入的上限是多少速度 例如最高600x 你在駕駛艙速度那欄就改600x 防止載不出來 但是原本2d的速度不變」「所以調窄 調霧有用摟」。細節在 #1041 22:09–22:14 的三則規劃留言。
  2. #1052 合併後：隧道的下一步派新 session（0134 壓縮過，不接新工作）：隧道口接地形與路塹、隧道內部與隧道燈、地下月台，用現有的 3D 套件組（作者：「那要不要畫隧道燈的地下 跟隧道月台 用現有codex素材組的出來嗎」→ 要；「記得改成遊戲風格而不是照搬」：照 art-style §7 任意組合、成品跟原本不同）。見決策 359「下一步」。
  3. 之後依序：§22.2 10e（3D 道路照真實高度）、10f（不同的高架橋），兩個都改 `Map3DScene.swift`，排在 359 之後；然後仲夏寶島號（第 11 名）、第 7 名其餘、第 14 名……
- **TDX 查過沒有道路高度**（作者：「精確高度如果要抓的話Tdx抓的到嗎」→「好，去跑 TDX 查一下」；2026-10-22 `tdx-check.yml` run 39865308650、39865353614）：`/api/basic/v2/Road/Traffic/SectionShape/Freeway` 只有平面的 LINESTRING；`Section/Freeway` 有路名、里程、速限、LinkID，沒有高度、高架或橋梁欄位；TDX 的道路路網線型只有國道與省道。所以 10e 照圖磚的 `brunnel`／`layer`（每層約 6 m）做，不用 TDX。
- **E1**：作者說還沒要上 App Store，不派、巡查不提（第 5 節）。
- **排程**：Threads 每日排程由新規劃重建（暫停）、刪掉綁在 01UsF4 的 `trig_01YPQ4fTJtzar7o3upbBQBE9`；01UsF4 的巡查提醒換手時已刪，新規劃自己排。

**第二次換手（2026-10-22 18:30 UTC，session_01Ddr2wiXx1Xhn2m9qNBDnDh 壓縮 2 次）**。這一段以下是上午換手時寫的，和這段不同時以這段為準。

- **合併了**：#1034（8c7b8e6d）、#1035、#1036（4095e8f6，`ci.yml` 綠）、#1038（f3c0d717，決策 355）。4095e8f6 綠了之後這一批只合了 #1038，還能再合 2–4 個。
- **main 已有的決策**：352、353、355。**354**（月台卡片，session_01Bajcx7SuZfZPAaLTq8DWM5）與 **356**（Fresnel，session_0136FXagwq4pwPNs3d9vWUHN，已壓縮 1 次）已登記、還沒合併。**下一個空的決策號是 357**；存檔版本 70。
- **開著的 PR**：#1037、#1039（session_01Hmkv6wxPNTX4HFyKxMeBcC，main full lane 的第 5 課與 3D 拉近測試，只改 UI 測試）、#1040（session_01XZM7WBK1v1RdHJdynRfngs，iPad 三個 UI 測試，其中地圖鎖的點擊範圍是 App 的修正）。都是 draft，綠了各自轉 ready；只改 UI 測試的隨時可合。
- **main 的 full lane**：29ebf5ed 與 8c7b8e6d 的紅都已有人修（上面三個 PR）；合併後看下一次 full lane。
- **還沒派**：§22.10 第 6 項（太陽的陰影貼圖）；§22.2 #10a（3D 預先載入）與 §22.2 其餘照順序；E1（演示模式的編譯旗標，App Store 送審前一定要做，見第 5 節；作者 2026-10-22：「還沒有要上 app store 先幫我記著 我要上再跟我說」，先不派、巡查報告不再提，作者說要上 App Store 時再提出來）。
- **排程**：Threads 每日排程 `trig_01MBWsHEjEzt6VzQ6BskFpku` 暫停中、綁在本 session；新規劃重建一個綁自己的（暫停）後刪掉它。本 session 的巡查提醒換手時刪除，新規劃自己排。

作者 2026-10-22：「要不要全部所有換個session了 都一直在壓縮了」→「好，照表換」；「壓縮到一定次數後幫我更換新session 指派的也一樣」。各 session 在手上的 PR 合併、#231 的登記結束之後才換，不在做到一半時換；要接手的事寫在這裡。

**開著的 PR**（2026-10-22 12:00 UTC）：
- #1020（決策 350，地圖的範圍、3D、縮放鈕，session_013fMmahDsHF9xHba1mJyASm）：ready，head d9fdb2bd。iPad 那個紅的 job 是手動的診斷 run，不是 PR 自己的；PR 自己的 iOS run 39761671036 綠。013f 在 d9fdb2b 跑一次只有 iPhone 的 `only_testing`，綠了就照第 1.2 節合併。`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 在 main 71a3807 也紅（run 39765719731），不是 #1020 造成的。
- #1025（決策 349，3D 色調，session_01H2iSUj5f1cCXAwjvuFvbsp）：draft，綠了它會轉 ready。

**main 的批次**：上一個綠的 `ci.yml` push 是 82ce09e9（#1021）。之後合了 4 個：#1019（決策 344，GameCore）、#1023（公園修正）、#1027（CI 優化的頻率）、#1026（演示模式 1/2，決策 351），main f565326f。這一批還能再合 1 個（#1020）；其他的等 f565326f（或之後最新的 push）的 `ci.yml` 綠了才合下一批。

**下一個空的決策號是 352**（351 已用；有人在 #231 登記了更大的號就用那個加一）。

| 線 | session | 做到哪 | 下一步 |
| --- | --- | --- | --- |
| 遊戲規劃 | 新 session（接 session_01CHQg7B6JqzbScGSjyDwHos，id 寫在 #231） | 舊的壓縮 2 次換手；#1012–#1019、#1021–#1024、#1026、#1027 已合併 | 第 1.1 節；開工先讀第 1 節、這一節、第 3 節開頭 |
| 地圖按鈕（決策 350） | session_013fMmahDsHF9xHba1mJyASm | #1020 ready | 合併後收工 |
| 3D 城市（§22.10） | session_01H2iSUj5f1cCXAwjvuFvbsp | 第 2 項色調 #1025 | 已壓縮 1 次：#1025 合併後收工，第 3–6 項寫回第 4 節 |
| 演示模式（決策 351） | session_01Q6ucfu4uY1YiX1buRCZzFr | PR 1 #1026 已合併；PR 2「鋪好這一帶的真實路線」在 `claude/demo-mode-real-lines` | PR 2 綠了轉 ready 合併 |
| 發版前小審查（#1019 起的程式 PR） | session_012YaVnnbN5pq9pjh53FF4RC | 進行中，範圍含 #1026 | 報告寫成 `docs/archive/PR1019_<N>_REVIEW_HANDOFF.md`；回報「可以發」或 P1、P2 修正 |
| Threads 貼文草稿 | session_01QAC77cR5wi8UFqoLxMDVH6 | 照作者給的前幾天貼文排今天的發文 | 只寫草稿、用 SendUserFile 給作者，不 commit、不發文 |

**發版前**（作者 2026-10-22：「演示模式做完 我就差不多要發文了 所以做完這項看需不需要pr review 我就發那版 跟發文」）：
- 這次是 TestFlight 第 82 版（上一版 81 是 #1003，7fc0d373），新的是 #1004 起。
- 演示模式兩個 PR 都合併；發版前小審查（上表）的 P1、P2 修正全部合併。
- 選定的那個 commit 在 main 上的 `ci.yml` 與 full lane 都綠了，才告訴作者「可以發（commit X）」，並告訴 Threads 草稿 session。`testflight.yml` 由作者自己按。
- Threads 每日排程（`trig_01FZhfBNQCdDW8iDpowANLZS`）維持暫停；它綁在舊規劃 session 上，新規劃照第 1 節那一列重建一個綁自己的（暫停），再刪舊的。發文由作者自己發。
- 舊規劃的巡查提醒 `trig_0195QqR2dnriwyNw5SrQT7Jr` 換手時已刪，新規劃自己排巡查。

**下一個空位依序派**（第 1 項演示模式已在做，見上表）：
1. **演示模式**（作者 2026-10-22：「要不要設置一個開發者模式 解鎖所有東西跟路線 不然我要演示都只能自己拉」）。設定裡一個開關，預設關。**藏起來**（作者：「要藏隱密一點只有我按得到嗎」）：只在測試版出現（Xcode 與 TestFlight，用決策 338 的 `TestBuild.isTest`），App Store 版完全沒有，因為 Apple 審查不准有隱藏功能；測試版裡也要在設定的「版本」那一列連點 5 下才出現，別的測試者不會誤開。打開時：課程、挑戰全開；新局自動無限資金、地圖擴張全開；實景地圖多一顆「鋪好這一帶的真實路線」，照現有示範（`RealWorldDemo`、`HighSpeedDemo`、`TRADemo`）的建法，把畫面範圍內的台鐵、高鐵、捷運鋪好並排車；成就與紀念章不算（和示範一樣）。前三項一個 PR，一鍵鋪路線另一個 PR。不升存檔、不動 GameCore。五方：玩家（演示一開就有車跑，一般玩家看不到也碰不到）、鐵道迷（鋪的是真實走向）、開發（用現有指令與示範建法）、美術（一個開關一顆鈕）、音樂（無）。
2. 網頁 `Web/CityView` 看得到的「技術試作」標示（NEXT_PRIORITIES 隨時可派的小修第一項）。
3. 之後照 NEXT_PRIORITIES §22.2 的順序。

已做完、2026-10-22 封存的：session_018gQPWzopcCfuR9gTAApKTj（#1019，決策 344）、session_01TCwdHtJTq9REwDrCSHzR11（#1024，審查 D）、session_014APxWZsoEbwngV3qd6QZtr（#1016，車站紀念章）、session_01T8UdZRFmxs93DFtUKX5V73（#1012，雨聲雷聲）、session_01MsTCquc1D1FqFiEdn6j3fz（#998）、session_01RU6kM49KUK5VFvU5osr8eP（決策 333、334、337：3D 跟車視角、下一班飛到月台、前面展望）、session_01QiPq4nZdq5bVS9MZ4rkr4L（#966、#970、#984；A6 與 A11／B7 還開著，§7.1）、session_01VVzExSvZcTej5eCqxdUEpY（審查 C #945–#961）、session_014SH8oLiB8EPtSm4afuuxNn（決策 335）。

**作者 2026-10-22 回報、已修**：廟、公園、站前店畫成全黑（#1008，套件模型放進場景時法線是零）；1× 時跟車與駕駛室一頓一頓（#1010，1× 一個遊戲秒要 10 個 tick，列車只滑 0.1 秒就停 0.9 秒，改成整秒滑完）。兩個都待實機確認。

**新任第一件事**：核對 NEXT_PRIORITIES §22.1 與 §22.2，把已合併的搬到 §22.3：第 1、4、5 名（決策 333、337、334）、第 7 名的第一項（決策 343）、第 15 名的前兩項（決策 342、345）；第 2 名（找不到的四個入口，session_01MsTCquc1D1FqFiEdn6j3fz）與第 3 名（素材包）做到哪要查 main 與 #231 再寫，§22.1 改成上表。


作者 2026-10-17 讓各線開工，合併交給遊戲規劃（「交給你綠了就合 紅了解衝突」、「由你四方思考後決定」）。分工照 `AGENTS.md`：Claude 做核心與整合，Codex 做 UI 測試、工具與獨立審查，Antigravity 做網頁試看與畫面。

| 線 | 誰 | 狀態 | 下一步 | 動 GameCore |
| --- | --- | --- | --- | :-: |
| 核心玩法：規則、配車、關卡、回饋第二批 | session_01Q48iRY9H6EmeUL8NPyfiDW | 第 1–5 個 PR 與決策 264 的後續已合併（決策 258、264、266、271）；收尾 #779（決策 273）；回饋第二批全部做完：#780（決策 274）、#792 每趟蓋章與 #795 長按路線看旅程（決策 276）；#785 延後的三項 #789（決策 275）、#790 | 高鐵示範（NEXT_PRIORITIES §16 第 4 項）：快轉 #801 已合併；#669 的長進路死結與台南—左營交會是決策 278（#804，已合併）：號誌開＋閉塞時白天不再死結、取消 60 → 45 班。北端夜裡的死結是決策 280（`claude/hsr-north-depot-room`：機廠有空股才入庫，機廠的股道算終點站的盡頭；取消 45 → 32 班）；計算時間是 `claude/hsr-traffic-speed`（結果逐位元不變，`docs/research/APP_TICK_COST_2026-10-18.md` §6）。左營出入線是決策 281；南港咽喉與照地形建是決策 283（`claude/hsr-nangang-throat`）。左營咽喉白天的死結是決策 287（`claude/hsr-zuoying-throat`）：看了第一個死結，是調度不是軌道。閉塞分界設在上行線匯入的斜線旁（決策 281 為出入線加的節點），進站的車停在那裡擋住出站的路，和要讓出股道的閒置車互等；分界改成只設在列車停下來不會妨礙別條軌道的地方，取消 86 → 44 班（平地 129 → 46）。照地形建時夜裡出庫的死結是決策 290（`claude/hsr-zuoying-depot-exit`）：有班次的路線，終點站有一股沒有車停、也沒有車正開往才從機廠出庫，並開往那一股；照地形一天取消 44 → 30、每小時結束時都沒有死結（平地 46 → 33）。「剛入庫 16 分鐘又出庫」是另一個機制（班次晚了、在等的車拿不到路時，出庫的判斷把它們當成趕不上），試過讓兩邊一致，量了變差（照地形 30 → 40），不採用。決策 290 之後剩下的取消逐班分類寫在 `docs/research/HSR_SIGNAL_BASELINE_2026-10-15.md` §13：最多的是接班的車晚到（晚點四成多來自快車跟在慢車後面，排定待避一次都沒排出來），其次是左營咽喉被一百多 km 外的進站車整段占著。決策 294（`claude/hsr-overtake-approach`）兩條一起改：時刻表裡的待避照排（慢車停側線等快車，最多多等 5 分），長區間的列車離站 14 km 內才排進站的路；照地形取消 30 → 13、平地 33 → 22。只做其中一條時某一種建法會變差，數字在決策 294 的「試過、不採用」。機廠與終點站之間的來回（作者這輪的第 3 步）由 session_01KFRB53UNrJR1yVGu2fGJog 接手做成決策 296（`claude/hsr-depot-shuttle`）；作者提的車輛運用（原車接下一班、閒得久的才入庫）試過、不採用（照地形取消 13 → 24，數字在決策 296「下一步」第 1 點的「之後」）。平地白天短暫的死結（第 4 步）是決策 297（`claude/hsr-flat-deadlocks`，session_01KFRB53UNrJR1yVGu2fGJog 開工、session_011GLH8sEjxxMsy2VEXa8szu 接手）：台中、左營月台上等下一班的閒置車擋到進站的車，那站沒有一班要開時就入庫；照地形取消 13 → 4、平地 18 → 2，每小時結束時都沒有死結，代價是機廠進出多了 2.5 倍。往前看 30／60 分、換月台不算後面的車、只在中間站生效，四種都量了、不採用（決策 297「試過、不採用」）。決策 297 的「下一步」第 1–3 點是決策 302（`claude/hsr-depot-churn`，session_011GLH8sEjxxMsy2VEXa8szu）：一組正在路上的車預估比出庫的車先到時，算成接得了那站的班，不再從一個半小時外的烏日機廠派車；台中 08:04 不再取消，照地形取消 4 → 2、平地 2 → 1。「擋路的車入庫前先看來回趕不趕得上」量了、逐位元相同；「在路上的車都算接得了」讓沒有閉塞的組合 21 時起卡死，都不採用。晚點的車追回時間是決策 306（`claude/hsr-catch-up`，session_011GLH8sEjxxMsy2VEXa8szu）：號誌與閉塞打開時，晚點的列車照到表定到站剩下的時間跑，最快照車的性能與彎道限速，不超過設計時速；照地形 取消 2 → 1、晚點中位數 7／11／9 → 3／3／9 分、平地取消 1 → 1、晚點中位數 4／10／11 → 2／4／9 分。沒有閉塞時也追回會在夜裡互等（台南的進路宣告、左營咽喉與要入庫的閒置車），量了、不採用。**交接：決策 302 的「下一步」第 1–3 點**（晚到的車停下那一兩分鐘的出庫、南港咽喉的取消、左營月台的互等）**與決策 306 的「下一步」**（沒有閉塞時的兩個互等與追回時間、平地五站停晚 93 分的那一班）。決策 306 之後還能做的五項、估計與順序在 §5；第 1 項（沒有閉塞時的互等）是決策 308（`claude/hsr-no-block-catch-up`，session_0125dMtwyMdz7mzoBCRNa1pn）：跟車的宣告放開擋住前車的車（台南）、不往終點那股要結束班次的車靠近並早一點換股（左營），條件放寬到沒有閉塞；號誌開、沒有閉塞時照地形取消 85 → 77、晚點中位數 69／74／144 → 46／43／62 分，平地 85 → 79、29／38／59 分，夜裡不再有車等到天亮；閉塞與號誌關的組合逐位元不變。剩下的在決策 308「下一步」。決策 294「下一步」其餘四點還沒人做：出站的路上停著的車不能跟（決策 212 的 (C)）、咽喉的容量與南港往台北共用上行線（軌道，§10）、計算時間（一天照地形 1,657 秒）、要不要讓示範的號誌與閉塞一起打開。第 6 個 PR（GameCore 的新目標）先不做。UI 測試交給 Codex（決策 266、271、273、274、276 列了要補的） | 是（決策 280、283、287、288、294、297、302、306、308） |
| 3D 生活感 | Claude session_01EPkWLr5a25LyJvCuvh1U3R | 四步完成：#734（259）、#745（263）、#765（267）、#768（268）、#769（269）、#771（270）；#770 收尾 #752；#772 修 71.1「3D 一放大就跳回 2D」；#776 配色亮度（決策 272）；#788 場景快取；#793 Meshy 試做模型規格與讀檔；#794 雨天的光線與霧（決策 277） | 決策 277 的後兩步：(a) 雨絲：2026-10-21 由 3D session_01Y25x9NJSKmAuP1M1K3Sf3C 做完（決策 320，`claude/map3d-rain-streaks`；實機的樣子與幀數還沒看）；(b) 站前商店街（條紋雨遮、屋頂立牌、下照燈）。**已解鎖**：作者 2026-10-21 的實機幀數（iPhone 17 Pro，台北近景 CPU 2.4–3.1 ms、GPU 2.2–2.7 ms，PLAYER_FEEDBACK 72.1 節）只用了一幀的兩成；交給 3D session_01Y25x9NJSKmAuP1M1K3Sf3C（派工的第 3 項）。店名、站名、招牌配色要換成本專案自己的，不沿用參考原作那五家店與「晴川站」（art-style §7） | 否 |
| 關卡的 UI 測試、full lane、GLB 轉換器 | Codex | 三張卡都已合併（2026-10-18）：#784 關卡 UI 測試（`LessonUITests` 12 個，決策 271 列的五項都有）；#802 full lane 拆工作（`LessonUITests` 自己一個 iPhone job `FULL_LANE_LESSONS_JOB`、`-lesson-stars` 檔名常數改 public、`FlexDispatchPropertyTests` 搬到較短的 shard）；#803 GLB → `.m3dmodel` 轉換器（`tools/glb-to-m3dmodel/`，Meshy 公車 1,543 面、8 色）。之後 #821 Peakline 圖資研究（§4.5） | (1) 公車模型接進 App：3D session 做（`Resources/Models/`、XcodeGen 重新產生 `.xcodeproj`、取決策號；模型在 `docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel`，轉換器已把車頭轉成 +x）；(2) meshopt／量化與 `.gltf` 橋接已實作於 `codex/glb-meshopt-bridge`，使用／接手點見第 7.3 節；App 接入仍由 3D session 做 | 否 |
| 開發工具 | Claude session_011Z9h1X1GcZZ3i1EKEEjDZj | `GameSim` #740（決策 260）、`Policy` #748（決策 261）、文件數字檢查 #760 都已合併 | 第 7.4 節剩下的項目 | 否 |
| 示範地圖照真實的高架與隧道（決策 279、281） | Claude session_01KeynzCwtDyLHTUYBfKxy1c（作者直接交辦） | #805、#807、#808、#809 已合併（瑞芳／平溪示範、宜蘭線示範、沿真實鐵路描線、參考庫新版）；`claude/hsr-real-structures`：左營機廠的出入線；高鐵示範照真實高架與隧道的建法做好，開關先關（決策 281） | Claude platform 做完（`claude/hsr-nangang-throat`，決策 283）：南港咽喉的卡死修好（遲到的車還在終點站的股道上，進站的車改去空的一條；沿路看對向車 20 km；兩列都還沒上共用軌道時遠的等近的），開關打開，號誌關的一天 `HighSpeedDemoDayTests` 全過。號誌開＋閉塞重量的結果：左營咽喉白天就卡住（平地 09 時、照地形 16 時起），下一步見決策 283。決策 287 看了第一個死結：是閉塞分界的位置（調度），不是出入線和進站的車共用咽喉，**軌道這邊不用改**。決策 290 做完夜裡出庫的死結（調度：終點站有空股才出庫），重量一天：照地形每小時結束時都沒有死結，所以**軌道仍不用為了死結改**。軌道這邊之後可以評估的（都不急，是示範的真實度與咽喉容量，不是死結）：出入線分成入庫、出庫兩條；左營咽喉照真實改成雙線加交叉渡線（現在八股只靠下行線上一串轉轍器） | 否（決策 283、287 動 GameCore） |

**main 的 full lane 紅燈（遊戲規劃 2026-10-20 派工）**：main 的 `ios-build.yml` full lane 從 784bb3a（#833，10-19 16:41）起連續 7 次紅，最後一次綠是 ae77ab4（#827，run 39254620337）。每次都紅的是 `LineDraftSummaryUITests` 兩個（#835 新加）、`NextStepChipUITests.testANewGamesNextStepOpensTheGoals`（#842 新加）、`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`。時紅時好的是 `LessonUITests` 第 8、9 課（清單捲不到按鈕）。已派 session_01MV9BgbHcs7XFafNDk76DyD：先分清楚是 App 的 bug 還是測試過時，再修，用 `only_testing` 驗證。修好以前不發版。
  - **修了**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-red-1020`，原因與證據在那個 PR 的說明）：`NextStepChip` 不是按鈕（App）；路線面板加第一站後停在原處、表單在畫面外（App，決策 299）；月台測試點到 #839 的涵蓋捷徑、第二個月台的偏移超過 80 m 月台（測試）；第 8 課的拖曳落在面板的捲軸上（測試）。
  - **還沒查**（修完後的 full lane 再紅才查）：第 9 課 `testTheNinthLessonsSightOpensItsTourismPanel` 只在 784bb3a 紅過一次，那時 #840 還沒合併，和它無關；`CoverageShortcutUITests:16`、`LineDraftSummaryUITests:75` 的 `Failed to get background assertion`（Simulator 逾時）；`StartSaveFlowSmokeTests:499` 的 `menu.backToStart` 沒停穩。各只紅過一次。
  - **2026-10-21，run 39526204987（5040730）兩個紅**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-coverage-ipad`）：兩個都是那個 job 的第一個測試、App 的第一次啟動。
    - **iPad 的 `TutorialJourneyUITests.testTheWholeTutorialOnAnIPad`（測試，已修）**：第一次啟動花了 35 秒（綠的時候 14–22 秒），接著點 Lessons，點在 (270, 688)，不在按鈕上（478–898, 499–580），課程清單沒開。App 的紀錄只有那一下觸控，看起來是畫面還在轉向時就算好了位置。改成等按鈕停穩再點，5 秒內清單沒開就再點一次。和 #870（決策 303）無關：#870 沒改課程清單，這一步在它之前。
    - **`CoverageShortcutUITests`（Simulator，沒改）**：第二次在 `app.launch()` 就失敗（`Failed to get background assertion … Timed out`，啟動後 19.6 秒）。App 那時已經開始畫面了（01:24:37 起每秒 120 幀），是 XCTest 和 Simulator 的交接逾時，測試的步驟一個都還沒跑。上一次是 `LineDraftSummaryUITests:75`（run 39415463138），也是那個 job 的第一次啟動。最近 15 次 full lane 的 iPhone job 中，第一次啟動從按下到 XCTest 接上要 6–32 秒，有時超過這次失敗時的 19.6 秒也沒事，所以不是單純太慢。「暖機」那一步用 `simctl launch`，不經過 XCTest，所以擋不住這個。測試沒辦法重試 `launch()`。**可能的下一步**（沒做，要多跑幾次才看得出效果）：暖機改用 `xcodebuild test-without-building` 跑一個很短的 UI 測試，讓 XCTest 的第一次交接發生在暖機裡。
  - **2026-10-21，run 39546432319（01e3c9a）兩個紅，都是測試**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-held-card-lesson`）：
    - **`TutorialUITests.testATouchHeldOnTheFoldedCardAsTheStepMovesOnOpensIt`**：測試讓下一步在 4 秒後到，要在那之前按住小卡。這次按下去時已經是點 Zoom out 之後 4.4 秒（XCTest 中間的等待與尋找就花了這麼久），小卡已經換到下一步的位置，按在地圖上（App 的紀錄：`map.hold at (506, 280)`）。改成 8 秒後才換下一步，按住 12 秒。
    - **`LessonUITests.testKeepPlayingClosesTheResultAndKeepsTheRailwayRunning`**：第二次打開路線面板時，面板還在滑進來就量了清單的位置，找「加入選取的車站」的拖曳全落在 x 815.7（面板舊的右緣），清單沒動，和決策 299「後來」裡 `LineDraftSummaryUITests` 的第一個原因一樣。`reveal` 改成先等清單不動。

**決策 284–286 的 iPhone UI 測試（Codex，`codex/feature-ui-284-286`）**：`Feature284To286UITests` 共 5 個測試，檢查新路線草稿的兩種警告、複線月台卡片與確認後的兩個月台項目、兩款觀光列車的型錄說明與選擇按鈕、景點的觀光列車加星文字。只放 full lane 的 `FULL_LANE_LESSONS_JOB`，PR gate 不加測試。Debug 參數 `-ui-testing -ui-test-world <name>` 可開 `separate-tracks`、`missing-platform`、`double-platform`、`catalog`、`sightseeing`；全部先存入每次清空的測試暫存 library，再經一般讀檔入口載入。VERIFIED：Linux Swift 6.4 的 warnings-as-errors build、5 種世界的建立與存讀一致、XcodeGen 2.46.0 產生專案；GitHub Actions／macOS 26.6.2、Xcode 26.6、iOS 26.5、iPhone 17 Pro 的 [only_testing run 39341335419](https://github.com/a91453/railway-game-ios/actions/runs/39341335419)（head `3fd877f0`）5/5 通過、0 failures，測試 298.160 秒，整個 UI 測試步驟 7:36，專案 drift check 與 build-for-testing 也通過。以最近成功的 lessons job 42:56 加上完整 7:36 保守估算是 50:32／75 分鐘；UI 步驟 36:44＋7:36＝44:20／55 分鐘，兩者都留十分鐘以上。UNVERIFIED：加入新類別後的整條 full lane、實體裝置與 Release archive。下一步：審查者從本卡 PR 的 Checks 接，合併後看正常的 full lane；本卡不另手動開整條 full lane。重現只用 `ios-build.yml` 的 `only_testing=RailwayGameUITests/Feature284To286UITests`。2026-10-20 依作者回報續解 PR #840：merge main `c46f5d2d`，唯一衝突是產生的 `project.pbxproj`，已用 XcodeGen 2.46.0 重建（重複產生結果相同），保留 main 新增的 `LineDraftSummaryUITests`、`CoverageShortcutUITests` 與其 App 元件。本卡的 5 個測試、Debug world、App 測試入口與 full lane 分配皆未改，`LinesPanel` 相對 main 仍只有新增 identifier；main 的新 UI 與其他 session 交接完整保留。merge 後 VERIFIED（Linux／官方 Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors -j 3` 乾淨通過（221.86 秒），5 種 Debug 世界重新建立並經 `SaveLibrary` 存讀一致；沒有跑本機全套測試。上述 5/5 Simulator 證據屬 merge 前 head；merge 後未另手動重跑，專案 drift、Xcode build 與 PR gate 看 PR #840 的新 Checks。存檔版本、決策編號、golden schema 不動。

**Kenney 素材（遊戲規劃 2026-10-17 決定）**：Antigravity 的試看 #773（`docs/art/town-scene-preview-2026-10-17/`）證實 Kenney 包是 CC0，可以用；但人物是大頭比例、每人 690–756、每台車 2,000 以上三角形，原生 3D 已有程式做的人、機車、汽車（決策 259），所以**不放進遊戲、不做 GLB 轉檔**。素材留在 `Web/CityView/public/models/town/`（`SOURCES.json`），遇到程式做不好、Kenney 剛好有的東西再改色組合後取用。

**引擎與素材線（遊戲規劃 2026-10-17 決定；作者問「unity + blender + tripo + claude + codex」要不要跟，說「你四方決定後 幫我做決定」）**：
- **不換 Unity，留在 Swift／SwiftUI／Metal。** 玩家：換引擎要停好幾個月的新功能。開發：GameCore（Swift，270 多條決策、golden、存檔與確定性測試）要改寫成 C# 或接原生外掛，CI 與 TestFlight 流程要重建；雲端的 Claude、Codex 跑在 Linux，打不開 Unity 編輯器。美術：別人跨過的坎是做素材的速度，這和引擎無關。音樂：無。
- **素材線照別人那套，但接進現在的架構**：作者已有付費的 Meshy（`tools/meshy/`，商用輸出歸作者，條款見那裡的 README），不另加 Tripo；Blender 是作者電腦上的選項，不是必要步驟（Meshy 的 smart topology 直接給低面數）。缺的只有「GLB 進原生 3D」這一段。
- **順序**：72.1 在實機量到 3D 幀時間之後，先試一個模型（台灣速克達特寫版或市區公車，#773 指出的缺口）：Meshy 生成、遊戲規劃先報點數等作者同意並由作者在 session 裡登入；Codex 寫 `tools/` 的 GLB 轉成遊戲模型的工具；3D session 接進 Metal。好看、幀數夠，才把這條線用到更多模型。
- **試做模型的規格**（3D 生活感，遊戲規劃 2026-10-17 同意）：`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`。先做市區公車（1,500 面以內），機車排第二。不帶貼圖，每個三角形烤成一個顏色、8 色以內，車身用實例的顏色。格式是二進位的 `.m3dmodel`，GamePresentation 讀檔的 `Map3DModelFile` 已經做好（Linux 測試）。GLB 轉換器已由 Codex 做完（#803，`tools/glb-to-m3dmodel/`）。接進 App 與公車上街 2026-10-21 由 3D session_01Y25x9NJSKmAuP1M1K3Sf3C 做完（決策 317，`claude/map3d-city-bus`：`Resources/Models/city-bus.m3dmodel`、`Map3DCityBus`、主要道路車流的 5%）；還沒做的是實機上同一畫面有沒有公車的 fps 比較（規格「怎麼判斷成功」的第三條）、機車（排第二），與把 glTF-Validator 加進轉換器（新依賴，只在本機跑過，等作者同意再照 GAME_AI_TOOLS §6.3 加）。點數由作者決定，遊戲規劃建議先做一次（約 35 點）；作者登入前不呼叫 Meshy。

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
- 3D：72.1 的 fps 回報 2026-10-21 到了（近景只用一幀的兩成，遠景 CPU 16.6 ms），決策 277 的雨絲與站前商店街**已解鎖**；Meshy 公車（`docs/art/meshy-city-bus-2026-10-18/`）已由 Codex 的轉換器轉好（#803，`city-bus.m3dmodel`，車頭轉成 +x），等 3D session 接進 App。那兩個 PR 順便照 GAME_AI_TOOLS §6.3 加工具：改 3D 畫面的加 pixelmatch 差異圖，接 Meshy 公車的加 glTF-Validator。
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

**預覽圖放哪裡（2026-10-22，session_011DWN98Fo4KePt7PLmgsV9e，遊戲規劃派工）**：遊戲不讀的預覽圖、截圖放私有庫 `a91453/railway-reference-private` 的 `Railway/game-art-previews/`，路徑和這裡一樣（`docs/art/<資料夾>/`、`tools/cityview-benchmark/examples/`）。這次從 main 01956db 搬了 138 個檔、約 31.7 MB（逐檔 SHA-256 核對，清單是私有庫的 `Railway/game-art-previews/MOVED_2026-10-22.sha256.txt`）；每個資料夾留 README（開頭一行寫其他圖在哪）、一張總覽圖、文字紀錄（`.md`、`.json`、`.html`、`.svg`）和測試讀的 `meshy-city-bus-2026-10-18/city-bus.glb`、`city-bus.m3dmodel`。**以後的規則**：PR 只把 README、一張總覽圖和小的紀錄放進 `docs/art/`，其他圖先在私有庫開 PR；各 kit 的 `rebuild.sh` 本來就拒絕寫進公開 checkout，`Web/CityView/tools/town-preview/preview.cjs` 改成一定要給輸出資料夾。git 歷史裡的舊檔沒有改寫，`.git` 不會變小。

## 3. 作者說過的話、還在等作者的事、遊戲規劃代為決定的事

| 事項 | 狀態 | 在哪裡 |
| --- | --- | --- |
| 10/31 正式對外：公開 TestFlight，App Store 之後 | 作者 2026-10-23（內測 47 人）：「我10/31想要正式上testflight 還是直接上app store」。**規劃的建議：10/31 開公開 TestFlight 連結**（外部測試最多 10,000 人，不必過 App Store 審查的上架項目），App Store 等公開測試約兩週、一週內沒有新的閃退與卡死再送審。時程：10/24 發 85.1（2D 6000×、3D 地面、課程引導），作者實機量過再開第二批內測；10/27 前後 86.1（第二批回報、3D 畫風 (e)）；10/29–30 只修 bug、不加新東西；10/31 用最後一個 `ci.yml` 與 full lane 都綠的版本開公開連結。**可以提早**（作者 2026-10-23：「好 照這三個條件」）：三條都達到，就在 86.1 那天（約 10/28）開，10/31 是最晚：(1) 85.1 作者實機量過，高鐵 6000× 不卡、3D 跟車不閃退；(2) 第二批內測進來後連續兩天沒有新的閃退或卡死回報（PLAYER_FEEDBACK）；(3) 那一版的 `ci.yml` 與 full lane 都綠。每一版發出後，遊戲規劃照這三條檢查，達到就告訴作者「可以開公開連結」；開連結是作者在 App Store Connect 的步驟。App Store 之前還要（作者的 Apple 帳號步驟加程式）：列車包的 StoreKit 2 與拿掉測試開關（決策 338，或第一版先不賣列車包）、隱私標籤、年齡分級、商店截圖與說明、送審說明（決策 335 的定位）。五方：玩家 30（公開測試讓更多人玩到，壞了還能每天修，不會留下一星評價）；鐵道迷 15（無）；開發 25（App Store 的審查與付費項目來不及在 8 天內做好又驗證）；美術 15（商店截圖與圖示可以趁公開測試期間準備）；音樂 15（無） | 這一列；#1041 |
| 這個 repository 維持公開，著作權所有 | 作者 2026-10-23：「我沒寫mit…怎樣能防止被拿走」→「授權」→「因為我要省action 費用所以只能公開」。**repository 不改私有**（公開的 Actions 不計費；改私有後 macOS 分鐘以 10 倍計，一次 full lane 就用完免費額度；遊戲「資料來源」頁也連到這裡提供 ODbL 資料與授權全文）。保護靠根目錄的 `LICENSE.md`（#1104）：著作權所有，未經書面授權不得重製、改作、散布或用來上架；自帶授權的檔案與第三方資料照各自的授權，從 OpenStreetMap、Overture Maps 整理出的資料檔依 ODbL 1.0。**以後的規則**：不要提議或替作者改成私有；不要加 MIT 或其他開放授權到整個 repository；新進的第三方程式或素材把它的授權檔放在自己的資料夾（`LICENSE.md` 的例外第 1 條才涵蓋得到）；還沒要公開的預覽與大型素材照舊放私有的參考庫。五方：玩家 30（有人照抄上架時好檢舉，玩家不會裝到假冒的）；鐵道迷 15（資料出處與 ODbL 照舊公開）；開發 25（CI 免費、不動建置）；美術 15（美術、模型明確屬作者）；音樂 15（音效、配樂同上） | `LICENSE.md`；#1104；#1041 |
| 現階段先優化，再加新功能 | 作者 2026-10-23：「現階段先優化遊戲再加新功能比較好對不對」→ 遊戲規劃的分法 →「好 就照這個順序」。**第 85 版是穩定版**：(1) 馬上做：卡頓、發熱、當機（2D 高鐵 6000× 只有 3 fps，決策 375）、3D 地面與道路插進山丘（§22.2 10e）、課程第 3–10 關的一步一步引導（決策 376，另一個帳號的 session_01QTjYzbHDE2QFpRux5BQSsW）；(2) 可以穿插：只加顯示、不動規則的小改動（像 #1089）；(3) 先不派：動 GameCore、存檔或新系統的大功能，等第 85 版發出、作者在實機重量過（6000× 的幀數、發熱）再從 NEXT_PRIORITIES 挑。五方：玩家 30（卡頓與看不懂比少一個功能更容易讓人放棄）；鐵道迷 15（示範要跑得順，真實路網才看得下去）；開發 25（先把量測與快取做好，之後加功能才有底）；美術 15（3D 畫風 (e) 屬於優化，可以一起做）；音樂 15（無） | 這一列；#1041 |
| 3D 地標怎麼做（101、台北車站與之後每一棟） | **固定規則**（作者 2026-10-23：「記得以後都用website的那種模型做法來調整地標」）。每一棟地標照三步做，PR 寫出每一步用了什麼：**(1)** 先用作者參考庫 `a91453/railway-reference-private` 裡的粗略模型（例如 `scripts/landmarks.py` 重組的形狀）當起點；**(2)** 再用官網 3D 試作（決策 152、239）的 Overture 資料核對足跡、高度、樓層。101 與台北車站在 Overture 裡的資料是從 OSM 搬過去的，兩邊完全一樣，所以規格直接讀 OSM（`height`、`building:levels`、`building:part`）；**(3)** 最後照真實照片調外觀細節（分段、出簷、屋頂、窗）。照片和 Mapbox 等地圖的畫面只拿來看，不放進 repository、不上傳到外部服務，也不描它們的模型或幾何（Mapbox 只能看外觀）。三角形數量照決策 238、267 的近中遠細節分級；顏色照決策 370 的 (e) 調色盤。 | 決策 370；#1107 |
| 遊戲的資料來源改了，官網也要改 | **固定規則**（遊戲規劃 2026-10-23，作者要求重寫資料來源頁時定的）：`Sources/GamePresentation/DataSourceCredits.swift` 的來源加、刪或改寫時，同一輪也改官網的資料來源頁 `a91453/railway-reference-private` 的 `Website/site/credits.html`（中英兩邊說法一致）。官網保留自己的截圖底圖說明與網站字型那一節，不放原始碼儲存庫的連結（`Website/README.md` 的「注意」），遊戲裡寫「可從原始碼儲存庫取得」的地方，官網寫「取得方式見遊戲內的「資料來源」頁」。新的中文字要重新產生網站字型（`Website/README.md`）。隱私權政策 `Website/site/privacy.html` 也一樣：遊戲加了網路連線、權限或會送出資料的功能，同一輪改它 | `DataSourceCredits.swift` 開頭的註解；`Website/README.md` |
| 高鐵開到台北時 3D 能不能邊開邊載入前方 | **第一個 PR 做了（決策 358，`claude/map3d-streaming-window`，session_01DQGby5PQyfvKAmzTey1zVE）**：實景地圖的 3D 以 512 m 一格的滑動視窗跟著鏡頭，前方 6 km 的格子在背景一塊 3 × 3 先蓋，遠在後方的丟掉；十倍速以內跟得上，超過 1,000 m/s 停止載入。還沒做的（高倍速的粗遠景是第二個 PR、非實景地圖、真實列車與街景跟著走、實機量測）寫在決策 358「下一步」。作者 2026-10-22：「那如果像高鐵開視窗到台北是不是沒辦法 還是可以移動的時候邊載入前方視野邊使用gpu 繪圖」。**規劃的回答：做得到，還沒做**。現在 3D 場景以焦點為中心一次蓋好（`Map3DScene.reach` 每邊 6,000 m、`margin` 1,500、`chunkSize` 512，`Map3DSceneCache` 在背景蓋），開出範圍就要重蓋。提議的做法：以 512 m 的格子做滑動視窗，前方的格子在背景執行緒先蓋、後方的丟掉；300 km/h（83 m/s）時前方 6 km 約有 70 秒的餘裕，10× 時只剩約 7 秒，所以高倍速用粗的遠景或限制速度。提議排在 §22.2 第 4 名（前面展望，已做完）之後、派給 3D 鏡頭那條線。作者 2026-10-22「你五方決定 排序」→ **規劃決定做**，排在 NEXT_PRIORITIES §22.2 第 10a 名（第 10 名紀念章之後、第 11 名觀光列車之前），給 3D 那條線；五方與分數寫在那一列 | NEXT_PRIORITIES §22.2 第 10a 名 |
| 網頁 3D 試作（高雄、台中）要不要標「技術試作」 | 作者 2026-10-22：「那我想問網頁3d試做的高雄/台中 能搬一點想法進遊戲嗎 怕大家看到後對遊戲太失望」。搬什麼、什麼順序已排進 NEXT_PRIORITIES §22.10（#1011），由 3D 城市線照做。作者 2026-10-22「你五方決定 排序」→ **規劃決定標**：網頁頁面上加一個看得見的「技術試作」小標，中英兩種，說明遊戲裡的 3D 正在逐步加入這些效果（頁面標題本來就寫「3D 城市試作」，但畫面上看不到）。五方：玩家：從網頁來的人期待和遊戲一致，比較不會失望；鐵道迷：無；開發：只改 `Web/CityView/` 的頁面與 `boot.js`，很小；美術：小標照網頁現有的 credits 樣式，不擋畫面；音樂：無。排在 NEXT_PRIORITIES §22.2「隨時可派的小修」第一項，有空位就派 | NEXT_PRIORITIES §22.2 |
| Codex 生成的 3D 素材包怎麼用 | 作者 2026-10-21：「現在多了一堆codex素材包你怎麼處理」→「全部都可以用是他自己生成的」。可用的包：#900 場景套件（`SceneKitBuilder`）、#913 車站套件（`StationKitBuilder`、`Map3DStationKit`）、#921 細節套件（`Map3DDetailKit`）、#925 工程套件（合併後）。**3D session 的接入順序**，一次一個 PR：(1) 車站（#922，決策 321）；(2) 站前商店街（決策 322）；(3) ~~#900 的透天厝放到城市地塊~~ 量過不做：一塊 64 m、約 22 戶的地塊近看從約 1,550 變約 12,000 個三角形（約 8 倍），會失去決策 231／242 的牆面貼圖，獨棟四面開窗排不成街屋（決策 326 的「沒有選的做法」）；(4) 細節零件放到車站與軌道旁，第一個是架空線與電桿（決策 326），接著號誌機、轉轍器；(5) 會動的零件最後做，照 `.claude/skills/motion/SKILL.md`。原則：包當函式庫用，不改包裡的檔案；近看才用模型，遠看是方塊；每步量三角形與畫面成本；GameCore、存檔、golden 不動。列車的車頭維持 #900 的弧形、顏色用新版（作者 2026-10-21，決策 318 的 #923）。**第二波素材**（遊戲規劃 2026-10-22 派工，3D session_01ShaLWGSyEn9fYcNjS8j5Gz，決策 331）：(1) 車輛：輕型捷運（`C`）已畫成綠色三節電車（`claude/map3d-kit-vehicles`；派工寫的 `L` 是線性馬達捷運，不改）；兩節綠色通勤車已接上，兩節的通勤電聯車畫成它（決策 331 續二）；中巴 #960 自己已加進車流；(2) civic／park／commercial／works kit 照真實資料放地標，近看才放：寺廟已用公共建築套件畫在真實位置（`claude/map3d-kit-temples`，決策 331 續），公園套件已放進實景地圖的公園（決策 331 續三）；商業套件已放在城市與高鐵大車站的站前（決策 331 續五）；機廠的工程套件與學校醫院還沒做；B7（非實景地圖的街道穿過站房）由 #976 修；(3) 車站附近少量住宅模型：量過不做（決策 331 續六：農地格都在 700 m 外，換城市地塊會在近景與遠景之間留下空洞或貴 8 倍）。還沒做的寫在決策 331「還沒做的」 | 決策 321、322、326、331；這一列 |
| 列車包（付費內容） | 作者 2026-10-22：「我現在更新的套件組要做成付費內容嗎」「開發版不能先鎖東西嗎 然後我輸碼解鎖」→ 五方建議後「好 照你的做」。**決策 338**：列車包現在只有三節都市電聯車，沒解鎖時照舊畫一般通勤車；設定的「測試」區有解鎖開關，只在 Xcode 與 TestFlight 的版本出現。**上架前要做**：作者在 App Store Connect 簽付費 App 合約、填稅務與銀行、建一次性購買的「列車包」商品並訂價；之後開 PR 接 StoreKit 2、加「購買」與「恢復購買」、拿掉測試開關，送審前確認 App Store 版本沒有「測試」區。之後的新車要不要放進包，加進 `TrainPack.sets`。338（續）：#992 的五節、七節輕軌也進了包，解鎖後兩節的輕型捷運畫五節輕軌、三節畫七節輕軌，其他節數照舊綠色電車 | 決策 338（`docs/decisions/338.md`） |
| 實景開局的「用我的位置」 | **已做，決策 335（#963，2026-10-22 合併）；實機待確認**。實景選點的地圖右上角「用我的位置」：只要求使用 App 期間的定位權限、取一次位置、四捨五入到約 1 公里後把框移過去；不在背景追蹤，位置不存、不傳出裝置；App Store Connect 的隱私標籤不用加「位置」（出處與給作者的送審說明在決策 335）。**CI 驗不到、要作者在 TestFlight 實機看**：(1) 第一次按時的權限對話框只有「使用 App 期間」，用途文字中英文都對；(2) 允許後框移到所在地附近，在本島或澎湖時沒有說明小卡；(3) 拒絕、或到「設定」關掉定位後再按，小卡說「這個 App 的定位已關閉……」，搜尋與點地圖照常；(4) 按下後的轉圈不會卡住（30 秒內有結果）。有問題就開一個 PR 改 `OneShotLocation`／`RealWorldPicker`。同一個決策 312 也沒做「已下載的地點」：存檔摘要沒有錨點，要做得先在 `SaveSummary` 記錨點 | 決策 335（`docs/decisions/335.md`）、ARCHITECTURE 決策 312 |
| 競爭對手與收購公司 | 作者 2026-10-21：「收購整條線 或公司會讓玩法變有趣嗎」→「好 排進去……然後競爭對手與收購公司再考慮一下」；2026-10-22 交給遊戲規劃五方決定。**規劃 2026-10-22 決定做 A「汽機車分走旅客」，不做 B「對手鐵路公司」、C「收購公司」**（決策 332 的「沒選的做法」）。A 由 session_018gQPWzopcCfuR9gTAApKTj 做，一步一個 PR：(1) 一頁設計 `docs/decisions/332.md`（#967，已合併）；(2) GameCore 的運具分配，存檔 70，`claude/mode-shift-core`（規則、`setModeShift`、玩家的新遊戲打開；挑戰、示範、教學不開），已合併（#986）；(3a) 車站卡、路線卡那一行與原因，`claude/mode-shift-cards`，已合併（#995）；(3b) 縣市上限、鄉鎮加縣市的工具、`DataSourceCredits`、實景地圖的量測，`claude/mode-shift-county`，已合併（#1001）；(3c) 點路線卡那一行跳到車站、站長只說一次的提示，`claude/mode-shift-hint`。之後的（高鐵城際、觀光客、每站的縣市上限、尖峰塞車）沒有人做，見決策 332「下一步」第 5 項。收購支線另排在 §19 第 9 名 | 決策 332；NEXT_PRIORITIES §20.2 |
| 69.1 之後先不開新工作 | 作者 2026-10-16（69.1 發版後）：「不用凍結了 但也先不要開工我要做pr review 跟ci優化」。發版凍結解除，PR 照一般規則合；但核心玩法第 4 個 PR（關卡）、3D 2b、文件數字檢查等都先不開，等作者說開工。現在只跑：PR #712–#754 審查（session_01QVLVMib2sHjahi6BdYdK48）、CI 優化（session_01LQE9Rif1ggbZsT3iYQiN7G）。各線都已通知 | #231 |
| 69.1 的發版 | 作者 2026-10-16：「交給你綠了就合 紅了解衝突 最後是試著發一版TestFlight 但前提是要所有pr都綠 無失敗」「記得要adhoc external」，之後「隨便 我來發69.1了」，作者自己跑了 run 69（e68f237）。#747 的 What to Test 晚兩分鐘合併，沒被帶上（`docs/research/PLAYER_FEEDBACK.md` 69.1）。教訓：What to Test 的 PR 要最先合，不要排在最後 | PLAYER_FEEDBACK |
| 航空遊戲手感借到鐵道 | **遊戲規劃 2026-10-16 決定**：③ 到站收入飄字併進核心玩法的回饋（#724 的「+$12」）；①座位圖、②每趟蓋章、④車型「剛好／太大／不夠」、⑤兩端站需求燈，排在核心玩法第 5 個 PR 之後，當「回饋第二批」，由遊戲規劃開 session。理由——玩家：先讓核心玩法好上手，再加細節；開發：和回饋共用同一套 GamePresentation 事件，晚做不重工；美術：照《沿線》的畫風重畫，不用影片的霓虹；音樂：蓋章可沿用目標旋律的音色 | session_01NoAXS67jevFRE5XRz37tcF（研究） |
| 高鐵示範的誤點 | 作者 2026-10-15：「沒差先誤點再看怎麼調整」。#660 之後誤點中位數約 7 分、最多 27 分，作者接受；調整方向記在 #660 的留言 | #660 |
| iPhone 左欄縮回 56 點後，iPad 建造欄還是 72 點 | 「作者決定的」沒有原話可查。**遊戲規劃 2026-10-16 決定維持 72 點**。理由——玩家：iPad 畫面大，72 點比較好點，也沒擠到地圖；開發：#721 已經合併，不用再動；美術：iPad 的工具欄留在左下，和 iPhone 本來就是不同排版（決策 226）；音樂：無。作者實機看了覺得要縮，再開一個小 PR | #721（已合併） |
| 加依賴：ACE-Step 1.5 當離線配樂工具 | **遊戲規劃 2026-10-16 決定：現在不加**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」）。玩家：現在缺的是好上手，不是配樂的種類；開發：要 Python 與 GPU，雲端 session 沒有 GPU，只能在作者電腦上跑，而且要改決策 219 §2.2；美術：無；音樂：MML Studio 的流程（決策 219）讓配樂和到站鈴同一種音色，生成的配樂音色不一致。配樂需要更多變化（聲音第 3、4 階段）時再評估 | 已決定 |
| 加依賴：`tools/` 用 glTF-Transform 與 meshoptimizer（npm），讓 3D 的 GLB 在電腦上轉檔 | **遊戲規劃 2026-10-16 決定：同意，只在 `tools/` 用**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」；加依賴是作者保留的決定，合併協調 session 再問作者本人，作者回「四方 思考 最後做決定」，#729 才合併）。條件：兩個都是 MIT；寫進 `tools/` 底下一個工具自己的 `package.json`，版本釘死，加上 lockfile；App 與 Swift 套件不讀它們，也不打包進 App；授權寫進該工具的 README。轉出來的模型照 art-style §7 拆零件、重組、換成調色盤顏色；原始 GLB 與對照留在 scratchpad 或私有參考庫。玩家：3D 的人、車、地標可以更快做到目標畫面；開發：Linux 沒有能讀 GLB 的 Swift 套件（第 4.1 節），用現成工具比自己寫解碼器小；美術：只是取零件的手段，成品還是遊戲自己的風格；音樂：無 | 已決定，3D 生活感 session 可以用 |
| CI 優化（決策 265，session_01LQE9Rif1ggbZsT3iYQiN7G） | 作者 2026-10-16：「我要做pr review 跟ci優化」。四項由遊戲規劃以四方決定：把 iOS 列為必要檢查、關掉 auto-merge 都先不改，#756 跑一陣子再評估；PR gate 的 UI 測試名單不動（`docs/research/CI_MEASURE_2026-10-16.md` 第 3 節 E）；分片逾時上限 20 分不改，下次重新分配分片時再看。之後若 macOS 又常排隊，先看研究文件的方案 | 已決定 |
| CI 流程優化（決策 329，session_01E8oiGWPQZ2a8wAE8tNvFKk） | 作者 2026-10-21：「還需要一個session優化ci流程」。三個 PR：新決策一個檔一個（`docs/decisions/`）；被取代的 PR run 不判紅、swift-build 崩潰重試一次；main 的 full lane 紅了在 #231 自動留言。量測在 `docs/research/CI_MEASURE_2026-10-21.md`。**之後可以做的**（量過，沒做）：`ios-build.yml` 的 Simulator 開機（約 2.0 分）和建置（約 2.6 分）並行，以及翻譯匯出（約 2.9 分）不排在 UI 測試後面——這兩項只能在 macOS 上驗；HANDOFF 這份本身三天衝突 8 次，可以照同樣做法把 §2 的各列拆成檔；`superseded` 讓 gate 變灰，要等某個 PR 真的有一輪被新 push 取消，才看得到效果 | 做完；之後的兩項沒人接 |
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

預覽圖在 `docs/art/map3d-*-2026-10-1*/`。畫風在 `docs/art/3d-style-2026-10-13/`（README 與總覽 `ftwplus-top.jpg`；其他圖在 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/`，同一相對路徑），最接近作者要的是 `ftwplus-street.jpg`。

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
- 深度是反轉的（決策 342）：近處 1、遠處 0，清成 0，比較用 `.greater`。2 cm 的層在所有鏡頭至少隔 18 個深度刻度（`Map3DDepthTests`）；改投影或加更薄的層時跑 `MAP3D_FRAME_REPORT=1` 的 `testTheDepthReport`。
- 陰影 pass 不寫深度、用 greaterEqual（決策 342 前是 lessEqual），最後才疊上去。
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
2. 擋住列車的建物變透明：決策 342 做了。玩家列車前面圓錐裡的城市畫成 25%（alpha to coverage），只有圓錐經過的 chunk 改畫。
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

示意圖相關檔案（2026-10-22 起在 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/3d-style-2026-10-13/`）：
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

### 4.6 3D 地圖的淡色模型樣子（決策 370，session_014cbL5XNksWgQgYNkhMDNxV，#1075）

作者 2026-10-23 要 3D 像 Mapbox Standard。預覽、選定、「玩得清楚嗎」的對照與數字在 `docs/art/map3d-mapbox-look-2026-10-23/README.md`；原圖與腳本在參考庫同名資料夾（參考庫 #53 已合併，#54 是之後的重捏地標與 `play/`）。規劃選 (b)，做進遊戲的是 README 裡的 **(b'')**。

做到哪：第 1 步（全城換色、柔光、路燈光）已做，見本節最後的「第 1 步做了」與 `docs/decisions/370.md`；下面的清單是當初的派工，留著對照。

接手的人要做的（#1070，決策 368 合併後）：

1. 先在 #1041 更新登記。
2. 寫 `docs/decisions/370.md`，寫清楚改了決策 241 的哪些部分、242 的哪些部分：
   - 241：路面的藏青四階改成白（#FFFFFF–#F8F8F8），人行道改成路緣 #8F949E，黃色中線留。
   - 242：牆面細節留，但淡（預覽裡細節對比乘 0.35，牆腳較暗，影子較深）。
3. 先做 101 與台北車站。形狀照參考庫 `scripts/landmarks.py`，那是重新組的，不是原網格；顏色照 README 的表，101 玻璃天藍 #C0DDEE。
4. 再做全城淡色：
   - `Map3DPalette` 換色，照 `compose_play.py` 的 `REMAP`／`KEEP`／`pale()` 和 `roads` 選項；
   - `map3dShade` 加上柔光，強度跟著時間（預覽頁 `index.html` 的 `look`）。
5. 實機看夜晚的路：(b'') 的路面與地面夜晚只差 ΔL* 4.5。
6. 跑 `Map3DSceneMemoryTests.testThe3DMapRoundBanqiaoFitsAPhone`，記憶體不能增加。淡色只換頂點色；留招牌就不省貼圖（約 30 MB 的數字在 README）。

(d) 融合版（session_015wf4dPgATxoWNLz6ef2PW7，2026-10-23）：(b'') 的淡色加中灰路面（L* 62，#949598–#A6A7AA）、白路緣，天黑後路面加路燈光（黃昏不開）。顏色與對比（含白色、有色公車）在 README「(d) 融合版」。作者看圖後，由遊戲規劃把 (a)、(b'')、(d) 一起評分。選了 (d) 的話，上面第 2、4 點的路面改用 (d) 的顏色；`map3dShade` 給路面一個新 layer，天空夠暗時加路燈光（預覽頁 `ROAD_LAMP` 與天空亮度 0.30–0.42 的 smoothstep）。(e) 圖示色的 (d)（同一 session，同日）：明度同 (d)，路改帶藏青色相的灰（C* 6，#9595A0–#A8A7B2），地面 #ECEEF6，中線、燈頭、窗燈 #FFC86B（路燈照在路面的光仍是暖白）；`play-e.jpg` 與 README「(e) 圖示色的 (d)」，五方加權 7.43。選了 (e) 的話，除了 (d) 那些，再改地面色與中線色，窗燈顏色改 #FFC86B；月台邊線和中線同一個顏色，要不要一起換再決定。

**作者選了 (e)，月台邊線保留 #F2C94C**（2026-10-23：「用分數最高的7.6那個」）。這一段取代上面的「規劃選 (b)」：做進遊戲的是 (e)，路是帶藏青色相的灰 #9595A0–#A8A7B2，地面 #ECEEF6，中線、燈頭、窗燈 #FFC86B，路燈照在路面的光照 (d)，月台邊線維持 #F2C94C。上面第 2 點的路面與第 4 點的換色改照 (e)，第 5 點改看黃昏：路燈比 (d) 早一點開，有色公車與白牆在灰路上才看得清（差距 4–11）。排序：等 §22.2 10e（3D 地面與道路插進山丘，session_01AEq1bFjyAS1nyPmCs6wW7p）合併後才派，避免兩邊改同一批 `Map3D*` 檔。順序：先換全城顏色、作者用 iPhone 看；再做 101 與台北車站；最後跑板橋的記憶體測試。五方用同一把尺（(a) 6.90、(d) 7.45、(e) 7.45、(e)＋月台邊黃 7.60）：玩家 30 是 8.5（軌道、列車、公車都清楚，夜晚路對地面差一點仍看得清）；鐵道迷 15 是 8（柏油路是灰的，月台邊維持安全黃）；開發 25 是 7（只換頂點色，窗燈多一個 uniform，記憶體與 (d) 相同）；美術 15 是 9（和 App 圖示同一套顏色，作者在意的風格保住）；音樂 15 是 5（無關）。

**第 1 步做了**（session_01BnZ6aE54dfdknXcyjYqUvQ，`docs/decisions/370.md`）：全城換成 (e) 的顏色（`Map3DPalette`、新檔 `Map3DLook.swift`）、柔光、路面 layer −11 與路燈光（天空亮度 0.70 起開，0.50 全亮，比 (d) 早）。夜晚路面對地面 ΔL* 14.1；黃昏列車、白牆、公車對路面最小 7.8。板橋記憶體測試綠，頂點數不變。對照圖 `docs/art/map3d-mapbox-look-2026-10-23/game-e.jpg`。還沒做的：

1. ~~第 2 步~~ 已做（同一 session，決策 370「第 2 步」）：101 與台北車站做進遊戲（`Map3DTaipeiLandmarks.swift`，線條 layer −5、−8、−9）。作者要照網頁版高雄車站的方法先抓規格，所以大小、高度、101 的塔位（在購物中心的角上，不在中間）照 OSM 的 building part，台北車站頂 30 m；細節照 `landmarks.py`。玩家地面上的軌道穿過時地標讓路，台北車站畫出來時套件的台北站房不畫。板橋記憶體測試綠，網格 +0.03%（車站遠看的模型）。對照圖 `game-landmarks.jpg`。之後作者要 101 上半部更好看：加了白色平台與四個玻璃小箱、倒梯形頂層、三階退台、細尖塔（508 m），每節白腰帶與四角白直條，八節照真的外斜 7°，夜裡每節一圈光帶、白簷與頂冠打燈、尖塔頂一點白光（新的 layer −10、−12；`taipei101-crown.jpg`）。台北車站照三步（參考庫起點、OSM 規格與 entrance 節點、照片只看）加了四面騎樓、十二個門、南北中門的門廳與小瓦頂、方窗帶、屋角起翹、脊飾、雙坡天窗（`station-detail.jpg`）。作者看過預覽，2026-10-23 說兩棟都可以合併（PR #1107）。
2. 實機（TestFlight）看黃昏與夜晚的路、白天白牆對路面（只差 ΔL* 3–9.5，靠路緣與陰影分）。
3. 天空與霧沒有改；要不要照預覽調淡，看實機再決定。
4. 地標還沒做的：
   - 實機看 101 的夜景（光帶、角落燈條、尖塔頂）與台北車站的窗帶，看亮度要不要調（`Map3DShaders.metal` 的 −10、−12 分支）；
   - 台北一帶沒有真實建物圖塊（決策 239 只有高雄、台中），101 周圍是城市的建物；要不要加是另一件事；
   - 之後的地標照 §3 的三步做（參考庫起點、OSM 規格、照片只看），夜裡要特別的燈就用 `towerGlass`／`floodlit`。

預覽工具：參考庫 `scripts/Map3DPreviewDump.patch`（`MAP3D_PLAY` 放列車與標籤位置），用法在那裡的 README。

### 4.7 鐵路低於地面的路塹（決策 375，session_01AEq1bFjyAS1nyPmCs6wW7p）

作者 84.1 的回報（駕駛室前面只有路、白色平面切進山）：道床低於 64 m 的地面的地方，現在挖一條溝（`Map3DTrench.swift`），地面、底圖、道路、標線、街上的車都讓開，深溝上的跨路留成橋。還沒做的：

1. 10e 其餘：照圖磚 `brunnel`／`layer` 把公路橋架高（每層約 6 m、兩端坡道、墩和 10f 共用）。跨溝的路現在只在溝深 6.5 m 以上、夾角大於 30° 時留在地面高度當橋；淺溝上的路是讓開的。
2. 真實路線（`Map3DRealTrains`）的路塹沒有挖。
3. 小瑕疵：兩段溝接在一起的地方可能有細縫；溝坡上的電桿腳埋在坡裡；溝的端面只在隧道口封。
4. 實機：TestFlight 上從高鐵示範的駕駛室看苗栗南的路塹（最深約 20 m），看坡的顏色、跨路的橋和 fps。

### 4.8 全地圖用真實建物足跡（決策 386，session_0111G2MZyPt5YSXpsF6azF2e）

第 1 步做完：`tools/overture-footprint-tiles/` 把 Overture 的台灣建物（196 萬棟）做成 z16 精簡圖塊，全台 29 MB；報告 `docs/research/OVERTURE_FOOTPRINT_TILES_2026-10-23.md`。資料檔沒有提交，照工具的 README 重建（約 2 分鐘）。還沒做的：

1. **第 2 步：GamePresentation 讀足跡、有足跡的地方用足跡**。chunk 載入時用 `PMTilesArchive` 讀它碰到的 ≤ 4 塊 z16 格，重心在這個 chunk 的建物用決策 239 的 `addRealBuilding` 擠出（near 與 far），取代那裡的程序房子；樓層照決策 386 第 6 點的順序（報告 §8）；在那之前先讓工具 `build` 照這個順序把臺中市建物圖（111 年版）與臺北市建築執照套繪圖的樓層填進樓層 0 的建物，都沒有的照第 5 點推算（報告 §7 的表與 `proposed_storeys`）。沒有足跡的地方照舊程序生成，**沿真實道路的程序房子與不蓋區是決策 385（session_01AgFLCW9xSb9fyLr8k57iZ1）**：動 `addCity` 或程序房子的放置之前先 `send_message` 給它，對齊用途分類與人口密度的來源。要保持 `Map3DSceneMemoryTests` 的板橋數字不升；足跡房子要不要加立面細節是這一步的美術決定（每棟不超過程序房子一棟）。量測範本 `FootprintWindowMeasure.swift.txt` 可以重用。
2. **第 3 步：打包**。決策 386 選全部打包：`taiwan.pmtiles` 改名（例 `RealWorld/taiwan_buildings.pmtiles`）加進 App 的資源與 `project.yml`、重產 Xcode 專案；看 TestFlight 的 App 檔案大小（報告裡 UNVERIFIED）。App 變得太大時的退路是 Background Assets 每縣市一包（工具已產出 `counties/`）。
3. **第 4 步：署名**。`DataSourceCredits` 與官網 `credits.html` 加 Overture Maps（ODbL 1.0）、OpenStreetMap（已有）、Shi 等人 East Asian buildings（CC BY 4.0，doi:10.5281/zenodo.8174931）。
4. 樓高來源還沒做完的（報告 §8）：推算在 p25–p75 裡改用 GHSL 挑高低（8.2，建檔時用 `tiff.py` 讀，App 不讀）；內政部 20 m DSM／DTM 從 TGOS 下載（這個環境 403）；臺中 113、114 年全市版是 RAR／7z（要解壓工具就是加依賴，先問作者）；國土測繪中心的授權由遊戲規劃轉給作者決定要不要問（要問的事在 §8.5）。
5. Overture 每月出新版；換版本時重跑 `extract` 與 `build`，在 PR 寫新舊棟數與大小。

### 4.9 機場等地不蓋房子、程序房子沿真實的街（決策 385，session_01AgFLCW9xSb9fyLr8k57iZ1）

作者 85.1：「機場不要有住宅看起來好怪」「而且也太整齊了吧」。做完的：實景 3D 地圖在機場、軍事用地、墓地、高爾夫球場、鐵路用地與港區不畫城市的房子，機場畫 OSM 的航廈與機棚（`tools/no-build-land/`、`RealNoBuildLand`）；程序房子沿底圖的真實道路排、面向馬路，寬窄、退縮、樓高、種類有變化，沒有路碰到的格子不放（`Map3DFrontage.swift`）。三角形與記憶體不高於 main（決策 385 第 3 點）。還沒做的：

1. **人口還在**：機場等地的格子仍有世界的居民（LandImport 的分區沒有這些地，決策 96），只是 3D 不畫。讓 LandImport 對這些地不給人口（GamePresentation 的資料工具）之後，GameCore 的城市成長才不會在那裡長；要不要升存檔、動不動 golden，到時量。沒有人接。
2. **和決策 386 第 2 步對齊**（§4.8）：有 Overture 足跡的格子不放沿街的房子；兩邊的用途分類與人口密度來源要一致。動 `addCity` 的人先 `send_message` 給這兩個 session。
3. **實機**：只在 Linux 的 WebGL 預覽看過（`docs/art/map3d-no-build-2026-10-23/`）；下一次 TestFlight 看 600 倍俯看小港與板橋，房子是不是太稀或太密（`Map3DScene.Builder.openShare` 與 `layFrontage` 的公寓比例）。

## 5. 已知、還沒派的待辦

| 事項 | 來源 | 狀態 |
| --- | --- | --- |
| 遊戲跑著時，以 `worldRevision` 記住的預覽每個 tick 都重算：複線升級（選取工具，不暫停）在 80.1 讓 iPad 卡死，`claude/double-track-upgrade-hang` 改成以 `commandRevision` 記。同樣以 `worldRevision` 記的還有建造工具的 `NetworkSession` 草稿、`PassingLoop`、`DepotYard`、`LevelPlatformTrack`：建造工具會自動暫停，但玩家在草稿開著時按播放就會一樣每個 tick 重算。另外第一次算長的「到兩端道岔」預覽在 Linux debug 要 0.4–1 秒（一次的停頓），實機沒量 | PLAYER_FEEDBACK 80.1 #1 | 沒有人接（GamePresentation 的小 PR：同樣改用 `commandRevision`，按 ✓ 時再算一次） |
| 高鐵示範快轉只有約八成速度（一個 tick 123 ms，間隔 100 ms） | 決策 248、#709 | 排在核心玩法之後 |
| 高鐵的長進路／閉塞區間死結、台南—左營交會 | #669，機廠 session session_01YNBmv76sfS8gJUnyRKEqHV（不再接新工作） | 沒有人接。機廠出庫已由 #678 處理；B 方案（`claude/hsr-depot-exit-priority`）量測失敗、放棄，紀錄在 #685。決策 255（單線提早折返）**沒有**解這一項：高鐵是單向的班次（決策 133），時刻表不會回到同一站，不會用到折返 |
| 決策 306 之後，號誌開著的高鐵示範還能做的五項（作者 2026-10-21 問「是不是已經優化到極限了」；車速這條路已到頂，最快就是車的性能與彎道限速，剩下的晚點與取消多半不是速度造成的）。照這個順序：(1) **沒有閉塞時的兩個互等與追回時間**（決策 306「下一步」第 1 點：台南的進路宣告、左營咽喉與要入庫的閒置車；沒有閉塞時一天還取消 85 班，效果最大），約 1 天，改 `RouteReservation.swift`、`RunDepot.swift`、死結判斷，可能動 replay；(2) **平地五站停晚 93 分的那一班**（決策 306「下一步」第 2 點），1–2 小時，查完多半併進別項；(3) **五站停跟在慢車後面**：五站停的表定本來就快，追不回來，晚點中位數停在 9 分，要從待避的排法下手（決策 294），約 1 天，結果不確定；(4) **南港咽喉**（照地形剩的南港 08:30 取消，決策 302「下一步」第 2 點），半天到 1 天，和下一行的六家基地都改示範的機廠配置，併成一件做；(5) **晚點時壓縮停站**（真實鐵路的做法，沒試過、沒量），約半天。五項都改同一塊 GameCore、量同一個示範，平行做要互相重量，所以一個 session 照順序做，全部約 3–4 天 | 作者 2026-10-21（session_011GLH8sEjxxMsy2VEXa8szu 估計與排序） | **第 1 項做完**：決策 308（session_0125dMtwyMdz7mzoBCRNa1pn），剩下的寫在它的「下一步」。其餘排在它之後，也排在 77.1（自動派車，改同一塊派車，影響每個初學者）之後；示範預設是號誌關，這五項只改善號誌開著的組合。順序由遊戲規劃排 |
| 高鐵示範北端的機廠改成真實的配置：南港站東的 2 條盡頭線（約 8 組）加新竹的六家基地（OSM：新竹站東約 500 m、下行線同側，8 股、每股約 420 m，`tools/hsr-depots/hsr_depots.json`），取代決策 221 的「南港機廠 11 股」（台灣高鐵北端沒有機廠，決策 280） | 作者 2026-10-18（session_01KeynzCwtDyLHTUYBfKxy1c，問「建六家機廠有幫助嗎」後說「寫進HANDOFF排著」） | **排在決策 302（`claude/hsr-depot-churn`）合併之後**：原本等的南港咽喉已由決策 283 修好、真實地形已打開，決策 297 後照地形一天只取消 4 班；決策 302 正在改機廠進出的判斷，六家也動機廠進出，同時做會互相干擾量測，所以等它合併、重量一天再做。它解不了南港咽喉的卡死（白天、終點站的調度）和左營夜裡的排隊（南端），只讓北端更真實；代價是南港與新竹之間每天早晚多約 70 km 的空車，可能有新的互等，要重量一天。動 `HighSpeedDemo.swift` 的機廠配置與決策 221，GameCore 不動 |
| §15.3 的內容：觀光列車（第一步在決策 286，後續見 §7.2）、支線劇本、掛機模式、「這版新增」卡片、台灣節慶、各站到站鈴、3D 拉近傾斜與駕駛艙視角、花錢的地方＋新台幣＋分時電價＋車站容量、股票 | NEXT_PRIORITIES §15 | 排在核心玩法之後；各站到站鈴等測試者回報 |
| 台灣以外的實景地圖沒有人口、地點、分區、水域、陡坡、建物覆蓋率與真實鐵路：新車站一律 10,000 人次、住宅區（決策 262 加了 127 個城市，`Ci/` 的 53 座本來就是這樣）。要補就照 `tools/real-world-population/README.md` 的工具，換成各國的 WorldPop 與 OSM 整包檔，一個國家一份資料 | 決策 262 | 沒有人接 |
| 3D：擋住列車的建物變透明、深度閃爍、道具穿模、真的台灣車與站房 | F 台灣版＋「定案前要補」 | 3D 生活感那條線之後 |
| 參考庫 2026-10-18 新增的兩個資料夾，不是新工作，是讓排好的項目省工的素材（照 NEXT_PRIORITIES §16 的順序用，不插隊）。`Railway/taiwan-rail-reference-clean/` 是 `site_archive_clean` 的新版：(1) 高鐵票價表 `source/data/thsr_fare.json`（TDX ODFare，全部站對、票種與車廂；補上 ARCHITECTURE「沒有真實高鐵的票價表」的缺口），給高鐵示範（§16 第 4 項）或「新台幣」那輪（§16 第 5.7 項）；(2) 台鐵時刻表 10-16 版、`thsr_schedule_dense.json`、國土測繪中心的橋隧改判 `rail_structures_official.json` 與較新的 `rail-3d/physical/`（`network.json`、`level-profiles.json` 都和 `site_archive_clean` 不同），給決策 279 的後續與重跑 `tools/real-railways/`、`tools/real-timetables/`；(3) 62 款車型、附出處的編組 `rail-3d/integration/formations.js`、12 個站區模型 `rail-3d/assets/stations/`，給上一行「真的台灣車與站房」。`Railway/world-rail-reference-clean/`：12 個海外城市的路網與班表、120 款車型，可補上上面「台灣以外的實景地圖沒有真實鐵路」那一行；單城班表 26–55 MB，要像平溪線一樣只抽需要的部分，署名照各檔 `source_notes`；`nyc_schedule_dense.lite.json` 的 `source_notes` 寫成 Entur（挪威），用之前先核對 | 參考庫 `058f833`；session_01B2b7QLdd5dVnXNZLmQbcQX 盤點 | (1) 的高鐵票價表已用在高鐵示範：決策 325（session_01YEY1CSzE5zYPKVPqDAMBAy，`claude/hsr-real-fares`，存檔 69），剩下的寫在決策 325「之後」（商務車廂、新台幣那輪換掉 NT$10＝$1）。其他沒有人接；各自跟著它服務的項目做 |
| 從空地畫的複線兩條之間沒有渡線：玩家在兩站點了不同的一條就不相連（70.1 的回報）。決策 284 只讓開新路線的字說出原因與接法；根本的做法是畫複線時兩端自動加渡線，或「月台」工具在複線上一次設兩條的月台，兩個都改建造規則，預覽寫在決策 284「沒選的」 | 決策 284、285、PLAYER_FEEDBACK 70.1 | **做了**（`claude/double-track-platforms`，決策 285）：選了第二種。「月台」工具點在複線的一條上、而旁邊那條和它不相連時，同一個動作兩條都設月台（同一站），兩站點了不同的一條也相連。兩條已經相連（有渡線）時照舊只設點的那條。剩下：從空地畫複線時兩端自動加渡線（第一種）沒有做，預覽在決策 285「沒選的」；待實機確認 |
| 73.1 的「終點無法折返」只從截圖推斷是列車比月台長（決策 284 改了字）。玩家的實際配置沒有存檔：下一版請測試者用「回報問題」附存檔，確認不是別的原因（例如終點的盡頭線放不下整列車） | 決策 284、PLAYER_FEEDBACK 73.1 | 待實機確認 |
| 提早折返（決策 255）後，列車卡的「本趟」仍從沒去的那一站算（74.1 截圖的「扒子岡 13:52 發」）。決策 288 已讓它照一般停站開走、時刻往前移，但卡片與跟隨列還沒說「在龜山提早折返」（決策 255 的「下一步」）。74.1 的玩家配置沒有存檔，下一版請測試者確認不再卡在那一站 | 決策 255、288，PLAYER_FEEDBACK 74.1 | **做了**（`claude/short-turn-card`，決策 255 的第二則「後來」）：卡片與跟隨列的本趟從折返站算，多一行「在龜山提早折返」。剩下：重複的時刻表認不出折返；74.1 待實機確認 |
| NEXT_PRIORITIES §17 的乙線「現實路網」：~~真實車站當建議站點~~（決策 295，`claude/real-station-suggestions`）→ ~~R1 轉乘站~~（決策 298，`claude/r1-transfer-stations`，存檔 64）→ ~~R2 電腦的車照已打包的時刻表在 2D 地圖上跑（只畫）~~（決策 304，`claude/r2-real-trains`）。甲線（M0 之後的 M1–M3、確認路線卡、空窗快轉）由做 M0 的 session 接著做 | 75.1 玩家建議（PLAYER_FEEDBACK 75.1 #1）、競品研究 #832；排序 2026-10-20 | 建議站點：決策 295 已合併（圖釘的大小與好不好點待實機）。R1：決策 298 做完（session_01TePLuBqSCAQxMhhJBTJ8Cq）；待實機：車站卡那一行、新遊戲的開關；決策 298「下一步」列了 R2 要接的地方。R2：決策 304 做完（session_0193ujbBhjzFo37QWceGdzcX）：捷運與輕軌逐班、高鐵一天的班次、台鐵照班距；車站卡列下一班；設定「真實列車」可關。待實機：膠囊的大小與淡度（`RealTrainTraffic.look`）、畫 157 列的時間、iPad 整張地圖。加減速：決策 304 的「後來」（2026-10-22，`claude/real-train-accel`）站間照網站的 `buildProfile` 加速出站、減速進站，高鐵有惰行，解不出時用 Mini Tokyo 3D 的退路；待實機看樣子。剩下的在決策 304「下一步」：3D 的真實列車、台鐵逐班時刻表（要打包參考庫的 2026-10-16 時刻表）、路線名與站名的英文；R3 照 §19 的順序 |
| 乙線的資料與時段研究（`docs/research/RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md`）：(1) 台中捷運（data.gov.tw 175718，2025 年只有 7 個月、只有出站）與桃園機捷（164957，雲端容器連不上，要作者在台灣下載 2025 年 12 個 CSV）有各站運量，淡海、安坑、三鶯、高雄輕軌、林鐵沒有；(2) 遊戲的一天時段已經接近北捷，差的是潮汐（住宅站早上進站真實 40–46%、遊戲最多 28%），建議三步：量尺報告 → 潮汐開關（GameCore，升一次存檔、量平衡，排在 #851 之後）→ 實景地圖用內政部電信信令的日夜人口（取代 geo-scene 第 4 項）；(3) 北捷路線色維持 App 的值 | 作者問「台中桃園 輕軌 三鶯有網址嗎」「台北捷運有分時段…日間夜間模型」；遊戲規劃派工 2026-10-20 | 研究做完。潮汐第 1 步（量尺）做了（`claude/tide-measure`，研究 §2.5），1.5 步（選資料：電信信令最好，OSM 只當細部）也做了（`claude/tide-data-choice`，研究 §2.6）；第 2 步也做了（決策 319，存檔 67），第 3 步沒有人接，見 §7.2「潮汐第 2 步」那一列。**運量（session_01RdsWZvY7RjZeZbiNvn8XP4，`claude/ridership-tmrt-tymc`，PR #869）**：台中捷運（2025 年 7 個月出站）、新北捷運的淡海與安坑輕軌、環狀線（新北捷運網站的每日各站進出站，2025-10 到 2026-09；`trtc_ridership.json` 的環狀線只有台北捷運閘門記到的部分，改用新北的）都已補。桃園機捷（桃捷公司網站每月「各站旅運量統計」PDF，2025 年 12 個月，（進＋出）÷ 2；開放資料 164957 雲端連不上）也已補。**還剩**：(a) 三鶯線現在是通車後 2026-07 到 09 的 3 個月（`--partial`，作者 2026-10-20 要的），2027-07 以後用 `build_ntmc_ridership.py --first 2026-07` 換成一整年；(b) 台中 2027 年初看 2026 是否 12 個月齊了再換；(c) 高雄環狀輕軌沒有各站運量（高雄捷運公司每月的 PDF 只有全線每天的筆數），它的站已改照輕軌的 1 點；高雄捷運公司若哪天公布分站的，再接進 `RealRidership`；(d) 林鐵沒有各站運量：data.gov.tw 林業及自然保育署阿里山林業鐵路及文化資產管理處的 13 個資料集（車站、路線、時刻表、票價等，2026-10-20 查）都沒有運量，afrch.forest.gov.tw 也沒有統計頁；要的話只能由作者照政府資訊公開法向該處申請，拿到前林鐵的站照後備 |
| 真實運量（決策 298：台鐵、高鐵、台北捷運、高雄捷運，#869 加的台中捷運、桃園機捷、新北捷運的淡海與安坑輕軌、環狀線、三鶯線）每年重跑：每年第一季前一年整年的資料出來後，照 `tools/real-ridership/README.md` 重跑（到時平鎮會有數字，廣慈/奉天宮現在是 2026-09 一個月（`--later`）；它 2026-08-30 才通車，重跑 2026 年時除以 365 天會只剩約三分之一，要先讓工具對年中通車的站只除以營運的天數，或繼續用 `--later` 的整月；台中看 2026 年是否 12 個月齊了；新北捷運用最近 12 個 `.ods` 月份，三鶯線現在只有 3 個月，2027-07 起有一年，到時換掉）。**高雄捷運要作者在台灣下載**：data.kcg.gov.tw 擋國外連線，雲端容器抓不到，請作者從 data.gov.tw [159641](https://data.gov.tw/dataset/159641)（入站）與 [159640](https://data.gov.tw/dataset/159640)（出站）下載兩個 CSV、附在對話裡，工具記下 SHA-256 與下載日期，原始 CSV 不進 repository | 決策 298 的「下一步」2、`tools/real-ridership/README.md` | 下一次是 2027 年第一季；台鐵、高鐵、台北捷運、台中捷運、桃園機捷（公司網站的 PDF）、新北捷運雲端自己抓得到 |
| 參考庫 2026-10-20 新增的 `Railway/geo-scene-reference-clean/`（台灣地理資料包）：遊戲的鐵路、車站、地形、居民人口比它準，不換。要融合的：(1) 新車站命名的地名加內政部的聚落（800 m 內有名字的居民 89.0% → 95.6%）、旗津區用官方外框補（`tools/place-names/`）；(2) 3D 的廟放到真實的廟址（`religion/temples.pmtiles`，19,201 座）；(3) 白天人口的比例，和 R1 一起量（先查出處，原包寫「模擬」）；(4) 21 個 `approx` 景點逐個核對、節慶與景點新種類用它的百大宗教活動與古蹟（§16 第 5.5 項）；(5) R2 移植它的 `RailEngine`／`BusEngine`。Ookla 不能商用，不用。之後不只鐵路的「線」（公車接駁 → 離島渡輪 → 航空）的參考也在研究 §6，排在 §17 甲、乙兩線之後 | `docs/research/GEO_SCENE_REFERENCE_2026-10-20.md`、NEXT_PRIORITIES §18；參考庫 `b3af6d8` | (1) 修正 lane、(2) 3D 那條線，都沒有人接；(3)–(5) 跟著它服務的項目做 |
| 建造時的潛力圖（決策 311）只在 Linux 量過 debug 的時間（台北一個畫面第一次約 0.1–0.16 秒），App 沒在實機看過：iPhone 直拿時圖例（潛力／涵蓋、時段兩列切換）高不高、第一次畫的停頓、台北市中心是否整片同一色 | 決策 311 的「下一步」，session_01XcsvN9dp6TVNhLU2TY4sJD | 下一次 TestFlight 時看；要改門檻或把計算移到背景，是 GamePresentation／App 的小 PR |
| 收購真實支線的後續（決策 315 第 2 步之後）：(1) 六家線、沙崙線（雙線電化，要兩條平行的正線與兩端的渡線，班次已能擷取）；(2) `dr1000` 車種（`PERF_DR1000`，動 `TrainType`、車種表與 3D 車）；(3) 收購時替玩家買下線經過的地塊（地圖擴張開著時，現在是拒絕並寫出擋住的圖塊）；(4) 第二批開放輕軌：淡海、安坑、高雄環狀（各站時刻排成 `LineRun`、輕軌車種；重運量捷運不開放） | 決策 315 的「後來」「之後」「量到的」 | 第 2 步（`claude/acquire-real-branch`，存檔 66）做完四條線。**(1) 做了**（`claude/acquire-double-track`，決策 323，存檔不動；雙線但沒有渡線，竹中與內灣線共用的連接沒試過）；(1) 還剩：兩線的年報（`AcquisitionReportTests`）、竹中與內灣線一起收購時的互等、渡線（要另一套鋪法）。(2)–(4) 沒有人接，順序由遊戲規劃排 |
| ~~收購的線上，低矮的長橋跨寬河床（內灣線竹東—橫山 499 m）被做成路堤~~，排除車站後的橋與高架比例只有 60%（6/10，`testALineBoughtFollowsTheRealStructures`） | 決策 315 的「量到的」、遊戲規劃 2026-10-21 | 做完（決策 279「後來：低矮的長橋」，`claude/low-bridges`，session_01PK2gs3bPYXPFbbJkwsDuUP）：原因不是 10 m 太高，是橋和引道的地面範圍一起被放掉；改成衝突時先放掉地面的，10／10，示範都不退。沒有剩下的 |
| 收購應該買到看得見的東西：第 1 天的人次收購與自己蓋一樣（兩邊都從轉乘點拿到常客，決策 298），價格裡的「沿線的常客」在遊戲裡沒有對應。可能的做法：買下既有的班次與車站運量、或免施工天數，之後再設計 | 決策 315 的「量到的」（CONCERNS）、遊戲規劃 2026-10-21 | 沒有人接 |
| 車站紀念章的後續：新章在地圖上那一站跳出來、目標面板的成就連結也能開護照、車站卡標這一站的章、依縣市分組 | 決策 348「沒有做」 | 做完（決策 353，`claude/station-stamps`，session_01Mj4uPjTo2pmTRVsXob6Ju9）：車站的標記放在車站面板；還沒做的（點車站時的小卡、縣市點進去）寫在決策 353「沒有做」 |
| 刪掉快車停的站被拒絕時，字沒有說要先刪掉哪個停站模式 | 決策 291 的「下一步」、PLAYER_FEEDBACK 75.1 #2 | 沒有人接（GamePresentation 的小 PR） |
| 自動派車時讓玩家調兩列車的發車：兩端對開、或晚前一班幾分鐘（77.1 #1）。現在「加開一列車」把班距設成「來回 ÷ 列車數」，從終點發的車和第一站共用一個派車間隔（`lastDispatch`，決策 23、172、264），所以做不到。要動 GameCore 的派車（每端各自的間隔或發車的錯開分鐘），升存檔 | PLAYER_FEEDBACK 77.1 #1；遊戲規劃 2026-10-20 | **已合併**：決策 309（#890，main `cbc7430`，存檔 65）。還沒做的寫在決策 309 的「下一步」（實機確認路線卡的選單、要不要加 UI 測試、停站模式的每個服務、單線開行車控制時的量測）。原本的排法：五方：玩家，初學者第二列車就卡住，影響大；鐵道迷，單線兩列車兩端對開、在中間站交會，最像真的（平溪、集集）；開發，GameCore＋存檔，和 302 同檔，排在它後面；美術，路線卡多一個選項；音樂，無 |
| ~~沿真實捷運、輕軌描線沒有真實高度~~（決策 279「後來」，`claude/metro-real-heights`）：`tools/real-railways/extract_structures.py` 的 `SYSTEMS` 只有台鐵、高鐵、林鐵，捷運的地下段鋪在地面。做法：把捷運與輕軌加進去（同一份 `level-profiles.json` 的 OSM bridge／tunnel），重產 `rail_structures.json`；描線照舊預設照真實高度（結構「自動」），玩家改「地面」就不套；建造費預覽寫隧道佔多少（地下貴）。五方：玩家要像真的、可手動省錢；鐵道迷：北捷多在地下；開發：只動資料工具；美術：地下段不再壓在街上；音樂：無 | 作者 2026-10-21，PLAYER_FEEDBACK 78.1 #7 | 資料與描線做好了（session_01PK2gs3bPYXPFbbJkwsDuUP）：七個系統，整條描四個門檻都過；一站一站描時端點照真實高度，394 個站剩 14 個在地面。**還剩**（決策 279「後來」第 4 點）：(a) 那 14 個站（六張犁、環北等：地形太粗互相衝突、環北坡度不夠），沒有人接；(b) 同系統上下重疊的兩條線（工具要帶 OSM 的 `ref`），沒有人接；(c) 建造費預覽寫隧道佔多少，沒有人接 |
| ~~量 OSM 軌道離官方多遠~~（`claude/osm-offset-measure`，`docs/research/OSM_OFFSET_2026-10-21.md`）。OSM 軌道和 Apple 地圖的偏移：投影沒有錯（兩邊都是 Web Mercator、WGS-84，台灣沒有 GCJ-02），是兩份資料本身不同。不能拿 Apple 地圖量偏移（授權不准取出它的資料）。做法：先寫工具量 OSM 軌道與國土測繪中心「臺灣鐵路」（data.gov.tw 73220，決策 279 用過）的距離分布；OSM 常偏 10 m 以上就把那些段換成官方幾何，大多在 2–3 m 內就改做「底圖對齊微調」（玩家拖底圖，存在存檔、只是畫面位移）。現在要完全對齊可用「OpenStreetMap」地圖樣式 | 作者 2026-10-21，PLAYER_FEEDBACK 78.1 #8（作者「都可以」） | 量測做好了（session_01PK2gs3bPYXPFbbJkwsDuUP，`tools/real-railways/measure_osm_offset.py`）：1,319 km 中位數 2.2 m、90% 在 6.5 m 內、超過 10 m 的 3.8%，每條線的平均位移都在 3 m 內（板南線東段 6 m，地下兩軌的畫法），所以照這一列的做法改做底圖對齊微調。**還剩**：(a) 底圖對齊微調本身（研究 §6：建議照實景地點各記一個位移，存檔加一個欄位、要取決策號），沒有人接；(b) 超過 10 m 的 72 段、36.7 km 要看衛星影像確認哪一邊對（研究 §4），沒有人接；(c) 高鐵沒量：「高速鐵路」（73221）的 tgos.tw 台灣以外 403，要作者在台灣下載 `HSRAIL_*.zip` 附在對話裡 |
| ~~iPad 的 `RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 在 main 上就紅~~ | #897 的 session 2026-10-21 對照出來 | **修了**（測試，`claude/ipad-uitests-red`，session_01XZM7WBK1v1RdHJdynRfngs）：iPad 橫拿時地圖看得到更多台北，月台的站名變成「Taipei」，取真實長度 16 節 320 m（`realPlatformCars`），比 254 m、爬 17‰ 的路段長，App 照規則拒絕。測試改成用月台長度的 stepper 調回 4 節（iPhone 橫拿大字要先捲到它） |
| ~~iPad 的 `MapLockUITests`「The lock opens the tile's card」在 main 上就紅~~ | #897 的 session 2026-10-21 對照出來 | **修了**（App，`claude/ipad-uitests-red`）：iPad 上鎖頭圓形的中間一列（圓心 y ± 0.3 點、整個寬度）點下去落到地圖，離圓心 2 點就開得了卡（only_testing run 39826506139 逐點量的；iPhone 每一點都開）。鎖頭的觸控範圍從 `Circle()` 改成 44 點的方形。其他地圖標記也查了、**修了**（`claude/map-marks-tap-rect`，`MapMarkTapUITests`，full lane）：委託案的旗子（`MapRequestMarks`，`Circle()`）一樣中間點不到，只在 iPad 紅（only_testing run 39841822269），改成 44 點的方形；景點星星（`MapAttractionMarks`）與提醒泡泡（`MapAlertBubbles`）是 `Capsule()`，iPad 點中間都點得到，不改。**還沒查**：3D 地圖的指北針 `map3D.compass`（`Map3DPreviewScreen`，`Circle()`，要先轉動地圖才出現）；工具列與卡片裡的膠囊（擴建地圖鈕、教學的膠囊、路線標籤）不在地圖標記上，擴建地圖鈕在 `MapLockUITests` 的 iPad run 點得到 |
| 簡單規則下，線的第一站有 2 股以上時，後到的列車整天等不到月台。重現：簡單規則（決策 258，沒有閉塞區間）、一條有班次（決策 133）的線，第一站 3 股（三貂嶺：正線＋兩條待避線），3 列車；第 1 天清晨，一列照班次在第一站過夜、停在別的列車路線所指的那股，另一列要開進第一站時，它路線指的那股有車，`alternativeRoute` 找到的空股被 `forbids` 擋下，因為線的計畫（`plannedDirections`）從第一站的每一股出發，每股都算有列車要反方向走；終點站的豁免（決策 278 的 `terminusTraversals`）只在有閉塞區間時才有。結果：那一列與後面的列車一直等，不算死結、沒有警告，第 30 天起 0 人次（平溪、集集、內灣三條收購的線都是）。玩家自己蓋、第一站多股、班次讓兩列同時停在第一站的線也會遇到。決策 315 用站序反過來（分歧站排最後）加每段指定股道繞開，GameCore 沒動 | 收購 session_017RbiiqGJTsLWDSz9q4Dukd 2026-10-21（決策 315 的「後來」）、遊戲規劃 | **修了**：決策 344（`claude/first-stop-platforms`）。往線的第一站的列車，可以逆著「只有那一股出發的列車才走」的那段進站，簡單規則也一樣；`long-leg-traffic.json` 重錄。決策 315 的站序沒有改回來，要改回來另量（決策 344「下一步」） |
| 審查 E 的 E1：App Review 的機器也是沙盒收據，送審的版本在設定的「版本」列連點 5 下，開得出演示模式與列車包的開關（審查準則 2.3.1 的隱藏功能）。**送審 App Store 前要做**：Release 版的開關改用只在 TestFlight workflow 加的編譯旗標，不再靠收據判斷。TestFlight 不受影響 | 審查 E（`archive/PR1019_1030_REVIEW_HANDOFF.md` 第三節），規劃 2026-10-22 決定第 82 版後先不做 | 沒有人接；碰 `testflight.yml` 的旗標要作者同意（CLAUDE.md）。作者 2026-10-22：「還沒有要上 app store 先幫我記著 我要上再跟我說」：作者說要上 App Store 時，規劃先把這一項提給作者 |
| 收購六家線（雙線，要另一套鋪法）不在收購第 2 步 | 決策 315 | **做了**：`claude/acquire-double-track`（六家線、沙崙線，決策 315「後來：雙線的六家線、沙崙線」、決策 323） |
| 演示模式「鋪好這一帶的真實路線」（決策 351 續篇）的後續：(a) 實機量一次鋪設要多久（Linux release 8 km 台北 12 條線：原本 11.8 秒，決策 351「後來」改快到 7.3 秒；196 秒是 debug）、按鈕在 iPhone／iPad 的位置；(b) 決策 351 續篇「缺口」列的：不用真實時刻表、只有 10 個系統有資料、林鐵機廠沒鋪、台北高鐵台鐵並行沒測、文湖線 35 m 彎道略過、中和新蘆共用段鋪兩次 | 決策 351 續篇，session_01Q6ucfu4uY1YiX1buRCZzFr（壓縮兩次後停） | (a) 待實機；(b) 沒有人接，只動 GamePresentation |

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

PR #873–#910 那一輪的 A 組（2026-10-21，session_01SvQ285hMiSeRsER1EXzfT9，[PR873_910_REVIEW_HANDOFF.md](archive/PR873_910_REVIEW_HANDOFF.md)）：11 個發現，修了 6 個。兩個 P1 是存檔讀不回：交錯發車的路線改成環線、買下的線拆站拆到沒了。另外修了 3D 快取重用了不含新焦點的場景、半夜的班距、色帶重疊、一個斷掉的連結。延後的 5 個在它第三節：
- **A6**（P2，GameCore）：**已修**（2026-10-22，#966）。沒修到的一種：班次晚派車時，列車自己時刻表的第一段已經被縮短，分不出是晚點；要讓列車記住班次的時刻（改存檔格式），交給下一個改決策 306 或 133 的 session，寫在決策 306 的「後來」。
- **A7**（P2，App）：**已修**（2026-10-22，#970）：實景地圖開始蓋時「新遊戲」頁一起關。Simulator 與實機還沒確認。
- A8（已修，#966）；A10（暫停中每個指令都重算快轉）已修：試跑移到背景（決策 330 的「後來」，`claude/night-skip-offer-off-main`）；A11（SceneKit 的建築與地點沒有用到）交 3D session。

PR #911–#944 那一輪（2026-10-21，審查 B，session_017M3NJsMXLafGDsSvidGhD6）：[PR911_944_REVIEW_HANDOFF.md](archive/PR911_944_REVIEW_HANDOFF.md)。修了兩個 P2：一日週遊券卡片建議的價格賣不出去（#934）、平交道路面上立著電桿（#938）。沒修的五個 P3 在它第四節，每項寫了交給誰：高鐵票價表沒驗站 ID、潮汐的車站示意圖沒看週末、自由模式關潮汐留著舊 `homeShare`、公車模型縮放沒防 NaN 與 3D 場景白白重建、站房可能壓到種子街道。
- 2026-10-22：B3 已修（#966）；B4、B6 已修，B5 定案為自由模式不動需求（決策 319「後來」）（#970）；B7 交 3D session。

PR #945–#961 那一輪（2026-10-22，審查 C，session_01VVzExSvZcTej5eCqxdUEpY）：[PR945_961_REVIEW_HANDOFF.md](archive/PR945_961_REVIEW_HANDOFF.md)。12 個發現，修了 8 個：#955 之前存下的環線交錯發車、拆站留下的收購資產讀不回（#974）；full lane 重跑轉綠不報、重跑舊的報過時消息；素材交接叫 session 疊在未合併的 PR 上（#942、#949、#957 的根因）。沒修的 4 個 P3 在它第四節：公車可能重疊、公車三角形超預算、商用套件 README 的零件名、還沒用到的通勤車模型；決策 332 被 #963 重用的事已由遊戲規劃改成 335。

PR #962–#1018 那一輪（2026-10-22，審查 D，session_01TCwdHtJTq9REwDrCSHzR11）：[PR962_1018_REVIEW_HANDOFF.md](archive/PR962_1018_REVIEW_HANDOFF.md)。36 個程式 PR、40 點；GameCore 的四個（#966、#974、#986、#995）沒有問題。5 個發現，修了 2 個（#1023）：公園場景上蓋城市地塊、鏡頭一動大公園就換場景。沒修的 3 個 P3 在它第四節，交 3D 城市線：阿里山林鐵在 3D 畫成通勤車、1× 同一秒內的掉頭晚一秒才看到、真實列車 1× 走半秒停半秒。#1005 的「有環就不報待避」查過不是 bug（`parallelTracks` 本來就把環算成 2 股）。

PR #1019–#1030 那一輪（2026-10-22，發版前小審查，TestFlight 第 82 版前）：[PR1019_1030_REVIEW_HANDOFF.md](archive/PR1019_1030_REVIEW_HANDOFF.md)。8 個程式 PR、9 點，沒有 P1、P2。#1019 重錄的 `long-leg-traffic.json` 逐值說明合理；演示模式在 App Store 版完全看不到。兩個 P3 沒修，在它第三節：E1 審查員的機器也是沙盒收據，連點 5 下開得出演示模式與列車包的開關，送審 App Store 前改用編譯旗標；E2 一鍵鋪路線的途中還能按播放與復原，一次復原退不完。

**大世界的效能**（決策 328，`claude/perf-2d-sim-speed`，2026-10-21；玩家回報 78.1、79.1：三十幾站後 2D 約 5 FPS、加速跑不到設定）。已修：夜間快轉試跑移出主執行緒、乘客排隊二分搜尋、上車排序、實景支線可購清單記住。還沒做、還沒人接：
- **2D 5 FPS 的主因**：Linux 量不到 SwiftUI 繪圖。要在實機打開「設定 → 地圖 → 幀數」，點開看哪一層（地面、軌道、列車、站名、天氣、推進後）每秒花最多。候選：`session.world` 每個 tick 都讓讀它的 view 重算；軌道畫布在交通覆蓋變了就整張重畫；站名畫布在候車數變了就重畫；夜色的 `.blendMode(.multiply)` 與站名的 `.colorMultiply`。量到哪層再對症改（拆出不常變的圖層、`drawingGroup`、降低重畫頻率）。
- **1200× 在大世界的 GameCore**：第 730 天的測試存檔一個 tick 改之前約 7～9 ms、改之後約 4.5 ms（Linux release），隨等車人數變慢（放人、上車、`makeNetworkPassengerPlan`）。再快要把乘客佇列照路線分組，會改存檔格式。報告：`LONG_GAME_REPORT=730 swift test -c release -Xswiftc -enable-testing --filter LongGameCostReportTests`。
- **Simulator 上的效能 UI 測試**沒有做：CI 的 Simulator 數字和實機差很多，先靠幀數顯示。

**82.1 的卡頓**（決策 363，`claude/perf-actions-82-1`，session_011kVCxFJEULkYyGGU7emgsx，2026-10-23；分三個 PR 的第一個，它壓縮 1 次後停在這裡）。已修：每次編輯重算整張地的車站涵蓋率、夜裡切速度與離開建設工具在主執行緒上試跑一整晚。報告：`ACTION_COST_REPORT=30 swift test -c release -Xswiftc -enable-testing --filter ActionCostReportTests/testWhatTheThreeActionsCost`（44 站、4 條線；`ACTION_COST_PROFILE=1` 跑給 callgrind 用的 50 次編輯）。還沒做、還沒人接：
- **(b) §22.2 第 25a 名**：高倍速每次換世界整個畫面重算（見下面「高倍速少換幾次世界」），要作者的幀數讀數。
- **(c) §22.2 第 10h 名，2D 每幀**：`MapCanvas` 的 `==` 比較 `traffic` 與閉塞，所以交通覆蓋一變整張軌道畫布重畫；可把閉塞與等候畫進自己的畫布。`MapLabelCanvas` 在候車數變了就重畫站名。夜色的 multiply 混色。不操作時降 2D 幀率上限。先請作者在大存檔開「設定 → 地圖 → 幀數」，記下哪一層最慢。
- **買一格地圖約 55 ms**（Linux release）：讀那一格的土地，`LandImport` 約 23 ms、GameCore `expandLand` 約 22 ms。可在玩家點選地塊時就在背景讀好（照地塊、範圍與資料組記住），按「買」時只套用。
- 編輯後第一次讀 `trafficOverlay`、`situationAlerts` 各約 1.3 ms，沒動。
- **遊戲規劃另外交代、給 (b)(c) 的人**（2026-10-23）：同一類還有 78.1 iPhone 17 Pro「手機發熱當機」、79.1 iPhone 17 Pro「6000 倍卡住」（79.1 還沒有決策 330）。(b) 先在 origin/main 量 6000× 的現況。發熱：看不操作、高倍速時 2D 是否一直以 120 Hz 重畫，可在 GamePresentation 定一個幀率上限規則（例如沒有手勢時 60 或 30），App 只接線，值與五方寫進新決策。TestFlight 沒有當機紀錄，分不出 watchdog 還是記憶體：入門 iPad（A16）記憶體較少，順便量大世界、高倍速時的記憶體峰值（批次推進時是否一次複製多份世界）。

**高倍速的主執行緒**（決策 330，`claude/fast-forward-main-thread`，2026-10-22；作者 iPad 宜蘭線 6000×：最長一幀 114 ms、推進後 max 44.8 ms）。已修：整點的站長建議（約 40 ms，幾乎全在 `firstLineWithoutPlaceToPass()`）移到 `LoopTick.work()`；幀數讀數把「推進後」拆成九段、多一行「清理」（放掉舊世界）、第一行多「其他」。報告：`TICK_REPORT_YILAN=432 swift test -c release -Xswiftc -enable-testing --filter TickCostReportTests/testWhatTheStepAfterATickCostsOnTheYilanLine`。還沒做、還沒人接：
- **請作者量**：宜蘭線 6000×，開「設定 → 地圖 → 幀數」，點開讀數，記下幾秒內的「最長一幀 · 其他」與「推進後」的 max。推進後的 max 應該從約 45 ms 降到幾 ms。
- **高倍速時畫面整個重算**（§22.2 25a，決策 367，`claude/perf-fast-forward-views`，2026-10-23）：作者 83.1 高鐵 600× 的「其他」200 ms 是 SwiftUI 重建畫面。已修：畫面框架（`ContentView`）不再讀 `session.world`（改讀 `session.screenFacts`），推進時不再清空已經空的 Undo／Redo 紀錄。Simulator 修後第一次等不到地圖，是這個示範在 Debug 版本來就慢、UI 查詢快照逾時，重跑一次就過（run 39895315471，細節在決策 367）；Debug Simulator 的「其他」前後看不出明確的差。還沒做：**84.1 已重量**（作者實機，高鐵示範 6000×：3 fps、軌道 329 ms/s ×2、其他 360 ms），接續是決策 377（下一條）；那時的下一步是讓 `MapView` 的子 view 只讀自己要的值（`MapAlertBubbles`、`MapAttractionMarks`、`HUDView` 的 `ViewThatFits` 四份、站長角落的 `stationMasterRefreshKey`），再不夠才在 ≥1000× 時每次 `advance(by:)` 多走幾個 tick（守住決策 143、248、195）。量法：`FastForwardFrameUITests`（`ios-build.yml` 的 `only_testing`）、`FAST_FORWARD_READS=50 swift test -c release -Xswiftc -enable-testing --filter FastForwardReadsReportTests`。
- **已修（`claude/no-place-to-pass`，決策 264 的「之後的修正」2026-10-22）：雙線的宜蘭線，站長說「沒有地方交會」**：原因是兩端月台前的轉轍器讓整段算成 1 股。以下是原本的紀錄。重現：宜蘭線示範（`TRADemo.make`，測試裡是 `TRADemoTests.opened`），開局後 6000×（`.fast`）跑 60 個 tick；`StationMasterAdvice(world:)` 回 `.noPlaceToPass(line: LineID(rawValue: 1), name: "TRA Local")`，也就是新聞裡站長說「TRA Local 沒有地方交會」；直接呼叫 `world.firstLineWithoutPlaceToPass()`（`AutoService.swift`，決策 264）回同一條線。宜蘭線是雙線，不該這樣說；可能是兩端的單線（留置線、折返段）被算進去。這個函式每遊戲小時約 38 ms（Linux release），現在在背景（決策 330），修的時候可順便看它要不要用指令版本記住。
- **地圖左半邊沒有地形陰影**（作者同一張截圖，畫面約 55% 處一條垂直分界）：`taiwan_terrain.pmtiles` 在宜蘭附近 z8–z10 的圖磚都在、相鄰邊緣高度連續，z9、z10 的圖磚分界在東經 121.64°，不是缺磚。下一步：請作者下次截圖時附上分界線的經度或地名（或在同一處打開 3D、拉近再截一張）；若正好是 121.64°，查 MapLibre 的 raster-dem 在那一層（`BaseMapStyle.hillshade`、`tileSize` 512）沒畫左邊那張的原因（記憶體、圖磚太大 291 KB、或 hillshade 需要鄰磚才準備）；若不是，看 2D 的地面畫布有沒有蓋住。
- **2D 大世界掉幀**（§22.2 10h，決策 371，`claude/perf-2d-map-frame`，2026-10-23 session_015LxxfmrvhBFnxLie4gd2Bs 從 session_018DNqCBcwA7znTnrzbUpTVF 的 `c075037` 接手完成）：軌道畫布拆成「軌道與路線」和「交通、建物、車站」，站名畫布拆成名字、候車數、標記三張，列車滑行限 30 fps（跟車 60）。Linux release 600×：軌道與站名每秒重畫從 9.6、10 次降到 0。還沒做：**84.1 已重量**（作者實機，高鐵示範 6000×：3 fps、軌道 329 ms/s ×2、其他 360 ms），接續是決策 377（下一條）；交通那張若還重，下一步是 `TrafficOverlay` 帶版本號、只比版本（現在逐項比 1.2 ms／tick）。細節在決策 371。拋棄用的 `claude/perf-2d-map-frame-baseline` 可以刪（proxy 擋刪除）。
- **2D 高鐵 6000× 3 fps**（TestFlight 84.1，決策 377，`claude/map-track-redraw-cost`，2026-10-23 session_01UxzgXQsTohBZKf3mrBWq27）：幀數表的「軌道」拆成「軌道與路線」「交通與車站」兩行；軌道、路線、區間車流的折線照螢幕 0.25 點簡化（整條高鐵 177 萬點 → 5,578 點，Linux 挑點與投影 180 → 76 ms）；地圖泡泡、景點標記、站長、狀態列只在顯示的東西變了才重算。Linux 找不到每秒兩次軌道重畫是誰叫的（世界一次都沒有叫）；Simulator 上是「軌道與路線」那一張、只在開地圖後 15–25 秒，所以幀數表的那一行後面加了重畫的原因（例「畫面移動 ×2」）。**請作者在高鐵示範 6000×（站名、候車數、票價與紀念章打開）開「設定 → 地圖 → 幀數」重量**，記下：fps、最長一幀與其中「其他」、「軌道與路線」與「交通與車站」各幾 ms/s、×幾、最長，以及「軌道與路線」後面寫的原因；下一步在決策 377「還沒做的」。**推進 106.6 ms/s（§22.2 第 41 名）沒有動**，依派工。
- **2D 高鐵 6000× 主執行緒**（TestFlight 85.1 作者實機：26–41 fps，最長一幀 173–200 ms 幾乎全是「其他」，推進後 · 音效 max 29 ms、收入 max 22 ms；決策 379，`claude/fast-forward-sound-income-other`，2026-10-23 session_019RS5qZNMdEtyEF7MkVyR4c）：「其他」最大的一塊是地圖每 tick 在主執行緒算列車滑行（Simulator「地圖跟著推進」每次 1.5–2.2 秒，Linux debug 504 ms），改在背景的 tick 裡算、地圖只補時間；音效與收入的時間判斷是 `AVAudioPlayer.play()`，提示音改在 App 自己的佇列播放（聲音、音量、間隔不變），幀數表多「播放音效」一行；幀數表把「其他」拆開：多「畫面更新」（run loop 等待前，SwiftUI 與 Core Animation）與底下的地圖、地圖列車滑行、地圖車流、地圖跟著推進、畫面框架、狀態列、站長，第一行寫「最長一幀 · 其他（畫面更新）」（#1108 已合併；改後的 Simulator 量測與 Linux release 讀數在決策 379「後來」，拆開後那三行在 Simulator 沒量到）。**請作者用同一個高鐵示範 6000× 重量**（步驟在決策 379 第 3 段），照「畫面更新」的分項修；下一步寫在決策 379「還沒做的」。推進（背景）是另一個 session 的；它每 tick 多算了滑行（原本在主執行緒），若推進成了瓶頸，照決策 379 第 4 段的下一步。
- **開新路線的比較抽屜蓋住 ✓**（TestFlight 85.1，決策 384，`claude/line-draft-drawer-checkmark`，2026-10-23 session_013WiLkQHTAxZL85F5PYxJuL）：抽屜讓開細節卡與右下角那一組；手機橫放時抽屜放進 ✓ 膠囊裡、在說明左邊，展開長條也不蓋 ✓。**還沒驗證**：實機上膠囊裡的抽屜好不好看、300 寬的長條讀不讀得清楚（決策 384）。

PR #755–#784 那一輪（72.1 那一天）的審查：修了 6 項（路線卡需求燈只數這條線、座位圖換行、關卡「繼續玩」會繼續、3D 場景快取分局、長按的診斷 trace、決策 266 的文字），延後的 10 項（`main` 在 abb306a 的 full lane 紅、`testHoldingAStationTracesItsBusiestTrips` 的根因、整平時的轉乘乘客、72.1 沒有自己的綠 full lane 等）連同原因與建議做法，寫在 `docs/archive/PR755_784_REVIEW_HANDOFF.md` 第四節。

第 5 關的複線（決策 378，session_01USKsgntpPbW3M49z6oSHen，目標 86.1）：**已修**。最長那段被拒絕是第二條軌道的控制點平移在急彎中間只離 3.81 公尺，改成分段鋪；修好後那段要的錢比第 5 關的現金多，引導改指 S1 旁沒有列車的那段，一次蓋好。預覽慢在找渡線時白切長軌道，GameCore 加一個不改世界的切開查詢先問，Linux release 從 175–744 ms 降到 40–95 ms。剩下：實機 Release 讀數；要再快得改 GameCore 的 fouling 增量或把預覽移出主執行緒（決策 378「下一步」）。

### 7.2 遊戲功能的後續（決策與研究裡寫了「之後」的）

**接手**：遊戲規劃排序後開 session。核心玩法（決策 254）做完以前都不開，除非下表另外寫了。
**方向**：照 NEXT_PRIORITIES §14 的權重排；開工時把這一列搬到第 2 節。

| 項目 | 出處 | 方向 |
| --- | --- | --- |
| 空白地圖「一鍵全開」 | 決策 200 第 6 點 | 併進核心玩法第 4 個 PR 之後的沙盒選項（關卡解鎖後才出現） |
| 颱風一年 1.5 個（氣象署平均 3.6 個），「留給作者決定」 | 決策 208 | **遊戲規劃決定：維持 1.5**。玩家：簡單規則是預設，颱風太頻繁會打斷剛學會的玩家；開發：不用動 golden；美術：無；音樂：無。寫實規則之後可以考慮照 3.6 |
| 劇本節慶（天燈節等）跟著農曆移動（要改存檔） | 決策 211 | 併進 §15.3「台灣節慶」那一項一起做 |
| 票價需求提示、借錢前試算、課程裡未解鎖車型的後續（§22.2 第 18 名做完，session_01QTjYzbHDE2QFpRux5BQSsW，`claude/adoring-fermat-lcewix`） | 決策 374「下一步」 | 都是可做可不做的小事：(1) iPhone 橫拿時票價段落多兩行、貸款段落多三行，TestFlight 看會不會太擠（UNVERIFIED，沒有 UI 測試）；(2) 觀光列車第 9 關才開，若玩家想早點用就把 `Lesson.number(unlocking:)` 的 9 提前；(3) 分期還款要動 GameCore 與存檔（決策 67 的貸款沒有期限），沒有排 |
| 彎道限速沒做的：道岔側向限速、節點折角、坡道影響速度、授權終點前照煞車曲線減速、擺式列車過彎加速、交會停站改用 RunCurve、出發時車尾在彎道內、跨呼叫的快取 | 決策 217 第 10 點 | 寫實規則的加深，排在核心玩法之後；簡單規則不受影響 |
| 長按路線看旅程（用車上與候車的乘客）、鏡頭自動縮放、弧線端點記號 | 決策 220 | 併進「回饋第二批」（第 3 節航空手感那一列） |
| 景點新種類：廟宇、夜市、博物館（新圖示、新季節係數） | 決策 250 | 併進 §15.3「台灣節慶」或觀光列車；廟宇可以和 3D 的廟埕一起做 |
| 真正的機客分離：機車掛上、摘下、換端（要改列車模型與存檔） | 決策 252 | 長期；觀光列車（§15.3）之後再評估 |
| 觀光列車的後續：加價、故事（車種圖鑑）、季節、3D 模型（含真正的蒸汽機車）、到站旋律（含汽笛）；具名列車五款已做完 | 決策 286「下一步」 | 第一步（藍皮解憂號、海風號，停靠景點旁加 0.5★）#819 已合併；山嵐號（`SHANLAN`，數字照海風號）#826 已合併；鳴日號（`MINGRI`，E500＋豪華客車，停靠景點旁加 1★，3D 用現成的 E500 與黑色客車）#1045 已合併；環島之星（`STAR`，E500＋6 客車，加 0.75★，價錢在海風號與鳴日號之間，3D 用 E500＋粉紅客車）#1047 已合併；仲夏寶島號（另加一列 `SUMMER`，`STEAM` 不動；CT273＋莒光客車，加 1.25★，買得便宜、營運最貴、起步最慢，2D 黑色圓頭，3D 暫用現成機車外形塗黑金）在 `claude/tourist-train-summer`。具名列車做完；下一步照決策 286「後來（第四次）」最後一點的順序，一個 PR 一項：加價（先決定誰付）、故事、季節（不做開關）、3D 模型（含蒸汽機車）、到站旋律（含汽笛） |
| 2D 車頭形狀多一種「機車頭」（`TrainNose`、`MapArt.drawCars`） | 決策 252 | 小 PR；美術線有空就做 |
| 照班距派車的越行：待避股在正線外側時，靠左行駛讓不停車的快車也走待避股，所以是慢車留在正線、快車走側線；照班次跑的線（決策 133）仍只用決策 59／294 | 決策 366「沒有做的」 | 有排待避的站，讓不停車的車在決策 202 的寬限內偏好直的正線；會動到既有路線，要量 golden 與 replay |
| 台鐵示範延長到七堵或蘇澳 | 決策 240 | 併進 §15.3「支線劇本」 |
| 一日週遊券的後續：限某條線的票（收購的支線各賣自己的，像平溪線）、多日券、票的插圖（卡片現在用 SF Symbol）、多條線與距離制車資的平衡量測；出票聲（決策 373）之後可照授權明確的售票機錄音的頻譜再調 | 決策 324、373 | 小 PR；限線的票等收購支線（決策 315）有人玩再做 |
| 支線情境包：內灣線 → 深澳線 → 六家線、沙崙線（一條一個 PR，只加一筆 `BranchLineChallenge` 的資料、用報告量一次目標；六家、沙崙通到高鐵站，等高鐵示範那條線告一段落） | 決策 289「下一步」 | 第一條集集線在 `claude/branch-line-jiji`；做法、量法照決策 289 |
| 用 `tra_track_sections.json` 每段的 `tracks` 決定描線時預設單線或複線 | 決策 247 | **做了**（`claude/trace-track-count`，決策 247 的「後來」第二則）：整段照多數決一種。剩下：一次描線中途換線（複線段兩條、單線段一條，接頭加渡線），等玩家需要時再做 |
| 坡道上的 X 渡線（四個道岔加中間菱形交叉要同坡度，要動 GameCore 的交叉規則） | 決策 233、247 | GameCore，等玩家回報需要時再做 |
| 拉近才聽得到那一站的鈴聲（`zoomGain()`）＋鈴聲圈 | RAILWAY_SOUND §2.8、§5 | 併進聲音 2b（NEXT_PRIORITIES §14），和各站到站鈴一起做 |
| 跟車行駛聲的後續（決策 343 做了一般電車與高速兩種循環）：過彎的摩擦聲（曲線限速處，研究文件 §7.3 的第三種循環）、柴油車自己的循環（現在柴油車也播電車聲）、隧道裡的回聲；NEXT_PRIORITIES §22.2 第 7 名「聲音」：夜間快轉時配樂收小由決策 372 做了（下一步：實機聽 12 dB 與淡出 3 秒、淡回 1.5 秒是否合適），一日券出票聲是決策 373（雨聲雷聲由決策 346 做了） | 決策 343「下一步」 | 過彎聲要先找到能下載的授權錄音（Freesound 在雲端 session 回 403，維基共享資源原檔回 429；Internet Archive 的 radio aporee 可以） |
| 雨聲雷聲的後續（決策 346 做了雨、颱風風雨與雷三種聲音）：車站與隧道裡雨聲變小、雨天跟車時車窗上的雨、實機聽音量 | 決策 346「下一步」 | 實機聽感要作者在 TestFlight 聽 |
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
| 潮汐第 2 步：住宅站早上進站多、晚上出站多（NEXT_PRIORITIES §19 第 10 名的後半） | 決策 319；研究 `RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md` §2.4–2.6；量尺 `Tests/GameCoreTests/TideReportTests.swift`（`TIDE_TIDAL=1` 量打開的） | **第 2 步做完**（session_017RbiiqGJTsLWDSz9q4Dukd，`claude/tide-switch`，存檔 67）：世界的開關 `tidalDemand`，新遊戲開，舊存檔、golden、示範、挑戰、入門關卡關；四個目標都達到（住宅站 07–09 進站 39.3%、進出比 6.8 倍、辦公站 6.0 倍、上班日 00–06 放出 0.9%）。強弱是 `StationDemand.homeShare`，由車站附近土地的居民 ÷（居民＋工作）拉開兩端（40%→0、85%→1000）；放出照每小時的中間。路線收班時少放旅客沒有做（深夜已經只剩 0.3%，理由在決策 319）。**還剩第 3 步**：實景地圖用內政部電信信令的鄉鎮日夜比（162907／162908）補上白天的人，寫進土地的工作（GamePresentation 與 App 內附的格網資料），`homeShare` 會自己跟著變，GameCore 不必再動；要解決鄉鎮同名（用代碼與界線）。沒有人接 |
| 自有建築第 2 批：學校、醫院（附近人口長得快）、夜市（併 §22.2 第 20 項觀光）、貨運站（帶貨）；公園與廟的旋轉、夜裡的燈；廟與飯店互相加星 | 決策 361「下一步」 | 第 1 批（公園、廟、外觀代碼、存檔 71）在 `claude/owned-building-kits`；下一批照決策 361 的做法加 `PlacedBuildingKind`、`looks`，存檔版本再加一 |
| 車站卡下一班分月台的後續：路徑偏好之外，用同一條線上一圈實際停的月台猜下一圈；真實列車有月台資料（TDX 即時看板）時照月台列；環狀線兩向終點相同時照下一站分方向（參考庫 klrt-board-directions） | 決策 354「下一步」 | 第一步（分月台、15 分鐘、沒車列下一班、真實列車照方向）在 `claude/station-departures-by-platform`；後續只動 GamePresentation，記上一圈月台若要存檔才動 GameCore |
| 匿名的本機操作計時（附在「回報問題」裡） | CORE_LOOP §1.6 第 6 點 | 核心玩法第 4 個 PR（關卡）時一起做，TestFlight 才問得出「第 1 關花幾分鐘」 |

### 7.3 3D 的後續

**Codex 蒸汽機車＋煤水車（2026-10-23，issue #1103）**：作者回報前導輪區過空後，新增汽缸外罩／煙箱承座／導輪架共408三角，其餘原模型13,672三角逐頂點不變；真正前版與同相機局部對照在私庫history/front-before及previews/steam-front-side-by-side.png。本輪10張參考的獨立兩單元原生靜態素材，霧綠／石墨／金砂、無紅色。配方`Map3DSteamTender.swift`，入口僅靜態註冊；完整編組14,080三角。公開只配方／工具／必要測試／文件／一張總覽，完整native／GLB／35七向／白模／剪影／同尺度／真前後／viewer／來源與ZIP在私庫`Railway/game-art-previews/docs/art/steam-tender-2026-10-23/`。重建與外觀／技術結論見[本批交接](art/steam-tender-2026-10-23/README.md)與`tools/steam-tender/README.md`，兩庫互鏈draft PR與最新head CI見issue #1103。 作者續報#1106紅字：selected-1在20分鐘job上限取消（無測試失敗），已同步main的#1120五份測試／新權重；模型與素材producer仍為1da739ca，原生／GLB逐bytes核對保持。最新CI狀態與timeout證據見#1103／#1106；不重複改CI分份規則。Linux Swift6.4 warnings-as-errors與20相關測試、實際幾何／支承／故障拒收、GLB／PNG／viewer／ZIP已驗證；真機Metal／效能／動畫及工程尺寸／真實車型仍未驗證。不改GameCore／存檔／golden／replay。**合併只增加靜態素材，不會讓營運列車自動換成這台**；車型映射、煤水車跟隨與連桿動畫是另案，不擅稱CT273。

**七節暖白霧藍低裙板都市電車（Codex，#1094，`codex/seven-car-blue-2026-10-23`）**：作者新七圖，兩端＋五中節近等長，端每側1／中每側2雙門、九屋頂箱、單端集電弓；獨立`Map3DSevenCarBlue.swift`，不是前批長短交替七節或四節底盤改殼。只新增靜態註冊。最終54.679×2.731×4.120m／13968三角為展示推估；隱藏28軸是補全假設、確切型號／工程尺寸不足。已修下裙露輪過多、車頭下方與接節下緣缺口，全部門窗玻璃逐三角不變。[外觀／技術／私有ZIP與viewer](art/seven-car-blue-2026-10-23/README.md)、[特徵與重建組裝](../tools/seven-car-blue/README.md)。10native／10GLB／70七向、實際白模／剪影／同相機前後在私庫。VERIFIED Linux Swift6.4 warnings-as-errors、19相關測試、原生讀回／精確組裝、封閉邊／真實殼支持／輪頂50mm淨空與遮擋／接節連續、六故障拒收、Blender／PNG／viewer。真機Metal／效能／動畫／工程規格UNVERIFIED；合併不會自動替換營運列車。無GameCore／存檔／golden／replay變更；兩庫draft與最新CI見#1094，未合併／auto-merge／TestFlight。

**四節暖白金砂都市列車（Codex，#1081，`codex/four-car-metro-2026-10-23`）**：作者新五張圖，四節等長傳統轉向架，與前批五／七節輕軌不同。獨立`Map3DFourCarMetro.swift`；四節每側兩組雙門、16軸、近直立兩端、橫向風擋、雙緩衝塊／中央連結器。每節12m為比例推估，全bounds50.130×2.802×3.694m／7912三角；中心x±18.45、±6.15m，只平移。已修第一版偏長、風擋偏高與輪頂重疊；[外觀／技術、私有成品與限制](art/four-car-metro-2026-10-23/README.md)、[重建與組裝](../tools/four-car-metro/README.md)。7原生／7GLB、49七向、同相機前後、白模／剪影、viewer與ZIP在私庫新目錄。VERIFIED Linux Swift6.4 warnings-as-errors、20測試、原生／組裝／GLB、封閉邊／玻璃支持／20mm輪淨空、缺面／反面／玻璃浮空拒收、PNG和viewer；真機Metal／效能／動畫及工程尺寸UNVERIFIED。**只註冊靜態素材，未綁營運車種，合併不會自動替換路網列車**；後續整合按12.3m節距。無GameCore／存檔／決策／golden／replay變更；兩庫draft PR與CI見#1081，未合併／auto-merge／TestFlight。 作者續報門不好看與無法合併：只修淺暖灰門葉／寬窗／腰帶，門外逐三角不變；門同相機前後與door-verification在私包。原selected-2超過20分鐘已定位，最新main同步後重跑；驗證完成後依作者合併意圖轉ready，不代合併。

**五節改色＋七節輕軌（Codex，#991，公開draft #992／私有draft #40，`codex/five-section-lrt-2026-10-22`）**：作者要求兩台都不要紅，最終五節暖白綠松／七節暖白霧藍。新增獨立七節配方`Map3DSevenSectionLRT.swift`，長—短—長—短—長—短—長，2/0/2/0/2/0/2雙門／側、六鉸接、單端集電弓。五節保留尺寸／門位／輪位／設備／編組，只改色並修trailing側窗沿錯誤對角造成的破口；其餘三角與前producer5a2fd38e逐位元比對。最新[外觀／技術及私有包](art/lrt-pair-2026-10-22/README.md)、[重建／共同軌面／組裝](../tools/lrt-pair/README.md)。12單元＋2編組＋2比較、112七向、白模／剪影／同相機五節改色與七節窗面修訂、viewer／ZIP在私有新目錄lrt-pair-2026-10-22，舊包不覆蓋。VERIFIED Linux Swift6.4 warnings-as-errors、28相關測試、原生組裝／GLB、12單元封閉邊／216主要玻璃承板與車殼支持、六種故障案例。七節45.5m是比例推估，隱藏四架八軸為補全假設；真機Metal／效能／動畫／工程尺寸UNVERIFIED。**兩台均為靜態素材，未綁營運車種，合併不會自動換路網列車**；整合須按各節長度／共同軌面，不能當一般七輛車。不改GameCore／Map3DTrainSets／營運／存檔／決策／golden／replay；最新CI以#992 head為準。未合併／auto-merge或TestFlight。

**接手**：3D 生活感 session 做完第 2 節的四步之後，由遊戲規劃排序。

| 項目 | 出處 |
| --- | --- |
| 三台列車統一遊戲配色（Codex，作者追加要求） | [三台配色總覽與前後對照](art/train-colors-2026-10-22/README.md)；暖白綠松電車／暖白霧藍通勤車／暖白柔綠都市車。三配方僅改顏色，8 單元＋3 編組幾何逐頂點相同；最新私有整合包取代舊包的配色版本，既有 ID 不改 |
| 新參考三節都市軌道車（Codex，#987；三節的通勤電聯車用它，決策 331（續四）） | [本批外觀／技術驗收及私有素材連結](art/three-car-urban-2026-10-22/README.md)；[重建、單元組裝與 viewer](../tools/three-car-urban/README.md)。三單元共 12 軸，每側兩組門；兩庫 draft PR，真機 Metal／效能未驗證 |
| 車輛素材跨 session 生成交接（原生配方、七向素材、驗證與兩庫 draft PR；從本批圓弧中巴往後續作） | [可直接複製給新 Codex／Claude 的完整 prompt](art/VEHICLE_ASSET_HANDOFF_PROMPT.md)；依當時 #231 與 PR merged 狀態選 base |
| 移軸（tilt-shift）效果 | 決策 229 |
| 路塹被 64 m 的地面格蓋住，地面沒跟著軌道切開 | 決策 229、231 |
| 隧道與地下月台（作者 2026-10-22「隧道跟地下月台……現在看會破圖」）：決策 359 做了第一步（隧道裡的玩家列車不畫、跟車鏡頭留在地面上），續一（session_014NB8yWZmutMBX3jDsXC3Sm）畫了隧道本體、隧道燈、新的隧道口，隧道裡的車畫回來。還沒做：(1) 隧道口與路塹接上地形（門框在 11–20 m 深的路塹裡被地面格蓋住，平地的門框孤零零；參考 `tunnel-portals.js`、`tunnel-apertures.js`）；(2) 地下月台（同一個 session 的下一個 PR）與地下的車、軌道、月台透視開關（再下一個；參考 `map3d.js` 的 `live-underground-3d`） | 決策 359 的「下一步」與「續一之後還沒做」 |
| 背面剔除先關著，之後要打開（`Map3DMetalView.swift:299` 還是 `setCullMode(.none)`） | 決策 229 |
| 3D 列車的集電弓、車門把手 | 決策 230 |
| 磁浮、懸吊、單軌、蒸汽沒有 3D 樣式，還是方塊（莒光號、藍皮、推拉式自強號、普悠瑪、太魯閣、EMU800、柴油客車已有模型，決策 318）；機車拉長到和客車同長、集電弓畫成降下 | 決策 230、252、318 |
| 影子不跟太陽方向偏移、建物彼此不投影、月台與雨棚底下沒有影子：決策 357 的太陽陰影貼圖做了（省電畫質仍只有決策 232 的團狀影子）；列車、行人、車輛還不投進貼圖 | 決策 232、357 |
| 站前商店街（決策 322）的後續：招牌的字與店一間間關燈已由決策 352 做了；代表站（35 站）沒有店；廣場被路或軌道切開的車站（十分）沒有店；店不放到城市地塊（要動決策 234、235） | 決策 322 |
| 架空線（決策 326）的後續：中間股道沒有門型架或吊架（車站套件有 `catenaryPortal`）；公路橋下的線沒有壓低（`rails.js` 有）；非實景地圖上玩家蓋的柴油支線也有線；接觸線高度與桿距照東京參考、不是臺鐵規範；號誌機、轉轍器還沒放；三貂嶺、十分一帶的軌道在高度檔的地面下約 6 m（原有問題，架空線在那裡不畫） | 決策 326 |
| 車站套件（決策 321）的後續：站房可能壓到實景底圖的道路（基隆）；高架站只有樓梯口、沒有高架下的大廳；站房跨在軌道上的橋上站房；真實站體輪廓（OSM `building=train_station`）沒有用 | 決策 321 |
| 地面的斑馬線、停止線、車道線（新的地面層要插進第 4.1 節的高度順序） | 決策 241 |
| 3D 的「地圖風格」設定（換配色） | 決策 241 |
| `tools/glb-to-m3dmodel` 靜態橋接已實作（`codex/glb-meshopt-bridge`）：`bridge.mjs --manifest` 讀 meshopt／量化 GLB 與 `.gltf`＋外部 `.bin`，用節點白名單、非 AI 來源／SHA 與 `recolorLightPaint: false`；只用固定版本的 core／extensions／meshoptimizer（五包 MIT），不用 functions。拒收貼圖、skin／動畫／morph 等；原 Meshy 入口與 #803 公車成品逐位元相同。接手從工具 README 與自製 `fixtures/static.manifest.json` 開始；App 接入、美術重組／配色、素材授權與實機幀數仍交 3D session，本工具 PR 不代表素材採用。之後另開 WorldCover 只上色圖層（參考庫 `build_worldcover.py` 與圖磚）與香港無貼圖量體任務 | `docs/research/PEAKLINE_MAP_ENGINE_STUDY.md` §8（#821）；補充與修正 `docs/research/PEAKLINE_STUDY_SUPPLEMENT_2026-10-19.md` §1–§4（#820）；轉換器原本是 Codex 的線（第 2 節） |
| 3D 畫面追上網頁試作（NEXT_PRIORITIES §22.10，3D session_01ShaLWGSyEn9fYcNjS8j5Gz 開工、2026-10-22 換手給 session_01H2iSUj5f1cCXAwjvuFvbsp 依序做）：(1) 天空漸層、太陽、星星月亮做完（決策 347，`claude/map3d-sky`；實機還沒看）；(2) 色調映射的肩部、網頁版的調色、貼地的薄霧做完（決策 349，`claude/map3d-grade`；泛光之後放 `Map3DQuality.high`；實機還沒看）；(3) 招牌、LED 看板、霓虹做完（決策 352，`claude/map3d-signs`，session_013jxDFuuw3kiAu4McNsCyBz；併 rank 15；實機的字大小、幀數、iPad、台中的預覽還沒看，見決策 352 的下一步）；(4) 路面標線（斑馬線、停止線、箭頭）與街道小物（號誌、公車亭、自動販賣機）做完（決策 355，`claude/map3d-road-markings`，session_019qs5F2dh6bGZjb9uzCs47j；實機的幀數與清晰度還沒看，號誌不輪替，見決策 355 的下一步）；(5) 玻璃與水面的反光（天空的 Fresnel、日光反射、夜裡玻璃映出城市燈、水面波紋）做完（決策 356，`claude/map3d-fresnel`，session_0136FXagwq4pwPNs3d9vWUHN；實機的強弱與幀數還沒看，波紋還有點規則，見決策 356 的下一步）；(6) 太陽陰影貼圖做完（決策 357，`claude/map3d-sun-shadow`，session_01NbDKX8YtpretK8Bbz6iq5V：太陽方向的深度圖，太陽轉半度、目標移四分之一格或場景換了才重畫；省電畫質不畫；iPad／iPhone 的幀數與 GPU 時間還沒量，見決策 357 的下一步）。§22.10 六項都做完；各一個 PR、各領一個決策號；不搬 AO、SSR、背景、地標、塔；鳥與飛機之後 | 決策 347、349、352、355、356、357 |
| Metal 的色調映射與泛光（作者說留待以後；2026-10-22 作者要網頁試作搬進遊戲，§22.10 把色調映射排成第 2 項，決策 349 做了肩部與調色；泛光仍留待以後） | `docs/art/map3d-night-terrain-2026-10-16/` |
| Fenn 3D 研究的建議，照順序，一次一個 PR，都在現有的 Metal 裡做：(1) 夜晚與黃昏的泛光＋色調映射，就是上一列，作者說留待以後，所以排到作者要時再做；(2) 實景建物依面積與樓層挑台灣的外牆樣式，補屋頂設備與一樓店面（`Map3DRealBuildings.swift`，可寫 Linux 測試）；(3) 假光貼片：車頭燈、廟與店面往上打的光、招牌光暈。不換 MapLibre、Apple Maps 或 wgpu，不搬 Kenney，手機不開 AO 或高解析度陰影 | [FENN_3D_WORLD_STUDY_2026-10-19.md](research/FENN_3D_WORLD_STUDY_2026-10-19.md) §5（#824） |
| 台北市中心 3D 建物很少：決策 345 已補。只有道路經過的格子改在路旁的空地蓋小一點的樓，台北車站一帶 433 個地塊從畫 73 個變 406 個。剩下的：實機看幀數與縮小的樓；台北的真實建物（決策 239 的管線多編一區，App 多約 2 MB）；河道與部分公園仍整格拿掉或不讓開。量法：`MAP3D_FRAME_REPORT=1 swift test --skip-build --filter Map3DFrameCostReportTests/testTaipeiLots` | 決策 345 的「沒有選的做法」與「下一步」 |
| 3D 跟車（決策 333）、看板點車飛到月台（決策 334）與駕駛室視角（決策 337）的後續：駕駛室內裝（眼睛照參考坐進車裡）與遠處路面會不會閃；在 3D 點列車開始跟車；實機看 85° 的「後方」會不會被建物擋住；真實列車（台鐵、高鐵）的看板也飛到月台，等 §22 的 3D 真實列車；月台邊的圈會不會被雨棚擋住 | 決策 333、334、337 的「下一步」 |
| 深度閃爍與擋住列車的建物（決策 342）的後續：實機看遠處路面還會不會閃、淡掉的建物好不好看、改畫的 chunk 多花多少 GPU 時間；台北市中心補建物之後再量的被擋比例已寫進決策 345（看線旁 120 m 6.5%，都看得穿）；圓錐沒有淡入淡出；真實列車前面的建物不透明 | 決策 342 的「下一步」與「沒有選的做法」 |
| 3D 的真實列車（決策 339）的後續：真實車站的月台與站房（真實列車現在停在沒有月台的地方）；車站卡「下一班」的真實列車版（§22.2 第 5 名後半，要替真實列車另開不是 `TrainID` 的頭）；真實軌道上的架空線；照實際車長；列車包（決策 338）合併後確認鎖住的 set 畫成方塊 | 決策 339 的「沒有選的做法」與「下一步」 |
| 3D 場景的記憶體（決策 368，83.1 跟車閃退）：真實地圖只在鏡頭 2 km 內蓋完整城市，板橋 1.8 GB → 763 MB。剩下最大的是遠看的簡化城市（板橋 1,050 萬頂點，約 450 MB）；App 上傳 GPU 後還留著 CPU 那份陣列，放掉可再省一半。之後加城市細節前先跑 `Map3DSceneMemoryTests.testThe3DMapRoundBanqiaoFitsAPhone` | 決策 368 的「下一步」 |
| slop-newyork（MIT）的 3D 做法能搬哪些（研究 session_01JxqePZhgA9tQuajjP9gsPm，2026-10-23，只有文件）：建議排序 (1) 城市方塊改實例，先做 `.far`（板橋 763 MB → 約 320 MB，估）；(2) 太陽陰影貼圖用 `.far` 當替身；(3) 小零件放進固定大小的池、依像素大小剔除；假室內與合成聲音列「之後」。等 §22.2 10e 與畫風 (e)（決策 370）都合併後由遊戲規劃派 | [SLOP_NEWYORK_3D_2026-10-23.md](research/SLOP_NEWYORK_3D_2026-10-23.md) §5、§6 |
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
| `ci.yml` 的 rest shard 撞 20 分上限（2026-10-23，session_01KcZCRGFREEAx22ncMXAMwJ，`claude/rest-shard-under-limit`）：main 43852fa 的 rest 有 953 s 測試、469 類，沒有一類特別大（最慢 5 類共 172 s）。6 s 以上的 GamePresentation 類別與 25 s 以上的 4 個 GameCore 類別（共 33 類、約 466 s）搬到 campaigns-16／-6／-15／-12（PR #1087），rest 在 PR 的 run 上 510 s；不加 shard、不改 timeout。campaigns-7 自己的兩個 campaign 一次 354 s、一次 603 s，搖擺很大，不要再往裡面放東西。**之後**：rest 再長，照 `swift-shards.sh` 的時間表註解再搬（run 摘要的「Slowest classes」只列 5 類，要整份 job log 才看得到每類時間）；小的 GameCore 類別不要搬，campaign shard 點名的類別在 `pr_plan` 會被當成「改到的 campaign」，讓改它的 PR 跑全套 | `swift-shards.sh` 2026-10-23 later 的註解 |
| campaign shard 再平衡（2026-10-23，session_01KcZCRGFREEAx22ncMXAMwJ，`claude/campaign-shards-under-limit`）：#1087 合併後 main 4d2c8ce 的 run 39932184002 上 campaigns-10 job 19.0 分（測試 891 s）、-11 812 s、-15 793 s。只搬 GamePresentation 類別（不改任何 PR 的 tier）：TRADemo → -3、RealWorldDemo → -4、Map3DStreetLife／StationCommerceCard／Map3D／LineLossDiagnosis → -6、RealRailwayTracing／Map3DStreaming → -13、NetworkPostcard／NewGameSaveProperty 回 rest；FlexDispatchPropertyTests（GameCore、自我測試用到）不動。不加 shard、不改 timeout。**之後**：同一組類別在不同 runner 上可差到 1.9 倍（campaigns-1 一次 384 s、一次 738 s），看分片空間要用它最長的那次；campaigns-1、-2、-14 最長已 12.3–13.5 分測試，不要再放 | `swift-shards.sh` 2026-10-23 after #1087 的註解 |
| TDX（運輸資料流通服務）查資料：`.github/workflows/tdx-check.yml`——#850 已合併。Actions → Check TDX API → Run workflow，`path` 填 `/api/basic/` 或 `/api/advanced/` 開頭的 API 路徑與查詢（預設台鐵第一個車站），回答在 run 的 artifact `tdx-response`（保留 7 天）。session 用 GitHub 工具觸發（`actions_run_trigger`，`tdx-check.yml`，ref `main`）再下載 artifact。金鑰是 repository secrets `TDX_CLIENT_ID`、`TDX_CLIENT_SECRET`，只有這個 workflow 讀得到；不要貼在對話、不要存進 repository。TDX 有票價、時刻、站表、路線色，沒有各站運量 | #850、決策 298 |

### 7.5 只等實機確認的

這些不擋任何工作，在 TestFlight 的「請測試者看」裡輪流問：
- PLAYER_FEEDBACK 標「待實機確認」的：54.1 的兩位玩家、56.1 的大多數則、59.1 之後美術線的三件事（選取列車的黃框、建物徽章會不會疊、建造面板好不好捲）。
- 61.1–68.1 各版請測試者看的項目。
- 到站鈴的聽感，以及幾個音軌一起循環時會不會漂移（RAILWAY_SOUND §11）。
- 56.1 #5：教學第 5 步的卡片蓋住 HUD，在 Linux 沒重現。教學之後會併進關卡（決策 254），到時一起看。
- 實景地圖的轉乘站（決策 298，#851）：新遊戲選項的「現實路網：轉乘」開關看不看得到、實景地圖是不是預設開；車站卡第一行「從…轉乘：每天約 N 人」在手機橫拿時會不會被截斷；在台北車站等大站旁蓋站，玩起來覺不覺得旅客變多（量出來第 14 天多 3–12%）。
- 2D／3D 交接（決策 313）：「拉近自動變 3D」預設開，放手才判斷之後是不是還會誤進 3D。常誤觸就把預設改成關（`Map3DHandoff.pinchOpensKey` 的 `@AppStorage` 預設值，在 `MapView.swift` 與 `SettingsView.swift`），不必重做；也看 3D 左上的「2D」「建設」兩顆鈕找不找得到、會不會擋到景。
- 3D 開在 2D 看的地方（2026-10-21，決策 313 的「後來」）：高鐵示範從台北按 3D、實景新遊戲按 3D，是不是都開在 2D 看的地方；2D 移到很遠再按 3D，等候是不是只有第一次。
- 3D 的列車標籤與路線色帶（決策 314）：拉近到 400 m 以內，畫面中間最多三列車頭上的「線號＋載客／定員」標籤大小、位置對不對、跟著車走順不順；軌道旁 0.3 m 的線色細帶看不看得到、會不會閃。標籤太小或太擠就調 `Map3DTrainLabels` 的 `reach`、`most`、`middle`；色帶太細或太粗就調 `Map3DLineBands.width`。
- 3D 跟車不再閃退（決策 368）：高鐵示範在台北、板橋一帶 600× 跟車切 3D，不再被殺；鏡頭快速移到 2 km 外時，城市先是遠看的樣子，一兩秒內補成完整的，看補的過程明不明顯。
- 3D 的 CPU 與 GPU（2026-10-21，決策 238 的「後來」）：
  - 統計面板多了「wait」一行，CPU 不再把等畫面（drawable）的時間算進去。
  - GPU 連續 1.5 秒超過 10 ms，就降到每點 2×2 像素，面板的 wait 那一行後面寫現在是幾倍。
  - 下一版請作者在同一個台北畫面記下時刻再看一次：
    - CPU 是幾 ms、wait 是幾 ms：CPU 掉到幾 ms、wait 有 10 多 ms，原本量到的就是等螢幕；CPU 還在 16 ms 上下，就用 Instruments 的 Time Profiler 找。
    - 降到 2× 之後 GPU 是幾 ms、畫面會不會跳一下、窗格看起來會不會太軟。太軟就把 `Map3DDrawScale.budget` 調高，或改用 MetalFX。
    - 兩組 GPU（2–4 ms 與 10–12 ms）為什麼差這麼多。
  - 設定的「3D 畫質」（決策 238 的「再後來」）：省電是不是真的少發燙、30 fps 看起來會不會卡；低耗電模式下自動有沒有改成省電（面板的倍數變 2×）；高畫質在 Pro 機上會不會燙到被系統降頻。
- 地圖提示整理（決策 310）：快速圖層多了「車資與章」一格之後，iPhone 直拿時和「快轉到早上」、下一步晶片排在一起放不放得下；地圖上只剩「滿載」章，看起來會不會太少。UI 測試交給 Codex（寫在決策 310）。
- 刪除路線賣掉列車（決策 327，2026-10-21 的玩家回報）：路線面板的「刪除」確認卡寫的列車數與金額對不對；拆月台或軌道被沒有路線的列車擋住時，訊息條的「出售」按鈕在 iPad 與 iPhone 上看不看得到、按不按得到；回報的玩家說地圖上看不到那列車，測試裡它停在第一站月台外約 6 m，要在實機上看它畫出來沒有。
- 找得到的入口（決策 336，#982 與第 26 名的 PR）：路線面板的「可收購的真實路線」與沒有可買時的那一行、車站面板最上面的「收購○○線…」、資料面板「今天」下面的貸款與票價、地圖左下有字的「擴建地圖」膠囊（手機橫拿時會不會擠到圖層鈕或縮放鈕）、建造時「這塊地還不是你的」旁邊的「擴建地圖」（✕／✓ 小卡變寬後會不會出畫面）、狀態列的景點星、列車卡的「時刻表／車隊總覽」、軌道卡的長按提示。另外 §22.9 沒查證的：選單第一層「明信片／成就」那排在手機上會不會只剩圖示。
- 3D 的範圍（作者 2026-10-21 問要不要放大到整張 16 km）：先維持前後左右各 6 km（`Map3DScene.reach`，最多 12 × 12 km；#899 之後移到哪建到哪）。3D 畫質設定（#902）合併後，請作者在台北遠景量降到 2× 之後的 GPU；還有餘裕才只在「高畫質」放大到整張地圖，其他兩個選項不變（遊戲規劃 2026-10-21 代為決定，PLAYER_FEEDBACK 78.1 #10）。
