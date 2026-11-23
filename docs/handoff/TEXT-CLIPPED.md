# TEXT-CLIPPED（AI 試玩員第一批：字被畫面邊緣切掉）

- session：session_01JMHz9Zmbk3a9d5WJUcAJZR，分支 `claude/text-clipped`。
- 存檔、golden、決策都不動。
- 截圖看不到：`ahui-01`、`jie-12` 與 `ui-testers/round1/SUMMARY.md` 不在 `a91453/railway-ui--testers` 的任何分支，也不在 assets-2，只在專案檔案裡。四項都照評分檔的一句描述從程式找原因。

## 做了什麼

| 項目 | 找到的原因 | 修法 | 把握 |
| --- | --- | --- | --- |
| 地圖底部「車站 2」名牌被切 | 2D 地圖的站名永遠畫在站的下方，沒看底部列與畫面下緣 | `MapLabelPlacement.nameOffset`：名牌（加線號徽章）下方放不下就畫到站上方、等候人數的膠囊上面；`MapLabelCanvas` 傳入底部列開始的位置。Linux 測試 `MapLabelPlacementTests.testANameNearTheBottomGoesOverItsStation` | 高（2D） |
| 教學「第 6 步，共 15…」截斷 | 步數和章名在同一列 `lineLimit(1)`，字大時整列一起被截 | 新的 `TutorialProgressLine`：步數優先、不截，章名讓位；輔助使用字級時章名換到下一列。三處（展開卡、收合卡、表單頂端的步驟列）共用 | 高 |
| 車站面板標題被切 | 推測：iPad 與直向時標題在導覽列正中，列高固定，大字級兩行放不下 | `PanelTitlePlacement.place(compactHeight:accessibilitySize:)`：輔助使用字級時一律放到列下方的一列。Linux 測試 `MapFocusTests` | 中（沒看到圖） |
| 開始畫面「新遊戲」卡片下緣被切 | 推測：橫拿大字時卡片剛好停在捲動的折線上，看起來像被切 | 開始畫面的捲動區打開時閃一下捲軸 | 低（沒看到圖） |

## 還留下什麼

- **作者或有截圖的 session 對照 `ahui-01`、`jie-12` 看一次**：車站面板標題與「新遊戲」卡片兩項是推測，若截圖裡是別的原因，照圖再修。
- 3D 地圖（Metal 畫的站名）沒有查，若截圖是 3D 地圖要另開一張。
- 2D 地圖的軌道編號（`drawTrackNumbers`）與泡泡避開站名時，仍以為名牌在站下方；名牌翻到上方只發生在畫面底部，影響小。
- UNVERIFIED：沒有 Simulator，畫面只在 CI 編譯；截圖驗收見 PR。
