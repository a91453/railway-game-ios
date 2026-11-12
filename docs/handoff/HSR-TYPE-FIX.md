# HSR-TYPE-FIX

派工單 HSR-TYPE-FIX（session_01YGNNuq7h66uai9AGCr2xMX，`claude/hsr-type-fix`，2026-11-12）。不動 GameCore、存檔版本、golden、ReplayFixtures、SaveFixtures；沒有用決策號（709 釋出）。背景：#1579 留言 6817547569。

## 查到什麼

- 「鋪真實路線」走的是 `DemoRealLines`（`GameSession.addDemoLine`），不是 `RealLineAcquisition`。後者只賣台鐵支線、輕軌、捷運（沒有高鐵），捷運與輕軌本來就照系統給車種（`RealBranchLine.trainType`），沒有洞。
- `addDemoLine` 對每個系統都用 `staffLine(..., type: nil, ...)`。在全臺地圖鋪「高鐵 台中–彰化」量到（Linux，修之前）：車種 nil、最高速 110 km/h（標準車）、12 節 4,224 人（每節 352）、3D 沒有對到任何車型（`Map3DTrainSet.set(forKey: "", count: 12)` 是 nil，畫成通用車）、路線不是高速線。捷運、輕軌、阿里山林鐵同樣是 nil。

## 改了什麼

- `DemoRealLines.trainType(ofLine:system:)`：高鐵 → 高鐵車（`staff` 的決策 168 規則 7 同時把路線變高速線）；阿里山林鐵 → 林鐵列車；文湖線 → APM；環狀線、機場捷運、三鶯線、台中捷運 → 中運量（B）；台北與高雄其他捷運 → 高運量（A）；淡海、安坑、高雄環狀輕軌 → 輕軌（C）；台鐵與沒列到的系統（海外地圖包）→ nil，照舊是遊戲的第一種車（遊戲沒有台鐵通勤電車的車種）。在售的線與 `RealBranchLine.trainType` 一致（有測試）。有自己車種的年代劇本不供應該車種時退回 nil。
- `DemoRealLines.platformLength`：月台照舊是「節數 + 1」節標準車長，但不短於該車種 `cars` 節的實長。真實車長的世界裡高鐵車一節 25 m，12 節（275 m）停不進原本的 260 m，月台變 300 m；其他系統的月台長度不變。
- 測試：`Tests/GamePresentationTests/DemoRealLinesTrainTypeTests.swift`（高鐵 台中–彰化：車種、300 km/h、960 人、全部在軌道上、高速線、3D 對到 `highSpeed`；板南線 A、安坑輕軌 C、平溪線 nil；各系統對照；月台長度）。

## 還留下的

- **舊存檔裡已經鋪好的線不補。** 不升存檔做得到的兩條路都不好：(1) 讀檔時把車改成高鐵車：舊線的月台是 260 m，12 節高鐵車 275 m 停不下，而且讀檔時改世界不經過指令紀錄；(2) 只在 3D 把 nil 的車畫成高鐵車：車還是 110 km/h、4,224 人，畫面與實際不符。玩家自己補的方法：復原後重鋪，或在路線卡用高鐵車重新配車（月台要先加長）。要替玩家補就得是一個新指令加月台加長，另外派。
- **3D 沒有在 Metal／實機看過**：只在 Linux 確認新鋪的高鐵車對到 `highSpeed` 這個車型鍵。請 Mac session 鋪一次「高鐵 台中–彰化」看一眼車與 300 m 月台。
- 台鐵仍是 nil（標準車、3D 通用車）：遊戲沒有台鐵通勤電車的 `TrainType`（NEXT_PRIORITIES §22.2 的車種工作），有了再接到 `trainType(ofLine:system:)`。
- `DemoRealLines.cars(ofSystem:)` 的節數沒有動（例如環狀線實際 4 節，這裡照台北捷運給 6 節）。
