# FULLLANE-135：135 full lane 雙線月台那支 UI 測試紅

- 派工：遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed（#2118，2026-11-16），bug。
- session：session_01JMHz9Z4h7F9NAPTXGX7g3w（雲端），分支 `claude/fulllane-135`。
- 號碼：決策、存檔、golden 都不動。

## 做了什麼

- 紅的：`Feature284To286UITests.testConfirmingADoubleTrackPlatformShowsBothPlatformsAtTheStation`，`Cannot reveal "station.platformTrack.0"`（main `89ed04b`，`ios-build.yml` run 43936559208，lessons 組）。
- 判斷：**(b) 測試壞了，畫面沒壞**。lessons 組 xcresult 的錄影（`kXCTAttachmentScreenRecording`）裡，車站面板有開（全螢幕，決策 746），「車站現況」有第 1、2 月台；拖了三次以後，「第 1 月台：加月台軌道」這一列就停在面板標題「海岸」底下，只差一點點沒露出來。後面 37 次短拖都從 (44, 181) 開始，這個點在動態島上（手機橫放時動態島在左邊，約 x 11–48、y 138–264）。從動態島開始的拖曳交給系統，App 收不到，清單就一直不動。
- 修法：`ToolbarSmokeTests.swift` 的 `clearOfScreenEdges` 從離螢幕邊 44 pt 改成 60 pt。60 pt 已經離開動態島，也還在列表卡片（約 x 78）的左邊。所有用它的拖曳一起改（LessonUITests、LineDraftSummaryUITests、WebsiteScreenshotTests、`dragUntilWhollyOnScreen`）。
- 玩家不會碰到：手指在面板任何地方都能捲，那一列也在。
- 上一次 full lane（`effa45a4`）綠的原因是推測，沒有驗證：只有長拖停下時那一列落在可見範圍上方，才需要往下的短拖（從高度的 0.45 開始，剛好在動態島上）。落在下方時，短拖從 0.75 開始，離開了動態島，所以能過。
- 同一次 full lane 的 second 組另有 2 支紅：`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`（`"map.build.confirm" Button did not settle`）與 `testTheUpgradePillStaysBesideTheTrackCard`（`The pill's ✓ cannot be tapped`）。和鋪軌卡片改版（#2302、#2309）有關，**不在這張工單**，已在 #2118 回報給規劃。

## 驗證

- VERIFIED（GitHub Actions，macOS，head `ebf615b`）：`ios-build.yml` 用 `only_testing: Feature284To286UITests` 手動跑（run 43947583556），整個 class 5 支全過，雙線月台那支 74.6 秒。拖曳的 x 已經是 60。PR #2320 的 `ci.yml`（43947589272）與 iOS gate（43947589591）也都綠。
- 這次手動跑，三次長拖就把那一列帶進可見範圍，沒有用到往下的短拖。所以「短拖從動態島開始」這條路徑沒有被再跑一次；修正是依 135 的錄影與座標推出來的。下一次 full lane 若又紅在 `Cannot reveal`，先看錄影裡拖曳的起點。
- 剩下的：無。second 組的 2 支 `RealWorldMapUITests` 紅由規劃另派。
