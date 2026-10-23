# 3D 地圖的預覽圖

決策 238。原生 3D 地圖在 Linux 上看不到（沒有 Metal），這組工具把 Swift 蓋好的場景輸出成檔案，用一頁 WebGL 照 `Map3DShaders.metal` 的同一個算式在無頭的 Chromium 裡畫，得到 PR 與 `docs/art/` 用的前後對照圖。決策 231–238 的預覽都是這樣做的。

**不是 Metal、不是 iPhone 的畫面**：光線、貼圖、陰影的算式相同，但抗鋸齒、精度與實機不同，實機要看 TestFlight。

## 檔案

- `Map3DPreviewDump.swift.txt`：一個 XCTest，蓋好場景後寫出頂點、索引、陰影與鏡頭。不是測試，所以不放在 `Tests/` 裡；要用時複製過去，用完刪掉。
- `index.html`：WebGL 頁，讀上面寫出的檔。
- `render.cjs`：用 Playwright 開那一頁，每個鏡頭拍兩張（有、沒有陰影）。檔案由本機 127.0.0.1 的一個小 HTTP 伺服器給（決策 385）：用 `page.route` 回應時，超過 100 MB 的場景會讓 DevTools 的管道斷掉。
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
| `MAP3D_WORLD` | `towns`（測試用兩鎮地圖）、`demo`（示範地圖）、`taipei`（台北車站的實景新局）、`taipeiline`（穿過台北車站的一條線，同畫面成本報告；決策 321）、`kaohsiung`、`taichung`、`douliu`（三個車站的實景新局；`douliu` 是決策 389 加的）、`realdemo`（瑞芳、平溪的實景示範）、`xiaogang`（高鐵示範的世界讀進小港機場周圍 3 km 的真實人口與分區，焦點在機場；決策 385） |
| `MAP3D_BASEMAP` | `1`：讀 App 的台灣底圖（決策 234） |
| `MAP3D_NOBUILD` | `1`：讀 App 的不蓋區與機場建物（`taiwan_no_build.json`，決策 385）；不設就是改之前的畫法 |
| `MAP3D_CITY` | `1`：讀高雄、台中車站周圍的城市圖塊（決策 239；要和 `MAP3D_BASEMAP=1` 一起用） |
| `MAP3D_FOOTPRINTS` | `1`：讀 App 的真實建物足跡（`taiwan_buildings.pmtiles`，決策 389；要和 `MAP3D_BASEMAP=1` 一起用） |
| `MAP3D_VIEWS` | 鏡頭，`名字:x:z:距離:方向角度` 以 `;` 分開，座標是場景的公尺；可再加 `:高度`，看那個高度的點（山上的車站，決策 321） |
| `MAP3D_CROP` | `x:z:半徑`：只輸出這一圈內的分塊（大場景會讓瀏覽器記憶體不夠） |
| `MAP3D_MINUTE` | 一天裡的第幾分鐘（`0`–`1439`），照那時的光線畫；預設 `840`（14:00） |
| `MAP3D_HEIGHTS` | `1`：世界還沒讀的地面用 App 的高度檔（`taiwan_heights.dat`），和 App 一樣 |
| `MAP3D_LIFE` | `x:z:距離`：決策 259 的行人與車輛，鏡頭在這個距離看這一點時畫的那些（時鐘的第 36,000 秒），每個實例展開成網格 |
| `MAP3D_LIFE_DETAIL` | `reduced`：和 `MAP3D_LIFE` 一起用，畫舊機型的份量（決策 259） |
| `MAP3D_BUSY` | `1`：和 `MAP3D_LIFE` 一起用，每個車站都當作候車 400 人、一天 8,000 人次 |
| `MAP3D_WEATHER` | `rain`、`thunderstorm`、`typhoon`：那種天氣的光線與霧（決策 277），和第 36,000 秒的雨絲（決策 320）。雨絲照手機畫：圖當成 533 × 300 點、每點 3 像素；預設是晴天 |
| `MAP3D_DETAIL` | `far`：輸出遠處看到的簡化版城市（決策 238）；`near`：近版但不含最近一層（決策 267 的騎樓、遮雨棚、晾衣）；預設是最近的完整版（連街道設施一起，決策 244：每個實例展開成網格） |
| `MAP3D_TRAINS` | `x:z`：在這一點的灰色地面上排出每一套列車（決策 318），一列一套：頭車、中間車、最後一節，最上面一列是一般通勤車；和 `MAP3D_CROP` 一起用 |
| `MAP3D_MIRROR` | `0`：玻璃與水面不反光（決策 356，同省電畫質），當作「之前」的圖；預設照 `Map3DReflection` 畫天空的 Fresnel、太陽高光、夜裡玻璃裡的城市燈光、水面波紋（波紋停在第 0 秒） |
| `MAP3D_SUN` | `0`：沒有太陽陰影貼圖（決策 357，同省電畫質；決策 232 的團狀影子照原本的深淺），當作「之前」的圖；預設照 `Map3DSunShadow` 的「自動」畫質畫（2048 見方，`index.html` 先從太陽畫一次深度）。預覽裡的招牌沒有接太陽陰影（App 有） |
| `MAP3D_SIGNS` | `0`：不輸出招牌（決策 352），當作「之前」的圖；看板的外框還在，因為它是網格。預設輸出 `<前綴>.signs`（每塊 16 個 float），`render.sh` 一起畫，時鐘照 `MAP3D_MINUTE`，LED 螢幕停在第一張圖 |

前後對照：在 `main` 的 worktree 與分支上各跑一次同樣的鏡頭，再把兩張上下拼起來（`docs/art/*/` 的圖都是上半 `main`、下半新版）。PR 只把一張總覽放進 `docs/art/<資料夾>/`，其他圖放 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/<同一資料夾>/`（作者 2026-10-21 的規則，CLAUDE.md）。

差異圖（`docs/research/GAME_AI_TOOLS_2026-10-15.md` §6.3）：前後兩張同一個鏡頭的圖，標出哪些像素變了、變了多少。只當審查的證據，不當通過門檻。

```sh
node tools/map3d-preview/diff.cjs before-close-shadows.png after-close-shadows.png diff-close.png
# 9321 of 1440000 pixels differ (0.65%)
```

- `diff.cjs`：在 `render.cjs` 用的同一個無頭 Chromium 裡用 canvas 解 PNG，跑 pixelmatch（門檻 0.1），寫出差異圖（紅色是變了的像素，其他淡掉）並印出變了幾個像素。
- `pixelmatch.mjs`：pixelmatch 7.2.0 的 `index.js`，一字未改（sha256 `52c6026c…5788`）；授權 ISC，版權行與原文在 `pixelmatch.LICENSE`（複製或改寫時一起保留）。作者 2026-10-21 同意加這個依賴（「pixelmatch 可以加」），只在 `tools/` 與本機用，不進 App 的 bundle，不加 npm 套件。
- 前後圖要同一個鏡頭、同一個時刻；只改一個東西時，在同一個分支上開關那個東西各輸出一次（例如決策 314 的路線色帶：`Map3DScene` 不給 `lineBands` 與給的），比兩個 worktree 省一次建置。
