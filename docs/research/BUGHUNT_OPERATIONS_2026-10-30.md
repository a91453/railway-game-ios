# 公測前抓蟲：營運（2026-10-30）

派工單 BH2（session_01YGNNumyVPsXrZoUxy84EdE，由遊戲規劃第 32 任派出），分支 `claude/bughunt-operations`，對照 `main` `9fb305d`（#1520 之後）。範圍：路線面板與單線頁、列車（買車、配車、時刻表、待避、折返、機廠）、車站面板、旅客、倍速與跳過夜晚、跟車與 2D 列車、新手教學與入門 10 關。BH1（建設）、BH3（經營與存檔）同時在跑。

**結論：沒找到 P1。** P2 兩項、P3 三項。P2-1 規劃判定等同 P1（「跳到早上」後切出 App 很常見），在這個 PR 修了；其餘留給公測後。GameCore、存檔版本、golden、fixtures 都不動。

## 1. 怎麼找的

用無頭的方式照玩家的順序實際玩（暫時的測試類，沒有提交），每一步之後看死結（`deadlockedTrains()`）、存檔讀回是否相同（`HeadlessGame.load(saveFile())`），結束再跑一天：

| 玩法 | 規模 | 結果 |
| --- | --- | --- |
| 入門 10 關照各關教的事玩 4 天（`LESSON_REPORT=4` 的 `LessonTargetReportTests`） | 17 種玩法 | 該過的全部金牌；第 4、9 關「什麼都不做」照設計不過 |
| GameSim `third-town` 政策 4 天 | 種子 2、3、5 | 0 死結、0 異常 |
| 第 5 關：3 分鐘班距補車、極端班距（2 分、1440 分、離峰 0 列）、跑中的線縮短停靠站、刪掉正在跑的線、再跑一天 | 1 局 | 0 死結，每步存讀相同 |
| 「猴子玩家」：在第 5、8、10 關隨機按 26 種列車與路線操作（買、賣、配、解配、放上、收回、折返、暫停、出發、補車、班距、環線、全天、快車、刪線、復原、跳過夜晚、倍速、跟車），每 10 步存讀 | 9 局 × 70 步 | 沒當掉、存讀全相同；1 局死結，見 P3-3 |
| 每條線先補到 3／5／10 分班距，再把三個時段改成 0／1／2 列 | 7 關 × 27 局 | 0 死結 |
| 單線頁的真實按鈕：改班距（3、10、30、5→30）、「加開一列車」一次與三次、「補足列車」、先加待避線再加車 | 第 3–10 關 × 兩條線 × 早上與 07:00，224 局 | 0 死結 |
| 白天任一時刻存檔、讀回，與沒存的同一局各跑 3 小時 | 種子 2、3 × 3 個時刻 | 逐位元相同 |
| 跳過夜晚中途存檔 | 1 | 存的是跳過用的 ×6000，見 P2-1 |

另外兩個只讀程式的審查（路線面板與單線頁；車站面板、圖表、倍速與跳過夜晚、3D 跟車、遊戲迴圈），對照 10/25 之後的合併：145a17c、ef1d0e2、b48ed55（決策 481、486）；f46f987、4f42394、77cf3a1、1cb4eb7（決策 472）；6f47f30（決策 478）；7cd3986、685b325（跳過夜晚）；807bb9e（決策 464）；1db4a36（決策 485）；4ac255e（決策 460）；e630500（決策 459）；GameCore 的 cb33fd6（決策 490）、9396fbf（決策 470）、0469322。彼此沒有打架：之後的提交都沒有改到同一段。

## 2. P2：明顯錯但能繞過

### P2-1 跳過夜晚時存檔，讀回來以 ×6000 跑（已修，這個 PR）

- **在哪**：`Sources/GamePresentation/GameSession.swift` 的 `worldToSave`（約 1512 行）。它把 `heldSpeed`、`speedBefore3D` 換回玩家的速度，但沒有看 `nightSkipRun`；跳過夜晚時世界的速度是跳過自己的（`NightSkip.speed`，通常 `.fast`）。
- **重現**：在晚上沒有車的地圖按「跳到早上」，跳的途中切到別的 App（`GameLauncher` 的背景自動存檔）或手動存檔；關掉 App 再「繼續」。遊戲以 ×6000 跑，新的 session 沒有 `nightSkipRun`，不會降回來，早上幾秒就過完。Linux 已重現：`NightSkipTests` 的 `world()` 上 `skipToMorning()`、`advance(ticks: 3)` 之後 `worldToSave.clock.speed` 是 `fast`，不是 `normal`。
- **修法（已做）**：`worldToSave` 一開頭，`nightSkipRun` 在時存成 `run.speed`（玩家按「跳到早上」之前的速度），跳之前暫停的就存成暫停，和結束跳過（`endNightSkip`）回到的狀態一樣；之後的 `heldSpeed`、`speedBefore3D` 照舊。回歸測試 `NightSkipTests.testASaveDuringTheSkipKeepsTheSpeedBefore`：跳之前 ×600、×60、×10 暫停三種，跳的途中存檔再讀回，速度與暫停都是跳之前的，除了速度和正在跳的世界相同；沒在跳時 `worldToSave` 與世界相同（存讀後也相同）。改之前紅（三種都讀回 `fast`），改之後綠。
- **五方**：玩家：切出去再回來早上就飛過去，以為壞了，要自己調回倍速；鐵道迷：無；開發：GamePresentation 四行、一個測試，不動存檔格式；美術：無；音樂：跳過時壓低的音樂，讀回後不會再壓，但速度錯是主要的。

### P2-2 分組的路線清單，「上一條／下一條」不照畫面上的順序

- **在哪**：`RailwayGameApp/Views/LinesPanel.swift` 的 `lineSummarySection`（約 470 行）把 `shownLines`（排序、篩選後，沒分組）交給 `LineNeighbours.around`（`Sources/GamePresentation/LinesPanelNavigation.swift`）；清單 `listedLines` 卻在超過一組時照 `lineGroups(shownLines)` 依種類重排。
- **重現**：建 6 條以上、有兩種以上的線（例如自己的線 A、貨運 F、自己的線 B–E，照這個順序建）。清單顯示「你的路線」A–E，再「貨運」F。打開 A 按「下一條線」：到 F，不是 B；頁面寫「第 2 條，共 6 條」，F 卻是畫面上第 6 列。收起來的組裡的線也會被一條條按到。
- **建議修法**：清單分組時（`lineGroups(shownLines).count > 1`），`shown` 與 `all` 都改用 `lineGroups(...).flatMap(\.lines)` 的順序；`LinesPanelNavigationTests` 加一個分組的例子。是否跳過收起來的組，照決策 481 的「照清單現在的順序」，建議跳過。
- **五方**：玩家：一條條看下去時跳來跳去，「第幾條」對不上；鐵道迷：無；開發：GamePresentation 的順序換成清單用的同一個函式，一個測試；美術：無；音樂：無。

## 3. P3：小毛病

### P3-1 打開的線離開篩選後，「上一條／下一條」換成所有路線的順序

- **在哪**：`LinesPanelNavigation.swift` 的 `around`、`positionText`（`shown.contains(id) ? shown : all`）。
- **重現**：篩選「需要注意」，打開一條沒有車的線，在它的頁上補車；它不再需要注意，「第 1 條，共 3 條」變成例如「第 5 條，共 12 條」，「下一條」到一條不在篩選結果裡的線。「虧錢」篩選過了午夜轉賺也一樣。
- **建議修法**：頁開著時記住打開那一刻的順序，之後只拿掉被刪的線；或把打開的線插回 `shown` 裡它在 `all` 的位置。
- **五方**：玩家：處理完一條要注意的線，按下一條卻離開了篩選；鐵道迷：無；開發：GamePresentation 小改加測試；美術：無；音樂：無。

### P3-2 跳過夜晚時可能跳出「跑不到設定倍速」的提示（只讀程式，沒在 Linux 重現）

- **在哪**：`GameSession.swift` 約 956 行，跳過夜晚中也照常 `speedLagWatch.record(speed: world.clock.speed, …)`，`SpeedLagHint` 不知道正在跳。
- **重現（推論）**：在大地圖（例如台北周邊七條線）打開「自動跳過安靜的夜晚」，若跳的 ×6000 連續 20 秒實際時間跑不到七成，提示會說這張地圖「大約只跑得到 ×N」，講的是玩家沒選的速度；按「改成…」會結束跳過；之後玩家真的選 ×6000 時，因為已經算看過，不會再提示。
- **建議修法**：`nightSkipRun != nil` 時呼叫 `speedLagWatch.pause()`，不記錄。實機確認 UNVERIFIED。
- **五方**：玩家：少見，但說的是自己沒選的倍速；鐵道迷：無；開發：一行加測試；美術：無；音樂：無。

### P3-3 對已經有車的線用「依班距配車」會買多的車，停在起站把線堵死

- **在哪**：`Sources/GamePresentation/LineStaffing.swift` 的 `staff`（約 155 行）：照 `lineStaffingPlan` 買 `plan.trains` 列**新**車，不扣掉線上已有的車；`lineMaximumTrains` 的上限只管新買的數目。多出來的車放在起站月台，因為線只能跑那麼多列（「路線現在只開 1 列（班距或軌道限制）」），永遠不出發，佔住終點月台。
- **玩家碰得到嗎**：單線頁只在線**沒有車**時才顯示這一段（`LinesPanel.swift` 的 `trainsSection`：`line.trains.isEmpty` 才 `staffSection`），有車時走「改班距」（`changeSelectedLineHeadway`），那條路 224 局都沒事。所以目前碰不到；猴子玩家那一局死結就是直接呼叫 `staffSelectedLine` 造成的。可能的例外（沒驗證）：線的自有班次沒有車、但快車等停靠模式（`patterns`）有車時，`line.trains.isEmpty` 仍是真的，會顯示配車。
- **重現（無頭）**：第 5、8、9、10 關，07:00 對第 2 條線（已經有 1 列）`staffSelectedLine(headway: 3／10／30)`，30 分鐘內第 1、2 條線的車死結到隔天。
- **建議修法**：`staff` 只買 `plan.trains` 減掉這個班次已配的車（或在有車時拒絕，請玩家用改班距）；`staffSection` 的條件改成整條線（含停靠模式）都沒有車。
- **五方**：玩家：現在碰不到，防的是之後有人把配車按鈕放到有車的線上；鐵道迷：無；開發：GamePresentation 一個條件與測試；美術：無；音樂：無。

## 4. 看過、沒問題的

- 路線面板：上一條／下一條的邊界（沒有越界，一條線時箭頭不顯示）、篩選沒結果時的字、單線頁上刪掉這條線（回清單）、復原建線或拆站時清掉選取、換線時班距選擇重設、從單線頁開始新線。關掉面板再打開還是那條線的頁：決策 481 說的就是這樣，不是 bug。
- 車站面板：站被拆掉時顯示「請選一個車站」、跳到沒畫出的組不動作、收起的「旅客與運量」組會被打開；圖表沒有資料、只有一點、少於兩站的線都有防護。
- 跳過夜晚：一分鐘的找法（7cd3986）和以前一樣、不會跳過頭或停不下來；先套用保留的倍速再算跳過（685b325）。3D 跟著的車被賣掉或刪掉時停止跟車。
- GameCore：決策 490（收購當天的線不放人去搭）、470（背景先算路線）、0469322（夜裡空圖保留白天路線）三個改動，上面的存讀與同局比較都沒有分歧。

## 5. 驗證

- VERIFIED（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors`；第 1 節的無頭玩法（暫時的測試類，已刪）；`LESSON_REPORT=4` 的 `LessonTargetReportTests`；P2-1 修好後，讀 `worldToSave` 或存檔的測試類全過（`NightSkipTests`、`BackgroundSaveTests`、`AutosaveSlotsTests`、`SaveSyncTests`、`HeadlessGameTests`、`Map3DFollowSpeedTests`、`ReleaseUIFixesTests`、`SharedNetworkTests`、`HighSpeedFirstMapReportTests`：110 個，1 個只在要求時跑的報告略過，0 失敗）。
- UNVERIFIED：實機、Simulator（P2-1 在實機切出 App 再繼續；P2-2、P3-1 的畫面順序只讀程式）；P3-2 只讀程式。
