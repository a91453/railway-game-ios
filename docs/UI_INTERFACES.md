# 介面規格：教學與地圖相機（第 0 步）

2026-10-03 定。C5（教學）與 E1（大地圖）的畫面要接兩個介面：教學的資料與地圖的相機。先把這兩個介面定下來，Claude Code 與其他代理（Codex，見 [`AGENTS.md`](../AGENTS.md)）就能同時做：

| 工作 | 誰 | 接的介面 |
| --- | --- | --- |
| CX-6：開始畫面、示範地圖、存檔流程的 UI 測試 | Codex | 不依賴這兩個介面 |
| CX-5：教學畫面（高亮框、步驟卡、按鈕） | Codex | [教學](#1-教學gamepresentation)、[識別碼](#2-識別碼tutorialtarget)、[App 端的標記](#3-app-端的標記與讀法) |
| CX-4：大地圖繪製（只畫畫面內、依縮放顯示細節、雙指縮放） | Codex | [相機](#4-相機gamepresentation) |
| 經濟平衡核對；C5 的真正步驟與判斷；E1 的 16 公里地圖；E2 | Claude Code | — |

介面之後如果要改，由 Claude Code 連同其他代理已經寫好的畫面一起改，不讓它們重做。

## 1. 教學（GamePresentation）

檔案：`Sources/GamePresentation/Tutorial.swift`、`Sources/GamePresentation/TutorialSession.swift`；測試：`Tests/GamePresentationTests/TutorialSessionTests.swift`。

照 `Ci/` 的地鐵導覽（`TUTORIAL_STEPS`、`startTutorial`、`showTutorialStep`、`_tutorialOnAction`、`dismissTutorial`）：遊戲畫面上一張步驟卡，有標題與說明，框出這一步講的控制項，按鈕是上一步、下一步（最後一步是「完成」）與略過。教學只是畫面狀態：不存檔，GameCore 不知道它。

### 畫面讀的資料

| 要顯示的 | 讀法 |
| --- | --- |
| 有沒有教學 | `session.tutorial`（`nil` 是沒有） |
| 第幾步、共幾步 | `tutorial.index`（從 0 起）、`tutorial.steps.count` |
| 標題與說明 | `tutorial.step.title(in: session.language)`、`tutorial.step.body(in: session.language)`；純文字，沒有 HTML |
| 要框出的控制項 | `tutorial.step.targets`（`[TutorialTarget]`）；卡片放在第一個旁邊，沒有就放畫面中央 |
| 這一步做完了沒 | `session.isTutorialStepDone`；沒做完時「下一步」停用（參考的 `_tutorialStepActionDone`） |
| 要不要顯示「上一步」 | `!tutorial.isFirstStep`（參考在第一步隱藏 `tutorial-prev`） |
| 「下一步」要不要寫「完成」 | `tutorial.isLastStep`（參考的 `common.done`） |
| 這一步要玩家做什麼 | `tutorial.step.goal`（`TutorialGoal`）；需要時可以顯示「做完這一步才能繼續」 |

### 按鈕呼叫的方法

| 按鈕 | 方法 |
| --- | --- |
| 上一步 | `session.showPreviousTutorialStep()`：第一步時不動 |
| 下一步／完成 | `session.showNextTutorialStep()`：沒做完時不動；最後一步結束教學 |
| 略過 | `session.skipTutorial()` |
| 遊戲選單的「教學」（從頭開始） | `session.startTutorial()` |
| 開始畫面的教學入口 | `launcher.startTutorial()`：開一局新遊戲，教學在第一步；和「新遊戲」一樣先保留自動存檔 |

這些方法都不改世界。按鈕的文字（上一步、下一步、完成、略過、教學）屬於 App 的 String Catalog，由 CX-5 加，附繁體中文（台灣用語）。

### 示範步驟

`Tutorial.demoSteps` 有三步，讓畫面有東西可以畫；C5 換成真正的步驟。

| `id` | 框出 | 做完的條件（`goal`） |
| --- | --- | --- |
| `demo.networkTool` | `tool.network` | 選了路網工具（`.chooseTool(.network)`） |
| `demo.buildTrack` | `map`、`panel.action` | 這一步出現之後蓋了新的軌段（`.buildTrack`） |
| `demo.end` | 沒有：卡片在畫面中央 | 讀完就好（`.read`） |

做完了沒，是由世界與 session 的**現在**推導的，不另外記錄：例如選了路網工具又換回選取，第一步就又變成沒做完。

C5 會換成真正的步驟（`Ci/` 的 `tutorial.step.0`–`11` 的內容步驟，改寫成觸控與這個 App 的工具），加新的 `TutorialGoal` 與 `TutorialTarget`（只增加，不改既有的名稱），需要時讓步驟打開面板（參考的 `openUI`）。畫面只要寫成通用的（不寫死步驟數、`id` 或某個目標），就不用跟著改。

## 2. 識別碼（`TutorialTarget`）

每個 raw value 是控制項的穩定名稱：各語言都一樣，版本之間不改。App 用 `.tutorialTarget(_:)` 標記控制項（第 0 步已經標好）。同一個控制項若也有 UI 測試用的 accessibility identifier，兩邊同名；目前是工具按鈕的 `tool.*`。

| raw value | case | 控制項 | 標記的位置 |
| --- | --- | --- | --- |
| `tool.select` | `selectTool` | 工具列的「選取」 | `ControlPanel.swift` 的 `ToolPicker` |
| `tool.network` | `networkTool` | 工具列的「路網」 | 同上 |
| `tool.train` | `trainTool` | 工具列的「列車」 | 同上 |
| `network.modes` | `networkModes` | 路網工具的模式：鋪設、月台、拆除 | `NetworkControls.swift` |
| `panel.action` | `actionButton` | 套用工具的按鈕：鋪設軌道、設置月台、拆除軌道、放置或派送列車 | `ControlPanel.swift` 的 `ActionButton` |
| `map` | `map` | 地圖 | `ContentView.swift` 的 `map` |
| `map.zoom` | `zoomControls` | 地圖的縮放按鈕 | `MapView.swift` 的 `zoomControls`（CX-4 改寫時保留） |
| `hud.lines` | `linesButton` | 打開路線面板的按鈕 | `HUDView.swift` |
| `hud.speed` | `speedControl` | 暫停／播放與速度選單（參考的 `#bottombar`） | `HUDView.swift` 的 `SpeedControl` |
| `hud.menu` | `gameMenu` | 遊戲選單：存檔、匯出、回到開始畫面 | `HUDView.swift` |

新的識別碼由 Claude Code 加：GamePresentation 的 enum 與 App 上的標記一起加。

## 3. App 端的標記與讀法

檔案：`RailwayGameApp/Views/TutorialTargets.swift`。

- `TutorialTargetBounds`：`PreferenceKey`，值是 `[TutorialTarget: TutorialTargetAnchor]`。`TutorialTargetAnchor` 是控制項的範圍（`bounds`），加上它所在的每個捲動區的範圍（`clips`）；`visibleFrame(in:viewport:)` 取畫面上看得到的部分，捲出捲動區的控制項就沒有。
- `tutorialTarget(_:)`：`View` 的 modifier，把這個 view 的範圍以它的識別碼回報上去；傳 `nil` 就不標記。
- `tutorialClip()`：掛在 `ScrollView` 上，裡面標記的控制項只算它露出來的部分（iPad 直向的控制面板、橫向的側欄）。

CX-5 的覆蓋層這樣讀（示意）：

```swift
.overlayPreferenceValue(TutorialTargetBounds.self) { anchors in
    GeometryReader { proxy in
        if let tutorial = session.tutorial {
            let viewport = CGRect(origin: .zero, size: proxy.size)
            let frames = tutorial.step.targets.compactMap { anchors[$0]?.visibleFrame(in: proxy, viewport: viewport) }
            // 框出 frames，卡片放在 frames.first 旁邊；沒有就放中央。
        }
    }
}
```

覆蓋層要注意：

- **不能擋住操作**：玩家要做了才能前進，所以被框出的控制項與地圖都要能點；只有卡片接收觸控（其他部分 `allowsHitTesting(false)`）。
- **找不到的目標不畫框**：目前的版面沒有那個控制項（例如 iPhone 與 iPad 的排法不同）時就略過；全部找不到時，卡片放畫面中央。
- **preference 不會離開 sheet**：路線面板、車站面板等 sheet 裡的控制項，要在那個 sheet 裡也掛覆蓋層才找得到。第 0 步的識別碼都在主畫面；C5 需要面板裡的目標時，由 Claude Code 一起定。
- **HUD 有兩種排法**：`HUDView` 用 `ViewThatFits` 在一排與兩排之間選，兩種都有標記。Simulator 上框的位置不對時，告訴 Claude Code（Linux 上無法驗證）。
- VoiceOver：步驟換了要能讀到卡片（例如 `AccessibilityNotification.Announcement` 或把焦點移到卡片）。

## 4. 相機（GamePresentation）

檔案：`Sources/GamePresentation/MapCamera.swift`；測試：`Tests/GamePresentationTests/MapCameraTests.swift`。

兩份參考用的都是網頁地圖的相機（MapLibre、高德）：一個中心點加一個縮放，用 `getBounds()` 只處理畫面內的東西（`Railway/` 的 `map3d.js` 還在外面多留一點邊界），依縮放決定畫多少細節（`Railway/` 的 `getZoom() >= 14`、`Ci/` 的 `MAP_STATION_PLATFORM_MIN_ZOOM = 16`）。這裡照同樣的分工。

座標：

- **世界座標**：`WorldCoordinate`、`PlanPoint`，整數，1 單位 = 1/64 公尺，一格 1024 單位，x 向東、y 向南。只有它會送進 `GameWorld`。
- **螢幕座標**：`ScreenPoint`，地圖 view 左上角起算的點（points），x 向右、y 向下。`ScreenSize` 是地圖 view 的大小。
- **`WorldRegion`**：俯視的世界矩形（`Double`），只用來決定畫什麼。

### `MapProjection`：畫面只依賴它

| 成員 | 用途 |
| --- | --- |
| `screenPoint(of:)`（`WorldCoordinate` 或 `PlanPoint`）、`screenPoint(worldX:worldY:)` | 世界 → 螢幕；高度不畫 |
| `worldPosition(at:)` | 螢幕 → 世界，不捨入 |
| `planPoint(at:)` | 螢幕 → 世界，捨入成整數，送 `GameWorld` 指令；取代 `MapScale.worldPoint` |
| `worldDistance(_:)` | 手指的觸控半徑換成世界單位；取代 `MapScale.worldDistance` |
| `visibleRegion` | 畫面看得到的範圍：只畫和它相交的東西 |
| `pointsPerUnit`、`tileSize` | 目前的縮放；原本依 `tileSize` 算的線寬、圓點大小照舊 |
| `detail` | 細節等級（`MapDetail`，由 `MapScale.detail(forTileSize:)` 決定） |

### `PlanCamera`：空白模式的相機

俯視、北朝上。只是畫面狀態，不存檔。

| 成員 | 用途 |
| --- | --- |
| `PlanCamera(map:viewport:)` | 第一次排版時建立：手機每格 `compactSize`（32 點）、從地圖西北角開始；iPad 整張地圖置中（和現在一樣） |
| `resized(to:)` | 地圖 view 的大小改變時（旋轉、分割畫面）：保留中心與縮放，超出範圍就收回 |
| `zoomedIn()`、`zoomedOut()`、`canZoomIn`、`canZoomOut` | 縮放按鈕：每次 8 點，以畫面中央為準 |
| `zoomed(by:around:)` | 雙指縮放：用手勢開始時的相機、目前的倍率與手指一開始的位置；手指下的點不動 |
| `panned(byX:y:)` | 拖曳：用手勢開始時的相機與目前的位移；手指下的點跟著手指，到地圖邊緣停住，整張地圖放得下的方向置中 |
| `centered(on:)` | 把某一點移到畫面中央（例如選到的車站），到邊緣停住 |
| `centerX`、`centerY`、`viewport`、`mapRegion` | 唯讀 |

**目前是固定比例的版本**：縮放範圍與步長照 `MapScale`（每格最多 64 點；最少到整張地圖放得下，但不小於必要；按鈕每次 8 點）。地圖西北角對齊畫面左上角時，`screenPoint(of:)`、`planPoint(at:)`、`worldDistance(_:)` 和現在的 `MapScale.center(of:tileSize:)`、`MapScale.worldPoint`、`MapScale.worldDistance` 結果相同（測試釘住），所以換成相機時畫面不會跳。E1 放大地圖時可能調整縮放範圍，介面不變。

### CX-4 怎麼接

- **繪製收 `some MapProjection`**：`TileArt` 的函式改收 `some MapProjection`，不要收 `PlanCamera`。E2 的實景模式會用 MapKit 的相機實作同一個 protocol，畫面不用重寫。MapKit 的相機可以旋轉與傾斜，所以每個點都用 `screenPoint` 換算，不要假設整個畫面同一個比例、也不要用位移量自己推。
- **只畫畫面內**：路網的邊用 `WorldRegion(enclosing: geometry.points)` 和 `visibleRegion.expanded(by:)` 比，相交才畫；車站、月台、列車同理。
- **相機是 view 的狀態**：地圖 view 用 `@State` 保存 `PlanCamera?`，在 `GeometryReader` 第一次拿到大小時建立，大小改變時 `resized(to:)`。不放進 `GameSession`，也不放進 GameCore。
- **點擊**：`session.tapMap(at: camera.planPoint(at: location), reach: camera.worldDistance(NetworkBuilding.touchRadius))`，路網工具用 `tapNetwork`，和現在一樣。
- **縮放按鈕保留**（VoiceOver、沒辦法用兩指時），並保留 `.tutorialTarget(.zoomControls)`。
- **細節等級**：現在的 `MapDetail` 有 `overview` 與 `full` 兩級。需要更多級時，CX-4 可以改 `MapScale.swift` 的 `MapDetail`、`detail(forTileSize:)` 與 `MapScaleTests`（只影響呈現，不影響模擬）。

## 5. 檔案歸屬與合併

| 誰 | 改這些 | 不改這些 |
| --- | --- | --- |
| CX-4 | `MapView.swift`、`TileArt.swift`、`NetworkOverview.swift`；需要時 `MapScale.swift` 的細節等級與 `MapScaleTests.swift` | 相機與教學的介面、`.tutorialTarget` 標記 |
| CX-5 | 新增自己的教學檔案（例如 `RailwayGameApp/Views/TutorialOverlay.swift`）；`ContentView.swift` 只加一行掛上覆蓋層；開始畫面加教學入口（`launcher.startTutorial()`）；遊戲選單加「教學」（`session.startTutorial()`）；自己的 String Catalog 字串 | 教學的介面（`Tutorial.swift`、`TutorialSession.swift`、`TutorialTargets.swift`）、其他畫面上的標記 |
| CX-6 | 開始畫面與遊戲選單的識別碼、UI 測試 | `.tutorialTarget` 標記 |
| Claude Code | 介面（`MapCamera.swift`、`Tutorial.swift`、`TutorialSession.swift`、`TutorialTargets.swift`）與識別碼；C5 的步驟與判斷；E1、E2 的 GameCore、golden 與存檔 | — |

- 某個 PR 需要改介面時，在 PR 說明，由 Claude Code 改。
- CX-5 與 CX-6 都會碰開始畫面與遊戲選單：先合併 CX-6，CX-5 再接上，衝突會很小。
- 每個 PR 都會改 `RailwayGameApp/RailwayGame.xcodeproj`：合併或 rebase 時不手動合併，一律用固定版本的 XcodeGen 重新產生（見 [`CLAUDE.md`](../CLAUDE.md)）。

## 6. 參考對照

| 參考 | 這裡 |
| --- | --- |
| `Ci/` `TUTORIAL_STEPS[i].target`、`targets`（CSS selector） | `TutorialStep.targets`、`TutorialTarget` |
| `Ci/` `title`、`body`（`tutorialStepText`，翻譯鍵 `tutorial.step.<i>.title`／`.body`） | `TutorialStep.title(in:)`、`body(in:)` |
| `Ci/` `startTutorial(force)` | `GameSession.startTutorial()`、`GameLauncher.startTutorial()` |
| `Ci/` `showTutorialStep(i)`：第一步隱藏 `tutorial-prev`，最後一步顯示 `common.done` | `showPreviousTutorialStep()`、`showNextTutorialStep()`、`isFirstStep`、`isLastStep` |
| `Ci/` `_tutorialStepDoneAction`、`_tutorialOnAction(action)`、`_tutorialStepActionDone` | `TutorialGoal`、`isTutorialStepDone` |
| `Ci/` `dismissTutorial(skip)` | `skipTutorial()`；最後一步的「完成」 |
| `Ci/` 卡片位置（`getBoundingClientRect`，目標下方或上方 12px，放不下就置中） | CX-5 的覆蓋層 |
| `Railway/` `map.getBounds()`，`map3d.js` 的邊界 `margin` | `visibleRegion`、`WorldRegion.expanded(by:)` |
| `Railway/` `getZoom() >= 14`、`Ci/` `MAP_STATION_PLATFORM_MIN_ZOOM` | `detail`（`MapScale.detail(forTileSize:)`） |
| MapLibre `project`／`unproject` | `screenPoint(of:)`／`worldPosition(at:)`、`planPoint(at:)` |
| MapLibre `getCenter`、`flyTo({center, zoom})` | `centerX`、`centerY`、`centered(on:)`、`zoomed(by:around:)` |
| `Railway/railway_game_reference_clean/web_runtime/touch_pinch_zoom.js`：兩指的距離每變 5% 縮放一格，以兩指的中點為準 | `zoomed(by:around:)`：倍率連續，手指下的點不動（CX-4 可以照它把一格的縮放換成倍率） |

比例：世界座標照舊是 1/64 公尺、一格 1024 單位。相機的 `Double` 只留在畫面，送回 GameCore 前捨入成整數（`planPoint(at:)`、`worldDistance(_:)`，並限制在 `WorldCoordinate.limit` 內）。

參考沒有、這裡自己定的：

- **做了才前進**由狀態推導：參考的快照裡 `_tutorialStepDoneAction` 從來沒有被設定，只留下四個動作名稱（`confirmLine`、`confirmCreateLine`、`adjLineInfoCap`、`speedOrPause`）；ROADMAP 的 C5 要求由世界狀態推導，在 Linux 上可以測。
- **地圖邊緣**：參考是沒有邊界的世界地圖；這裡拖曳停在地圖邊緣，整張地圖放得下的方向置中（和原本可捲動的地圖一樣）。
- **沒有大小的 view**（第一次排版之前）視為 1 × 1 點，縮放保持正數。
- 參考的 `metrobuilder_tutorial_done`（看過就不再自動開啟）、`openUI`（步驟打開面板）、`cardPosition` 還沒有，C5 視需要加。
