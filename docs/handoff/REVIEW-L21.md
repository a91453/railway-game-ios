# REVIEW-L21（2026-11-14）

- 派工：遊戲規劃（專案討論串「審查今天合併的 PR」）。雲端 Linux，分支 `claude/project-thread-1d1ves`。#2118 留言 6879513880。
- 存檔版本、決策號、golden schema：都沒用。只加兩個文件，`Sources/`、測試、fixtures 沒動。
- 報告：`docs/research/REVIEW_L21_2026-11-14.md`。範圍 `d64cc2e..11dca65`（#2131–#2210，約 60 個改程式的 PR）。

## 結果

- P1：0。P2：1。P3：7。存檔 v97–v101 相容沒有問題。
- 下一輪 L22 從 `11dca65` 之後合併的 PR 起數（#2211 只改文件，不算）。

## 還留下什麼（都還沒有人做，請規劃派）

1. **P2-1**（#2201）：回主畫面背景存檔失敗、玩家已開新局時，離開的那一局被丟掉；新局被「存檔中」蓋住、回主畫面按了沒反應。
   GamePresentation，Linux 可測（`ReturnToStartInBackgroundTests` 加一條），雲端可做。bug，排在功能前。
2. **P3-1、P3-2**（#2190 月台清單在號誌關掉時）：交給 PB-3 一起做。
3. **P3-3、P3-4、P3-5、P3-7**（效能，未量）：交給效能那串，用最重的存檔（香港全線、30 MB 台灣）量一次再決定。
4. **P3-6**（文件：版本 96 的註解）：下一個碰 `SavedGame.swift` 或 `DemandEvents.swift` 的 PR 順手改。

## UNVERIFIED

- 本機只跑了 `swift build --build-tests` 與一個沒有提交的探測測試（P2-1 的輸出在報告裡）。
- 其餘發現都是讀程式；iOS、Metal、iCloud、實機都沒有。
