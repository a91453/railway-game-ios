# 3D 地圖的指北針（決策 269 的「後來」，2026-10-21）

`options.png`：三種畫法在四種底（面板、地圖，淺色、深色）與 64／44／32 點，最後兩格是模糊與灰階（art-style skill 的預覽腳本）。

| 檔 | 畫法 | 結果 |
| --- | --- | --- |
| `a-chosen-light.svg`、`a-chosen-dark.svg` | 淺底圓鈕、藏青外框；針是 MapLibre 指北針的兩個三角形，北紅（`metroRed`）南白，藏青描邊。深色模式換成 `panel` 的深底與淺色外框 | **採用**。灰階下北（深）南（淺）仍分得開，32 點也認得出 |
| `b-with-n.svg` | 同 A，針上方加一個 N | 沒採用：44 點時 N 只有 5 點高，擠在針尖上；北紅南白已經說明方向 |
| `c-arrow.svg` | 藏青實心圓鈕，只有紅色箭頭與白色小尾巴 | 沒採用：在深色地圖上圓鈕和地圖黏在一起（右下兩格），看起來像「導航」而不是指北針 |

App 裡的針是 SwiftUI 的 `Shape`（`Map3DPreviewScreen.swift` 的 `Map3DCompassNeedle`），座標和 `a-chosen-*.svg` 相同；SVG 只是預覽，不放進 Asset Catalog。
