# 交接：PR #712–#754 的審查（69.1 收工那一晚）

Session：https://claude.ai/code/session_01QVLVMib2sHjahi6BdYdK48（2026-10-16），由遊戲規劃 session_01V1xd3H9vNkuZoSA3czNfGm 派工。作者原話：「開始pr review到最新」。從 `main` f5ba673（#747 的合併）開始。上一輪 #685–#711 見 [`PR685_711_REVIEW_HANDOFF.md`](PR685_711_REVIEW_HANDOFF.md)。

- 存檔版本、決策編號、golden schema 都沒有用到。
- GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改。
- 一個 PR：`claude/pr712-754-review`，這份交接加上第三節的三項修正。GameCore 沒有改。

做法和上一輪一樣：開了四個唯讀 agent 分工：
- GameCore：#736、#750，以及 #751 怎麼用 GameCore；
- GamePresentation 與 App：17 個 PR；
- 3D：#734、#745、#752；
- UI 測試、CI 時間、發版後的 full lane。

每個發現我都自己讀程式確認過。寫得出 Linux 測試的，先在 `origin/main` 跑、確認會失敗，再修。

## 一、合併狀態

- #712–#753 共 42 個號碼**全部是 PR，全部已合併**。`git log origin/main --merges` 每一個都找得到。
- #754（貨運路線開關的說明文字，`claude/freight-toggle-hint`）還開著，沒有審，只看了改哪些檔：`FreightText.swift`、`LinesPanel.swift`、`FreightSessionTests.swift`。和這裡的修正沒有重疊。

## 二、69.1 發版與 `main` 的 CI

### 合併時 iOS 檢查還沒跑完的 PR

`main` 只強制要求 `Swift CI (gate)`。下面五個 PR 開了自動合併，合併時 Xcode build job（模擬器建置、PR gate 的 UI 測試、繁中檢查）都還在跑：

| PR | 合併 | Xcode build 結束 | 結果 |
| --- | --- | --- | --- |
| #750 | 17:53:54 | 17:58:16 | 綠 |
| #746 | 17:56:33 | 18:02:09 | **紅**：`RealWorldMapUITests` 的 `Missing button: place.tra-taipei`。17:51 log 裡就已經記下這個失敗，比合併早 |
| #752 | 18:05:54 | 18:12:03 | 綠 |
| #751 | 18:07:00 | 18:07:53 | 綠 |
| #753 | 18:33:20 | 18:43:06 | 綠（run 38947817250） |

- #748 的 PR iOS run（38945587091）也是紅的。原因是從 `main` 帶進來的同一個 #746 問題。它在 18:31 照樣合併了。
- #746 的紅燈由 #753 修好：identifier 改掛在標題上，測試先捲到臺北。

**建議**（給合併協調）：PR 的 auto-merge 只等 `Swift CI (gate)`，動 App 的 PR 不要開 auto-merge，或者合併前看完 `iOS App Build`（CLAUDE.md 的批次規則本來就這樣要求）。

### 69.1（testflight.yml run #69）

- run 38948391970，commit e68f237（#753），**成功**（18:34–18:51 UTC）。
- 發版的 commit 沒有自己的 full lane，`ci.yml` 的 push run（38948243207）也被下一次 push 取代、取消了。
- 前一個 commit 5974c0f 的 full lane（38945089520）在 18:43 被取消。取消前跑完的部分只紅了 #746 那一支，#753 已修。

### 發版後的 full lane

run 38949414352（f5ba673，18:42 UTC 開始）：iPad 教學綠（19:05）；兩個 iPhone job 寫這份時還在跑 UI 測試。結果見這個 PR 的最後一個 commit。

### Swift CI 時間（`ci.yml` push，最近 12 次）

- 中位數約 16.8 分鐘（16.0–18.4），和上一輪（15.7–18.2）差不多。
- 最長的 shard 又回到 `rest`，最多 17.7 分鐘（#748 那一次）。
- runner 有兩種速度：
  - `rest` 建置約 1.5 分鐘的是快的，測試要 7.9–10.0 分鐘；
  - 建置約 2.5 分鐘的是慢的，測試要 12.7–14.3 分鐘。
- 同一種 runner 前後比，`rest` 的測試多了約 0.5–1.5 分鐘：
  - `PolicyTests`（#748）合計 25.8 秒；
  - `HeadlessGameTests`（#740）每個不到 13.5 秒；
  - #740 加的 executable target 沒有讓建置變長。
- 還沒到要重新分 shard 的程度。`rest` 連續幾次超過 18 分鐘時，照 #718 的做法搬一兩個 class 出去。
- PR gate 的 UI 步驟：這五個 PR 的中位數 8.8 分鐘，超過 CLAUDE.md 寫的約 6 分鐘。沒有查是哪一支變慢，列進第四節。

## 三、修的（`claude/pr712-754-review`）

| # | 項目 | 來源 | 修法 | 驗證 |
| --- | --- | --- | --- | --- |
| 1 | 寫實規則下按「在這裡加待避線」，錢不夠時訊息說「沒有足夠的現金**加開一列車**」 | #751，`PlayerCommand.actionText` 的 `.autoService` 只看 `newLine` | 計畫不買車（`trains == 0`）時說「建這條待避線」（"build this passing loop"） | `AutoServiceTests.testAPassingLoopRefusedForCashIsNamedAsTheLoop`（新）。在 `origin/main` 失敗：`Not enough cash to add a train: …`；修正後通過 |
| 2 | 實景地點清單的「鐵路車站」群組把 identifier 傳到每一列，蓋掉各站的 `station.<id>` | #646 就有；和 #753 修的地點群組同一種寫法 | identifier 改掛在群組標題上，和 #753 一樣 | 沒有 UI 測試讀 `railway.*` 或清單裡的 `station.*`，所以現在不會紅；以後有測試要點車站列才會壞。App 的 SwiftUI，交給 `ios-build.yml` 編譯 |
| 3 | 實景開局測試捲到臺北之後直接 `tap()` | #753 | 改用 `tapMiddle(of:)`。`scrollUntilShown` 的註解寫明它不問能不能點，同檔另一支也這樣用 | 交給 PR 的 UI gate（這支在 gate 裡） |

## 四、延後（等穩定）

分類照上一輪第十一節：只動 App 或 GamePresentation、局部、不改存檔與 GameCore 行為的，現在修；其餘延後；拿不準的歸大。

| 項目 | 為什麼延後 | 建議做法 | 預估影響範圍 |
| --- | --- | --- | --- |
| **自動待避線時被抬起的列車，放不回去就默默離開自己的路線**（#751，`AutoService.swift` `apply`，約 542–558 行） | 兩個 agent 都讀程式確認了，但我在 Linux 上做不出「兩端都被佔住」的情況（試了 240 分鐘的各個時刻，被抬的車每次都放得回去），沒有測試。改法也有取捨。 | 被抬起的車放不回去時，直接 `throw .trackReserved(train)`，整個指令拒絕。`addPassingLoopToSelectedLine` 的試算已經會接住這個錯誤，說「等它開過去再按一次」。開新線、加開列車兩條路沒有試算，要一起加。另一個做法：另外記 `stranded`，不要和新車共用 `held`（現在 558 行會把它蓋掉），訊息說「N 列車暫時離線，請到車隊重新配車」。 | `AutoService.swift`、`AutoServiceTests`（要先造出兩端都被佔住的世界） |
| 開線預覽的記憶以 `commandRevision` 為鍵（#751） | 很少發生，金額本身是對的。 | 鍵加上遊戲分鐘，像 `LineDispatchHoldMemo` 一樣。 | `AutoService.swift` 的 `lineOpeningPreview` |
| **3D 斜交平交道**（#745，`Map3DStreets.swift` `addLevelCrossing`） | 3D 幾何，`Map3DLevelCrossing` 要多存一個角度，改完要在裝置上看。交給 3D 生活感那條線（session_01EPkWLr5a25LyJvCuvh1U3R，HANDOFF §4.4），第 2b 步一起做。 | 三件事：(1) 柵欄與警示燈的腳只在路和軌道垂直時才在路邊。120°、140° 時離軌道中心只有約 0.5 m（道床半寬 2.3 m），雙鎮世界的 9 個平交道都是 48° 或 138°。改成沿軌道法線離中心 3.8 m，再找它和路邊線的交點。(2) 平台沿路方向固定 ±2.6 m，斜交時鐵軌在路邊只升 0.65 m，平台高 0.92 m。`deckHalf` 改成乘 `1/|sinθ|`。(3) 複線（兩條邊相距 4 m）只認第一個交點，第二條就擋路，複線兩側的街都斷頭。改成允許同一段路上多個相距不到約 8 m 的交點，平台蓋住全部。 | `Map3DStreets.swift`、`Map3DLevelCrossing`、`Map3DStreetLifeTests` |
| `Map3DStreetLifeTests` 的「車道下有路」容差從 4 m 放寬到 12 m（#745） | 和上一項同一個檔案，一起改。 | 改成量點到路段的距離，容差回到路寬一半。另外 `testATownsStreetsKeepOffTheTrackButWhereTheyCrossIt` 把每個平台前後 ±12 m 都排除在檢查外，剛好蓋掉上一項的 (2)。 | `Map3DStreetLifeTests` |
| 3D 路上的人車用手機時鐘（#734，`Map3DPreviewScreen.swift`） | 表現層，不是 bug，是設計：午夜所有人車跳一次位置，遊戲暫停時照樣走。 | 改用遊戲時鐘的秒數，暫停時停下。 | `Map3DPreviewScreen.swift` |
| #752 的模型檔不是 repo 裡的 `build_train.py` 產生的 | 可追溯性問題，不影響執行。GLB 的 `asset.generator` 是 `railway-game-ios tools/trains/build_train`，但 `build_train.py` 用 Blender 匯出，會寫成 Blender 的 generator；`SOURCES.json` 說 AO 是「analytical」，`build_train.py` 卻用 Cycles 烘焙。重跑 `build_train.py` 得不到這兩個檔。 | 請做 #752 的代理把真正產生檔案的腳本提交上來，或照實改 `SOURCES.json`。 | `tools/trains/`、`Web/CityView/public/models/trains/SOURCES.json` |
| #752 的小地方 | 美術判斷或死設定，不影響玩家。 | (1) `trains.js` 的 `cab.lamp` 改了 `at`、`f`、`width`、`tall`、`lens`，但有 `cab.screen` 時只讀 `lamp.housing`，這些新值沒有作用。(2) 頭燈的位置比真車高，正面看像鼻頂上兩顆眼睛。(3) `Map3DModels.swift` 用 `style.name == "highSpeed"` 字串分支（約 293、301、312 行）。(4) 每節中間車都有受電弓整流罩，真車 12 節只有幾節有。(5) `paint()` 的 `screenFrom`、`skirtLimit` 改動也影響所有車型的車頭。(6) 文件資料夾日期是 `2026-10-17`，比合併那天晚一天。 | `Web/CityView/src/world/trains.js`、`Map3DModels.swift`、`docs/art/n700-game-style-2026-10-17/` |
| #714 放寬了教學全程測試 | 動教學測試會多跑 iPad job。現在接受直接看到第 17 步；這時第 16 步「指著現金和速度選單」的兩個檢查（`check(cash)`、`check(speed)`）不會執行。 | 第 16 步一下就過去時，在第 17 步之後補看那兩個元素存在。 | `TutorialJourneyUITests.swift` |
| #749 的列車卡版面鍵 | 還沒紅過。同一個「整張捲動」版面，如果某次快照有露出 `details.scroll.whole`、某次沒有，會得到兩種鍵，造成誤報。 | 版面鍵只看卡片本身的型別，不看子元素。 | `MapInteractionTests.swift` |
| PR gate 的 UI 步驟 8.8 分鐘（目標約 6 分鐘） | 要看每支測試的時間，才知道該把哪支移到 full lane。 | 從最近幾個 PR 的 xcresult 列出 gate 每支測試的秒數，照決策 199 把不穩或太慢的移到 full lane。 | `.github/workflows/ios-build.yml` 的 gate 名單 |
| 說明頁的 `help.<id>` 也掛在 DisclosureGroup 上（`HelpView.swift:36`） | 無害：答案列只有一段文字，沒有自己的 identifier，也沒有測試讀它。 | 之後動到這個檔案時，照第三節第 2 項移到標題上。 | `HelpView.swift` |
| 實景地點搜尋沒有符合時，清單照常顯示分組，不寫「找不到」（#746） | 介面文字的設計。 | 搜尋字不是空的、地點和車站都沒有符合、地圖搜尋也還沒送出時，顯示一行「沒有符合的城市或車站」。 | `RealWorldPicker.swift` |

## 五、審查後判定沒有問題

- **#750 修好了 #736 Codex 審查的三項**。GameCore agent 在 worktree 裡逐一把修正拿掉，三個測試都會失敗：
  - (a) 折返站的乘客下車：拿掉 `Boarding.swift` 的那一條，`testRidersForTheCallLeftOutGetOffWhereItTurns` 有 6 處失敗；
  - (b) 虛擬離站多算一次：放回 #736 的 `serve`，離站 3 ≠ 2，乘客 200 ≠ 100；
  - (c) 一天測試的進度判準：讓 `shortTurn` 回傳 nil，每個 3 小時的時窗都失敗。
- **提早折返（決策 255）**：
  - 決定性：`advance(n)` 和 n 次 `advance(1)` 一樣，n 取 5、37、300、1440，有乘客和沒有乘客都測過。
  - 沒有新的存檔狀態，存檔版本仍是 63。
  - 固定班次只往一個方向跑，不會觸發。
  - 貨運線、空車回送不會壞。
  - 有待避處時不會走到折返。
- **#751 的原子性**：`.autoService` 是一個 `PlayerCommand`，在副本上做、一次 Undo 全部還原，可以 Codable 往返，重播是決定性的。只有第四節「抬起的列車放不回去」那一項是成功之後結果和訊息不一致。
- **#737 的快取**：
  - 描線預覽以 frame、bounds、起點、終點為鍵；鐵路資料晚到時不會記住空結果。
  - 等候原因以 `commandRevision` 加遊戲分鐘為鍵。
  - 換語言要重開 App，所以不會記到舊語言的字。
- **#727 語言選單**：只讀 App 自己的設定，不會把裝置語言誤當成玩家選的；兩種語言都齊。
- **#746 搜尋**：不分大小寫、重音、空白、撇號、連字號，「臺」和「台」算同一個字。
- **3D**：
  - 決定性：全部用 `map3DRandom` 依位置或 id 加 salt。
  - 平交道和種子街道的設施都算進區塊範圍。
  - 索引都是 `UInt32`。
  - 人車每幀最多 1,400 人加 400 車，緩衝區不會溢出。
  - 減少動態效果時，人站著、車不動。
  - #752 的模型：每節三角形在預算內，寬 2.944 m，`index.json` 指的檔案都在，測試只有新增斷言，`Agent: Antigravity` 是 AGENTS.md 規定的標記。
- **#713、#716、#717、#720、#721、#724、#725、#728、#735、#739、#740、#748**：沒有發現權威性、原子性或玩家文字的問題。
- **UI 測試**：
  - #716、#719、#730 修的是根因。
  - #712 等時鐘的寫法已被 #716 整段取代。

## 六、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 第三節第 1 項的測試在 `origin/main` 失敗，修正後通過。
  - `AutoServiceTests`、`WholePriceTests` 通過。
- **UNVERIFIED — 交給 CI**：
  - 第三節第 2、3 項：App 的編譯，以及 UI gate 的 `testARealWorldGameStartsFromAPlaceAndIsSavedAsOne`。
  - PR 的 GamePresentation tier。
- 3D 的發現是 3D agent 在 worktree 裡用探測測試量的（`Map3D*` 96 個測試全綠，另外寫的探測測試沒有提交）。

## 總表

| | 發現 | 現在修 | 延後 |
| --- | --- | --- | --- |
| GameCore | 0 | 0 | 0 |
| GamePresentation 與 App | 5 | 2（待避線訊息、鐵路群組 identifier） | 3（抬起的列車、預覽記憶、搜尋沒有符合） |
| 3D | 4 | 0 | 4（斜交平交道三件算一項、測試容差、手機時鐘、#752 可追溯性與小地方） |
| UI 測試與 CI | 5 | 1（tapMiddle） | 4（#714、#749、gate 時間、說明頁 identifier） |
| **合計** | **14** | **3** | **11** |
