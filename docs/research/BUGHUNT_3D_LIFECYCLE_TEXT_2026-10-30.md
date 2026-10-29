# 公測前抓蟲：3D 載入、App 生命週期、語言與顯示、回報問題（2026-10-30）

派工單 BH6（遊戲規劃第 32 任派，session_01YGNNunkFC5hJCzour2bMup，`claude/bughunt-3d-lifecycle-text`）。對照的是 `main` 9fb305d。效能與畫質分層不重做，見 [`PERF_TIERS_2026-10-30.md`](PERF_TIERS_2026-10-30.md)。

標記：**VERIFIED** 是這個 session 在 Linux（Swift 6.4）真的跑過；**UNVERIFIED** 是只讀程式，要 Simulator 或實機才答得出來。

## 0. 結論

- **P1：沒找到。** 沒有當掉、記憶體爆掉、存檔遺失、卡死或整段漏翻是能在 Linux 重現、或讀程式就確定的。
- P2 一項（3D 地圖不受字級上限管，要 Simulator 確認）、P3 兩項，見第 2 節。
- 只有 Simulator 或實機答得出來的，列在第 3 節，寫了怎麼驗。

## 1. 做了什麼

### 1.1 跑過的（VERIFIED，Linux）

- `swift build --build-tests -Xswiftc -warnings-as-errors`：乾淨。
- 這幾類的測試全綠（134 個，1 個要環境變數才跑而略過）：`BackgroundSaveTests`、`AutosaveSlotsTests`、`GameLauncherTests`、`LanguageChoiceTests`、`LocalizationTests`、`Map3DSceneMemoryTests`、`ProblemReportTests`、`DeviceDiagnosticsTests`、`DeviceLoadTests`、`FrameTimeRecordTests`、`Map3DQualityTests`、`Map3DSceneHoldTests`、`Map3DStreamingTests`、`Map3DWeatherTests`、`DayNightTests`、`Map3DSkyTests`、`Map3DNightAndGroundTests`。
- 3D 場景的記憶體，用 App 的資料重量一次（`MAP3D_FRAME_REPORT=1`，`Map3DCityMemoryReportTests/testTheCitysMemory`）：板橋 367.8 MB、台北 518.4 MB，和決策 460 寫的 367.6／516.7 MB 相同，沒有變大。
- 語言：
  - String Catalog 用 `check-localization.py` 的 `catalog_issues`（不需 Xcode 匯出的那一半）檢查：307 個 key，0 個問題；沒有中文當 key、沒有英文欄位寫成中文。
  - App 的 `Text`、`Button`、`Label`、`Toggle`、`Section`、`navigationTitle`、`accessibilityLabel`、`accessibilityHint`、`Picker` 直接寫字面字串的，都在 catalog 裡；沒有一個直接寫中文。
  - `DisplayLanguage.text(英, 中)` 的每一處（App 與 GamePresentation）：英文那一半有中文的只有一處，是 Wikimedia 照片作者的名字（`DataSourceCredits.swift:773`），照實寫，不是漏翻；中文那一半沒有照抄英文的。
  - 一個不提交的暫時測試：英文的 `GameSession` 以最快倍速跑示範地圖、三個沙盒挑戰（各 30 天）、入門 10 關、每週挑戰，每一 tick 看狀態列，跑完看新聞紀錄：0 則有中文。新聞只有 1–4 則一局，涵蓋得不多。
- Dynamic Type 的上限：`ContentView` 有 `.dynamicTypeSize(...xxxLarge)`（`UI_THEME.md` 第 5 條「整個畫面的字級上限是 xxxLarge」）；開始畫面整個在 `ScrollView` 裡，不設上限也不會擠爆。

### 1.2 讀過、沒有問題的程式路徑

- **3D 開開關關**：`Map3DMetalView`（MTKView）不被任何單例強引用：`FrameTimeBenchRunner.view3D`、`Map3DCameraLink.view`、`Map3DChunkStreamer.view`、`Coordinator.view` 都是 `weak`；`onCamera`／`landed` 捕捉 weak 的 coordinator；主執行緒的 `CFRunLoopObserver` 在離開視窗時 invalidate；GPU 的 completion handler 不捕捉 view。串流的背景建置用 `[weak self]`，3D 關了之後建好的 chunk 就丟掉。北方羅盤、2D 地圖滑行的 `CADisplayLink` 會留住 target，但都是有限的動畫，跑完就 invalidate。
- **場景快取**（決策 269、460，審查 L-1 的 `Map3DSceneHold`）：`tight`（4 GB）的機器關掉 3D 就放掉，建到一半關掉的建完才放、其間重開就沿用；回開始畫面與系統記憶體警告都會放。10/25 之後的改動（#1421 決策 460、67bae9e 審查 L-1、1db4a36 決策 485、cdd674c 雨）彼此沒有打架。
- **記憶體少時先降**：`Map3DMemoryWatch` 每半秒看一次，低於 300 MB 降一步，10 秒內不再降；`Map3DSceneCache` 與 `Map3DMetalView` 各自聽系統的記憶體警告。
- **切到背景、來電、鎖螢幕**：`scenePhase` 不是 `.active`（拉下控制中心、來電橫幅、鎖螢幕、回主畫面都是）就停遊戲迴圈、停 15 分鐘的定期自動存檔、在背景寫一份自動存檔、同步 iCloud，並向 iOS 要背景時間等寫完（`BackgroundSave`，佇列是序列的，自動存檔一定先寫完）。`inactive` 與 `background` 都會呼叫，但 `setActive` 只做一次。音樂與音效在 `AVAudioSession` 中斷結束後恢復。畫面流暢度的紀錄在 `willResignActive` 停、`didBecomeActive` 再開，背景的時間不會算成卡頓。
- **被系統殺掉後重開**：離開前景時就寫好的自動存檔（`autosave.json`，整檔原子寫入）是「繼續」讀的那一份；壞掉的會往前退（決策 192）。開新局、上課、挑戰前，舊的自動存檔先移成輪替的一份（`archiveAutosave`），不會被上課的局蓋掉。在前景當掉時最多丟 15 分鐘，照設計。
- **低電量模式、發燙**：3D 每秒 30 格、不畫陰影與反光（`Map3DQuality.plan`），每半秒重讀；遊戲迴圈依 CPU 等級與發燙決定最多佔多少時間（`TickPace`，決策 460）。
- **夜晚與天氣**：天氣換的時候在 `Map3DWeather.changeSeconds` 內漸變；夜晚、天空、霧有各自的測試（上面全綠）。**季節**：3D 地圖沒有季節，沒有可切換的。
- **回報問題**：寫好的訊息有版本、build、系統、裝置型號、每一關花的時間、遊戲中時有遊戲狀態與 3D 的格（`Map3DLoadGovernor.report`），再接上 MetricKit 記到的卡住與閃退、最近的畫面流暢度與裝置等級。送出用系統分享表（郵件、訊息或其他 App），App 本身不連網：**沒有網路時郵件會留在寄件匣、等有網路再寄**，App 這邊沒有要處理的錯誤。需要網路的只有設定裡的「3D 城市」示範，連不上時已有中英文提示（`CityView3D.swift:165`）。

## 2. 找到的問題

### P2-1 3D 地圖不受 xxxLarge 字級上限管（UNVERIFIED，要 Simulator）

- **在哪**：`RailwayGameApp/Views/ContentView.swift:120` 的 `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` 放在 `.sheet`、`.fullScreenCover(isPresented: $screen.showsMap3D)` 之前。SwiftUI 的環境值只往內傳，所以從這裡打開的 3D 地圖（`Map3DPreviewScreen`，地圖上疊著速度、跟車的駕駛 HUD、指北針、按鈕）與面板的 sheet，用的是系統的字級，最大到 AX5。`UI_THEME.md` 第 5 條說整個畫面上限是 xxxLarge；3D 地圖正是「地圖和控制項共用一個畫面」的那種。面板的 sheet 是清單、會捲，問題小；3D 地圖不會捲。
- **怎麼重現**：iPhone（SE 寬最明顯）設定 → 輔助使用 → 顯示與文字大小 → 放大文字，打開「更大的輔助使用大小」並拉到最大；開一局、點 3D 鈕、跟一列車。看駕駛 HUD 與底下的按鈕有沒有被擠出畫面或互相蓋住。對照：同樣字級的 2D 地圖停在 xxxLarge。
- **建議修法**：在 `fullScreenCover` 的內容（`Map3DPreviewScreen(...)`）上也加 `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`；`FleetOverviewSheet.swift:155` 的班表全螢幕、`LinesPanel.swift:2522` 的運行圖看了再決定。修了要照 ui-review 拍最大字級的截圖。這次沒有改：Linux 無法確認現況，也不能拍截圖。
- **五面向**：
  - 玩家：用大字的人在 3D 地圖上可能按不到按鈕；一般字級的人沒有差別。
  - 鐵道迷：無。
  - 開發：一行 modifier，和 2D 地圖同一條規則。
  - 美術：3D 的 HUD 維持設計時的比例。
  - 音樂：無。

### P3-1 附上存檔失敗時，回報問題的按鈕變灰

- **在哪**：`RailwayGameApp/Views/SettingsView.swift:695-705`（`ProblemReportRows`）。打開「附上存檔與指令紀錄」後，如果檔案寫不出來（`commandLog.file == nil`，例如裝置空間滿了），會走 `else` 那一支，而它 `.disabled(attachesCommandLog)`：只看得到「無法寫出檔案：…」，「回報問題」按不下去。
- **怎麼重現**：Linux 無法；實機要讓暫存目錄寫不進去（空間滿）。從程式就看得出兩支的條件。
- **繞過**：把「附上」關掉，就能送沒有附件的那一則。
- **建議修法**：`else` 那一支只在「附上且還在寫」（`commandLog == nil`）時停用；寫失敗時照常送文字，並在說明那行多一句「這次只送文字」。
- **五面向**：
  - 玩家：空間滿的時候正是最需要回報的時候，不該要先猜到關掉開關。
  - 鐵道迷：無。
  - 開發：改一個條件，加一句中英文。
  - 美術：無。
  - 音樂：無。

### P3-2 3D 地圖每次更新都重算場景的 key（未量）

- **在哪**：`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:220` 的 `.task(id: Map3DSceneKey(world: session.world, ...))`。`session.world` 每 tick 都變，body 每次都建一個 key；`Map3DSceneKey.init`（同檔 593–606 行）裡有 `world.roads?.allCells.count`，玩家自己鋪過路時 `allCells` 是 `cells.union(built)`，每次把整張路網的格子併成一個新 Set；另有 `Map3DLineBands.Signature(world:)`。
- **怎麼重現**：實景地圖、鋪過一段自己的路後開 3D，看 3D 角落詳細數字的「main … ms」；沒有量，所以不知道有多少。
- **建議修法**：key 改用 `cells.count + built.subtracting(cells).count` 一類不建新集合的算法，或由 session 在路網改變時記一個計數；改之前先用 PERF 的方法（決策 485 的主執行緒量測）量一次。
- **五面向**：
  - 玩家：大地圖跟車時可能多一點主執行緒時間；量到才知道。
  - 鐵道迷：無。
  - 開發：只改 App 的 key，不動 GameCore。
  - 美術：無。
  - 音樂：無。

### 已知、不重複列的

- 4 GB 機器開 3D 的記憶體、App 留著的那份場景（`built.scene`，板橋 368 MB、台北 518 MB）：決策 460 的「下一步」1、2。
- 換語言下次開啟才生效、舊新聞維持寫下時的語言（狀態列訊息只有一種語言）：設計如此（`SettingsView.swift:163`、`NewsLog.swift` 的 `NewsItem`）。

## 3. 只有 Simulator 或實機答得出來的（UNVERIFIED）

沒有用 macOS runner（全面檢查在用）。發版前在實機照這張表看：

| # | 看什麼 | 怎麼看 | 對的樣子 |
| --- | --- | --- | --- |
| 1 | 4 GB 機型開大城市 3D | iPhone 12／13 mini：實景地圖台北車站附近開 3D、拖動一分鐘，關掉再開，共 10 次；之後「回報問題」 | 不閃退；回報裡「記憶體最高／最少剩」沒有一次比一次高（沒漏）；`tight` 每次開要等幾秒是正常的 |
| 2 | 整個臺灣開 3D | 「整個臺灣」新局，蓋一條長線，在線上不同地方開 3D、跟車跑過幾個城市 | 不閃退；串流的區塊跟得上，遠處先粗後細 |
| 3 | 3D 開著切到背景 | 3D 跟車時回主畫面 30 秒再回來；再試鎖螢幕、來電（接起再掛斷） | 回來時畫面接著畫、時間沒有補跑；音樂恢復；回報問題沒有多一次卡住 |
| 4 | 背景存檔與被殺掉 | 遊戲中做一個好認的改變（例如新蓋一站）後立刻回主畫面，在 App 切換器把 App 滑掉，重開按「繼續」 | 那一站在 |
| 5 | 低電量模式 | 3D 開著時從控制中心打開低電量模式 | 角落的 fps 降到約 30；關掉後回到約 60 |
| 6 | 夜晚、天氣切換 | 3D 開著用快轉跑過傍晚到夜晚、碰到下雨的一天 | 漸變沒有閃白、沒有整片黑；雨不比地圖畫得勤（PERF 修的） |
| 7 | 最大字級（P2-1） | 見 P2-1 | 2D 地圖、3D 地圖、主要面板都不擠爆 |
| 8 | 深色模式 | 系統切深色，看開始畫面、HUD、各面板、3D 的卡片 | 字與底色對比夠；沒有白底白字 |
| 9 | 英文介面 | 設定 → 語言選 English，重開，走第 1 關與開一局實景地圖 | 介面沒有中文、沒有顯示 key（站名、地名是資料，照資料） |
| 10 | 回報問題沒網路 | 飛航模式下按「回報問題」選郵件送出 | 分享表照常出現；郵件留在寄件匣，有網路後寄出 |

## 4. 驗證

- VERIFIED（Linux，Swift 6.4）：build `-warnings-as-errors`、第 1.1 節列的測試類、場景記憶體報告、String Catalog 與字串的檢查、英文 session 的暫時測試（沒有提交）。
- UNVERIFIED：第 2 節三項的現況與修法、第 3 節全部（Simulator 或實機）。
- 這個 PR 只有文件：GameCore、存檔版本、golden、SaveFixtures、ReplayFixtures、決策號都不動。
