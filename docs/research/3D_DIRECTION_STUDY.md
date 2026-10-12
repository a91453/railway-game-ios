# 3D 開發方向研究：EveryCityMap、MapLibre 的 3D 與參考庫的 rail-3d

查閱日期：**2026-10-12（UTC）**。

| 來源 | 版本 |
| --- | --- |
| 遊戲 | `origin/main` **`0f3a7db`**（#396 合併後） |
| `a91453/railway-reference-private` | **`7328c2af6407b95194087162cfc62a6211a92692`** |
| [everycitymap.com](https://everycitymap.com/) | 2026-10-12 下載的首頁、`/city/tokyo`、`/create`、`/attribution`，以及它們載入的 23 個腳本 |
| MapLibre Native | App 用的 iOS 6.31.0（決策 97）；style spec 與 issue #252 在同一天查閱 |

作者交來另一個 AI 的報告，要求研究目前的 3D 開發方向。報告的主張：

- EveryCityMap 的 3D 城市是 MapLibre 畫的，作者自己確認過；所以那種畫面不必付費用 Mapbox。
- 遊戲的 MapLibre 地圖只要補三件事就有 3D 建物：建物圖層、傾斜與旋轉的相機、光照與配色。
- 但 MapLibre 的 3D 先暫緩，優先把 Tokyo 的 3D 城市試作（決策 152）接上 GameCore。
- 最終是「遠景 MapLibre、近景專用 3D renderer、底層同一個 GameCore」。

本文件是那份研究：

- 查證報告的說法，包括 EveryCityMap 線上版實際載入的程式；
- 查 App 用的 MapLibre Native 在 iOS 上能做到哪些 3D；
- 盤點遊戲現在和 3D 有關的程式與參考庫的 3D 實作；
- 比較幾條路，提出第一步。

**範圍：只有本文件與 ROADMAP Phase 8 的一行連結。** App、GameCore、GamePresentation、`Web/`、golden、存檔、replay 與 workflow 都沒有改。存檔版本、決策編號、golden schema 都不動（工作登記 #231）。

## 1. 結論

1. **報告的大方向對。**
   - 建造用的 2D 地圖維持 MapLibre Native 加自製底圖（決策 97、151）。
   - 不 fork MapLibre，不自己寫地圖引擎。
   - 3D 要畫遊戲自己的狀態才有意義。
   - 原生 Metal／RealityKit 等實機量測後再決定（ROADMAP Phase 8 本來就這樣寫）。
2. **報告有兩處和查到的不符。**
   - EveryCityMap 線上版載入的是 **Mapbox GL JS 3.30.0**，用 Mapbox 的 Standard 樣式；它的腳本裡沒有 MapLibre（§3）。
   - 它 3D 模式的建物外牆、地標模型與樹，都是 Mapbox Standard 內建的。MapLibre 的 `fill-extrusion` 只能畫出單色的量體，做不出同樣的畫面。
3. **App 用的 MapLibre Native 在 iOS 上沒有 3D 地形**（§4）。
   - 建物擠出、山的陰影、傾斜旋轉都有。
   - 決策 151 寫的「地形圖磚之後可以直接給 MapLibre 的 `terrain` 用」只在網頁版（MapLibre GL JS）成立。
4. **報告沒算到兩個成本**（§5）。
   - 軌道、車站、列車與城市是 SwiftUI Canvas 用俯視的 `PlanCamera` 畫的，MapLibre 只是跟著它的背景。底圖一傾斜，遊戲畫的東西就對不上，所以整個覆蓋層都要改成 3D 投影。
   - OSM 的建物圖層是第二座城市：它不會隨 GameCore 的城市成長、收購（決策 146）與玩家的建物改變。決策 151 就是因此拿掉它的。3D 的建物要從 `GameWorld` 推導（[PROCEDURAL_CITY_STUDY.md](PROCEDURAL_CITY_STUDY.md) §7）。
5. **參考庫已經有「MapLibre 加 3D 鐵道」的完整實作：`Railway/site_archive_clean/rail-3d/`**（§6）。
   - MapLibre GL JS 5.9.0 的底圖、OSM 建物擠出、Terrarium 地形。
   - three.js 放在 MapLibre 的 custom layer 裡，畫列車編組、軌道、高架橋墩與隧道口。
   - 傾斜、旋轉、跟車鏡頭都有。
   - 它用一台相機同時處理遠景和近景，所以報告擔心的「兩種 renderer 之間無縫切換」在這個做法裡不存在。
   - 它的座標和遊戲的 `RealWorldFrame` 是同一種關係：錨點緯度的 Web Mercator，世界的一公尺是一個線性比例。
6. **建議的第一步：唯讀的「3D 檢視」**（§8）。
   - 以 rail-3d 的網頁為底，在 App 的 WKWebView 裡畫玩家自己的路網、結構物與列車。
   - 資料由 GameCore 的 `railwaySnapshot()` 給，頁面只畫、不回寫；建造照舊在 2D 地圖。
   - 這一步回答三個問題：網頁 3D 在 iPhone 上畫真實的路網夠不夠順；座標、高度與結構物對不對得上；3D 要不要變成主畫面。
   - Tokyo 試作的近景城市、原生引擎都等它的結果再決定。

## 2. 報告的查證

| 報告的說法 | 原始碼或查到的 | 判定 |
| --- | --- | --- |
| EveryCityMap 用 OSM 資料，有六種主題，可以切換 2D／3D | 首頁、`/attribution`：資料是「© OpenStreetMap contributors, ODbL 1.0」，主題有 Atlas、Metro、Ink、Paper、Night、Watercolor | 對 |
| 作者確認用的是 MapLibre、OpenFreeMap／OpenMapTiles、Mapterhorn 地形，水彩是自訂 WebGL shader | 線上版載入 Mapbox GL JS 3.30.0、Mapbox Streets v8 的圖磚與 `mapbox.mapbox-terrain-dem-v1` 的地形；沒有自訂的 WebGL 圖層，水彩是一組配色（§3）。報告引的作者貼文找不到；Peerlist 的專案頁回 403 | **不對**（至少現在的線上版不是） |
| 漂亮的畫面不是付費用 Mapbox 才有 | 3D 模式打開的是 Mapbox Standard 內建的 `show3dBuildings`、`show3dFacades`、`show3dLandmarks`、`show3dTrees` | **不對** |
| MapLibre 有用建物輪廓與高度產生 3D 建物的官方範例 | GL JS 的 [Display buildings in 3D](https://maplibre.org/maplibre-gl-js/docs/examples/display-buildings-in-3d/)；Native iOS 3.6.0 起支援 `fill-extrusion` | 對 |
| 自製 PMTiles 刻意省略 building 圖層 | 決策 151 第 2 點：沒有建物、土地使用、興趣點、鐵道 | 對 |
| `OSMMapBackground.swift` 禁止 MapLibre 的旋轉與傾斜手勢 | `RailwayGameApp/Views/OSMMapBackground.swift:146-149`：縮放、拖曳、旋轉、傾斜四種手勢都關 | 對；原因沒說到（§5） |
| 加上三件事就能做出 MapLibre 3D | iOS 沒有 3D 地形（§4）；傾斜要重做覆蓋層，OSM 建物是第二座城市（§5） | 部分對 |
| Tokyo 試作可以呈現更細的建物、道路、鐵路與車輛 | 決策 152、[PROCEDURAL_CITY_STUDY.md](PROCEDURAL_CITY_STUDY.md) §3：程序外觀、窗戶 shader、街道設施 | 對 |
| 優先把 Tokyo 3D 接上 GameCore | 試作和遊戲完全沒有連接；只有兩塊預先編譯的 1.5 km 地點；實機效能沒量（§5、§7） | 方向對，範圍太大 |
| 目標：遠景 MapLibre、近景專用 3D renderer、同一個 GameCore | 和 ROADMAP Phase 8 一致；rail-3d 用一台相機同時處理遠近（§6） | 對；另有不必切換的做法 |

## 3. EveryCityMap 的實際做法

**怎麼查的**：下載首頁、`/city/tokyo`、`/create` 的 HTML。它是 Next.js（Turbopack）網站，所以再抓頁面引用的腳本，以及腳本裡再引用的腳本，到沒有新的為止，共 23 個；然後在裡面搜尋關鍵字。只讀，沒有複製任何程式。

**引擎**：

- 首頁的 `<main>` 標著 `data-renderer="mapbox"`。
- 地圖的腳本（約 1.85 MB）裡是 Mapbox GL JS，版本字串 `"3.30.0"`。
- 23 個腳本裡都找不到 `maplibre`。

**建立地圖**（地圖腳本裡的應用程式碼，節錄）：

```js
this.map = new s.Map({accessToken: a, container: i.container,
  style: "mapbox://styles/mapbox/standard", config: {basemap: this.config}, ...})
```

`basemap` 的設定（節錄）：

```js
show3dObjects: "3d" === r, show3dBuildings: !0, show3dLandmarks: !0,
show3dFacades: !0, show3dTrees: !0, showPlaceLabels: !0, ...
```

**它自己加的**：

- 圖層 `ecm-drawing-paper`（紙張底色）、`ecm-natural-areas`、`ecm-wetlands`、`ecm-road-linework`、`ecm-road-names`、`ecm-metro-rail`（含 `-casing`、`-ties` 枕木）。
- 光照 `ecm-ambient`、`ecm-celestial`（Mapbox v3 的 lights）。
- 它的圖層用 Standard 樣式的 `slot` 插入，讀的是 Mapbox Streets v8 的圖層：`landuse_overlay`、`road` 是 Mapbox Streets 的圖層名，OpenMapTiles 沒有這兩個名稱。
- 地形：`addSource("ecm-terrain", {type: "raster-dem", url: "mapbox://mapbox.mapbox-terrain-dem-v1", ...})`。
- 水彩：同一批圖層換顏色與透明度（例如 `"watercolor" === i ? .72 : .9`）。沒有找到 `type: "custom"` 的 WebGL 圖層。
- 傾斜：地圖腳本裡有 `maxPitch: 85`，其他腳本裡的鏡頭傾斜值有 35、50、55。

**對遊戲的意義**：

- EveryCityMap 的 3D 好看，主要靠 Mapbox Standard 的外牆、地標模型、樹與光照。這些是 Mapbox 的服務：要帳號與金鑰、依用量計費。
- MapLibre 沒有同等的東西，`fill-extrusion` 只有單色量體、光照與（Native 6.28.0 起）圓角。
- 遊戲不採用 Mapbox。台灣的底圖是隨 App 打包、離線、遊戲自己樣式的 OSM 圖磚（決策 151），改用 Mapbox 等於放棄這些。
- 近看的城市細節，Tokyo 試作（決策 152）已經超過地圖式的量體：程序外觀、窗戶、招牌與街道設施。

## 4. MapLibre Native（iOS）能做到的 3D

| 功能 | MapLibre GL JS（網頁） | MapLibre Native iOS（App 用 6.31.0） | 對遊戲的意義 |
| --- | --- | --- | --- |
| 建物擠出 `fill-extrusion` | 有 | 有（3.6.0 起；圓角 6.28.0 起） | 可以，但資料要來自 GameCore 的城市（§5） |
| 山的陰影 `hillshade`（Terrarium 的 `raster-dem`） | 有 | 有（Terrarium 編碼 6.0.0 起） | 已在用（決策 151 第 8 點） |
| **3D 地形** `setTerrain` | 有 | **沒有**：style spec 的支援表標 iOS ❌，[issue #252](https://github.com/maplibre/maplibre-native/issues/252) 還開著。2026-09-22 有人說 #4190 的分支（`mapriot/maplibre-native` 的 `mapriot/terrain`）已能用在 iOS App，沒有合併 | 原生地圖上的列車、高架與隧道沒有地形可以貼 |
| 傾斜與旋轉 | 有 | 有 | App 目前關掉（`OSMMapBackground.swift:146-149`） |
| 自訂圖層 | WebGL，three.js 可以共用地圖的 context | `MLNCustomStyleLayer`，要用 Metal | rail-3d 的 three.js 圖層不能直接搬進原生地圖，要重寫成 Metal |
| Mapbox Standard 的外牆、地標、樹 | 沒有 | 沒有 | 做不出 EveryCityMap 那種畫面 |

所以「在原生地圖上傾斜、畫 3D 列車與地形」要：重做覆蓋層、用 Metal 寫自訂圖層，而且沒有地形。同一件事在網頁版的 MapLibre GL JS 上，參考庫已經做好了（§6）。

## 5. 遊戲現在和 3D 有關的部分

- **2D 地圖**：
  - 軌道、車站、列車、建物都是 SwiftUI Canvas 畫的，相機是俯視、北朝上的 `PlanCamera`（`Sources/GamePresentation/MapCamera.swift`）。
  - 實景地圖的底圖（MapLibre Native 或 Apple 地圖）只跟著這台相機，不接受自己的手勢（決策 50、97）。
  - 只讓底圖傾斜，Canvas 畫的東西就和底圖對不上。所以要傾斜，就要把覆蓋層也改成 3D 投影，或整個搬進 MapLibre 的圖層。
- **底圖沒有建物**（決策 151 第 2 點）：
  - 原因之一是底圖自己的建物會疊在遊戲的城市建物（決策 126）下面。
  - 遊戲的城市由 GameCore 決定：每個土地格的用途與密度 D1–D4、成長、收購（決策 146）、公司的建物（決策 94、173）。
  - 直接打開 OSM 的建物圖層，畫的是另一座靜態的城市。
- **列車的平滑移動**（決策 182，`Sources/GamePresentation/TrainMotion.swift`）：在兩個 tick 之間沿軌道內插列車的位置。它屬於呈現層，3D 也可以用同一份內插。
- **GameCore 給 renderer 的資料**（`Sources/GameCore/Railway/RailwaySnapshot.swift`，S4 起）：
  - 節點的世界座標、是不是隧道口；
  - 每條邊的線形（中心線與縱斷面，`TrackAlignment`）；
  - 月台的點、高度與結構（`TrackStructure`：地面、高架、橋、隧道，自動的邊每 16 m 一段）；
  - 每列車的車頭位置與車身的中心線。
  - ROADMAP Phase 8 已經寫好規則：3D renderer 只讀它，不回寫，mesh、相機與內插都不進模擬。
- **座標**（`Sources/GamePresentation/RealWorldMap.swift` 的 `RealWorldFrame`）：
  - 實景世界的中點在錨點，x 向東、y 向南，一個世界單位 1/64 m。
  - 底圖是 Web Mercator：世界的一公尺畫成錨點緯度地面的一公尺。
  - 所以世界座標和 Mercator 座標之間只差一個平移與縮放，沒有另外的投影。
  - 空白地圖沒有錨點（`GameWorld.geoAnchor` 為 `nil`）。
- **3D 城市試作**（決策 152、161、163）：
  - 頁面是 `Web/CityView/`（Tokyo 的網頁），放在官網的 `/city/`，App 用 WKWebView 開官網的網址，沒有網路就看不到。
  - App 和頁面之間沒有任何傳資料的程式：沒有 `evaluateJavaScript`，也沒有 `WKScriptMessageHandler`。
  - 只有兩塊預先編譯的 1.5 km 地點：高雄車站與臺中車站。高雄的 `rails.json` 是空的，臺鐵與捷運都在地下。
  - 列車是頁面自己沿 OSM 鐵路等速跑的動畫，不停站，不讀 GameCore。
  - 列車的外型有這個專案自己的流程：`tools/trains/`（`bake_model.py`、`build_train.py`）與 `.claude/skills/rolling-stock/`，模型寫到 `Web/CityView/public/models/trains/`（例如 N700S 的頭車與中間車）。它們是一般的 GLB，換一個 three.js 的畫面也能用。
  - App 內的幀時間、記憶體與發熱都沒有量（UNVERIFIED）。
- **研究**：
  - [PROCEDURAL_CITY_STUDY.md](PROCEDURAL_CITY_STUDY.md)：Tokyo 的建物生成，以及真實建物與模擬建物的分工（§7）。
  - [PHASE8_ASSET_INVENTORY.md](PHASE8_ASSET_INVENTORY.md)：參考庫的 3D 素材與三個候選原生引擎（SceneKit、RealityKit、SwiftGodot）。

## 6. 參考庫的 3D

### 6.1 `Railway/site_archive_clean/rail-3d/`（可讀的 ES module）

這是作者網站的 3D 鐵道，正是「MapLibre 加 3D」的做法：

- **底圖**：MapLibre GL JS **5.9.0**（`vendor/maplibre-gl.js`，BSD-3-Clause），樣式是 OpenFreeMap 的 Positron（`vendor/ofm-positron.json`）。
- **建物**：OSM 的 `fill-extrusion`（`index.html:6057` 起，`id: 'building-3d'`，`minzoom` 13，高度讀 `render_height`）。
- **地形**：`raster-dem`、`encoding: 'terrarium'`、`tileSize` 512（`integration/map3d.js:399`），開著時 `setTerrain`，並畫山的陰影。
  - 地形讀不到時（連續 3 次錯誤，或等 12 秒），列車退回平坦高度（`map3d.js:84-92`）。
  - 地形圖磚本體（`terrain/` 的 14 個分片）不在快照裡，只有 `manifest.json`。
- **3D 物件**：three.js（`rail-3d/vendor/three.module.js`，r170，MIT）放在 MapLibre 的 custom layer 裡，共用地圖的 WebGL context：
  - `live-vehicles-3d`、`live-tunnel-apertures`、`live-vehicles-underlay`、`live-underground-3d`（`map3d.js:409-430`）；
  - 錨點 `MercatorCoordinate.fromLngLat([121,24])`，以公尺為單位的本地座標（`map3d.js:45`）。
- **列車**：
  - `integration/formations.js` 的 `FORMATIONS`（各車種的車長、車寬）與 `assembleFormation`；
  - `integration/train-path.js` 的 `makePath`、`makeHeightProfile`、`formationPoses`：沿路徑擺每一節車；
  - 車輛模型在 `assets/blender-map-v1/`（40 個 `.bin` 與 `manifest.json`，格式見 [PHASE8_ASSET_INVENTORY.md](PHASE8_ASSET_INVENTORY.md) §2）。
  - 頁面收的資料是 `vehicles` 陣列：每列車的經緯度、路線的座標、在路線上的距離與方向（`map3d.js` 的 `createLiveMap`）。
- **結構物**：`integration/rail-structures.js`（道碴、枕木、鋼軌、高架梁與橋墩）、`tunnel-apertures.js`、`tunnel-portals.js`、`portal-clearance.js`。
- **車站與地標**：`station-layer.js`、`blender-buildings.js`（`far.mesh.bin`）。
- **相機**：傾斜與旋轉全開（`index.html:5801`，`maxPitch: 75`，預設傾斜 55°）；跟車與環繞鏡頭（`integration/camera-motion.js`、`follow-framing.js`）。
- **晝夜**：`integration/train-lighting.js`、`train-halo-style.js`、`environment/sun.mjs`（決策 182 的 2D 晝夜已經參考過它們）。

### 6.2 其他

| 參考 | 內容 | 這裡用得上的 |
| --- | --- | --- |
| `Ci/reference_snapshot/` | MapLibre 加 OpenFreeMap；3D 建物是 Liberty 樣式自己的 `building-3d`；`setTerrainEnabled`、`setBuilding3dEnabled` 之後用 `easeTo({pitch: …})` 把地圖傾斜。實作這些的 `lib/osm-map.js` 不在快照裡 | 只有做法，沒有可搬的程式 |
| `MapBuilder/reference_snapshot/` | Mapbox GL JS 3.4.0，沒有用到 3D 與傾斜 | 沒有 |
| `Simulator/reference_snapshot/` | three.js r185 的模型鐵道（毫米尺度），E201 的 GLB | 結構物的造型（[PHASE8_ASSET_INVENTORY.md](PHASE8_ASSET_INVENTORY.md)） |
| `Railway/city_world_reference/` | 壓縮過的 three.js r186 城市，有 LOD 與 instancing | 台灣的城市外觀（[PROCEDURAL_CITY_STUDY.md](PROCEDURAL_CITY_STUDY.md) §4） |
| `OpenWorld/reference_snapshot/` | three.js r186 的台灣開放世界：`play/assets/taiwan-tra/` 有 EMU3000（4.4 MB）、普悠瑪（3.5 MB）、太魯閣（3.4 MB）的 GLB；`play/assets/trains/` 有臺鐵、高鐵、磁浮的車頭與車身（含 LOD1）；`play/src/world/city-metro-world.js` 的程序車門在停站時滑開 | 近看的列車模型與滑門（決策 169 的「之後」） |
| `Website/site/city/` | 決策 163 部署的 3D 城市試作 | 不另外處理 |

## 7. 幾條路的比較

| | A：原生地圖上的 3D（報告的第三階段） | B：Tokyo 試作接上 GameCore（報告的第二階段） | C：以 rail-3d 為底的 3D 檢視（本文建議） | D：原生 RealityKit／Metal |
| --- | --- | --- | --- | --- |
| 做法 | MapLibre Native 打開傾斜與擠出；覆蓋層改成 3D 投影或 Metal 自訂圖層 | 頁面讀遊戲的狀態；城市、道路、鐵路要能在任何地點產生 | WKWebView 裡跑 MapLibre GL JS 加 three.js，讀遊戲的狀態 | 自己的 3D 畫面 |
| 尺度 | 全台灣 | 1.5 km 的預先編譯地點；全台要串流產生圖塊（全台足跡約 80 MB gzip） | 全台灣（rail-3d 本來就是全島） | 自己決定 |
| 地形 | **沒有**（§4） | 平地；之後接 H1 的高度 | 有（GL JS 的 `setTerrain`；遊戲的 `taiwan_terrain.pmtiles` 本來就是 Terrarium） | 自己做網格 |
| 列車與結構物 | 要用 Metal 寫 | `rails.js` 可改讀遊戲的線形；列車要重寫 | 已有編組、高架、隧道口；換成讀遊戲的資料 | 全部自己做 |
| 近看的城市 | 只有量體 | 最好（程序外觀、窗戶、招牌） | 只有量體；之後可再接 Tokyo | 移植 Tokyo 的演算法（PROCEDURAL_CITY_STUDY §9） |
| 離線 | 有 | 現在要網路（決策 163） | 打包進 App 就有；底圖與地形圖磚已經在 App 裡 | 有 |
| 實機效能 | 原生，應該最好 | 沒量 | 沒量 | 原生 |
| 工作量 | 大（覆蓋層加 Metal） | 大 | 中（主要是接資料） | 最大 |

選 C 當第一步的理由：

- **工作最少**：rail-3d 已經有地形、傾斜、跟車鏡頭、編組、高架、隧道口，缺的只是改讀遊戲的資料。
- **尺度對**：玩家的世界可以是全台灣（決策 88、167），高鐵示範有 352 km（決策 170）；rail-3d 本來就畫全島。
- **座標對**：`RealWorldFrame` 和 rail-3d 的錨點都是錨點緯度的 Web Mercator 加公尺的線性比例，換算是一個矩陣。
- **地圖資料可以重用**：自製底圖的樣式與 `taiwan.pmtiles` 在決策 151 已經用 MapLibre GL JS 畫過；`taiwan_terrain.pmtiles` 是 Terrarium 編碼、512 像素，和 rail-3d 的地形來源同一種。
- **不鎖死引擎**：它是唯讀的檢視，和建造分開。量測不夠好時改走 D，GameCore 這邊的資料轉換照樣用得上。

## 8. 建議的第一步：唯讀的 3D 檢視

1. **資料（GamePresentation，純函式，Linux 上有測試）**：
   - 把 `railwaySnapshot()` 轉成頁面要的 JSON：每條邊的中心線與高度、結構（地面、高架、橋、隧道）、隧道口、月台，以及每列車的車身中心線與車種。
   - 列車位置用決策 182 的 `TrainMotion` 內插。
   - 座標給世界座標加 `RealWorldFrame` 的錨點，或直接給經緯度。
2. **App**：
   - 實景地圖多一個「3D 檢視」的入口，用 WKWebView 開頁面。
   - App 用 `evaluateJavaScript` 定時送資料（例如每秒幾次，其餘由頁面內插），頁面只畫。
   - 建造照舊在 2D 地圖，3D 裡不能改任何東西。
3. **頁面**：
   - 從 rail-3d 的 `map3d.js` 移植：底圖用遊戲自己的樣式與 `taiwan.pmtiles`，地形用 `taiwan_terrain.pmtiles`。
   - 列車用 `formations.js` 的編組，結構物用 `rail-structures.js`。
   - 建物先不畫，或用 GameCore 的建物格畫成 `fill-extrusion` 的量體（高度依密度，[PROCEDURAL_CITY_STUDY.md](PROCEDURAL_CITY_STUDY.md) §7）。
4. **量測（實機，TestFlight）**：
   - 用高鐵示範（決策 170）當最重的情境，量幀時間、記憶體、發熱與耗電。
   - 也量一般的實景地圖、近看與遠看。

**不在第一步**：在 3D 裡建造、Tokyo 的近景城市、空白地圖（沒有錨點）、車站的 3D 站房、近看用的精細列車模型（`tools/trains/` 與 OpenWorld 的 GLB）。

**頁面放哪**：

- 照決策 163 放官網：更新不必送審，但要網路。地圖的圖磚約 57 MB（決策 151），也得另外放上官網。
- 打包進 App：離線可用；頁面直接讀 App 已經有的 `Resources/BaseMap/` 圖磚，不用重複一份。代價是 App 多出頁面本身的大小（MapLibre GL JS 約 1 MB、three.js 與頁面程式另計），頁面更新要送審。
- 本文建議打包，由作者決定。

## 9. 需要作者決定

1. **3D 檢視用哪個當底**：rail-3d（本文建議）或 Tokyo 試作。
2. **頁面放哪**：官網（決策 163 的做法）或打包進 App（本文建議，§8）。
3. **排在哪**：
   - 已經在 `main` 上的是經營（#396 逐線報表）與晝夜畫面（#402）。
   - 還開著的是車輛經濟（#395）與公司評等（#403）。
   - 3D 檢視要插隊，或排在它們之後。

## 10. 缺口

| 缺口 | 處理 |
| --- | --- |
| MapLibre Native iOS 沒有 3D 地形 | 3D 走網頁的 GL JS；之後若走原生，用 #4190 合併後的版本，或自己做地形網格 |
| 空白地圖沒有錨點 | 3D 檢視先只給實景地圖；空白地圖之後用一個假的錨點、不畫底圖 |
| 台灣以外的底圖要網路（OpenFreeMap） | 和 2D 一樣 |
| rail-3d 的車輛模型和遊戲的車種不是同一套（PHASE8_ASSET_INVENTORY §7.2） | 先用代表外觀；高鐵、EMU3000 有對應的模型（rail-3d 的 `700t`、`tools/trains/` 的 N700S、OpenWorld 的 `emu3000.glb`） |
| rail-3d 的地形分片不在快照裡 | 用遊戲自己的 `taiwan_terrain.pmtiles`（決策 151 第 8 點） |
| 網頁 3D 在 iPhone 上的效能 | 第一步的量測 |
| 3D 裡的觸控建造 | 不在第一步；量測之後再決定主畫面 |

## 11. 授權

- **rail-3d、OpenWorld**：作者的參考庫，依 `CLAUDE.md` 授權移植。它們打包的程式庫保留各自的告示：MapLibre GL JS（BSD-3-Clause）、three.js（MIT）、pmtiles.js（BSD-3-Clause）。OpenWorld 的 GLB 移植時，照 `OpenWorld/SANITIZATION_REPORT.md` 列的署名資料逐件核對。
- **EveryCityMap**：只為查證讀它公開的網頁與腳本，沒有複製任何程式、樣式或資料。
- **Mapbox**：不採用。

## 12. 查證邊界

- **VERIFIED（本機，Linux 雲端容器）**：
  - EveryCityMap：下載首頁、`/city/tokyo`、`/create`、`/attribution` 與 23 個腳本，用 `grep` 找到 §3 的程式片段（Mapbox GL JS 版本字串、`new Map` 與 `basemap` 設定、`ecm-*` 圖層、地形來源、`maxPitch`）。23 個腳本裡都沒有 `maplibre`。
  - 遊戲：`OSMMapBackground.swift:146-149` 的手勢、`RailwaySnapshot.swift` 的欄位、`RealWorldFrame` 的說明、決策 97、151、152、161、163、182 的內容、`Web/CityView/` 沒有和 App 交換資料的程式（`grep`）。
  - 參考庫：`map3d.js` 的 custom layer、錨點、地形與退回平坦的程式行，`index.html` 的 `building-3d` 與 `maxPitch: 75`，MapLibre GL JS 5.9.0 與 three.js r170 的檔頭，OpenWorld 的 GLB 檔名與大小、滑門的程式行。
- **來自網頁文件、沒有在 App 裡驗證**：MapLibre Native 的支援表（style spec）與 issue #252 的狀態。
- **UNVERIFIED**：
  - 報告引的 EveryCityMap 作者貼文（找不到）；EveryCityMap 以前的版本是不是用 MapLibre。
  - 網頁 3D（GL JS 加 three.js）在 iPhone 的 WKWebView 裡的幀時間、記憶體與發熱。
  - §7 各條路的工作量是估計。
  - 本 PR 沒有改 Swift，沒有跑 `swift build` 或測試。

## 來源

- [EveryCityMap](https://everycitymap.com/)
- [MapLibre Native issue #252：Terrain3D](https://github.com/maplibre/maplibre-native/issues/252)
- [MapLibre Style Spec：Terrain](https://maplibre.org/maplibre-style-spec/terrain/)、[Layers](https://maplibre.org/maplibre-style-spec/layers/)、[Sources](https://maplibre.org/maplibre-style-spec/sources/)
- [MapLibre Native iOS 6.28.0 release notes](https://newreleases.io/project/github/maplibre/maplibre-native/release/ios-v6.28.0)
- [Metal support for MapLibre Native iOS](https://maplibre.org/news/2024-01-19-metal-support-for-maplibre-native-ios-is-here/)
- [MapLibre GL JS：Display buildings in 3D](https://maplibre.org/maplibre-gl-js/docs/examples/display-buildings-in-3d/)
