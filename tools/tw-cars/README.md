# 台灣街上的汽車（決策 838）

3D 地圖台灣（與香港、羅瓦涅米）街上的轎車、休旅車、廂型車，與台灣的黃色計程車。原件是 Kenney Car Kit 的四台車（CC0），在作者的參考庫 `a91453/railway-reference-private` 的
`Railway/town-scene-reference-clean/source/assets/car-kit/Models/GLB_20format/`（參考庫 commit `dcc81adea1287c7f0cbb2648a0931df7b4a09ee8`）。`reshape.mjs` 改形、換色，再由 `tools/glb-to-m3dmodel/bridge.mjs` 轉成 `RailwayGameApp/Resources/Models/tw-*.m3dmodel`。

```sh
# 從 repo 根目錄；Node 22；先在 tools/glb-to-m3dmodel 跑過 npm ci --ignore-scripts；
# 參考庫放在這個 repo 旁邊（或用 KIT=<car-kit 的 GLB 資料夾> 指定）
tools/tw-cars/build.sh [WORK_DIR]
```

重跑逐位元相同。

| 檔（`Map3DStreetModel`） | 原件 | 尺寸（長×寬×高，m） | 三角形 |
|---|---|---|--:|
| `tw-sedan`（`car`） | `sedan.glb` | 4.63 × 1.78 × 1.44（Corolla Altis） | 986 |
| `tw-suv`（`suv`） | `suv.glb` | 4.46 × 1.83 × 1.62（Corolla Cross） | 1,094 |
| `tw-van`（`van`） | `van.glb` | 4.70 × 1.75 × 1.95（Town Ace／短 Hiace） | 1,036 |
| `tw-taxi`（`yellowTaxi`） | `taxi.glb` | 4.63 × 1.78 × 1.44＋車頂燈（1.66） | 1,026 |

香港的士（參考 `street-agents.glb` 的 car）是 2,076 個三角形，這四台約一半。

怎麼改：

- **不留貼圖**：Kenney 的車用一張 512×512 的色票圖（4 列 × 16 欄漸層）。每個面看它 UV 落在哪一格，換成遊戲的色：第 2 列＝車身（`Map3DStreetLife.carPaints[0]` 的白，進遊戲時改成 alpha 0，由每台車自己的顏色上色）；第 3 列深灰＝水箱罩、輪拱（`Map3DStreetModel.tyre`），藍灰＝保險桿、側裙（`trim`），淺灰＝車牌、排氣管（`steel`）；第 4 列淺藍白＝車窗（`glass`），黃＝頭燈（`headlamp`，夜裡亮），紅＝尾燈（`tailLamp`，夜裡亮）。對不到的格會讓工具停下來。
- **側窗連成一條**：Kenney 的車窗只是車門上一小塊；真車的側窗從 A 柱連到 C 柱。座艙側面（法線朝外、在側窗下緣以上、不比側窗更外面，所以後照鏡不算）改成玻璃。
- **車輪**：原件每顆 332 個三角形，換成十角柱的胎（`tyre`）加外側一片鋼圈（`steel`，凸出 1 cm）。
- **休旅車**：原件是軟頂吉普，車頂與後半座艙是深灰；車頂（0.75 以上的藍灰面）改成車身色，像跨界休旅；拿掉尾門上的備胎。
- **計程車**：車身以下照轎車拉到 1.44 m；車身以上的車頂燈改成白色、夜裡亮。黃色由遊戲給（`carPaints` 最後一格）。
- **比例**：Kenney 的車是玩具比例（長 2.55、寬 1.5、高 1.15），照真車把長、寬、高各自拉伸。

授權：Kenney Car Kit 是 CC0 1.0（https://kenney.nl/assets/car-kit，頁面寫「Creative Commons CC0」，2026-11-17 看過）。參考庫那一份沒有附 Kenney 的 `License.txt`（`town-scene-reference-clean/ATTRIBUTION_AND_RIGHTS.md`）。CC0 不要求署名；遊戲的資料來源頁（`DataSourceCredits`，id `kenney`）寫了 Car Kit 的網址。不用 Kenney 的標誌。

比對的照片（只拿來比形狀與顏色，不放進這個 repo，在素材庫 `game-art-previews/docs/art/tw-cars-2026-11-17/`）：Wikimedia Commons 的 Toyota Corolla Altis E210（台中，WC-QHS，CC BY-SA 4.0）、Toyota Corolla Cross Hybrid（Alexander-93，CC BY-SA 4.0）、Toyota Town Ace（Retired electrician，CC0）、Toyota Wish 計程車（CEFICEFI，CC BY-SA 3.0）。
