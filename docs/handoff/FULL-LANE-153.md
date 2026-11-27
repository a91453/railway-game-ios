# FULL-LANE-153（2026-11-27）

- 派工：協調者（DEBUG-153 壓縮後交回的三項）。雲端 Linux，分支 `claude/project-thread-a4iwlb`。
- 對象：main `550e1377`（153 加上 #2825）手動 full lane，run 46018530736。DEBUG-153 收了 build job 的語言測試（#2835）；這裡是其餘三個 job。
- GameCore、存檔版本、golden schema、決策號都不動。三項都**不是 App 的 bug**。

## second job：RealWorldMapUITests 三項（測試過時，改了）

三支都從開始畫面走「新遊戲 → 真實地圖 → 台北 → Build Here」（`startARealWorldGameFromTaipei`），都是大字、手機橫拿。11-27 凌晨 `d5572844` 的 full lane 這三支都過。

- `testThePlatformConfirmStaysAboveTheDockUnderATallBanner`、`testTheUpgradePillStaysBesideTheTrackCard`（AccessibilityXL）：台北那列停在 y 179，正好在搜尋欄底下（iOS 26 的玻璃導覽列，清單捲到它下面）。點台北點到搜尋欄，鍵盤出來、Build Here 收起來，`realWorld.start` 找不到。失敗錄影 135～143 秒看得到。好的那晚台北停在 y 282。
- `testTheRealWorldMapIsReachedWithTheLargestText`（AccessibilityXXXL）：40 次拖曳都沒捲到台北，錄影最後還在「整張地圖」的說明裡。好的那晚用了 38 次（只差 2 次）；#2824 把福岡地圖的說明加長（四縣、新幹線、特急），最大字時多好幾行，就不夠了。
- 改：`scrollUntilShown` 的「看得到」範圍避開搜尋欄（搜尋欄和清單重疊時，列的中點要在搜尋欄下緣 8 pt 以下）；`startARealWorldGameFromTaipei` 捲地點清單最多 90 次。

## lessons job：Feature284To286UITests 四項（環境，暖機時限改 8 分）

- 四支都在 `launch` 失敗：「Application ... does not have a process ID」。App 其實有起來：xcresult 裡 App 的輸出每 2 秒一行 `action frames 120 in 2000 ms`，是 XCTest 沒接上（log 裡沒有 `Setting up automation session`）。第 4 支的第二次和之後的測試都正常。
- 前面的「Warm up the app's first launch」在 second、lessons 兩個 job 都跑滿 5 分被停（second 的安裝加啟動用了 4 分 12 秒；好的那晚 3 分 15 秒）。`ios-build.yml` 的註解記過同樣的事：暖機被停在半路、第一個類別（就是 Feature284To286UITests）接著起不來。
- 改：兩處暖機的 `timeout-minutes` 5 → 8。仍是 `continue-on-error`，只在 full lane 跑（PR 不跑），快的晚上不多花時間。UNVERIFIED：要看之後幾晚 lessons job 的第一個類別。

## iPad：testLargeTextTutorialNavigation、testTheLineStepLeavesTheLinesPanelUsable（等 #2833）

- 550e1377 早於 #2833（`9c0c5c4`）。這晚 iPad job 有 103 次「Wait for com.apple.springboard to idle」，`testLargeTextTutorialNavigation` 第一次 `dock.build` 點不到、第二次過；`testTheLineStepLeavesTheLinesPanelUsable` 兩次都紅（Lines 被蓋住的判斷逾時、之後關不掉 App）。和 DEBUG-153「iPad 變慢」同一個樣子：前一支 `testEnglishTutorialNavigation` 結束時先關 App 再轉方向，轉到主畫面。#2833 已改成先轉再關。
- 沒改測試。看 `9c0c5c4` 之後第一次 full lane 的 iPad job：springboard 的 60 秒等待還多不多、這兩支綠不綠。

## UNVERIFIED

- RealWorldMapUITests 三支：這個 PR 用 `ios-build.yml` 的 `only_testing` 跑過才算（結果補在 PR）。
- 暖機 8 分、iPad 兩支：只能看之後的 full lane。
