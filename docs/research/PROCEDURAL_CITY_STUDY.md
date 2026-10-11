# 程序化城市研究：jeantimex/tokyo 與 Phase 8 的城市建物

查閱日期：**2026-10-10（UTC）**。

| 來源 | 版本 |
| --- | --- |
| 遊戲 | `origin/main` **`8ed64bd`**（#322 合併後） |
| [jeantimex/tokyo](https://github.com/jeantimex/tokyo) | **`17c8bbe5a6c57c75fe504a58ac3fb16004a27573`**（2026-10-07），MIT，Copyright (c) 2026 Yong Su |
| `a91453/railway-reference-private` | **`581db83b2739e17a47cecf2c1773666b62c1ae4a`** |
| Overture Maps buildings | release `2026-09-23.1`（與 [OSM_BUILDING_SURVEY.md](OSM_BUILDING_SURVEY.md) 同一版） |

作者交來一份報告，建議把 Tokyo 專案當 Phase 8 的核心技術參考，先做獨立研究，再做高雄車站附近 1 km² 的 iOS 3D 試片。本文件是那份研究：

- 逐檔讀 Tokyo 的 `meshing.js`、`streamer.js`、`tileformat.js`、`props.js`，以及產生街道設施的編譯工具；
- 查證報告的說法；
- 對照私有參考庫與 [REFERENCE_PORT_INVENTORY.md](REFERENCE_PORT_INVENTORY.md) 的 P8-2、P8-4、P8-11；
- 用高雄、台北兩個 1 km² 的 Overture 真實足跡實際跑一次 Tokyo 的建物生成，量建物數、三角形數與記憶體。

**範圍：只有本文件與 `tools/procedural-city/` 的兩支量測腳本。** App、GameCore、GamePresentation、golden、存檔、replay 與 workflow 都沒有改。存檔版本、決策編號、golden schema 都不動（工作登記 #231）。

## 1. 結論

1. **報告的方向對。** Tokyo 的建物生成器填的正是 Phase 8 盤點列為「自己要做」的缺口：用途 × 密度的程序外觀（[PHASE8_ASSET_INVENTORY.md](PHASE8_ASSET_INVENTORY.md) §7.2）。它讀的是任意的真實足跡，台灣的 Overture 足跡可以直接餵進去。
2. **可以移植的是演算法，不是 renderer。** `meshing.js` 的建物部分（約 380 行）是不依賴 three.js 的純函式，輸入是足跡、樓層、高度、用途，輸出是頂點陣列。它可以逐行翻成 Swift，放在 GamePresentation，Linux 上也測得到。窗戶不是幾何，是 GLSL 的 fragment shader 依每面牆的「窗格座標」畫出來的，要另外翻成 Metal。
3. **報告有一處和原始碼不符：Tokyo 的建物沒有依距離簡化的 LOD。**
   - 每個 256 m 圖塊的建物是一個 mesh，近看遠看都一樣。
   - 遠處只靠 shader 把窗格淡掉。
   - 依距離換的只有樹（160 m）、招牌（230 m）、屋頂與牆面照片（600／900 m）。
   - 真正把遠處的建物換成方塊的程式在私有參考庫：city_world 的 `regionLots` 的 `emitFarTile`／`lodTile`（§4）。
4. **台灣的足跡夠，樓層不夠。** 量測（§6）：
   - 高雄車站 1 km² 有 639 棟，只有 23 棟（3.6%）有樓層或高度。
   - 台北車站 1 km² 有 1,418 棟，555 棟（39%）有。
   - 沒有樓層的建物，高度得由遊戲自己的用途與密度（D1–D4）決定。這和報告的建議一致。
5. **私有參考庫有台灣風格的程序建物，而且比 Tokyo 更貼近台灣。**
   - city_world 的打包檔有一套以地塊為單位的生成器：透天店屋、公寓、中層、塔樓等，還有騎樓、鐵捲門、冷氣室外機、水塔、頂樓加蓋。
   - 也有依圖塊載入、遠近換外觀的機制，以及 instanced 的街道設施。
   - 這些都是壓縮過的 Vite 打包檔，讀得懂但不好直接搬。
   - 建議用 Tokyo 可讀的程式碼當骨架，台灣的外觀詞彙與參數從參考庫取（§5）。
6. **iOS 預算要自己控制。**
   - 照 Tokyo 原樣產生，台北 1 km² 約 6–21 萬個三角形、14–48 MiB 頂點資料（沒有 index 的 80 bytes／頂點）。
   - Tokyo 預設的視野半徑 900 m 約 2.5 km²，原樣搬到手機太重。
   - 試片要：有 index 的緊湊頂點格式、遠處的建物改成簡單擠出（約 24–42 個三角形一棟）、陽台這類一層一組的細節只在近處畫。

## 2. 報告的查證

| 報告的說法 | 原始碼或量測 | 判定 |
| --- | --- | --- |
| 從真實城市資料產生可即時渲染的 3D 城市，補上外觀、道路、樹與交通設施 | README、`tools/pipeline/`：PLATEAU、OSM、GSI 編譯成二進位圖塊，用戶端串流並產生網格 | 對 |
| 程序化建築：樓層、屋頂、窗戶、陽台 | `buildingMesh`：平頂加女兒牆、小屋的四坡或兩坡屋頂、頂樓設備、公寓的陽台；窗戶在 shader（`materials.js` 的 `FACADE_MAIN`） | 對；窗戶不是幾何 |
| 256 m 分區載入 | `geo.js` `TILE = 256`；`Streamer.update` 依焦點半徑載入、加 250 m 遲滯卸載、近的先載、2–4 個 worker | 對 |
| LOD 細節分級：遠景簡化建築 | 建物沒有遠近兩版；只有樹、招牌、照片換 LOD，窗格在遠處由 shader 淡成平均色 | **不對**；真正的建物 LOD 在參考庫的 `regionLots` |
| 道路與地形貼合 | `drape.js` 沿地形三角形切道路與標線，`roadprofile.mjs` 處理橋與匝道 | 對；這是 P8-4 與 S4 結構物的參考 |
| 街道設施生成 | `landscape.mjs` `placeProps`：大路每 17 m 交錯放路燈、每 11 m 行道樹，小巷每 30 m 一支電線桿並牽電線，14% 旁邊有自動販賣機 | 對 |
| 共用模型、大量實例化 | `props.js` 的 `Pool`：全城每種模型一個 `InstancedMesh`，圖塊進出時重寫 | 對 |
| 日夜與燈光 | 窗戶亮燈、路燈與車燈畫進光照圖（`lamplight.js`） | 對；對應 P8-7 |
| 程式 MIT，資料各有授權 | `LICENSE` MIT；README 列 PLATEAU、GSI、OSM（ODbL）、Poly Haven（CC0）、ez-tree（MIT）、takram（MIT）；`earcut` 是 ISC | 對 |
| Overture 涵蓋約 98% 人口所在地 | OSM_BUILDING_SURVEY「Overture Maps」：98% 的人住在每人 5 m² 以上的地方 | 對 |
| 台灣的樓層與高度大量缺漏 | 全台只有約 5% 的足跡有樓層；高雄 1 km² 3.6% | 對 |
| 作者不建議手機瀏覽器 | README：「not recommended for mobile browsers」 | 對；`performance.md` 的量測是 RTX 5090 桌機 |

## 3. Tokyo 的程式逐檔

座標：Tokyo 是公尺，x 向東、y 向上、z 向南。GameCore 是 x 向東、y 向南、z 向上，每公尺 64 單位（ARCHITECTURE 決策 29）。兩者的平面方向相同，換算是 `(x, y, z)_Tokyo = (x, z, y)_GameCore / 64`，不需要鏡射。

### 3.1 `src/world/meshing.js`（580 行）

`buildingMesh(buildings, tx, tz, marks)` 是要移植的核心。它把一個圖塊的建物轉成 `Float32Array` 的頂點陣列，不依賴 three.js；Tokyo 在 Web Worker 和 Node 測試裡都直接執行它。每一棟：

- **種子**：`hash3(i*31+k, tx*13+5, tz*17+3)`，用建物序號與圖塊座標算出的整數雜湊（不用系統亂數）。同一份輸入每次得到相同的外觀，符合專案的「隨機性由（種子、用途、序號）的雜湊產生」。
- **類別**（`category`）：PLATEAU 的用途代碼對到六類外觀：
  - 透天（HOUSE）、公寓（APARTMENT）、住商（MIXED）、商業（COMMERCIAL）、公共（PUBLIC）、玻璃帷幕（GLASS）；
  - 商業高於 45 m，或高於 24 m 且種子 < 0.25，是玻璃帷幕；
  - 用途不明的，9 m 以下算透天，其餘一半公寓一半商業。
- **牆色**：每類一組色盤（`PALETTE`，RGB 加牆面材質：磁磚、清水模、粉刷、磚、金屬浪板）。亮度乘上 0.92–1.08，再拉向空拍照的冷灰（`aerial`，七成二）。這套色盤是東京的，台灣要換（§5）。
- **樓層**：`floors = storeys || round(牆高 / 3.2)`，層高夾在 2.5–6 m。
- **屋頂**：
  - 透天、低於 13 m、單一外框、足跡填滿最小外接矩形的 78% 以上、短邊半寬 > 1.8 m 時，做四坡或兩坡屋頂，各半機率。屋脊高 `min(2.6, 短邊半寬 × 0.5, 高 − 2.4)`，簷口出挑 0.4 m。
  - 其他都是平頂加女兒牆：透天 0.3 m、高於 30 m 的 1.2 m、其餘 0.75 m。
- **牆**：
  - 每條足跡邊一個四邊形，從地面下 4 m（`SINK`，讓牆接上斜坡）到牆頂加女兒牆。
  - 每條邊依類別的窗格寬（`BAY`：透天 3.4 m、公寓 3.3、住商 3.2、商業 3.0、公共 3.4、玻璃 1.5）取整數個窗格。窗格座標寫進頂點屬性 `aFacade`，shader 依它畫窗。
- **頂樓設備**：平頂、面積 > 70 m²、高 > 7 m 才有。
  - 4 層以上、面積 > 110 m² 的有樓梯間。
  - 另外 `min(5 或 7, 面積/120 + 1)` 件：六成是一排冷氣室外機，18% 是架高的水塔，其餘是機房或風管。
  - 用拒絕取樣放在足跡內、離邊 0.7 m 以上的位置。
- **陽台**：公寓與住商、2 層以上才有。
  - 主要立面是最長、最朝南的邊（`len × (0.65 + 0.35 × 法線z)`）。
  - 和它方向相近（夾角餘弦 ≥ 0.85）、長 4 m 以上的邊都加陽台，每層一組：樓板、前板與兩側板，深 1.05 m。
  - **三角形數主要來自這裡**（§6）。
- **PLATEAU 專用的部分**：LOD2 的真實牆面與屋頂（`b.surfaces`）、屋頂照片（`photo`）、鐵塔（`tower.js`）。台灣沒有這種資料，移植時不需要；地標交給參考庫的 Blender 模型（§4）。
- **輸出**：每頂點 position、normal、color、`aFacade`（窗格 u、離地高、層高、種子）、`aBldg`（建物高、類別 + 8 × 材質、面種類、窗格寬）、`aPhoto`、`aMark`，沒有 index；另有 `ends`，讓點選時從頂點序號查回是哪一棟。

同一檔的 `terrainMesh`、`roadMesh` 是地形與路面（P8-4），依賴 `drape.js` 沿地形三角形切割。地面高度目前是 H1–H3 的高度格網（決策 124），可以接，但不在第一步。

### 3.2 `src/world/streamer.js`（273 行）

- `update(focus, eye)`：
  - 焦點半徑內（預設 900 m，`main.js`）沒載的圖塊依距離排序，近的先送 worker；同時最多 `workers × 2` 個。
  - 圖塊中心離焦點超過半徑加 250 m 才卸載。這是遲滯，避免在邊界上來回載入。
  - 依「眼睛到圖塊最近點」的距離（含高度）換樹、招牌、照片的 LOD；換回時門檻乘 1.25–1.3，也是遲滯。
- `onResult`：
  - 把 worker 傳回的陣列建成每種材質一個 mesh：地形、路面、標線、建物、模型，一個圖塊大約 5–8 個 draw call。
  - 圖塊不會動，不算矩陣（`matrixAutoUpdate = false`）。
- `unload`：釋放每個圖塊自己的幾何與貼圖；共用的設施模型不釋放，只從 pool 拿掉這塊的份。
- `buildingAt`：用 `ends` 二分搜尋，從點到的三角形找回建物。

移植時對應呈現層的「只畫畫面內」與分級顯示（E1 已做 2D 版）。worker 換成 Swift concurrency 的背景工作；遲滯與近的先載可以原樣照搬。

### 3.3 `src/shared/tileformat.js`（196 行）

- 一個 256 m 圖塊一個檔，little-endian：
  - 檔頭：魔數 `TKY1`、版本 7、圖塊座標、各類筆數。
  - 建物：用途 u16、樓層 u8、旗標 u8、底高、高、量測高、OSM 材質與顏色的提示 u32、多邊形；多邊形是 u16 個數、u16 環數，每環 u32 點數加 f32 x,z。
  - 地面：種類、代碼、多邊形。
  - 設施：種類、變體、u16 旋轉、x、z、縮放。
  - 電線、牆、招牌。
- 外框逆時針、洞順時針，環不重複第一點。
- 編譯器與用戶端共用同一份程式，`npm test` 做來回測試。

台灣只需要建物與設施兩段。f32 公尺可換成相對圖塊角的 i16 公分（±327 m，蓋得住 256 m 圖塊），點的大小減半。量測（§6）：照原格式，高雄 1 km² 47 KiB（gzip 26 KiB），台北 109 KiB（gzip 54 KiB），約 40 bytes 一棟。全台 1,981,032 棟約 80 MB gzip。只能分區下載或只帶玩家選的地區，不能整包打進 App；試片只要一個 1 km²，可以直接打包。

### 3.4 `src/world/props.js`（730 行）與 `tools/pipeline/landscape.mjs`

- `props.js`：
  - 每種設施的模型只建一次，用 box、圓柱等基本形合併。例如日本電線桿是水泥桿、兩根橫擔、路燈臂，三成五多一個變壓器。
  - `Pool` 把全城同一種模型的所有實例放進一個 `InstancedMesh`。容量不夠時放大成 1.5 倍；圖塊進出只重寫矩陣。
  - 樹近處是 ez-tree 的完整模型，遠處是簡單形狀，以圖塊為單位換。
- `performance.md` 第 6 步量到：設施改成全城 pool 之後，draw call 從 4,146 降到 1,839，整城白天 13.3 → 9.5 ms。
- `placeProps`（編譯時執行，產生設施清單）：
  - 公園與樹林：抖動格點，依地面種類的間距與填充率。
  - 大路：每 17 m 一盞路燈，左右交錯，放在路緣外 0.45 m；每 11 m 一棵行道樹，75% 機率。
  - 小巷：每 30 m 一支電線桿，固定在路的一側；相鄰兩支距離 < 55 m 時牽電線，14% 旁邊有自動販賣機。
  - 每格（3.5–6 m）只放一件（`taken`），不放進建物、車道或水裡。
- 台灣可以沿用路燈、行道樹、電線桿的放法。日本特有的（販賣機、郵筒、鳥居、止まれ）換成台灣的：機車停車格、變電箱、廟宇香爐等；這是缺口，要自己定。道路幾何要先有 OSM 道路；目前 App 的實景地圖由 MapKit 畫路，GameCore 沒有道路。

### 3.5 外觀 shader（`src/world/materials.js` 的 `FACADE_PARS`／`FACADE_MAIN`）

窗戶、窗框、直櫺、一樓店面、雨痕與牆腳的髒污，都在 fragment shader 裡依 `aFacade`、`aBldg` 計算：

- **窗戶的位置與大小**：
  - 每個窗格內窗的矩形依類別：住宅 `0.26–0.74 × 0.36–0.78`；公寓、辦公 `0.14–0.86 × 0.30–0.82`；帷幕 `0–1 × 0.26–1`。
  - 透天與公寓兩成的窗格是實牆。
- **室內**：用 interior mapping 畫出室內，有房間的深度與窗簾。
- **夜間亮燈**：每間房依雜湊決定，一部分房間每 90–330 秒可能換一次。
- **遠處**：窗格小於一個像素時（`fwidth`），淡成平均色，避免閃爍。這就是它的建物 LOD。

這段 GLSL 約 250 行，要翻成 Metal（SceneKit 的 shader modifier、RealityKit 的 `CustomMaterial` surface shader，或直接 Metal）。好處是窗戶不增加三角形；代價是每個 fragment 的計算量，手機上要量。

### 3.6 `performance.md` 給 iOS 的教訓

- 瓶頸在 CPU 走訪與 draw call，不在 GPU。對策是：
  - 一個圖塊一種材質一個 mesh；
  - 全城設施 pool；
  - 不動的東西不算矩陣；
  - 燈光畫進光照圖，而不是放幾千個真正的光源。
- 水面鏡像（整座城再畫一次）佔整城 6.4 ms 裡的 2.4 ms，手機版可以不做。

## 4. 私有參考庫有什麼

依 `CLAUDE.md` 的順序先查參考庫（全部授權可用）。路徑相對於參考庫。

| 參考 | 內容 | 和 Tokyo 的關係 |
| --- | --- | --- |
| `Railway/city_world_reference/source/assets/world-DCb11kLR.js`（1.4 MB）、`world2-C75H4-WR.js`（550 KB），壓縮打包檔 | 以地塊為單位的台灣建物生成器：類型 `shophouse`、`mid`、`apt`、`tower`、`setback`、`low`、`site`；每塊有樓層、一樓高 `gH`、層高、`roofY`、女兒牆；`facadeDetails`、`facadeSigns`、各區立面色盤，貼圖 atlas 有 SHUTTER、ARCADE、AC_FRONT、TANK_STEEL、PARAPET_ORN、ROOF_*；遠處 `emitFarBox`。參數例：店屋一樓 3.8–4.3 m、層高 3.4–3.7 m；中層一樓 4.2–5.2 m、層高 3.1–3.35 m。`pickType`／`floorsFor`／`widthFor` 已在 [PHASE6C_BUILDINGS_STUDY.md](PHASE6C_BUILDINGS_STUDY.md) 讀過 | 和 `buildingMesh` 重疊，但外觀詞彙是台灣的；生成單位是地塊，不是任意足跡 |
| 同上 `world-DCb11kLR.js` 的 `streets:*` | 街道設施的 `InstancedMesh` pool，每圖塊用可見遮罩壓縮槽位，`addUpdateRange` 局部更新 | 和 `props.js` 的 `Pool` 同一招，多了局部更新 |
| `.../regionLots-9J5Pqa_O.js`（19 KB） | 地塊建物的圖塊串流與 LOD：`buildFar(tile)` 呼叫 `emitFarTile` 產生遠景方塊；`lodTile(tile, camX, camZ, bodyR, detailR, …)` 依距離切換本體、地塊、細節、夜燈。它載入的 `regionDriver-*.js` 不在快照裡（缺） | 補上 Tokyo 沒有的建物 LOD |
| `.../tilePool-CqQmg_WR.js`（8.5 KB） | GPU 緩衝池，屬性有型別（f32、f16、u8），快取視錐平面 | 補 Tokyo 的上傳路徑：緊湊頂點格式 |
| `.../buildWorker-BPjJt4Vl.js`（404 KB） | Worker 產生特定街廓（「huaxi」店屋街：騎樓、鐵捲門、招牌、atlas 窗、頂樓女兒牆），傳回可轉移的緩衝 | 和 Tokyo 的 worker 同模式；內嵌的 MIT 註解見 PHASE8_ASSET_INVENTORY §5 |
| `.../build-2kUI5-ha.js`、`build-BU46ZK3j.js`（110–119 KB） | 頂樓與立面零件：女兒牆、水塔、冷氣、鐵皮加蓋、欄杆陽台、線腳；閩南、磚、裝飾風格 | 對到 Tokyo 的頂樓設備與陽台，但是台灣的樣子 |
| `Railway/site_archive_clean/rail-3d/station-models.js`（170 行，可讀） | `buildStation(meta, footprint)`：GeoJSON 足跡轉公尺、三角化；屋頂依類型的高度函數（平、塔、雨棚、拱、傘、斜、歇山、雲）；每條邊有牆、飾帶、窗帶，塔每 4 m 一條樓層帶、每 12 m 一根柱 | 車站與地標的程序模型，和一般建物分開 |
| `rail-3d/blender-buildings.js`、`assets/{blender-buildings-v1,historic-buildings-v2}/` | 47 份手工地標的 `far.mesh.bin`：無檔頭、24 bytes 一頂點（位置 xyz、法線 xyz，f32，Z-up 公尺），`model.json` 的 `drawGroups` 給材質與範圍 | 地標用它，一般建物用程序生成 |
| `rail-3d/station-layer.js` 126–139 行 | 地標的 near／far：縮放 ≥ 14、距離 < 3,500 m 才畫，縮放 ≥ 16 用 near；非同步載入用 ticket 防止競爭，失敗 30 s 後重試 | 單棟的 LOD，沒有圖塊與遲滯 |
| `rail-3d/integration/landscape-trees.js`（107 行） | 樹林多邊形內 26 m 雜湊格點放樹，觸控裝置上限 700 棵；兩個 `InstancedMesh`（樹冠、樹幹） | `placeProps` 的樹林部分的小型版 |
| `Ci/reference_snapshot/` | 只有 MapLibre 的 `fill-extrusion`／building-3d 圖層設定 | 沒有網格生成 |
| `Simulator/`、`MapBuilder/` | three.js 本體、一份列車 GLB；2D 路網編輯器 | 和城市建物無關 |
| `Railway/railway_game_reference_clean/` | 文件、RailwayCore wasm、觸控縮放 | 無關 |

## 5. 對照表

依 `CLAUDE.md` 每個新 Stage 要附的對照表（來源 → 目標）。目標檔案都是提案，本 PR 沒有建立。

| 來源（檔案／函式） | 目標（提案） | 換算與說明 |
| --- | --- | --- |
| Tokyo `meshing.js` `buildingMesh`（牆、平頂、女兒牆、坡屋頂、頂樓設備、陽台）、`minAreaRect`、`insideRings`、`edgeDistance`、`hash3` | `Sources/GamePresentation/CityMesh/BuildingMesher.swift`（純 Swift，Linux 可測） | 公尺 → 世界單位 ×64；軸 `(x, y, z)_Tokyo = (x, z, y)_GameCore`；`hash3` 照搬（32 位整數乘法，`&*`）；保留 MIT 告示 |
| Tokyo `category`（PLATEAU 用途代碼 → 六類）、`PALETTE`、`BAY`、`PITCHED_ROOFS` | 同上的 `FacadeStyle`：`LandUse`（八種）× `BuildingDensity` → 類別 | 住宅 D1 → 透天，D2+ → 公寓；商業 → 住商或商業；辦公 → 商業，D4 → 帷幕；工業物流 → 新的「廠房」（缺）；學校與公共設施、觀光休閒 → 公共；農業 → 透天；公園 → 不生建物。色盤改用參考庫的台灣色盤 |
| 參考 city_world `world*.js` 的地塊類型與參數（`gH`、層高、女兒牆）、`build-*.js` 的水塔、冷氣、鐵皮加蓋、騎樓 | `BuildingMesher` 的台灣零件 | 店屋一樓 3.8–4.3 m、層高 3.4–3.7 m 等，參數照搬；先反壓縮讀懂，再逐項移植 |
| Tokyo `earcut`（ISC，3.2.4） | `BuildingMesher` 內的三角化 | 翻成 Swift 並保留 ISC 告示，不新增套件 |
| Tokyo `streamer.js` `update`／`unload`（半徑、250 m 遲滯、近的先載、在途上限） | `Sources/GamePresentation/CityMesh/CityTileStreamer.swift`（只決定哪些圖塊要載，Linux 可測）；App 端建 mesh | 256 m 圖塊 = 16,384 單位；遲滯與上限先照搬，手機上再調 |
| 參考 `regionLots` `emitFarTile`／`lodTile` | 同上的遠景 LOD：簡單擠出（不畫陽台與頂樓設備） | 量測：簡單擠出約 24–42 個三角形一棟（§6 的 1 層情境） |
| Tokyo `tileformat.js`（建物段）、參考 `tilePool` 的緊湊屬性 | `tools/procedural-city/` 的編譯工具，產生 App 資源 `RealWorld/buildings/<區>.bin` 與 Swift 讀取器 | 點改 i16 公分相對圖塊角；用途改成遊戲的分類或不存（由土地格決定） |
| Tokyo `props.js` `Pool`、`landscape.mjs` `placeProps`／`forEachAlong`；參考 `streets:*` pool、`landscape-trees.js` | P8 的街道設施層：一種模型一個 instanced 繪製 | 路燈 17 m、行道樹 11 m、電線桿 30 m 照搬；需要 OSM 道路（缺） |
| Tokyo `materials.js` `FACADE_MAIN`（窗戶、店面、interior mapping、夜燈） | App 的 Metal shader（引擎未定） | 約 250 行 GLSL；`aFacade`、`aBldg` 放進自訂屬性或 UV 通道 |
| Tokyo `drape.js`、`terrainMesh`、`roadMesh` | P8-4 地形與路面 | 接 H1–H3 的高度格網；第一個試片不做 |
| 參考 `rail-3d/blender-buildings.js` 的 `far.mesh.bin` | 地標（台北 101、總統府、車站） | 已在 PHASE8_ASSET_INVENTORY §7.1 |
| 參考 `rail-3d/station-models.js` `buildStation` | 車站程序模型 | 和一般建物分開，之後再做 |

## 6. 量測：高雄、台北車站 1 km²

**做法**（`tools/procedural-city/`）：

- `extract_patch.py`：從 Overture 讀兩個以車站為中心、1 km 見方範圍內的建物。足跡重心在範圍內才算，和 Tokyo 編譯器分圖塊的規則相同；不含地下建物。座標轉成 Tokyo 的局部公尺。
- `measure_patch.mjs`：
  - 把建物依重心分到 256 m 圖塊（1 km² 跨 16 塊）。
  - 用 Tokyo 原版的 `buildingMesh` 與 `encodeTile` 跑：import 一份 checkout，沒有複製 Tokyo 的程式。
  - 有樓層的照樓層；只有高度的用高度 ÷ 3.2 m；兩者都沒有的，照三種假設。
  - 用途給兩種：不明（公寓有陽台）、商業（沒有陽台）。

**資料**：

| 地方 | 建物 | 有樓層或高度 | 來自 OSM | 建蔽率 | 足跡的點 | 圖塊檔（gzip） |
| --- | --- | --- | --- | --- | --- | --- |
| 高雄車站 | 639 | 23（3.6%） | 202 | 25.5% | 3,589 | 47.4 KiB（25.8） |
| 台北車站 | 1,418 | 555（39%） | 1,329 | 41.0% | 8,554 | 109 KiB（54.4） |

**三角形與頂點記憶體**（Tokyo 原樣：沒有 index，80 bytes 一頂點）：

| 地方 | 用途 | 沒有樓層的當作 | 三角形 | 每棟 | 最多的圖塊 | 頂點 MiB | 產生時間 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 高雄 | 不明（有陽台） | 1 層（Tokyo 的預設） | 15,382 | 24.1 | 3,629 | 3.5 | 58 ms |
| 高雄 | 不明 | 6 層（D2） | 78,887 | 123.5 | 11,648 | 18.1 | 109 ms |
| 高雄 | 不明 | 18 層（D3） | 136,055 | 212.9 | 22,592 | 31.1 | 141 ms |
| 高雄 | 商業（無陽台） | 1 層 | 17,925 | 28.1 | 4,094 | 4.1 | 25 ms |
| 高雄 | 商業 | 6 層 | 54,215 | 84.8 | 7,064 | 12.4 | 56 ms |
| 高雄 | 商業 | 18 層 | 45,905 | 71.8 | 6,514 | 10.5 | 43 ms |
| 台北 | 不明（有陽台） | 1 層 | 74,615 | 52.6 | 9,415 | 17.1 | 86 ms |
| 台北 | 不明 | 6 層 | 134,845 | 95.1 | 13,396 | 30.9 | 119 ms |
| 台北 | 不明 | 18 層 | 209,437 | 147.7 | 26,356 | 47.9 | 162 ms |
| 台北 | 商業（無陽台） | 1 層 | 59,756 | 42.1 | 6,777 | 13.7 | 54 ms |
| 台北 | 商業 | 6 層 | 83,416 | 58.8 | 7,803 | 19.1 | 68 ms |
| 台北 | 商業 | 18 層 | 77,856 | 54.9 | 7,323 | 17.8 | 56 ms |

產生時間是 Node 22 單執行緒，Intel Xeon 2.1 GHz（雲端容器），16 塊合計，含 JIT 暖機；不是 iPhone 的數字。

**讀法**：

- **陽台是三角形的大宗。** 陽台一層一組，6 層的公寓每棟約 124 個三角形，同樣的建物當商業（沒有陽台）約 85 個。高了的商業反而變少，因為超過 45 m 成了帷幕，頂樓設備較少。
- **遠景的簡單擠出約 24–42 個三角形一棟**（1 層、沒有頂樓設備的情境）。
- 台北的「1 層」情境已經比高雄多，因為台北有 39% 的建物有真實樓層，不受假設影響。
- **推到手機的視野。** 以台北的密度、近景半徑 300 m（約 0.28 km²）用完整外觀、外圈到 900 m 用簡單擠出估：
  - 近景 3.8–5.9 萬個三角形（0.28 km² × 台北 6 層到 18 層的情境）；
  - 遠景 3.4–8.4 萬個（扣掉近景後約 2.26 km²；每 km² 1.5 萬是高雄的 1 層情境，3.7 萬是台北 1,418 棟 × 約 26 個）；
  - 合計約 7–14 萬個三角形。
  - 改用有 index、法線與顏色壓縮的頂點（約 24–32 bytes 一頂點、頂點重用約一半），頂點記憶體在 10 MiB 以下。
  - 這是估算，沒有在 iOS 上跑（UNVERIFIED）。
- **產生時間不是瓶頸。** 一個圖塊幾毫秒，背景執行緒來得及。

## 7. 台灣的資料怎麼接：真實建物與模擬的建物

報告指出要分開「真實世界的背景建物」與「城市自動成長、玩家蓋的建物」，避免重疊或重複計入經濟。專案現在的規則已經大致決定了這件事：

- 經濟只有一份：GameCore 每個 64 m 土地格一棟邏輯建物（`Building`：用途、密度 D1–D4、居民、就業），玩家建物是 `PlacedBuilding`。
  - 實景地圖依面積收購（決策 146）。
  - 建蔽率將換成 Overture 的真實值（決策 147，`claude/real-coverage-grid` 進行中）。
- 實景地圖平常不畫城市的方塊，真實城市由 MapKit 底圖畫（決策 126 第 5 點）。

所以 3D 只要「畫」，不要「算」。提案（屬於呈現層，GameCore 不動）：

1. **有真實足跡的格**：畫該格裡的 Overture 足跡。
   - 高度優先用 OSM 的樓層；沒有的，用該格目前的 `BuildingDensity`。
   - 同一格的建物用雜湊在該密度的名義樓層附近分布：不是每棟都 40 層，D4 的格有幾棟高的、其餘中層，依 Overture 足跡的面積。
   - 城市長高（密度升級）時，同一批真實足跡跟著變高；決策 140 的成長動畫可以沿用。
2. **城市長出來的新格**（沒有真實足跡）：用參考庫的地塊生成器，依 `widthFor` 切地塊，產生合成足跡，再走同一個 `BuildingMesher`。
3. **玩家建物**：
   - 玩家建物蓋到的真實足跡不畫，和決策 146 收購的面積一致。
   - 玩家建物自己用程序外觀或 Meshy 模型。
4. **地標與重要車站**：用參考庫的 Blender 模型與 `station-models.js`，其餘 Meshy 素材也留在這一類。

以上全部由 `GameWorld.land`、`GameWorld.buildings` 與打包的足跡檔推導，不另存世界、不回寫，和 `CitySkyline`（決策 126）同一種「衍生、不存檔」的資料。沒有經濟會被重複計算。

## 8. 對照 Phase 8 的項目

| 項目（REFERENCE_PORT_INVENTORY） | Tokyo 帶來的 | 還缺的 |
| --- | --- | --- |
| **P8-2** 城市建物、站房、地標／遠景 | 任意足跡的外觀生成（牆、屋頂、頂樓設備、陽台、窗格屬性）、窗戶 shader、依建物點選 | 台灣色盤與零件（參考庫）、八種用途的對照、廠房外觀、遠景 LOD（參考庫 `regionLots`） |
| **P8-4** 地形、景觀 | 地形網格、路面與標線貼地形（`drape.js`）、橋與匝道的高度、遠山背景（`backdrop.js`） | 台灣的道路資料（OSM 道路不在 App 裡）；試片先用平地或 H1 的高度格網 |
| **P8-11** renderer、相機、資源匯入 | 256 m 圖塊串流、遲滯、背景產生網格、一圖塊一材質一 mesh、設施 pool；`performance.md` 的量測方法 | 引擎沒選；iOS 的幀時間、記憶體、耗電沒量 |
| P8-7 夜景 | 窗戶亮燈、路燈與車燈光照圖 | 之後 |
| P8-1 列車 | `trains.js`（205 行）只是沿 OSM 鐵路的外觀動畫 | 不採用：列車位置由 GameCore 的 `railwaySnapshot()` 決定 |

## 9. 下一步：iOS 試片

> 2026-10-11 更新：作者在 iPhone 17 Pro 試過 Tokyo 的輕量版可行，選了「直接照搬」而不是下面的 Swift 移植：Tokyo 的網頁原樣放進 App 的 WKWebView，地點改成高雄車站（ARCHITECTURE 決策 152）。下面的 Swift 路線保留作為之後的選項。

建議下一個 PR 做報告的第二步：高雄車站 1 km² 的試片。範圍：

1. **打包資料**：`extract_patch.py` 的高雄部分轉成圖塊檔，約 26 KiB gzip，放進 `RealWorld/`。`DataSourceCredits` 加上 Overture（ODbL）與 Shi 等人（CC BY 4.0）；決策 147 若先合併，就沿用它加的那兩條。
2. **`BuildingMesher.swift`**（GamePresentation）：
   - 移植 `buildingMesh` 的非 PLATEAU 部分與 earcut，用 Linux 測試固定輸出：三角形數、包圍盒、同一輸入兩次結果相同。
   - 可以用本文件的數字當對照：高雄、6 層、不明用途要是 78,887 個三角形。
3. **3D 畫面**：一個實景地圖的「3D 預覽」入口，或只在除錯選單；可旋轉 360° 的相機、一個方向光。用上面兩項，先不做窗戶 shader，或只做最簡版。
4. **量測**：在 TestFlight 實機量幀時間、峰值記憶體、首次產生時間，比較有與沒有陽台、遠景擠出的半徑。

需要作者決定：

- **引擎**：PHASE8_ASSET_INVENTORY §3 列了 SceneKit、RealityKit、SwiftGodot。專案的最低版本是 iOS 17。
  - SceneKit：自訂頂點屬性加 shader modifier 最容易接 Tokyo 的窗戶。但 Apple 在 2025 年宣布 SceneKit 只做維護、不再加新功能。
  - RealityKit：自訂網格的 `LowLevelMesh` 要 iOS 18，iOS 17 只有 `MeshDescriptor`；窗戶要寫成 `CustomMaterial`，窗格屬性得塞進 UV 通道。
  - 直接用 Metal：控制最多，工也最多。
  - 這幾點都還沒在專案裡驗證（UNVERIFIED）。
  - 建議試片用 RealityKit 的 `MeshDescriptor` 先做沒有窗戶的版本；若窗戶 shader 在 RealityKit 做不到，再比 Metal。
- **試片放在哪**：一般玩家看得到的入口，或只在除錯選單、TestFlight 給作者看。
- **陽台**：台灣的公寓多是鐵窗與外推陽台，Tokyo 的開放式陽台不一定像。先關掉陽台（6 層的情境三角形少三到四成），等參考庫的鐵窗零件移植後再開。

## 10. 授權

- **Tokyo 的程式**：MIT，Copyright (c) 2026 Yong Su。移植時在新檔案保留著作權與 MIT 全文（`RailwayGameApp/Resources/Licenses` 或檔頭），並在 App 的授權畫面列出。本 PR 沒有複製 Tokyo 的程式：量測腳本 import 一份外部 checkout。
- **earcut**：ISC（Mapbox），移植時保留告示。
- **Tokyo 的資料與素材不採用**：PLATEAU、GSI、空拍照、Poly Haven 貼圖（CC0）、ez-tree（MIT）、takram 雲（MIT）。台灣的足跡用 Overture。
- **Overture buildings**：整體 ODbL 1.0；台灣的來源是 OSM（ODbL）與 Shi 等人（CC BY 4.0，doi:10.5281/zenodo.8174931）。打包進 App 的圖塊檔是衍生資料庫，要在 `DataSourceCredits` 標示，並依 ODbL 可以提供衍生資料。`extract_patch.py` 的輸出不提交進 repo。
- **私有參考庫**：依 `CLAUDE.md` 授權可用；`buildWorker` 等九檔內嵌的 MIT 註解照 PHASE8_ASSET_INVENTORY §5 處理。

## 11. 缺口

| 缺口 | 處理 |
| --- | --- |
| 台灣 95% 的足跡沒有樓層 | 用遊戲的密度（§7）；之後可查 GHSL 等全球建物高度格網（OSM_BUILDING_SURVEY「重新量測」） |
| Tokyo 的色盤、陽台、販賣機、電線桿是日本的 | 用參考庫的台灣零件與色盤；參考庫沒有的（機車停車格、廟宇、鐵窗細節）自己做 |
| 參考庫的地塊生成器是壓縮打包檔，`regionDriver-*.js` 缺 | 先反壓縮整理讀懂；缺的 driver 用 Tokyo 的 `streamer.js` 補 |
| 工業物流（廠房）沒有對應的外觀 | 自己定：大跨度、低、鋸齒或平頂、少窗 |
| 道路、人行道、路燈要有道路資料 | 實景地圖目前由 MapKit 畫路；3D 要道路就要從 OSM 整包檔（決策 93 的 pyosmium 流程）另做道路檔 |
| 全台足跡約 80 MB gzip | 分區下載或只帶玩家選的地區；試片只帶 1 km² |
| iOS 上的幀時間、記憶體、耗電 | 試片在實機量 |

## 12. 查證邊界

- **VERIFIED（本機，Linux 雲端容器）**：
  - 讀過 Tokyo `17c8bbe` 的 `meshing.js`、`tileformat.js`、`streamer.js`、`props.js` 的模型與 `Pool`、`materials.js` 的外觀 shader 前段、`constants.js`、`tileWorker.js`、`geo.js`、`terrain.js`、`tools/pipeline/compile.mjs` 的建物段、`landscape.mjs` 的 `placeProps`，以及 README、`performance.md`、LICENSE。
  - 私有參考庫的檔案與行數、`station-layer.js` 126–139 行、`regionLots`／`world*` 的關鍵字與參數，已用 `grep` 核對。
  - §6 的數字：`extract_patch.py` 與 `measure_patch.mjs` 實際跑過兩次，結果相同。
- **UNVERIFIED**：
  - iOS 上的一切：幀時間、記憶體、shader 翻譯、RealityKit／SceneKit 的能力與 iOS 版本限制。
  - §6 推到手機視野的三角形與記憶體估算。
  - 參考庫壓縮打包檔的完整行為（只讀了關鍵字附近）。
  - 本 PR 沒有改 Swift，所以沒有跑 `swift build` 或測試。
