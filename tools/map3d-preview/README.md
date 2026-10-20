# 3D 地圖的預覽圖

決策 238。原生 3D 地圖在 Linux 上看不到（沒有 Metal），這組工具把 Swift 蓋好的場景輸出成檔案，用一頁 WebGL 照 `Map3DShaders.metal` 的同一個算式在無頭的 Chromium 裡畫，得到 PR 與 `docs/art/` 用的前後對照圖。決策 231–238 的預覽都是這樣做的。

**不是 Metal、不是 iPhone 的畫面**：光線、貼圖、陰影的算式相同，但抗鋸齒、精度與實機不同，實機要看 TestFlight。

## 檔案

- `Map3DPreviewDump.swift.txt`：一個 XCTest，蓋好場景後寫出頂點、索引、陰影與鏡頭。不是測試，所以不放在 `Tests/` 裡；要用時複製過去，用完刪掉。
- `index.html`：WebGL 頁，讀上面寫出的檔。
- `render.cjs`：用 Playwright 開那一頁，每個鏡頭拍兩張（有、沒有陰影）。
- `render.sh`：把上面串起來。

需要 Node 與 Playwright（Apache-2.0，只在開發機用，不進 App）。雲端 session 已裝好 Chromium，不要再 `playwright install`。

## 用法

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/towns MAP3D_WORLD=towns \
  MAP3D_VIEWS="near:2000:-2420:320:30;far:0:0:2600:0" \
  swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/towns /tmp/towns near,far
rm Tests/GamePresentationTests/Map3DPreviewDump.swift
```

環境變數：

| 變數 | 意思 |
| --- | --- |
| `MAP3D_DUMP` | 輸出檔的前綴（必填） |
| `MAP3D_WORLD` | `towns`（測試用兩鎮地圖）、`demo`（示範地圖）、`taipei`（台北車站的實景新局）、`kaohsiung`、`taichung`（兩個車站的實景新局）、`realdemo`（瑞芳、平溪的實景示範） |
| `MAP3D_BASEMAP` | `1`：讀 App 的台灣底圖（決策 234） |
| `MAP3D_CITY` | `1`：讀高雄、台中車站周圍的城市圖塊（決策 239；要和 `MAP3D_BASEMAP=1` 一起用） |
| `MAP3D_VIEWS` | 鏡頭，`名字:x:z:距離:方向角度` 以 `;` 分開，座標是場景的公尺 |
| `MAP3D_CROP` | `x:z:半徑`：只輸出這一圈內的分塊（大場景會讓瀏覽器記憶體不夠） |
| `MAP3D_MINUTE` | 一天裡的第幾分鐘（`0`–`1439`），照那時的光線畫；預設 `840`（14:00） |
| `MAP3D_HEIGHTS` | `1`：世界還沒讀的地面用 App 的高度檔（`taiwan_heights.dat`），和 App 一樣 |
| `MAP3D_LIFE` | `x:z:距離`：決策 259 的行人與車輛，鏡頭在這個距離看這一點時畫的那些（時鐘的第 36,000 秒），每個實例展開成網格 |
| `MAP3D_LIFE_DETAIL` | `reduced`：和 `MAP3D_LIFE` 一起用，畫舊機型的份量（決策 259） |
| `MAP3D_BUSY` | `1`：和 `MAP3D_LIFE` 一起用，每個車站都當作候車 400 人、一天 8,000 人次 |
| `MAP3D_DETAIL` | `far`：輸出遠處看到的簡化版城市（決策 238）；`near`：近版但不含最近一層（決策 267 的騎樓、遮雨棚、晾衣）；預設是最近的完整版（連街道設施一起，決策 244：每個實例展開成網格） |

前後對照：在 `main` 的 worktree 與分支上各跑一次同樣的鏡頭，再把兩張上下拼起來（`docs/art/*/` 的圖都是上半 `main`、下半新版）。

還沒有差異圖：下一個改 3D 畫面的 PR 順便加（抄 pixelmatch 的單一檔案，ISC，不加 npm 套件；只當審查證據，不當通過門檻），見 `docs/research/GAME_AI_TOOLS_2026-10-15.md` §6.3。
