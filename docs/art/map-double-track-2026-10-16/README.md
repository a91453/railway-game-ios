# 複線的路線色帶（決策 249）

台鐵示範，宜蘭到二結之間，靠蘭陽溪的一段，iPhone 橫向（844×390 pt）。這些圖不是 App 截圖：先從 Linux 測試把 `LineMap` 的結果輸出成資料，再照 `MapArt.drawLines` 的寬度與畫法畫成 SVG（路基、中心線、色帶、箭頭；沒有徽章、車站與地面）。R 是 16 m 在畫面上的點數，手機預設是 32。

| 檔案 | 內容 |
| --- | --- |
| `before-default.png`、`after-default.png` | 預設縮放（R=32），改之前與之後 |
| `before-overview.png`、`after-overview.png` | 縮小（R=14，概覽） |
| `before-near.png`、`after-near.png` | 放大（R=48，真實寬度） |
| `after-colourblind.png` | 之後，色盲友善色票（決策 216） |
| `altB-single.png` | 沒選的 B：每條軌只畫一條代表色 |
| `altC-cap3.png` | 沒選的 C：最多三條，其餘用「+n」（這張圖沒畫出「+n」牌） |
