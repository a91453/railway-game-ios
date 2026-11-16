# ROVANIEMI-TWO-LINES

## 進度

- 做了什麼：羅瓦涅米同一局兩條線都能收購（任一順序），決策 [809](../decisions/809.md)。只改 GamePresentation `RealLineLaying`，加 `RovaniemiRailwaysTests.testBothLinesAreBoughtInOneGame`。
- 已驗證：Linux 上相關 7 個測試類別 59 個測試通過；香港六條倒序同一局全買下。
- 下一步：無（PR 等 CI）。

---

- 派工：遊戲規劃，2026-11-16。Session：session_01JMHz9cVYgP3gDY184uKCCQ（雲端，Opus 5.5）。分支 `claude/rovaniemi-two-lines`。決策 809。
- 存檔（107）、golden（77）、SaveFixtures、ReplayFixtures、GameCore：不動。
- 根因：後買那條第一次鋪線時，GameCore 回「並行太近」（KJA→MUL）或「交叉」（MUL→KJA）；只有「交叉」會再試抬高共站。修法：海外的線有共站時，「並行太近」也再試。細節在決策 809。

## 檢查其他有共站的地圖

- 香港：六條出售中的線正序（既有測試）與倒序（這次臨時跑）同一局全部買下，沒有被拒。
- 台灣：不是「一張地圖賣全部的線」，而是圍著一條線開的世界；共站的組合（竹中的六家線與內灣線、淡海輕軌綠山線與藍海線）各有自己的測試（`LiujiaLineTrainsTests` 等），這次沒有另外全買一次。

## 還留下什麼

- `docs/handoff/ROVANIEMI-MAP-2.md` 第 1 點（備用車擋夜車一分鐘）不在這張，屬 DEADLOCK-D1。兩條線同一局跑一天，卡住最長仍是 1 分鐘（與單線相同）。
- 地圖開放與否不在這張（不開）。

## UNVERIFIED

- 預覽工具 `MAP3D_BUY=vr:KJA,vr:MUL` 的畫面沒有重拍；後買那條在羅瓦涅米的月台是高架，3D 的樣子沒看。
- iOS 建置與實機（macOS CI、TestFlight）。
