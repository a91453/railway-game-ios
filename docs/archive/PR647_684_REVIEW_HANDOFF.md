# 交接：PR #647–#684 的審查與修正，上一輪第四節的 8 項，CI 時間

Session：https://claude.ai/code/session_01AZENQFLiGrxko8ouYVPoTv（2026-10-15），由派工 session_01AaAj4wvJMxJQuLWAoYu6S8 派出。從 `main` 1e82b0f1（#682 的合併）開始；機廠出庫 B 決定不開 PR、台鐵實景示範 #684 合併之後，把 #683、#684 也審了，兩個 branch 都合併了 031251ad（#684）。上一輪 #627–#646 見 [`PR627_646_REVIEW_HANDOFF.md`](PR627_646_REVIEW_HANDOFF.md)。

- 存檔版本、golden schema 都沒有用到；ARCHITECTURE 決策沒有新號碼，只在決策 228、231、234 後面加了「後來」。
- GoldenScenarios、ReplayFixtures、SaveFixtures 都沒有改。
- 兩個 PR：
  - `claude/pr647-682-review`：這份交接、GamePresentation 與 App 的修正、String Catalog。
  - `claude/pr647-682-review-core`（#687）：GameCore（決策 228 之後整批與逐秒不一樣），`campaigns-11` 多一個類別。
- 機廠出庫 B（session_01YNBmv76sfS8gJUnyRKEqHV）回覆它不改 `RunSpacing.swift`、`advance`、`moveTrains`；之後量測決定不合，沒有 PR。台鐵實景示範（session_01MLwtcQ9xdCfhkNuE4ZWRXr）#684 合併之後，這裡才改它的 `RealRailways.swift`、`GameLauncher.swift`、`StartView.swift`、`TRADemoTests.swift`（第三節第 12、13 項）。

做法：

- 六個唯讀 agent 分工（#683、#684 另一個）：GameCore 與存檔（#657、#660、#668、#673、#678、#682）；3D 地圖（#648–#679 的十三個與 `tools/map3d-preview`）；GamePresentation 與 App（#649、#654、#657、#664、#665、#671、#673、#677、#681、#682）加上上一輪第四節；UI 測試、CI 腳本、文件與 `main` 的 CI 紀錄；CI 時間。
- 每個發現我自己讀程式確認；能在 Linux 寫的都先寫測試，在 `origin/main` 跑過確認失敗，再修。

## 一、合併狀態

範圍 #647–#684 共 38 個號碼，**全部已合併**（`git log origin/main --merges` 每一個都找得到），沒有關閉未合併或還開著的。

## 二、`main` 的 CI（2026-10-15 01:33 – 20:36 UTC）

| Workflow | run 數 | 成功 | 失敗 | 取消 | 在跑 |
| --- | --- | --- | --- | --- | --- |
| `ci.yml`（push） | 36 | 34（2 個重跑第二次才綠） | 0（最後結果） | 1 | 1（1e82b0f，#682） |
| `ios-build.yml` 完整 lane | 10 | 6 | 3 | 0 | 1（a0acef1，#678） |

| run | commit | 失敗 | 根因 | 修了 |
| --- | --- | --- | --- | --- |
| ci 38732564221 第 1 次 | bf89ee4 | `rest` exit 141（2567 個測試全過） | `sort \| head -5` 在 pipefail 下 SIGPIPE | #662 |
| ci 38746386552 第 1 次 | 61d2f08 | campaigns-16、campaigns-9 建置中 context canceled | 基礎設施 | 重跑綠，沒再出現 |
| ci 38756621281（取消） | 2370c62 | — | concurrency：8 秒內三個合併 | 69b8599 綠 |
| ios 38709237236 | 6e86506 | 教學收合卡片點擊被取消 | 換步驟時卡片重建 | #658（測試補點） |
| ios 38720199489 | 2ec70b2 | iPad 教學轉向中點擊、路線列在導覽列下、job 接近 80 分 | 未停穩、點擊位置、時間 | #659 |
| ios 38773737363 | 27b1dde | `SettingsUITests` 捲動 16 次不夠 | 測試 | #680 |

沒有還沒處理的紅燈。都是測試或 CI 腳本，不是 App。

## 三、修的 bug

每一項的「修正前／修正後」見第八節的對照表。

### `claude/pr647-682-review`（GamePresentation、App）

1. **實景車站建議的月台長度比真的長約 25%**（#673，`RealRailwayGameplay.swift` `realPlatformCars`）：
   - 用 16 m 換算成節數，但 #673 之後月台工具照 `world.platformCarLength` 蓋（新遊戲有真實車長，20 m）。三坑（簡易站，真實 188 m）建議 11 節，蓋出 220 m；猴硐 270 m 建議 16 節，蓋出 320 m。
   - 改用 `world.platformCarLength`：三坑 9 節（180 m），猴硐 13 節（260 m）。
   - 測試：`RealRailwayGameplayTests.testARealPlatformIsNoLongerThanTheRealOneWithRealCarLengths`（新）。`testPlatformLengthDefaultsFromTheTRAStationGrade`、`testARealPlatformLengthIsNotKeptForTheNextStation` 原本鎖住 16／11 節（新遊戲有真實車長，鎖住的正是這個錯），期望值改成 13／9。
   - 實景示範（關著真實車長）不變，`RealWorldMapUITests` 的月台不受影響。
2. **跟隨的車停止服務後，配樂一直壓低到下一步**（#671，`GameSession.endFollowIfGone`）：
   - 只有跟隨、取消跟隨、取消選取、刪路線和每一步之後會重算。暫停時停止跟隨車的服務，配樂一直小 6 dB 到恢復時間或回主選單。
   - 每個編輯都會走到 `endFollowIfGone()`，在那裡重算（`updateMusicDuck` 只在變了時才通知）。
   - 測試：`SoundCueTests.testStoppingTheFollowedTrainBringsTheMusicBackAtOnce`（新）。
3. **最短的待避線在還沒有車時用 16 m 算**（#673，`PassingLoop.swift` `passingLoopLength`）：
   - 真實車長的世界還沒買車時是 96 m，之後買的六節車 120 m 進不去。改用 `world.platformCarLength`。
   - 測試：`PassingLoopSessionTests.testTheShortestLoopHoldsSixCarsOfTheLengthTrainsWillHave`（新）。
4. **實景建物：區域只有南北一半在場景裡就整個不畫**（#672，`Map3DRealBuildings.swift`）：
   - 提早跳過的條件，x 用重疊、y 用包含（`corners[1].y <= maxY && corners[0].y >= minY`）。路網在高雄或台中車站以北或以南超過 750 m，所有真實建物消失，換成程序生成的。
   - 改成兩軸都用重疊。
   - 測試：`Map3DRealBuildingsTests.testAnAreaHalfInTheSceneNorthOrSouthStillStands`（新；修正前北、南兩半都是 0 棟，東、西兩半 403 棟）。
5. **實景建物與街道設施的外觀跟著場景原點變**（#672、#679，`Map3DRealBuildings.swift`、`Map3DRealGround.swift`）：
   - 亂數種子用場景座標，而場景原點是「蓋了的東西的中間」。鋪一段軌道，所有真實建物的牆色、店面、材質、水塔，以及行道樹、路燈的間距、缺口、大小、綠色都重抽。
   - 改用地圖上的位置（加上原點的公尺數）當種子。
   - 測試：`Map3DRealBuildingsTests.testARealBuildingsLookDoesNotMoveWithTheScenesOrigin`（新；修正前五個位移全部不同）。街道設施要建 `Map3DBaseMap`，測試裡建不出來，同一個改法、沒有自己的測試。
6. **診所的陰影轉了 90 度，門口的雨遮埋在樓裡**（#666，`Map3DBuildings.swift` `addClinic`）：
   - `addShadow` 的長寬對調；雨遮放在 `forward * (width / 2 + 0.7)`，但樓沿 `forward` 長 `length`，雨遮在樓裡面看不到。
   - 改成 `length: length, width: width`，雨遮放在 `length / 2 + 0.7`。
   - 測試：`Map3DBuildingsTests.testAClinicsShadowAndCanopyFollowItsFootprint`（新，兩個朝向）。
7. **實景地圖的道路、地表、陰影蓋在道床上**（#663、#656、#679，`Map3DScene.railLift`）：
   - 道床頂只比地面高 0.1 m，水 0.24、公園 0.20、道路 0.28–0.36、中線 0.38、陰影 0.40 都在它上面。程式註解與決策 234 說它們在道床下面。軌道穿過道路或公園時，道沙被路面蓋住，只剩軌頂。
   - `railLift` 0.45 → 0.85：道床頂 0.5 m。列車、月台、洞口一起高 0.4 m（`Map3DTests` 用常數比較，跟著變）。決策 231 第 4 點、決策 234 加了「後來」。
   - 測試：`Map3DRealGroundTests.testARealWorldSceneHasTheRealMapsRoadsWaterAndParks` 加一個斷言「陰影低於道床頂」（修正前 0.4 不小於 0.1）。
8. **拖曳中工具變淡可能卡住**（上一輪第四節，#632；`ContentView.swift`）：
   - 只有拖曳結束或取消時才改回來。換工具、開關面板時地圖的拖曳沒結束，工具一直半透明。
   - 換工具或面板時改回不淡。App 的 SwiftUI，沒有 Linux 測試，**UNVERIFIED LOCALLY**。
9. **#654 的機廠勾選 UI 測試可能點到導覽列下的列**（`MapInteractionTests.testTheLinePanelTicksALinesDepot`）：
   - #659 修了 `LineRoutePreferenceUITests` 同樣的問題（線路面板的清單延伸到導覽列下），這支沒有跟著改。加上 `below: bar.frame.maxY`。只在列停在導覽列下時失敗，寫不出必定失敗的測試。
10. **沒在用的 String Catalog key**（上一輪第四節）：13 個（Unfollow、Follow Train、Following Train、Over capacity、人口格線的兩句、Population (/1km²)、Charge by distance (standard steps)、Inspect stations and track、Select a station on the map…、Tap a station to select it.、Urban Demographics、Houses, shops and offices, where you tap），每一個在 App 與 GamePresentation 的 Swift 都找不到。刪掉。萬一有一個其實在用，`ios-build.yml` 的翻譯檢查會報「匯出有、目錄沒有」。上一輪說「約 13 個」，另一個 agent 數到 18 個是把 Energy、Maintenance 等用插值的鍵也算進去，那些還在用。

12. **英文玩家看到「Zhongli_Yilan」**（#684 讓它更常出現；資料本來就這樣，`RealWorldDemo` 也有）：
    - `station_names.json` 用底線分開中壢「Zhongli_Taoyuan」與中里「Zhongli_Yilan」，`RealRailways.Station.name(in:)` 原樣給玩家，台鐵示範的站名與停靠站就寫「Zhongli_Yilan」，`TRADemoTests` 還鎖住了它。
    - 改成「Zhongli (Yilan)」「Zhongli (Taoyuan)」：仍分得出兩站。依名字找真實車站（`stations(named:near:)`）也認得新的寫法。
    - 測試：`RealRailwayGameplayTests.testNoStationNameShowsTheDatasSuffix`（新）；`TRADemoTests` 的站名期望值跟著改。
13. **高鐵與台鐵示範可以同時在建**（#684，`GameLauncher`、`StartView.swift`）：
    - 兩個按鈕各自只在自己的示範建置中停用。先點高鐵再點台鐵，兩個都在背景建（各要幾秒），先建好的開，另一個丟掉：開的可能不是最後點的那個。
    - `GameLauncher.isOpeningADemo`：任一個在建時，兩個都不再開始；兩個按鈕照它停用。
    - 測試：`TRADemoTests.testTheLauncherBuildsAndOpensIt` 加「台鐵在建時高鐵不開始」（修正前回傳了一個 task）。

### `claude/pr647-682-review-core`（GameCore）

11. **決策 228 之後，一分鐘整批推進和 60 次一秒推進結果不同**（#660，`GameWorld.advance`、`RunSpacing.swift`）：
    - 違反決策 37（`advance(n)` 等於 n 次 `advance(1)`，2× 等於 1×）。高鐵示範第 3 分鐘 THSR 4 就不同（#660 之前 240 分鐘都一樣）。遊戲速度不同結果就不同；`CommandLog` 把連續 advance 合成一筆，問題回報的重播重建不出裝置上的世界。
    - 修正與代價見決策 228 的「後來」：有列車可能被擋時，span 裡只有列車逐秒移動。本機 debug：高鐵示範一天 401 → 約 760 秒，台鐵示範一天 162 → 185 秒。
    - 測試：`HighSpeedDemoBatchTests.testAMinuteInOneStepIsSixtyOneSecondSteps`（新，`campaigns-11`）。
    - 試過、沒採用：只看「span 走得到的距離內」會不會被擋（第 5 分鐘仍差 66 m）；再加上最快的車一個 span 的距離（第 6 分鐘仍差 1 unit）；整個 advance 迴圈逐秒（1106 秒）。

## 四、沒修，需要之後處理或只回報

- **狀態列會改寬度的元素**（上一輪第四節）：仍在。#681 在四種排法都加了委託鈕（徽章是 overlay，不加寬），整列寬 34 pt，小手機更早換成兩層。要整體決定狀態列，交給美術 session。
- **#644 跟隨列很窄時超出**（上一輪）：仍在（`FollowBar.swift` 每一列都 `.fixedSize()`）。版面設計，交給美術 session。
- **#638 Advanced 開關的 accessibility frame**（上一輪）：仍在，要在 Simulator 上看。
- **#638 月台測試依賴真實地形**（上一輪）：仍在。測試問題。
- **`TutorialJourneyUITests.swift` 的 `map.style`**（上一輪）：仍在、無害。只為了這個改教學測試檔會在 PR 多跑 iPad 教學 job，沒改。
- **`unknownLinePattern` 的「pattern #3」**（上一輪）：停站模式的序號，不是內部 ID，照上一輪暫留。
- **#657 切開坡道軌道**：工具用點下的距離檢查豎曲線，GameCore 用切點的 chainage；剛好在豎曲線邊緣時，玩家看到一般的「軌道形狀不合」而不是「轉轍器不能在變坡處」。測不穩定，低。
- **#658、#659 的 UI 測試補點**：教學收合卡片換步驟時重建、Advanced 開關 390 ms 的觸控沒反應。測試沒有放寬斷言，但玩家的點擊也可能被吃掉。要在 Simulator 上看 view 的 identity 有沒有變。
- **#680 捲動 16 → 24 次**：原因是從清單底邊開始拖，拖到捲動邊緣。把起點往上移才是根本。測試問題。
- **3D 地圖（App／Metal，Linux 不能測）**：
  - depth32Float、非反向 Z，最遠的俯視時 0.04 m 的疊層間距只有 1–2 ulp，可能閃爍；改反向 Z。要在裝置上看。
  - 道具不算進 chunk 的範圍，8–10 m 高的電線桿頂端還在畫面裡時可能被裁掉。
  - 預覽畫面的統計（「CPU … ms · GPU … ms」等）只有英文；決策 229 的量測工具，刻意的。
  - `.task(id:)` 取消不會取消 `Task.detached`，舊的、較慢的建置可能晚到蓋掉新的場景。
- **#660 `RunSpacing.catches`** 用 `Double`（GameCore 唯一的浮點）；整數都小於 2^53，實際上是決定性的。
- **#684 的北端側線不是真的**：`TRADemo.depots[0]` 是示範自己放的（OpenStreetMap 在頭城附近沒有側線），但 OpenStreetMap 的鳴謝說它給了「台鐵示範的側線」。只有宜蘭、蘇澳新的側線來自 OSM。可以改鳴謝的字，沒有功能影響。決策 240 在檔案裡排在 241、242 後面，只是順序。
- **CI 的 Swift 版本**：Linux 的 `swift:6.4-noble` 現在是 6.4.1，SessionStart hook 和 CLAUDE.md 寫 6.4.0。

## 五、審查後判定不成立

- **「Track #12／軌段 #12」是內部編號**：決策 201 允許（軌段編號畫在地圖上）。
- **#657 渡線在豎曲線端點、曲線上捨入低於 T₀**：7 個位移 × 平／384 m 爬坡，14 個都蓋得出渡線。
- **#660 `waitsForPlatform` 可能永遠等**：要兩列都誤點又互等，沒看到發生。
- **#660 `joiningPreferredPath` 沒有重查後面的軌道還接著**：路線的軌道不能被切開或拆掉。
- **3D**：列車法向沒有用逆轉置（伸縮約 1，fragment 會正規化）；PMTiles 解碼對壞資料會 trap（只讀內建資料）；退化三角形（略過或無害）。

## 六、存檔、遷移與 GameCore 檢查

- **存檔 62（#673，決策 227）**：`carPitch` 在檢查車尾之前讀出，只接受 16 m、20 m 或車種長度，16 m 時不寫；`realCarLengths` 預設關；61→62 只是註解，正確；`SaveFixtures/v62-real-car-length.json` 在。
- **#657**：切點高度用 chainage；兩段各檢查 40‰；在副本上做，失敗不改世界；渡線的距離 `max(22 m, T)` 與 GameCore 一致。
- **#668**：單位換算正確，只在目錄後面加列，性能預設的比對不變。
- **#678**：只在交通管制開時把誤點加到到站時間，溢位飽和。
- **#682**：`pricingCopy` 的餘額 2^60，低於上限 2^62；唯一在指令中途的收入（換車種退款）在費用檢查之後，所以總價和實際扣的一致。
- **變數名稱遮住函式**：掃過每個改到的檔案，沒有新的。

## 七、審查過、沒有問題（摘要）

- **GameCore 與存檔**：#657、#668、#673、#678、#682；#660 除第三節第 11 項。
- **GamePresentation 與 App**：#649（上一輪的修正都對）、#654、#664、#665、#677、#681、#682；#657、#671、#673 除第三節。
- **3D 地圖**：索引都是 `.uint32`；頂點與 instance 的排列和 shader 一致；繞向與法向手算過；地形內插、相機、LOD 的遲滯方向、太陽方向；PMTiles 與 CityTile 的讀取；決定性；資源與 ODbL／earcut／puff 的授權都在。
- **UI 測試與 CI**：#658、#659、#680 沒有放寬斷言；#662 的 `awk 'NR <= 5'` 正確；#659 的 job 時間；沒有新的 `testflight.yml` 觸發、沒有秘密。
- **文件**：#647、#650、#651、#653、#667、#669 抽查的事實都對。
- **#683**：沒有放寬 UI 測試，跟著 #593 的鏡頭改。
- **#684**：參數化之後高鐵的每一條路徑結果都不變（月台長度、側線、節數、費用、機廠位移、`passes` 在高鐵資料裡不會發生）；`tra-yilan-schedule.json` 142 班、班號不重複、時間只往前、停靠照路線順序、車款都在 `TRADemo.models`；政府資料開放授權條款的鳴謝兩種語言都有；`project.pbxproj` 有新的資料檔；`TRADemoTests` 在 `campaigns-11`、`TRADemoDayTests` 在 `campaigns-16`。

## 八、修改前失敗／修改後通過

| 項目 | 測試 | `origin/main`（1e82b0f1） | 修正後 |
| --- | --- | --- | --- |
| 1 | `RealRailwayGameplayTests.testARealPlatformIsNoLongerThanTheRealOneWithRealCarLengths` | 失敗：猴硐 20480 > 17280，三坑 14080 > 12032，三坑 11 ≠ 9 | 通過 |
| 2 | `SoundCueTests.testStoppingTheFollowedTrainBringsTheMusicBackAtOnce` | 失敗：0.501 ≠ 1 | 通過 |
| 3 | `PassingLoopSessionTests.testTheShortestLoopHoldsSixCarsOfTheLengthTrainsWillHave` | 失敗：6144 ≠ 7680 | 通過 |
| 4 | `Map3DRealBuildingsTests.testAnAreaHalfInTheSceneNorthOrSouthStillStands` | 失敗：north、south 都是空的 | 通過 |
| 5 | `Map3DRealBuildingsTests.testARealBuildingsLookDoesNotMoveWithTheScenesOrigin` | 失敗：五個位移全部不同 | 通過 |
| 6 | `Map3DBuildingsTests.testAClinicsShadowAndCanopyFollowItsFootprint` | 失敗：陰影 39.6 ≠ 26.7；雨遮 13.35 < 19.79 | 通過 |
| 7 | `Map3DRealGroundTests.testARealWorldSceneHasTheRealMapsRoadsWaterAndParks`（加的斷言） | 失敗：0.4 不小於 0.1 | 通過 |
| 11 | `HighSpeedDemoBatchTests.testAMinuteInOneStepIsSixtyOneSecondSteps` | 失敗：第 3 分鐘 THSR 4 不同 | 通過 |
| 12 | `RealRailwayGameplayTests.testNoStationNameShowsTheDatasSuffix` | 失敗：["Zhongli_Taoyuan", "Zhongli_Yilan"] | 通過 |
| 13 | `TRADemoTests.testTheLauncherBuildsAndOpensIt`（加的斷言） | 失敗：台鐵在建時高鐵仍開始建 | 通過 |
| 8、9、10 | 寫不出 Linux 測試（SwiftUI 狀態、只偶發的 UI 測試、String Catalog 由 macOS 的翻譯檢查驗） | — | 交給 `ios-build.yml` |

## 九、CI 時間

**Swift（`ci.yml` push）沒有變慢**：一次 run 從開始到最後一個 job 的中位數 15.4 → 15.8 分（一週前 10 個 run、#660 之後 19 個 run）。但：
- 每個 run 的 job 分鐘 176 → 220（+25%），測試分鐘 138 → 172：多了新的測試（`HighSpeedDemoDayTests` 等）。
- 建置步驟每個 job 1.0 → 2.3 分，17 個 job 各建一次，約 36 job 分鐘。
- 一週前 25 個 job、排隊中位數 4 分；現在 17 個 job、幾乎不排隊，所以總時間沒變。
- shard 之間差不到 ±5%（最長 campaigns-8 732 秒，`GoldenScenarioTests` 一個 358 秒），重新平衡最多省 15 秒，所以**沒有改 `classes_of`**（改 CI 腳本要跑完整 tier，不划算）。真正的下限是 `BoardingPropertyTests`（668 秒，自己一個 shard）和 `LineDispatchPropertyTests`（608 秒），要再快得把它們拆半。
- 這裡的 GameCore 修正（#687）讓 `campaigns-16` 變長（本機 950 秒，估計 CI 約 740 秒、job 15–16 分），批次測試放 `campaigns-11`，兩個 shard 約一樣長。
- PR 的 tier：25 個 10-15 的 PR run 都照決策 185，沒有多跑。

**iOS 完整 lane 變慢了**：iPhone 的 UI 測試步驟中位數 20.1 → 44.4 分（最多 55 分，上限 75），job 26.2 → 56.5 分；原因是 UI 測試 27 → 63 個（每個平均 37 → 47 秒）。PR 的 gate 沒變（7.0 → 7.2 分）。
- 建議（沒做）：完整 lane 的 iPhone 測試拆成兩個 job（例如 `MapInteractionTests` 加 `RealWorldMapUITests` 一個，其他一個），約 25–30 分，但每三小時多占一台 macOS（上限 5 台）。或照現在的增加速度，幾天內要再提高 75／95 分的上限。
- 字串匯出又編譯一次 App（每 job 2.6–3.1 分），決策 187 列為等作者決定。

數字來源：`ci.yml` run 37562305381 等 10 個（一週前）、38732564221 等 19 個（#660 之後）；完整 lane 38789203602 等 11 個、37912890169 等 5 個。

## 十、驗證

- **VERIFIED（本機 Linux，Swift 6.4.0）**：
  - 兩個 branch 都 `swift build --build-tests -Xswiftc -warnings-as-errors` 沒有警告。
  - 第八節每個測試在 `origin/main` 跑過、失敗；修正後通過。
  - 修正後通過：`RealRailwayGameplayTests`、`SoundCueTests`、`PassingLoopSessionTests`、`Map3D*Tests`（67 個）、`TRADemoTests`、`RealWorldDemoTests`、`NearestStationNamingTests`、`PlaceNamingTests`。
  - 第 3 項：在修正前的 `PassingLoop.swift` 上 6144 ≠ 7680，失敗。
  - core（#687）：golden、replay、存檔與班次相關的 177 個測試通過、值沒有變；合併 #684 之後 `campaigns-16`（1062 秒）、`campaigns-11`（769 秒）通過。
  - `swift-shards-selftest.sh` 通過。
- **UNVERIFIED LOCALLY — requires macOS/Xcode CI**：`ContentView.swift`（第 8 項）、`MapInteractionTests`（第 9 項）、`Localizable.xcstrings`（第 10 項）、3D 地圖在裝置上的樣子（第 4–7 項）。
- 其餘交給 CI。

## 總表

| | 發現 | 修了 | 沒修 |
| --- | --- | --- | --- |
| 上一輪第四節 | 8 | 2（拖曳變淡、沒在用的 key） | 6（狀態列寬度、跟隨列超出、Advanced 框、月台測試、`map.style`、pattern #） |
| GameCore | 2 | 1（第 11 項） | 1（`catches` 的 Double，只回報） |
| GamePresentation（含 3D） | 8 | 8（第 1–7、12 項） | 0 |
| App 與 UI 測試 | 12 | 2（第 9、13 項） | 10（#657 錯誤訊息、#658／#659 補點、#680、3D 的四項、北端側線的鳴謝、Swift 6.4.1） |
| **合計（這一輪）** | **22** | **11** | **11** |

另有 5 項判定不成立（第五節），不計入。兩部分合計修了 13 項，沒修 17 項（上一輪的 6 項加這一輪的 11 項）。
