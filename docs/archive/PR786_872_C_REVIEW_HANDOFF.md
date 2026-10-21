# 交接：PR #786–#872 的審查，C 組（App 畫面、UI 測試、3D 與工具）

Session：PR 審查 C 組（session_01BF7givYQyH1bqCVbRTcCog，2026-10-21），由遊戲規劃 session_01WW7o3decEv5LY59nYVqnDN 派工。從 `main` f4f1b3a（#871 的合併）開始。A 組（行車控制與調度）與 B 組（建造、真實資料、經濟）各有自己的交接；上一輪見 [`PR755_784_REVIEW_HANDOFF.md`](PR755_784_REVIEW_HANDOFF.md)。

- 存檔版本、決策編號、golden schema 都沒有用到；GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改；GameCore 沒有改。
- 一個 PR：`claude/pr786-872-review-c`。改的是 GamePresentation 的三個檔、`tools/glb-to-m3dmodel/glb.mjs`，以及它們的測試；決策 301、303 各補一段「後來」。
- 做法：甲線的 6 個 PR（#835、#837、#839、#842、#861、#870）與兩個 skill PR 是我自己逐行讀的；畫面與 UI 測試的 9 個、3D 與工具的 8 個各交給一個子 agent 讀，它們回報的發現我再讀一次程式，寫得出 Linux 測試的都先在 `main` 跑紅。
- 只算**在 `main` 上重現了**的發現；讀程式看到、Linux 測不到的列在第三節「沒有重現」，不算發現。

## 一、每個 PR 一行

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #835、#837 M0 | 新路線草稿的一行（`LineDraftSummary`：站數、長度、時間、價錢，memo 的鍵）；經濟面板的「今天」卡（`TodayAccount`：整點入帳、午夜那一小時與每天的費用算進前一天，GameCore `settleHour`／`settleDay` 對過） | 沒有問題。開局不在整點時，第一個整點之前寫「今天（截至 06:00）」、三列都是 0，不算錯 |
| #839 決策 292 | 涵蓋切換（`CoverageShortcut` 的記住與放回）、`CoverageSummary` 的比例與「—」、`CityMap.coveredCells` 抽出後兩處共用、UI 測試的等待 | 沒有問題 |
| #842 決策 293 | 六個下一步、memo 的鍵（指令與遊戲日）、只打勾一次、編輯後與時間走過時都會檢查 | 沒有問題。「有一天賺錢」只看留著的 720 天，兩年以前賺過、之後都沒賺時會變回沒完成；可以接受 |
| #861 決策 301 | 三項分數的直線換算與門檻（逐一驗算決策寫的 15 分、75%、92.5% 等邊界）、樣本不夠、最弱一項與修正、memo；買車卡每小時成本的四捨五入 | **發現 1**（擁擠的中文名稱意思相反），已修 |
| #870 決策 303 | 時段裁切與跨午夜、首末班的範圍、班距、要買幾列、起訖站停不下時的上限、memo、錢不夠時的處理 | **發現 2**（「還差多少」不跟著現金走）、**發現 3**（「1 trains」），已修；第三節一項沒有重現 |
| #786 | `LessonUITests` 的 `revealPastMenus`（#858 後來改用車站面板的清單） | 沒有問題 |
| #791 | `LessonUITests`、`StartSaveFlowSmokeTests` 的等待改成看期限的輪詢；「繼續玩」會讓時鐘走，和 `GameSession.keepPlaying()` 一致 | 沒有問題 |
| #798 | `FrameMeter` 只寫 trace；`TickCostReportTests` 只在 `TICK_REPORT` 時跑，毫秒換算對 | 沒有問題 |
| #802 | shard 分配（`FlexDispatchPropertyTests` 只在一個 shard）、`ios-build.yml` 的拆分、`preferencesFileName` 改 public、開關點 0.8／0.2 | 沒有問題 |
| #840 | `FeatureUITestWorld` 用 `GameWorld`／`GameSession` 的指令蓋世界，只在 Debug 加 `-ui-testing` | 沒有問題 |
| #858 | 開線表單捲到最上面、`NextStepChip` 的無障礙 | 第三節一項沒有重現（減少動態效果） |
| #859 | 決策 300 的角落一排（`MapCornerRow` 對照資料來源的排法），iPhone 16 Pro 與 SE 橫拿算過 | 不會重疊；第三節一項沒有重現（觸控高度） |
| #860、#862 | 只改 UI 測試（`waitUntilStill`、長按 1.5 秒） | 沒有問題；#862 記下的模擬器 2 秒約 8 幀，實機若也這樣，0.8 秒的長按會被當成點一下，待實機看 |
| #788 3D 快取 | 回到開始畫面與記憶體警告時 `clear()`、拉近停下才先蓋（`Map3DHandoff.buildsAhead`） | 第三節兩項沒有重現（App 的程式） |
| #794 決策 277 | `Map3DWeather`、`Map3DLighting` 的雨天光、霧的近遠 | 沒有問題；2 秒的光線變化是淡入淡出，motion skill 允許 |
| #793 | `.m3dmodel` 讀取的長度與上限檢查 | **發現 6**（沒有可畫的三角形也讀進來），已修 |
| #797、#799 | Meshy 公車的資料與文件；轉換器測試逐位元重做提交的 `.m3dmodel` | 沒有問題 |
| #803 GLB 轉換 | `glb.mjs`、`jpeg.mjs`、`convert.mjs` 的邊界、Huffman、PNG 濾波、座標轉向 | **發現 4、5**（讀不可信的檔：共用節點、PNG 解壓炸彈），已修 |
| #830 meshopt bridge | 外部 `.bin` 的路徑檢查（`realpath` 之後擋 `..` 與絕對路徑）、原子寫入 | 沒有問題（`bridge.test.mjs` 要的套件這裡沒裝，沒有跑） |
| #841 CityView 截圖 | `tools/cityview-benchmark/capture.cjs` | 沒有問題（`--warmup` 的錯誤訊息說「正數」但 0 也收，不值得改） |
| #847、#848 diagnosing-bugs | 對照 CLAUDE.md：只用 Swift 6.4、golden／存檔／replay 的「never」、只跑快的檢查、交接寫進 HANDOFF；表裡每個測試、環境變數、GameSim 指令與 HANDOFF §7.5 都查過存在 | 不衝突。glTF-Validator 的「到時候加」是作者 2026-10-20 交給 session 判斷的（`GAME_AI_TOOLS_2026-10-15.md` §6.3）。小地方：`TICK_REPORT=300 swift test --filter TickCostReportTests` 沒寫 `--skip-build`，旗標和 CI 不同時會整個重建（CLAUDE.md 說要先 build 再 `--skip-build`）；是文件的小事，沒有改 |

## 二、發現（都在 `main` f4f1b3a 上重現過）

| # | PR | 嚴重度 | 重現 | 預期 | 實際（`main`） | 處理 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | #861 | P2 | `LineSatisfactionTests.testEachTitleNamesWhatAHighScoreMeans` | 分數越高越好，名稱說的是好的那一面，兩種語言同義：「Room on board」 | 中文「車上擁擠」：「車上擁擠 30%」讀起來是三成擁擠，其實是很擠 | 改「車上空間」；決策 301 補「後來」 |
| 2 | #870 | P2 | `LineConfirmationTests.testTheShortfallFollowsTheCash`：一條線開著，卡片開著讓時間走到營運成本把現金壓到價錢以下 | 卡片寫「還差多少」、「開通路線」關掉 | memo 的鍵沒有現金（現金隨 tick 變，指令計數不變），還寫可以買、按鈕開著；反過來錢夠了按鈕也還關著，要改一個設定才更新。按下去 GameCore 會拒絕、不會壞世界 | 價錢與計畫照舊 memo，「還差多少」每次照現在的現金算（便宜：只比一次錢）；決策 303 補「後來」 |
| 3 | #870 | P3 | `LineConfirmationTests.testTheTrackLimitOfOneTrain`：同一段單線上的第二條線，要 2 列 | 「1 train can wait…」 | 「1 trains can wait…」 | 一列時用單數；中文「等它開出後」 |
| 4 | #803 | P3 | `node --test convert.test.mjs` 的「a node shared by two parents…」：40 層、每層把下一層列兩次的 GLB（不到 2 KB） | 馬上拒絕 | 只擋環，不擋共用：每條路徑走一次，2^40 次，跑不完（子 agent 量到 20 層 12 秒）；三角形上限在走完之後才檢查 | 整個場景記住走過的節點，第二次碰到就拒絕（glTF 規定一個節點最多一個父節點） |
| 5 | #803 | P3 | 「a PNG is inflated no further than its header says」：表頭說 1×1、64 MB 的零壓成約 64 KB | 解到表頭說的大小就停 | 先整個解開才比長度：子 agent 量到 1 MB 的 PNG 吃到 2 GB | `inflateSync` 給 `maxOutputLength`；寬×高上限 4096×4096 |
| 6 | #793 | P3（App 還沒讀 `.m3dmodel`） | `Map3DModelFileTests.testAModelWithNothingToDrawIsRefused`：0 個三角形、或只有零面積的 | 拒絕（轉換器也拒絕 0 個） | 讀成一個沒有頂點、範圍是 +∞ 到 −∞、長度 −∞ 的模型，之後縮放或剔除會變 NaN | 新的錯誤 `nothingToDraw` |

第 1–3、6 項的測試在 `main` 的程式上跑：1–3 失敗（訊息見 PR），6 的錯誤種類在 `main` 不存在、子 agent 的探針在 `main` 失敗（「read: 0 triangles, minimum inf…」）。第 4、5 項在 `main` 的 `glb.mjs` 上：4 跑不完（把層數改成 0 才跑得完，兩支都紅），修好後 6 支全綠、連跑三次。

## 三、沒有重現（讀程式看到的，Linux 測不到；不算發現，延後）

| 項目 | 為什麼延後 | 建議做法 | 範圍 |
| --- | --- | --- | --- |
| 3D 場景快取的鍵只數建物與月台的**個數**（#788，鍵是 #785 加的）：同一週裡賣掉一棟、再放一棟（或拆一座月台、再蓋一座），鍵一樣，3D 還畫著賣掉的那棟 | `Map3DPreviewScreen.swift` 是 App 的程式，Linux 測不到；子 agent 讀程式找到（`Map3DSceneKey`，`BuildingSale.swift` 的 `removeAll` 與 `PlacedBuilding.swift` 的 `append`） | 鍵加上最後一棟建物與最後一座月台的 id（或 id 的雜湊）；改了交給 `ios-build.yml` 編譯 | `Map3DPreviewScreen.swift` |
| `Map3DSceneCache.clear()` 只丟掉 `building`、沒有取消；蓋場景的 `Task.detached` 不看取消。記憶體警告之後馬上再開 3D，會有兩個整個場景同時在蓋 | 同上；要實機的記憶體數字才知道值不值得 | 鍵相同就沿用進行中的工作；不同才 `cancel()`，並在 `Map3DScene.init` 裡加取消點；或只丟掉已經蓋好的 | `Map3DPreviewScreen.swift`、`Map3DScene.swift` |
| 開線表單捲到最上面（#858）與決策 188 原本那一處，`withAnimation { proxy.scrollTo… }` 不管「減少動態效果」 | App 的程式；iOS 的捲動本來就大多不理這個設定 | 讀 `accessibilityReduceMotion`，用 `MotionRule` 的版面動畫，打開時直接跳過去 | `LinesPanel.swift`（約 139、150 行） |
| 角落一排的鈕（#859）在實景地圖、資料來源佔滿下面那條時，往下的觸控延伸是 0，只剩 44×28 點 | App 的版面，要實機看；看起來是刻意的（下面是資料來源） | 那時往上延伸，或整排再抬高 16 點 | `MapView.swift`（約 698–704 行） |
| 確認路線卡（#870）的預覽用 `targets: nil` 算，按「開通路線」時 `createLineFromDraft(as:)` 用實景路線的目標班距；兩者在實景地圖上可能買不同的車、價錢不同；而且有目標班距時若規劃不出來，會改走沒有車的 `.createLine`（卡片的註解說不會這樣） | 要一張有真實路線的實景地圖才能測；這輪沒有做出來 | 預覽與開通用同一份 `real?.targets`（把 `createLineFromDraft` 算 `real` 的那段抽出來共用）；`planned == nil` 而且有卡片時留著卡片、寫原因 | `LineConfirmation.swift`、`GameSession.swift`（空窗快轉的 session 在改 `GameSession`，先問它） |
| `TICK_REPORT` 那一行沒寫 `--skip-build`（#847） | 文件小事 | 改成 `swift build --build-tests -Xswiftc -warnings-as-errors` 之後 `TICK_REPORT=300 swift test --skip-build --filter TickCostReportTests` | `.claude/skills/diagnosing-bugs/SKILL.md` |

## 四、檢查

- **VERIFIED（Linux，Swift 6.4.0）**：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`swift test --skip-build --filter "Map3DModelFileTests|LineConfirmationTests|LineSatisfactionTests|MapLineDraftTests|LineDraftSummaryTests"` 全過。改的不是 campaign，沒有 shard 要跑。
- **VERIFIED（Linux，Node 22）**：`node --test convert.test.mjs` 6 支全過。
- **VERIFIED**：`python3 -I tools/golden-checks/doc_numbers.py --check` 差異 0。
- **UNVERIFIED**：App 沒有改；`ios-build.yml` 會照 PR 的檔案決定跑不跑。
