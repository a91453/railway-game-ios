# 3D 地圖的接地陰影（2026-10-15）

ARCHITECTURE 決策 232。每張圖上半是決策 231（有貼圖、沒有陰影），下半加上接地陰影。

- 軟體算圖：場景從 Swift 輸出，WebGL 照 `Map3DShaders.metal` 的同一個算式在 Chromium 裡畫，光線是遊戲的下午兩點。
- **不是 Metal、不是 iPhone 的畫面**（UNVERIFIED），要等 TestFlight。

| 圖 | 看什麼 |
| --- | --- |
| `flats.jpg` | 公寓與透天厝的街廓：腳下一圈柔和的暗影，不再像浮在地上 |
| `houses.jpg` | 一個街廓的兩排透天厝，最近的 90 m |
| `viaduct.jpg` | 示範地圖：高架下一條影子，塔樓裙樓腳下的暗影 |
| `towers.jpg` | 鎮中心的塔樓，300 m |

列車的影子在預覽裡沒有畫（預覽沒有列車），由 `Map3DShadowTests` 檢查。
