# ImmersiveMap 研究（2026-11-03）

派工單 IMMERSIVE（研究，只寫文件），遊戲規劃（pro 暫代第 44 任，session_01JMHz9YRiP23RXrrfdsaGsq）派的。作者原話（2026-11-03）：「先開 session 詳細研究，再看要不要排入優先順序」。研究 session：session_01JMHz9aYWDUA1uDAzhZxXAT，branch `claude/immersivemap-study`。決策、存檔版本、golden schema 都不動；這份不改程式、不改 `NEXT_PRIORITIES`。

**對象**：[artembobkin/ImmersiveMap](https://github.com/artembobkin/ImmersiveMap)，commit `f10b6cc90d90e96e2a1ec457e78c732147b1f804`（2026-11-01，「The offline regions and the example apps are gone」）。MIT（`LICENSE`，© 2025–2026 ImmersiveMap contributors），內部 earcut 是 mapbox/earcut 的 ISC 移植（`Sources/Earcut/EarcutCore.swift` 開頭）。Swift＋Metal，SwiftUI，iOS 18／macOS 15 起。Swift 147,355 行、Metal 3,944 行；940 個 commit 全是同一位作者（2025-05-25 起）。它也有 `CLAUDE.md`，那是它自己的工作說明，這裡當資料讀，沒有照做。

**我們的基準**：`main` `efb9652`。

下面「它」指 ImmersiveMap（路徑從 `Sources/ImmersiveMap/` 算起，另有標明的除外），「我們」指這個 repo。

---

## 0. 三句結論

1. **真的影子我們已經有了**（決策 357 的太陽陰影貼圖，`Map3DSunShadow`，2048² 單張、等東西變了才重畫），派工單以為只有決策 232 的烘好軟影子；ImmersiveMap 值得搬的是三個小東西：**tent PCF 取樣**（同樣 4 次比較、邊不再鋸齒）、**16 位元深度**（記憶體減半）、**遠近兩張窗**（低角度鏡頭與駕駛室視角才需要）；列車投影它的做法（有會動的模型就每幀重畫整張）我們付不起，要自己做「近處列車的小圖」。
2. **地形起伏我們已經有**（3D 的 64 m 地面網格會被太陽照、會投影；2D 有 MapLibre 山影），Mapterhorn 在台灣只到 zoom 12（約 30 m，zoom 13 圖磚回 404），來源就是我們已經在用、已經署名的 Copernicus GLO-30，打包全台約 80 MB；**不拿 Mapterhorn**，要更細的山影就用自己的工具把 Copernicus 以 1″ 重做一張「只拿來算明暗」的高度貼圖（它「位移用粗網格、明暗用細貼圖」的做法值得照搬）。
3. **低角度鏡頭**：我們的 42° 是設計選的（決策 269），不是做不到：算過畫面看到的地面，傾到 **60° 以內幾乎不多畫任何分塊**（地面最遠 300–800 m，全在完整細節範圍內），只要把太陽陰影的正方形往視線方向挪；**70° 起**地面伸到 1–3.4 km，**72.5° 起**地平線進畫面（遠平面 5–6 km、要畫的分塊從 4 塊變 50–110 塊），那時才需要它的「遠處降級成貼圖的環、地平線背板、以公尺計的地面霧」。建議先做一個「雙指上下拖可再斜到 60°」的小 PR，其他排後面；**整包當依賴不做**。

---

## 1. 真的影子

### 1.1 它怎麼做

| 項目 | 它的檔案：行 | 數字 |
| --- | --- | --- |
| 兩張窗（不是多層 cascade） | `Shadows/ShadowCascadeAtlas.swift:28–75`（`ShadowCascadeSlot.near = 0`、`.far = 1`，45、49 行） | 一個 depth texture array，兩個 slice，各自一個 render pass；不用 `render_target_array_index`（iOS 模擬器沒實作） |
| 深度格式 | `ShadowCascadeAtlas.swift:33` | `depth16Unorm`：投影收緊到投影者的深度範圍再 clamp，32 位元沒多買到精度，卻多一倍記憶體與頻寬 |
| 解析度 | `Configuration/ImmersiveMapSettings.swift:1512` | 預設 4096²（可設 256–4096）；兩張 × 4096² × 2 bytes = **64 MiB** |
| 近窗涵蓋 | `ImmersiveMapSettings.swift:1513` | 半徑：zoom 12 24 km、14 6 km、16 1.5 km、18 500 m（每 zoom 減半） |
| 遠窗涵蓋 | `ImmersiveMapSettings.swift:1514` | 近窗的 4 倍（96 km … 1.5 km）；遠窗淡入帶起點要在近窗外才開，否則只畫一張 |
| 強度 | `ImmersiveMapSettings.swift:1511` | zoom 14 以前 0（不跑任何影子 pass）、15 起 0.22；太遠時山影交給 hillshade |
| 重用 | `Shadows/ShadowMapReuseController.swift:7–34、117` | 太陽與建物不動，所以窗沒過期就不重畫；擬合時把範圍放大 1.1 倍（`radiusMargin`，34 行）當移動餘裕，中心對齊整數 texel；兩張窗各自判斷，近窗重畫不拖遠窗。**有會動的模型投影時每幀重畫**（12、118–122 行，`hasMovingShadowCasters`） |
| 開關閘 | `Shadows/ShadowPassGateResolver.swift:60–85` | 有影子狀態 **且** 至少有一種投影者（建物、模型、山）才跑；pass 規劃與取樣兩邊叫同一個函式，同一幀不會不一致 |
| 地面遮罩 | `Shadows/GroundShadowMaskPipeline.swift:11–26`、`Shadows/Shaders/GroundShadowMask.metal:60` | 全螢幕一個三角形，從像素反推視線打到 z = 0 平面，查一次影子寫進 `r8Unorm`；解析度 **0.4 倍**畫面（20 行；註解寫「Half resolution」，值是 0.4）。原因：平面地面是好幾層混色疊起來（土地、幾種道路、覆蓋層），每層都查一次影子要 4–6 次，現在一次 |
| 取樣 | `Render/Shaders/Shared/RenderUniforms.h:176` 起 | Castaño 的 3×3 tent PCF（The Witness）：**4 次硬體雙線性比較**、算好權重，重建一個 C1 連續的 tent 核；`tentSpread` 再放寬邊（預設 softness 1.5） |
| 兩窗交接 | `RenderUniforms.h:159`（`shadowCascadeBlend`） | 近窗外圍四分之一淡進遠窗；遠窗外圍四分之一淡出 |
| 山投影 | `ImmersiveMapSettings.swift:966`（`castsShadows`） | 地形也畫進影子圖；但影子 zoom 14 起才有、地形 13.7 起就壓平，所以預設下山影其實靠 hillshade |

**每幀花多少**：它沒有在 repo 裡寫實測數字；Linux 沒有 Metal，這裡量不到 —— **UNVERIFIED**。能從結構推的：沒重畫的幀只多「地面遮罩一個 0.4 倍全螢幕 pass」＋每個有幾何的接收者 4 次比較；重畫的幀多一個或兩個只寫深度的 pass。

### 1.2 我們現在

決策 232 的團狀影子：`Sources/GamePresentation/Map3DGeometry.swift:576`（`addShadow(inner:outer:darkness:)`）、`Map3DScene.swift:979`（每棟樓、樹、高架、列車腳下一片）、`RailwayGameApp/Views/Map3D/Map3DShaders.metal:586`（`map3dShadowVertex`，最後混色疊上），夜裡淡到 0.4（`Map3DGeometry.swift:701`）。

**加上決策 357 的太陽陰影貼圖**（派工單沒提到，這是最重要的對照）：

| 項目 | 我們的檔案：行 | 數字 |
| --- | --- | --- |
| 一張正方形窗 | `Sources/GamePresentation/Map3DSunShadow.swift:26、50–55` | 2048²；半邊 = 鏡頭距離 × 1.1，220–1,800 m，以 1.3 倍分級；鏡頭 4 km 外不畫 |
| 深度格式 | `RailwayGameApp/Views/Map3D/Map3DMetalView.swift:455` | `depth32Float`，2048² = **16 MB**（1024² 4 MB） |
| 重畫 | `Map3DMetalView.swift:477`（`wantedSunRegion`）、`Map3DSunShadow.swift:62–67` | 太陽轉 0.01 rad、目標移出半邊的 1/4、換級、場景重蓋；兩次至少隔 0.25 s（超預算 1 s） |
| 畫進去的 | `Map3DMetalView.swift:499`（`drawSunMap`） | 太陽看得到的分塊（完整或簡化）、遠景方塊實例（決策 455）、街道設施實例；**列車、行人、車輛不畫** |
| 取樣 | `Map3DShaders.metal:159–172`（`map3dSunSeen`） | ±1 texel 四個點各一次 `sample_compare`，**等權平均**（盒狀） |
| 畫質 | `Map3DSunShadow.swift:35`（`plan`） | 省電不畫；自動在低電量或 `.serious` 發熱不畫；GPU 超預算 1024²／1 s |
| 夜裡 | `Map3DSunShadow.swift:166` | 太陽強度 0 就不畫不查；月光不投影 |

決策 357 量過一次重畫：台北 800 m 鏡頭，30 塊、160,541 個網格三角形＋5,273 個設施實例，約 20–50 萬三角形、30–60 個 draw，只寫深度；平常好幾秒才重畫一次。

### 1.3 差在哪、能搬什麼

| 它的 | 我們的對應 | 要不要搬 | 好處 | 估工 |
| --- | --- | --- | --- | --- |
| Castaño tent PCF（`RenderUniforms.h:176`） | `map3dSunSeen` 的 4 點等權（`Map3DShaders.metal:159–172`） | **搬**（MIT，註明出處） | 取樣次數不變（4 次比較），斜邊不再一階一階；決策 357 的「影子邊鋸齒」實機待看項直接改善 | 1 PR，shader 約 30 行＋Swift 傳 texel 尺寸不變；Linux 只能測 uniform 排法 |
| `depth16Unorm` | `depth32Float`（`Map3DMetalView.swift:455`） | **搬** | 16 MB → 8 MB、取樣頻寬減半。我們深度範圍是目標前後各 4 km（`depthReach`），8 km ÷ 65,536 ≈ 12 cm 一級，小於現在的 0.3 m 深度偏移 | 同上一個 PR，約 5 行；要實機看有沒有新的痤瘡 |
| 兩張窗＋交接帶（`ShadowCascadeAtlas`、`shadowCascadeBlend`） | 一張，以目標為中心 | **等鏡頭放寬到 60° 以上或處理駕駛室視角時才搬**（決策 357「下一步」第 3、4 項已記：駕駛室看遠處沒影子、4 km 外沒影子） | 低角度與駕駛室視角遠處有影子 | 1–2 PR，Swift 約 300–450 行（它的 `ShadowFrameStateResolver.swift` 778 行，我們不要它的球面與地形部分）、shader 約 40 行；兩張 2048² depth16 = 16 MB，和現在一樣 |
| 窗擬合放大 1.1 倍＋整數 texel | 已經有：`moveShare` 0.25 與對齊 texel（`Map3DSunShadow.swift:67、127`） | 不用搬 | — | — |
| 投影者閘（`ShadowPassGateResolver`） | 已經有：強度 0、太遠、省電就不畫 | 不用搬 | — | — |
| 地面遮罩（0.4 倍） | 我們每個面查一次（城市、看穿、招牌三個 fragment） | **先量再說** | 我們實景地圖的地面也是好幾層疊（覆蓋、人行道、道路、標線，`Map3DRealGround.swift`），每層各查一次；值不值得要看實機的 overdraw 與 GPU 時間 | 若做：1 PR，約 200 行（新 pass、新貼圖 0.4 倍 × r8，iPhone 直式約 0.5 MB） |
| 會動的模型 → 每幀重畫整張 | 列車不投影（決策 357 第 3 點） | **不照搬** | 我們一次重畫 20–50 萬三角形，每幀做會直接吃掉 `Map3DMotionBudget` 的 standard 60 萬（`Map3DMotionBudget.swift:67–71`） | — |

**列車與地標會不會投影**：

- **地標**：會。台北地標（決策 457）是蓋進分塊網格的（`Map3DScene.swift:362`，`addTaipeiLandmarks`），`drawSunMap` 畫分塊時就畫進去了。
- **列車**：現在不會，只有貼地的團狀影子。建議做法（我們自己的設計，參考它「每張窗各自判斷要不要重畫」的思路）：另開一張**只放近處列車**的小深度圖（1024² depth16 = 2 MB，涵蓋目標 ±200 m），每幀重畫（只畫 `Map3DModelReach` 已經在畫的近處車廂），shader 取兩張的較暗值。成本：近處十幾節車，每節幾千面，約 3–8 萬三角形一幀，**要算進 `Map3DMotionBudget`**（決策 417 的同一份預算，負荷重時第一步就關掉它）。估 1–2 PR，Swift＋Metal 約 250–400 行＋Linux 測試（範圍、預算計數）。
- **夜裡**：照決策 357 — 太陽強度 0 時兩張都不畫不查；列車的小圖也跟著關（夜裡列車有決策 334 的發光地環）。
- **Reduce Motion**：影子不是動畫，不受影響；太陽每轉半度跳一次重畫也不是轉場。唯一要注意的是列車影子每幀跟著車走 —— 那是車本身在動，照現有規則（`.claude/skills/motion/SKILL.md`）不屬於介面動畫，不關。

**要實機量**：tent PCF 前後的影子邊；depth16 的痤瘡；地面多層疊時每幀 GPU 時間（看值不值得做地面遮罩）；列車小圖每幀的 GPU 時間；iPhone 17 Pro 與舊 iPad 各一。

---

## 2. 地形起伏、山影與山的陰影

### 2.1 它怎麼做

| 項目 | 它的檔案：行 | 數字 |
| --- | --- | --- |
| 資料 | `Configuration/ImmersiveMapSettings.swift:973` | Mapterhorn `https://tiles.mapterhorn.com/{z}/{x}/{y}.webp`，Terrarium 編碼、512 px |
| 何時起伏 | 同檔 `:976–977` | zoom 10 起從平面升起，**zoom 13.7 起壓回平面**（理由在 846–866 行的註解：30 m 的格子含建物與森林，近看會變成不存在的小丘，所以街景站在平面上） |
| 位移與明暗分開 | 同檔 `:982`（`displacementMaximumZoom` 10）、註解 896–912 行；`Tile/Relief/Shaders/GroundRelief.h:44–48` | 網格頂點只照 zoom 10 的高度位移（阿爾卑斯緯度 53 m 一點，zoom 13 的磚只要 64 格而不是 256 格，三角形少 16 倍）；**明暗用更細的地形貼圖逐像素算** |
| 山影 | `Tile/Relief/Frame/GroundReliefHillshade.swift`（129 行） | 場景光的方向、樣式的陰影色／亮面色、依離眼睛的距離淡出 |
| 山的陰影 | `ImmersiveMapSettings.swift:966`（`castsShadows`） | 地形畫進 §1 的影子圖；預設影子 zoom 14 起才有，地形 13.7 就壓平，所以預設看不到山投影，要把影子起點調低 |
| 快取 | 同檔 `:984` | 放掉的地形保留 50 MB（約 50 磚） |

### 2.2 我們現在

- **3D**：地面是 64 m 一格的網格（`Map3DScene.swift:992`，`addGround`），高度來自 `RailwayGameApp/Resources/RealWorld/taiwan_heights.dat`（12 MB，Copernicus GLO-30 取到 1.875″ ≈ 58 m，決策 124）。頂點有法線、被太陽照，所以 **3D 本來就有「山影」**（逐頂點，58–64 m 的細度）；地面也在分塊網格裡，所以**山會投影**進決策 357 的貼圖 —— 但只在那個正方形內（半邊最多 1.8 km），更遠沒有。
- **2D 真實地圖**：MapLibre 的 `hillshade` 圖層（`Sources/GamePresentation/BaseMapStyle.swift:141–150`：照參考庫 `map3d.js`，光從 315°、exaggeration 0.42），資料是我們自己做的 `RailwayGameApp/Resources/BaseMap/taiwan_terrain.pmtiles`（10 MB，`tools/basemap/build_terrain.py`，zoom 0–10、512 px ≈ 70 m 一像素）。
- **2D 高度圖層**：`Sources/GamePresentation/TerrainMap.swift:29`，自己算的高度色＋西北光明暗（最多 1,025 × 1,025 角點，`:31`）。

### 2.3 Mapterhorn 能不能打包台灣

這次實際打了它的端點（2026-11-03）：

- `tilejson.json` 的署名是 `© Mapterhorn`（連到 `mapterhorn.com/attribution`），Terrarium、512 px。
- 台灣中部 zoom 12 的磚（`12/3424/1766`）200，131 KB；**zoom 13（`13/6849/3533`）404** —— 台灣沒有 zoom 13 以上的光達資料，只有全球的那一層。它的設定註解也寫「30 m everywhere to zoom 12 and lidar deeper where a country publishes it」（`ImmersiveMapSettings.swift:809–812`），全球那層就是 Copernicus GLO-30。
- 本島外框（120.0–122.05°E、21.85–25.35°N）在 zoom 12 有 1,080 磚；隨機抽 40 磚，平均 57.6 KB（海上的磚 52 bytes）→ zoom 12 約 **62 MB**，加上 zoom 0–11 估 **約 80 MB**（金門、馬祖另計，幾 MB）。我們現在 2D 山影 10 MB、3D 高度 12 MB。
- 授權：程式 BSD-3；資料是「各來源的開放授權」，完整清單在 `download.mapterhorn.com/attribution.json` —— **這次抓回 404，台灣這一格的確切授權條款 UNVERIFIED**。若用，`DataSourceCredits` 要加「© Mapterhorn」並保留底下 Copernicus 的那一句（我們已經有，決策 115、124）。

**結論：不拿 Mapterhorn。** 在台灣它就是 Copernicus GLO-30（我們已經用、已經署名），好處只有「30 m 而不是我們的 58 m」—— 這個我們自己的工具就做得到（決策 115 抽 Copernicus 時是 1″，決策 124 才降到 1.875″）。多一個署名、80 MB、授權清單還抓不到，換不到新資料。國土測繪中心 20 m DEM 才是真的更好的資料，但 tgos.tw 在這個環境回 403（ARCHITECTURE 決策 115 的記錄），仍是缺口。

### 2.4 可以搬的是做法

| 它的 | 我們的對應 | 建議 | 估工 |
| --- | --- | --- | --- |
| 位移用粗網格、明暗用細貼圖（`GroundRelief.h:44–48`） | 3D 地面逐頂點的法線（64 m） | **搬做法**：把 Copernicus 以 1″（約 30 m）重做一張只給 shader 算明暗的高度貼圖（例如 R16，台灣本島約 1.2 萬 × 1.3 萬點 → 依分塊切片只載入鏡頭附近），地面 fragment 用它算法線；網格不變 | 2 PR：工具（`tools/basemap/` 加一支，Python，約 150 行）＋ App（貼圖載入、shader 約 60 行、Swift 約 200 行）；檔案大小估 20–40 MB（壓縮後，**UNVERIFIED**，要先量）—— 要作者看要不要多帶這些 MB |
| 13.7 起壓平（30 m 資料近看是假小丘） | 我們鏡頭 60–800 m 一直有起伏，軌道要它 | **不搬**（我們的地面是遊戲規則的地面，GameCore 的軌道坡度用它）；但它的理由提醒：細貼圖的明暗在 150 m 以內要淡出，否則 DSM 殘留的建物會變成山坡上的斑點 | 併在上一列 |
| 山投影要遠窗 | 山只在 1.8 km 正方形內投影 | 跟 §1 的兩張窗一起做 | 見 §1.3 |
| 2D 山影更細 | `taiwan_terrain.pmtiles` 到 zoom 10 | 可選：`build_terrain.py` 的 `MAX_ZOOM` 加到 11（約 35 m 一像素，和 30 m 資料相當），檔案估 3–4 倍（+20–30 MB，**UNVERIFIED**） | 1 小 PR，工具改一個常數＋重產；要作者同意 App 變大 |

**要實機量**：細明暗貼圖每幀多一次取樣的 GPU 時間；記憶體（只載附近的切片）；中央山脈與台北盆地邊在 150–800 m 的樣子。

---

## 3. 低角度鏡頭

### 3.1 它

- 最大傾角 **85°**（`ImmersiveMapSettings.swift:2335`，`Float.pi * 17 / 36`），每個 zoom 都可以；最近到 zoom 18（`:2346`，「再近就超過圖磚畫的細度」）。
- 有傾斜手勢（`tiltGestureSensitivity: 2.0`）、傾角追隨的半衰期 0.06 s（`pitchFollowHalfLife`，`:307、358`），另有「高 zoom 多給一點傾角」的曲線（`highZoomPitchExtension`，預設 0）。
- 撐住低角度的不是單一技巧，是一整套：
  - **環狀 LOD**（`Tile/Visibility/RingRuleSets.swift:30–103`）：zoom 15–16 時目標那圈是完整幾何，第 1–3 圈降一級、畫成 64 texel 的貼圖，第 3–13 圈降四級、128 texel 貼圖、沒有線與字；zoom 17 起只到第 2 圈，再外面只剩「地平線背板」。
  - **地平線**：`Horizon/`（背板、邊、帶狀網格）。
  - **地面霧**：`GroundFog/`，長度以公尺計，所以每種螢幕、每種傾角看到的是同樣的地面。
  - **影子**：近窗依「看得到的地面」擬合（`ImmersiveMapSettings.swift:1410–1412` 註解），看不到的公尺不花 texel。

### 3.2 我們

- `Sources/GamePresentation/Map3DCamera.swift:38`：視角高 35°；`:46–48`：800 m 外平視、120 m 內 42°（**決策 269** 從 55° 改下來：舊曲線 170 m 時太斜、遠處分塊排到畫面頂、交接時跳；**決策 313** 交接改在 2D 最近處）；傾角**只跟距離**，沒有傾斜手勢（決策 269 的表：MapLibre 的手動 pitch 記為缺口）。
- 遠平面 `:120`：距離 × 6 ＋ 4,000 m。
- 完整細節：鏡頭 1.6 km 內、目標或眼睛下方 max(700 m, 1.2 × 距離) 內（`:173`、`wantsDetail`）；串流的場景 2 km 內完整（`Map3DScene.swift:100`，決策 368 為了記憶體），保留目標 3 km 內（`Map3DStreaming.swift:43`），整個場景各方向 6 km（`Map3DScene.swift:89`），分塊 512 m（`:85`）。
- **駕駛室視角早就幾乎水平**（決策 337：`Map3DFollow.swift:181–183`，往下 1.1°、鏡頭 68°）：所以「畫到地平線」引擎是畫得出來的，天空（決策 347）與霧（決策 349）都在。

### 3.3 卡在哪 —— 算出來的

用我們自己的相機參數（視角 35°、遠平面 6d＋4000、iPhone 402×874 直式與橫式）算畫面裡地面的範圍（scratchpad 腳本，Python，純幾何，**VERIFIED**（Linux）；分塊數是 512 m 格、目標放在格角的粗估）：

| 鏡頭距離 | 傾角 | 直式：地面最遠（離目標） | 直式：分塊 | 橫式：地面最遠 | 橫式：分塊 | 地平線入鏡 |
| --: | --: | --: | --: | --: | --: | :-: |
| 200 m | 42°（現在） | 125 m | 4 | 225 m | 4 | 否 |
| 200 m | 50° | 164 m | 4 | 270 m | 4 | 否 |
| 200 m | 60° | 285 m | 4 | 410 m | 4 | 否 |
| 200 m | 70° | 1,396 m | 8 | 1,718 m | 14 | 否 |
| 200 m | 75° | 5,240 m | 24 | 6,292 m | 74 | **是** |
| 400 m | 60° | 570 m | 6 | 821 m | 10 | 否 |
| 400 m | 70° | 2,791 m | 14 | 3,436 m | 42 | 否 |
| 400 m | 75° | 6,302 m | 32 | 7,622 m | 112 | **是** |

（35° 視角的上緣在傾角 + 17.5°，所以傾角過 72.5° 就看得到地平線。）

所以：

| 傾角上限 | 卡在哪 | 要動什麼 |
| --- | --- | --- |
| **≤ 60°** | 幾乎不卡：地面最遠 300–800 m，全在完整細節範圍（700 m／1.6 km）與串流範圍（3 km）內，分塊數不變。唯一的問題是**太陽陰影正方形以目標為中心**（半邊 220 m 起），畫面上半的地面可能在正方形外（例：200 m、60°、橫式到 410 m） | `Map3DCamera` 加一個「手勢多給的傾角」（決策 269 的曲線照舊當預設）；`Map3DSunShadow.region` 的中心往視線方向挪半個可見深度。約 1 PR、Swift 150–250 行（GamePresentation＋手勢）＋Linux 測試；不動 GameCore |
| **60–72°** | 地面伸到 1.4–3.4 km：`wantsDetail` 的 reach 以目標／眼睛下方為中心，遠處分塊會是簡化版（看得出換級）；影子正方形蓋不到 | 上一列＋影子要兩張窗（§1.3）；完整細節的範圍改成沿視線方向（不是圓）。2–3 PR |
| **> 72.5°** | 地平線入鏡、遠平面 5–6 km、分塊 24–112 塊；`Map3DStreaming.around` 3 km、場景 6 km，靜止時橫式 75° 會看到場景邊；三角形預算（`Map3DMotionBudget`，standard 60 萬；遠景分塊的靜態三角形另計）**UNVERIFIED** | 它的整套：遠處環改成貼圖或更粗的方塊、地平線背板、以公尺計的霧把場景邊藏起來。4–6 PR，大；駕駛室視角的經驗（霧、天空）可以直接用 |

**它的哪些能搬**：傾斜手勢與追隨半衰期（概念與數字，約 50 行）、「依看得到的地面擬合影子窗」（§1.3 的兩張窗）、霧以公尺計（我們 `Map3DLighting.fogScale` 已經是倍率，可以改成公尺）。環狀 LOD 的貼圖化依賴它的圖磚 pipeline（MVT → 貼圖），我們是分塊網格，**不能直接搬**，只能借「遠處用更便宜的表示」這個想法 —— 我們的對應是已有的 `far`、`farBoxes`（決策 455），還可以再加一級「只有地面與屋頂色塊」。

**作者的目標畫面**是 150–200 m 時 34–40°（HANDOFF §4.4，決策 269）。所以預設曲線不動，60° 只當手勢可以去的上限，放手後保持（不彈回），拉遠超過 `flatFrom` 時照舊回平視。

**要實機量**：60° 時影子挪過去後拖地圖的重畫頻率；70° 與 75° 的分塊數、三角形、GPU 時間（設定裡的幀數讀數）；記憶體（決策 368 的 3.4 GB 上限）。

---

## 4. 其他可借的（只列有實際好處的）

| 它的 | 我們的 | 結論 |
| --- | --- | --- |
| 建物圓角擠出 `Tile/Parse/Buildings/BuildingRoundedExtrusion.swift`（280 行）：每個垂直角一個斜面、屋頂邊一圈，法線取兩面的，內插後看起來是圓角；半徑取窄邊 1/4 與高度一半以內 | 我們的近景建物是 `addBox` 與配方（`Map3DBuildings.swift`，決策 235 的工廠斜屋頂、山牆等），遠景是方塊實例（決策 455） | **可借，只用在近景的實景建物足跡**（台北的大樓）：一個四角盒從 10 個三角形變約 30 個；遠景方塊實例共用 30 個索引，圓角會打破實例化，不改。好處是近看柔和、像商業地圖。估 1 PR、約 200 行（MIT，註明出處）。優先度低 |
| 屋頂 `BuildingRoofLookup.swift`（99 行） | — | 不是屋頂造型，只是「標籤放到屋頂高度」的查表。**沒有可搬的屋頂**；我們的斜屋頂、山牆比它多 |
| 標籤碰撞 `Labels/Collisions/`（`LabelCollisionSolver` 等，標籤全部 5,377 行） | 3D 的名牌是 SwiftUI 疊在上面（`Map3DTrainLabels.swift`），2D 的避讓在 `MapClutter.swift:63`（決策 510） | **不搬**：它是 GPU 文字標籤的整套（排序、字形、碰撞），我們的 3D 名牌少、是 SwiftUI |
| PMTiles `Sources/PMTiles/`（934 行：HTTP range、leaf LRU、同時請求共用） | `Sources/GamePresentation/PMTilesArchive.swift`（153 行，mmap 本地檔、gzip） | **不搬**：我們只讀 App 內的檔案，不需要 HTTP 與並行；它多的 gzip 以外格式我們也沒有 |
| MVT 解碼 `Sources/Mvt/`、earcut `Sources/Earcut/` | 我們已有 `VectorTile.swift`、`Earcut.swift` | 不搬（已有） |

---

## 5. 不該拿的與風險：整包當依賴

**結論：不加依賴。** 理由：

1. **平台**：它 iOS 18 起（`Package.swift`），我們 App 是 iOS 17（`RailwayGameApp/project.yml:20`、`Package.swift` `.iOS(.v17)`）。要用就得丟掉 iOS 17 玩家。
2. **第二套 renderer**：我們的 3D 是自己的 Metal（`Map3DMetalView.swift` 1,470 行＋`Map3DShaders.metal` 790 行＋GamePresentation 5 萬行的場景），2D 是 MapLibre。再加一套 15 萬行的地圖引擎，要讓列車、軌道、城市、車站畫在它的場景裡，等於重寫整個 3D 的接法；兩套 renderer 各自的記憶體（它的影子圖預設就 64 MiB）疊在決策 368 的 3.4 GB 上限上。
3. **作者主機的資料**：預設底圖與模型是 `tiles.immersivemap.dev` 上的 PMTiles（`Configuration/ImmersiveMapTilesService.swift:19、27`），地形是 Mapterhorn 的線上端點；我們的 2D／3D 都是離線打包（決策 151、234），也不想依賴別人的主機與流量。
4. **單人維護**：940 個 commit 同一人、2025-05 才開始、最新一個 commit 還在刪功能（「The offline regions and the example apps are gone」）—— API 還在動。
5. **新依賴本來就是作者的決定**（CLAUDE.md Workflow）；這份只建議「讀它、照 MIT 搬小段並註明」，不建議加套件。
6. Linux CI：它的模組幾乎都 import Metal；Earcut／Mvt／PMTiles 這三個看起來不碰 Metal，但這次在 Linux 試編被 session 的權限擋下（外部程式碼），**UNVERIFIED**；反正這三個我們都已經有。

搬小段時：保留它的 MIT 版權行（`Copyright (c) 2025-2026 ImmersiveMap contributors`），寫進該檔開頭與決策；Castaño tent PCF 本身是公開的演算法（The Witness 的部落格），照它的寫法與出處都註明。

---

## 6. 對照表（它 → 我們）

| 它的檔案／函式 | 我們的檔案／函式 | 做法 |
| --- | --- | --- |
| `Render/Shaders/Shared/RenderUniforms.h:176`（tent PCF） | `Map3DShaders.metal:159` `map3dSunSeen` | 移植（MIT） |
| `Shadows/ShadowCascadeAtlas.swift:33` `depth16Unorm` | `Map3DMetalView.swift:455` `makeSunMap` | 照改 |
| `Shadows/ShadowCascadeAtlas.swift` 兩個 slot＋`RenderUniforms.h:159` 交接 | `Map3DSunShadow.Region`／`rows`、`drawSunMap` | 想法，自己寫（等 §3 的 60° 以上或駕駛室視角） |
| `Shadows/ShadowMapReuseController.swift` 每窗各自重用 | `Map3DMetalView.swift:477` `wantedSunRegion` | 已有同等；加「列車小圖每幀、靜態圖照舊」 |
| `Shadows/GroundShadowMaskPipeline.swift`、`GroundShadowMask.metal` | 無 | 先實機量 overdraw |
| `Tile/Relief/Shaders/GroundRelief.h:44–48` 明暗與位移分開 | `Map3DScene.addGround`（`Map3DScene.swift:992`）＋shader | 想法；資料自己從 Copernicus 1″ 做 |
| `ImmersiveMapSettings.swift:973` Mapterhorn | `taiwan_heights.dat`、`taiwan_terrain.pmtiles`、`build_terrain.py` | 不用 |
| `ImmersiveMapSettings.swift:2335` 85°、傾斜手勢、`pitchFollowHalfLife` | `Map3DCamera.swift:46–48`、`tilt(atDistance:from:)` | 手勢與數字的想法，上限 60° |
| `Tile/Visibility/RingRuleSets.swift`、`Horizon/`、`GroundFog/` | `Map3DCamera.wantsDetail`、`Map3DStreaming`、`Map3DLighting.fogScale` | 想法，> 72° 才需要 |
| `Tile/Parse/Buildings/BuildingRoundedExtrusion.swift` | `Map3DMesh.addBox`（實景建物足跡） | 可選移植（MIT） |
| `Sources/PMTiles/`、`Sources/Mvt/`、`Sources/Earcut/` | `PMTilesArchive.swift`、`VectorTile.swift`、`Earcut.swift` | 已有，不用 |

---

## 7. 建議排序（給遊戲規劃決定要不要排進 `NEXT_PRIORITIES`）

| 順序 | 代號（建議） | 內容 | 大小 | PR 數 | 估行數 | 動 GameCore | 模型 | 放哪 |
| --: | --- | --- | --- | --: | --: | :-: | --- | --- |
| 1 | **SUNPCF** | tent PCF＋depth16（§1.3 前兩列） | 小 | 1 | shader 30＋Swift 10＋測試 | 否 | Sonnet | **110 版**：小、直接改善決策 357 待看的影子邊、記憶體減半；要截圖驗收（small change） |
| 2 | **TILT60** | 雙指上下拖可再斜到 60°；太陽陰影正方形往視線方向挪（§3.3 第一列） | 中 | 1 | 150–250 | 否 | Opus | **110 版或下一版**：作者會喜歡的畫面變化、成本最低的那一段；預設曲線（決策 269）不動 |
| 3 | **TRAINSHADOW** | 近處列車的小深度圖，每幀，算進 `Map3DMotionBudget`（§1.3） | 中 | 1–2 | 250–400 | 否 | Opus | 110 之後：鐵道迷最看得到，但要先有 1 的實機結果 |
| 4 | **RELIEF30** | Copernicus 1″ 明暗貼圖＋shader（§2.4） | 中 | 2 | 工具 150＋App 260 | 否 | Opus | 更後面：先量檔案大小，App 變大要作者點頭 |
| 5 | **SUN2WIN** | 影子兩張窗（近／遠），順便補駕駛室視角遠處的影子 | 中大 | 1–2 | 300–450 | 否 | Opus | 跟 6 一起，或駕駛室視角被抱怨時 |
| 6 | **TILT75** | 60° 以上：沿視線的細節範圍、遠處更便宜的一級、地平線、霧以公尺計 | 大 | 4–6 | 1,500＋ | 否 | Opus | 更後面，要先有 2 的實機數字 |
| — | 地面遮罩、建物圓角、2D 山影 zoom 11 | 見各節 | 小～中 | 各 1 | — | 否 | Sonnet | 量了再說／作者要才做 |
| — | ImmersiveMap 當依賴、Mapterhorn 資料 | — | — | — | — | — | — | 不做 |

1 與 2 不同檔（1 是 shader 與 `Map3DMetalView` 的貼圖；2 是 `Map3DCamera`、手勢與 `Map3DSunShadow.region`），可以同時派；3、5 都改 `drawSunMap` 與 `map3dSunSeen`，要排隊。都不動 GameCore、存檔、golden。

### 五方

- **玩家**：1 看不出「改了什麼」但影子乾淨；2 是看得到的新玩法（把城市斜著看、看街景天際線）；3 讓列車像真的停在陽光下；6 是大工程，等 2 證明大家會用再做。
- **鐵道迷**：3 最重要（列車在月台與高架上的影子）；4 讓山線（北迴、南迴、阿里山）的山形更像；地形資料來源不變，仍是 Copernicus，不混入另一家主機的資料。
- **開發**：只搬 MIT 的小段並註明，不加依賴；每項都在 GamePresentation 有 Linux 測得到的部分（區域、範圍、預算計數），Metal 的部分交給 iOS build 與實機；最大的風險是 6 的三角形與記憶體，所以排在最後並要求先量。
- **美術**：tent PCF 讓斜邊不再一階一階；60° 的低角度最能讓決策 457 的地標與實景街道被看到；圓角建物是可選的柔化，不急。
- **音樂**：無。

---

## 8. 它的 README 圖（只連結，不放進 repo）

- [地球與歐洲](https://github.com/artembobkin/ImmersiveMap/blob/f10b6cc90d90e96e2a1ec457e78c732147b1f804/Assets/readme-globe-europe.png)
- [馬特洪峰：起伏、山影、山的陰影](https://github.com/artembobkin/ImmersiveMap/blob/f10b6cc90d90e96e2a1ec457e78c732147b1f804/Assets/readme-matterhorn.png)
- [策馬特山谷](https://github.com/artembobkin/ImmersiveMap/blob/f10b6cc90d90e96e2a1ec457e78c732147b1f804/Assets/readme-zermatt-valley.png)
- [曼哈頓：擠出建物、影子、街名](https://github.com/artembobkin/ImmersiveMap/blob/f10b6cc90d90e96e2a1ec457e78c732147b1f804/Assets/readme-manhattan.png)
- [羅馬廣場：傾斜鏡頭](https://github.com/artembobkin/ImmersiveMap/blob/f10b6cc90d90e96e2a1ec457e78c732147b1f804/Assets/readme-rome.png)
- [柏林夜色](https://github.com/artembobkin/ImmersiveMap/blob/f10b6cc90d90e96e2a1ec457e78c732147b1f804/Assets/readme-berlin-night.png)

---

## 9. 這次怎麼查的、什麼沒驗證

- **讀了**：它的 `README.md`、`Package.swift`、`LICENSE`、`Sources/ImmersiveMap/Shadows/`（全部 1,504 行的結構與註解）、`Tile/Relief/`（3,623 行的結構）、`Configuration/ImmersiveMapSettings.swift` 的影子、地形、相機段、`Tile/Visibility/RingRuleSets.swift`、`Tile/Parse/Buildings/`、`Sources/PMTiles/`；我們的決策 232、269、313、337、357、368、417、455，`Map3DSunShadow.swift`、`Map3DMetalView.swift`、`Map3DShaders.metal`、`Map3DCamera.swift`、`Map3DStreaming.swift`、`Map3DScene.swift`、`TerrainMap.swift`、`BaseMapStyle.swift`、`PMTilesArchive.swift`。
- **參考庫**：這份是對外部專案的研究，不是新 Stage，沒有新開參考檢查；相關的參考庫來源已在決策 124（Mapterhorn 的 manifest 在 `Railway/site_archive_clean/rail-3d/`）、357（`Web/CityView/src/world/environment.js`、`town-scene-reference-clean`）記過。
- **VERIFIED**（Linux，這個 session）：Mapterhorn 端點的回應碼與大小（zoom 12 200、zoom 13 404、40 磚抽樣）；§3.3 的地面範圍計算（Python，純幾何）。
- **UNVERIFIED**：它每幀的 GPU 成本（Linux 沒有 Metal）；它的 Earcut／Mvt／PMTiles 在 Linux 能不能編（權限擋下）；Mapterhorn 台灣那一格的完整授權清單（`attribution.json` 404）；Copernicus 1″ 明暗貼圖的檔案大小；2D 山影 zoom 11 的檔案大小；§7 各項的行數都是估的。
