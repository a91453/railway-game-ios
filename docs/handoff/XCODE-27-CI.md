# XCODE-27-CI：CI 與發版換 Xcode 27（2026-11-18 交接）

PR #2453（分支 `claude/project-thread-uiu8hg`，草稿，**還不能合**），決策 857。原串壓縮過一次，照規則不再接新工作，剩下的交下一個 session。

## 現況

- 做完：八個 workflow 改 `runs-on: xcode-27`、`.github/actions/select-xcode`（Xcode 27.2）、`.github/scripts/select-simulator.py`、`.github/actionlint.yaml`、`testflight.yml` 的檢查改 27 以上、文件。App 編得過、沒有新警告；未簽署封存綠；PR 的 iPhone gate 測試在 f650b28 綠。
- 沒做完：**iOS 27.2 上的 full lane 還有 14 支 UI 測試紅**（下表）。決策 857 §6：full lane 綠才合。
- `main` 照舊用 Xcode 26 發版，期限 2027 年 4 月，不急。

## full lane 的紅單（run 44299210747，head f650b28，2026-11-18）

| job | 測試 | 訊息 | 分類 |
| --- | --- | --- | --- |
| second | `SettingsUITests` 7 支（`testTheGameMenuOpensTheProblemReport`、`…OpensTheSameSettings`、`…OpensSettingsWithTheLinesPanelOpen`、`testTheGameMenusReportCanAttachTheSaveAndCommands`、`testTheGameMenusSettingsIsInReachOnAPhoneOnItsSide`、`testTheMapAndMenuShortcutsOpenTheirScreens`、`testTheIdleModePutsTheControlsAwayUntilATap`） | `Missing menu.settings`／`menu.report`／`menu.postcard`／`menu.ambient`（:303、:326） | A |
| lessons | `Feature284To286UITests.testTheSightShowsTheSightseeingTrainBonus` | `Missing "menu.more" Button`（:183） | A |
| iPad | `TutorialUITests.testTheTutorialStartsWithoutADataLayer` | `No visible tutorial menu action`（:624） | A（多半） |
| iPad | `TutorialUITests.testTheLineStepLeavesTheLinesPanelUsable` | `The Lines button is covered: button (83,941,48,52), card (inf,inf,0,0), folded (143,945,272,44)`（:202） | 未查 |
| build | `ShellLayoutUITests.testTheToolsColumnsButtonsAreOneSize` | `controls.toggle` 寬 56，其餘 48（ToolbarSmokeTests.swift:1047） | 未查 |
| build | `MapButtonsUITests.testThePhonesLayerStripKeepsClearOfTheCard` | `"map.quickLayer.strip" StaticText did not settle`（:437） | 未查 |
| build | `MapInteractionTests.testConstructionHUDAppearsDuringTrackPreview` | `MapConstructionHUD must appear when preview is active`（:906） | 未查 |
| build | `MapInteractionTests.testTheNewLinesCheckIsClearOfTheStationPairDrawer` | `The two stations are compared`（:1761） | 未查 |

其餘全過：build job 87 支裡 4 紅、second 38 支裡 7 紅、lessons 18 支裡 1 紅、iPad 9 支裡 2 紅。兩個 job 的「Warm up the app's first launch」超過 5 分鐘（`continue-on-error`，不影響結果，但 27.2 的第一次啟動比 26 慢，值得看一眼）。

**分類 A（原生選單丟識別碼，已知修法）**：iOS 27.2 的選單裡，`ControlGroup` 內與第二層 `Menu` 內的項目只剩標籤、`accessibilityIdentifier` 是空的。改用 `app.menuItems("menu.xxx", label: 語言對應的標籤開頭)`（`RailwayGameApp/UITests/ToolbarSmokeTests.swift`），`TutorialUITests` 與 `HUDAlignmentUITests` 已是這樣寫。還沒改、照同一個原因會紅的檔：`SettingsUITests.swift`（`tapHittable`、`openSettingsFromTheGameMenu`）、`Feature284To286UITests.swift`（`menu.tourism`、`menu.more`）、`PromoMaterialTests.swift`（`openFromGameMenu`、`menu.more`）、`WebsiteScreenshotTests.swift`（很多處；它只在 `website-screenshots.yml` 跑，不在 full lane）。選單結構在 `RailwayGameApp/Views/HUDView.swift`。

**「未查」的五支**：沒讀過結果包，不知道是 iOS 27.2 的版面差異（例如 `controls.toggle` 寬 56）、另一種輔助使用樹差異（另一個已知的是 `hudFrameMark` 擋住點擊檢查，已用 `.accessibilitySortPriority(1)` 修），還是本來就不穩。先看同一支在 `main` 最近的 full lane（Xcode 26）是不是綠的，再在 iOS 27.2 上重現。

## 接手怎麼做

1. 讀 #2118、決策 857、這個檔；分支接著用（或併 `origin/main` 後再推）。
2. 先改分類 A（純測試檔），再查五支未查的。不跳過、不停用任何測試。
3. 一次推上去，用 `ios-build.yml` 的 `only_testing` 驗紅的那幾支，最後手動跑一次 full lane（`workflow_dispatch`，選分支；約 1.5 小時，佔 3 台 macOS runner）。
4. full lane 與 PR 的 CI 都綠才合 #2453，合後在 #2118 釋放決策 857 的登記，並請協調者更新記憶（CI 改用 `xcode-27`）。
5. f650b28 那次 PR run 的 iPad job 是被取消的（run 44292383881，不是測試紅也不是逾時），gate 因此紅；推新 commit 後會重跑。

## 在作者的 Mac 上重現時

Mac 有 Xcode 27.2 與 iOS 27.2 的 Simulator。2026-11-18 連跑 UI 測試把負載衝到 241，所以：一次一台 Simulator、一次一個 `xcodebuild`，加 `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -jobs 4`、前面 `nice -n 15`，每輪跑完關掉 Simulator，只跑必要的幾支。那台 Mac 的權限規則擋 `xcrun simctl shutdown all`，要逐台 `shutdown <UDID>`。

## 沒驗證的

- 實機上的外觀與手感（iOS 27 SDK 編出來的畫面要在 TestFlight 版再看一次）。
- 真正的 `testflight.yml`（簽署、上傳）還沒用 Xcode 27 跑過。

## 2026-11-18 晚：接手後（分支 `claude/project-thread-mszmc5`，取代 #2453 的分支）

14 支紅單都已用 `only_testing` 在 iOS 27.2 上跑綠（iPhone 與 iPad）：

- **原生選單丟識別碼（9 支）**：`SettingsUITests`（`tapHittable(_:label:in:)`、`openSettingsFromTheGameMenu`）、`Feature284To286UITests` 改用 `menuItems(_:label:)`。`PromoMaterialTests`、`WebsiteScreenshotTests` 還是舊寫法（不在 full lane，失敗時只少截圖），下次跑截圖前要改。
- **`MapButtonsUITests` 圖層條**：`hudFrameMark` 排在後面後（f650b28），標記本身不再 hittable，改 `waitUntilStill()`。
- **`ShellLayoutUITests` 欄寬**：iOS 27 單獨放在玻璃 tile 裡的按鈕（細節切換鈕、建設中的建設與完成）回報整塊 tile 的 frame（56×48）；測試用 `touchFrame(_:)` 量 tile 裡的觸控範圍。
- **iPad `TutorialUITests` 資料圖層**：示範鋪真實路線時速度鈕停用，27.2 的 iPad 超過 5 秒，暫停鈕改等 30 秒。另一支（Lines 按鈕被蓋）第二輪就過了，沒改。
- **`MapInteractionTests` 建線預覽 HUD**：第二輪就過了，沒改。
- **`MapInteractionTests` 新路線第二站（App 修正）**：手機橫放、上方有訊息時，新路線的 ✕✓ 上下都放不下，蓋在起點站與下一站上，點下一站按到 ✕。`MapBuildConfirm.siteObstacles` 讓 `.line`／`.addStop` 的按鈕避開它所在的站（同決策 744 的做法）。還沒在實機看過。
- 失敗時用 `XCUIApplication.logTree(_:)` 把無障礙樹印進日誌；觸控落在哪個 view 在 `ui-*-trace` artifact（API zip 讀得到）。

還在等：最後 head 的手動 full lane。前一輪 full lane（e6eabfc）`second` job 有兩支 `HUDAlignmentUITests` 紅，都是模擬器慢（第一支 App 啟動 225 秒沒有 process、第二支 UI 查詢逾時），不是測試邏輯；若再出現，考慮在 `ios-build.yml` 加長暖機或重試第一次啟動。
