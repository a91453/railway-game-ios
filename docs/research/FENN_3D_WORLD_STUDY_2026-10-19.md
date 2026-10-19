# Fenn 的 3D 世界怎麼做的，和《沿線》差在哪

2026-10-19。基準：main `fa2e3ff`。來源在文末；「讀過程式」指的是下載開發者公開網頁的 JavaScript 後讀出來的內容，「推論」則是沒有直接證據的部分。

## 1. 結論

- Fenn（iOS，Fenn AI Inc.，YC F26）的開發者是 Charly Delaroche，曾經帶領 Zenly 自製 3D 地圖引擎的團隊，也在 Apple 工作過。Fenn 只有少數挑選過的地區有 3D：巴黎（1.58 版，10/1）、舊金山 Dolores Park（1.60，「有車、Muni 電車和真實的坡」）、Lombard Street（1.61，「深色模式下 3D 世界在夜裡發光」）。另外還有 1.63 版加入的地球儀，按需要下載後快取。所以它不是全世界都有 3D。
- **它沒有用 Kenney。** 開發者公開的澀谷場景，建築、窗、屋頂設備、招牌、人車全部由程式產生，貼圖則是執行時用 Canvas 2D 畫出來的，沒有載入任何 GLB 模型（讀過程式）。看起來像 Kenney，是因為兩者都是平塗色的 low-poly。
- **澀谷的地理資料是 OpenStreetMap，不是 Apple Maps**：`shibuya_osm.json`，以 Overpass 取得（ODbL），範圍 500 m 見方，2026-09-01 抓取（讀過程式）。
- Fenn 的 iOS App 推測是這樣組成的：全世界的底圖由 Apple Maps（MapKit）負責，少數地區再疊上開發者自己引擎畫的 3D。這是推論，依據有三點：(1) 他的「Apple Maps 裡可操控的 3D 飛機」貼文，社群註記說明是用 MapKit 疊上去的自製畫面；(2) Apple 的開發者支援已經說過，MapKit 沒有加入自訂 3D 的 API，現成的做法是在 MapKit 上方疊一層透明 Metal，並讓兩邊的相機同步（munim-maps）；(3) 他的巴黎場景是 Rust 的 wgpu 引擎（讀過程式），而 wgpu 在 iOS 上直接跑 Metal。
- **對《沿線》來說：不需要換引擎。** 遊戲已經有自己的 Metal 3D 地圖（決策 229 起），功能包括依 Overture 建物輪廓擠出的真實建物（決策 239）、夜裡亮窗與路燈光圈（決策 229 續）、分塊與遠近分級（決策 238），以及實例化的人、車、列車。Fenn 的畫面和遊戲現在的差距不在架構，而在三樣便宜的東西上：**bloom＋色調映射**、**依建物大小選外牆樣式**，以及**假的光（地上與牆上的光暈貼片）**。見第 5 節。

## 2. 查證：貼上來的那份分析哪些對、哪些不對

| 原文說法 | 查證 |
| --- | --- |
| 開發者曾參與 Zenly 地圖、做過程序化的遊戲風 3D 地圖 | 對。TechCrunch 2022 年的報導寫到他帶領約 10 人團隊，用 C/C++ 自製跨平台引擎（PBR、deferred、temporal shadow maps、照真實太陽位置算影子）；資料是 OSM 加上授權資料，套用規則自動轉換，只有地標是手工外包建模。首批城市就包括台北。 |
| Zenly 用「Metal／Vulkan」 | 來源沒寫。報導只說「low-level C and C++」，沒有提到使用哪個圖形 API。 |
| 澀谷 Demo 約 500 m、巴黎約 1 km²、WebGL2、手機用較輕的畫質 | 對，網站上的字與程式都這樣寫。補充：巴黎的主版本其實是 WebGPU（Rust wgpu 編成 WASM），WebGL 版只給不支援 WebGPU 的瀏覽器用。 |
| 很像 Apple Maps＋Kenney | 不對。澀谷場景用的是 OSM，模型全部由程式產生，沒有 Kenney（第 3 節）。 |
| 「真實輪廓＋程序化外觀＋少量客製模型」 | 對，而且可以講得更精確：程式依建物大小與一個以建物 id 為種子的亂數，從 7 種外牆樣式中挑一種；只有 109、西武這些地標是逐棟手畫的。 |
| 漂亮的關鍵是燈光 | 對。做法是發光材質加 bloom 加假光貼片，沒有真的燈光（第 3.3 節）。 |
| 不能把 Apple Maps 的建築抓出來重用 | 對（Apple 條款），本專案也不需要這麼做。 |
| 建議 MapLibre Native＋Metal「最值得先驗證」、請 Codex 做獨立原型 | 不適用。`3D_DIRECTION_STUDY.md` 已經比較過 MapLibre，而遊戲早就走了自製 Metal 這條路，原型也已經存在（`Map3DScene`、`Map3DMetalView`）。 |
| 用 Kenney City Kit | 遊戲規劃在 2026-10-17 已經決定**不把 Kenney 放進遊戲**（HANDOFF §2：人物大頭、面數高，而且程式畫的人車已經有了），只在程式做不好時取零件用。 |

## 3. 讀程式看到的做法（澀谷，three.js WebGL）

開發者的公開網站 `3dscenes.qualityf2p.workers.dev` 有 18 個場景（澀谷、巴黎羅浮宮、紐約、白川鄉、弘前、LAX、樟宜等）。澀谷的程式拆成 `ground`、`buildings`、`station`、`signs`、`traffic`、`life`、`streetscape`、`nightglow` 幾個模組。

### 3.1 資料

`shibuya_osm.json`：555 棟建物（360 棟有 `height`、388 棟有 `building:levels`）、260 條道路、572 條步道、88 段鐵路（含銀座線的高架）、79 個號誌、47 個斑馬線、1,102 個 POI。座標全部先轉成以十字路口為原點的公尺座標（x 東、z 南），和本專案 `geo.js` 的投影同一套概念。

### 3.2 建物（`buildings` 模組）

1. 輪廓直接擠出成牆，屋頂加一圈女兒牆。
2. 高度的取法依序是：`height` → `levels` × 層高 → 依用途給預設值，最低 4 m。
3. 外牆樣式依大小決定，並以建物 id 為種子的亂數選（決定論）：
   - 車站、橋、或面積 > 4,200 m² → `plain`
   - 高 < 9.5 m 或不到 2 層 → `shop`（一樓店面）
   - 高 ≥ 58 m → `curtain`（玻璃帷幕）
   - 面積 < 270 m² 且 4–9 層，78% 機率 → `zakkyo`（雜居ビル，窄樓上掛滿招牌）
   - 其他：34% `band`（水平帶窗）、32% `grid`（格子窗）、18% `balcony`（陽台）、16% `curtain`
4. 窗戶不是貼圖，而是凸出牆面幾公分的小方片，用 InstancedMesh 畫，分 5 種材質。夜裡把其中 4 種的發光強度設成 1.45（帷幕那種是 0.75 倍），亮哪些窗由亂數決定。
5. 一樓沿街面畫一圈店面帶。
6. 屋頂設備全部實例化：冷氣、大型冷氣、水塔、天線桿、樓梯間、冷卻塔、管線、屋頂補丁。
7. 地標（109、西武等）的外牆用 Canvas 2D 畫兩張圖，一張白天的顏色圖、一張夜晚的發光圖，同一個函式畫兩次。

### 3.3 夜景（`nightglow` 模組）

**沒有用真的燈光。** 用 Canvas 畫幾張黑底白漸層的貼圖，當成疊加混合的貼片：
- 圓形漸層 → 路燈打在地上的光圈
- 縱向漸層加橫向遮罩 → 打在牆上往上淡出的光
- 扇形 → 車頭燈照在路上的光
- 柔邊橢圓 → 招牌的光暈

再加上：
- ACES filmic 色調映射
- UnrealBloom（讓亮的東西暈開，預覽圖裡路燈周圍的光暈就是這個）
- GTAO（環境光遮蔽）
- 4096 的陰影貼圖

### 3.4 手機怎麼降級（讀過程式）

| 等級 | 解析度上限 | 貼圖 | 陰影 | AO | bloom | LOD | 三角形上限 |
| --- | --- | --- | --- | --- | --- | --- | --: |
| high（電腦） | 2× | 2048 | 4096 | 開 | 開 | 1 | 500 萬 |
| mobile | 1.5× | 512 | **關** | **關** | **開** | 0.5 | 200 萬 |
| lite（WebGL 當掉後重載） | 1× | 512 | 關 | 關 | 關 | 0.5 | 120 萬 |

重點是：**他在手機上關掉陰影和 AO，但保留 bloom。** 可見 bloom 是這種畫風在手機上 CP 值最高的一項。

### 3.5 巴黎（`citygpu`）

- 引擎是 Rust 的 wgpu，用 wasm-bindgen 編成 WASM，跑在 WebGPU 上。
- 幾何預先在電腦上烘好成一個 pack（`npm run citygpu:pack`），用 meshopt 壓縮，執行時只負責下載與繪製。
- 地形用「平台（plateaus）＋邊緣混合」表示。
- 人由幾顆球和圓柱拼成（頭、頭髮、身體、腿、腳、手臂）。

## 4. 和《沿線》現在的 3D 對照

| 項目 | Fenn 澀谷 | 《沿線》原生 3D（main `fa2e3ff`） |
| --- | --- | --- |
| 引擎 | three.js（巴黎是 wgpu） | 自製 Metal（決策 229） |
| 真實建物 | OSM 輪廓＋高度標籤 | Overture 輪廓＋估算樓層，目前只有高雄、台中站周邊（決策 239） |
| 外牆樣式 | 依大小選 7 種，以 id 為種子 | 依用途 `RealKind` 分 7 類，窗戶畫在著色器裡（`Map3DPaint.bays`） |
| 一樓店面、屋頂設備 | 有，實景建物也有 | 種子城市的透天厝有（決策 267）；**實景建物沒有**（HANDOFF §4.4 的缺口） |
| 亮窗 | 實例化窗片＋發光 | 著色器以 hash 決定每格亮不亮（決策 229 續） |
| 路燈光圈 | 疊加貼片 | `addPool` 放在陰影 mesh（決策 229 續） |
| 車燈、牆面打光、招牌光暈 | 有 | **沒有**（HANDOFF §4.2 列為建議） |
| bloom | 有，手機也開 | **沒有** |
| 色調映射 | ACES | **沒有**（線性） |
| AO | GTAO，只在電腦上開 | 沒有（ARCHITECTURE 列為「貴」） |
| 依機型降級 | 3 級＋當掉後重載 | 人車份量依 GPU 分級（決策 259） |
| 地標 | 逐棟手畫 | 廟（決策 268）；真的台灣站房還沒做 |

## 5. 建議：照順序，一次一個 PR，都在現有的 Metal 裡做

1. **Bloom＋色調映射（只在夜晚與黃昏開）。**
   - 做法：多一個 HDR render target，取亮部、降採樣模糊、疊回去，最後做一次 ACES 近似。
   - 為什麼排第一：現在的路燈頭、亮窗、廟的燈籠都已經會發光，只差把光「暈開」，畫面就會接近預覽圖。這也是 Fenn 在手機上唯一保留的後製。
   - 位置：`Map3DMetalView`（App 端，Linux 上無法驗證）。著色器有改時，`tools/map3d-preview/index.html` 要跟著改（HANDOFF §4.2）。
   - 實機驗證：iPhone 17 Pro 要維持 60 fps；舊機型關掉（比照 lite 級）。
2. **實景建物依大小選外牆樣式、補上屋頂設備與一樓店面。**
   - 現在的實景建物只依用途分類。改成用面積、樓層數，加上以 id 為種子的 `map3DRandom`，在台灣自己的樣式裡挑：透天厝、窄樓（台灣版的雜居：每層掛直式招牌）、帶窗公寓、陽台公寓、帷幕大樓。
   - 屋頂設備和雨遮沿用決策 235、267 的零件。
   - 位置：`Map3DRealBuildings.swift`（GamePresentation，可以寫 Linux 測試）。
3. **假光貼片。**
   - 內容：車頭燈的扇形光（每幀實例化）、廟與商店牆面往上打的光、招牌的光暈。
   - 車燈與招牌在 HANDOFF §4.2 本來就列為建議做法，這一步等於照 Fenn 的方式把它們做出來。

不建議：
- 換成 MapLibre、Apple Maps 或 wgpu。
- 把 Kenney 搬進遊戲。
- 在手機上開 AO 或高解析度陰影。

## 6. 架構風險（另一份研究的補充）

作者在同一天另外收到一份《沿線 Fenn 3D World 技術研究》（約 56 KB，作者以附件提供，基準同為 main `fa2e3ff`）。那份報告沒有讀到開發者的 Demo 程式，也沒有拿到影片，所以它關於 Fenn 的段落以本文第 1–3 節為準。它另外對遊戲現有 3D 做了靜態盤點，下面收錄其中本文沒寫到的部分。每點都註明可信度：「已核對」是本 session 讀過程式確認的；「未重現」是只看過程式、沒在 App 裡試過的。

1. **3D 場景每週才重建一次，城市在一週內的變化不會出現。**
   - 已核對：`Map3DSceneKey`（`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift`）只含高度檔是否就緒、軌道段數與最後一段、月台數、玩家建物數、第幾週。城市每晚成長（`LandDemand.growLand`）不在裡面。
   - 這是刻意的設計：註解寫明「城市每晚成長，按週更新」。所以這是要不要改成每天更新的取捨，不能當成 bug。
   - 未重現：數量不變的變更（例如買下城市建物）可能不會觸發重建。
2. **場景是一次整個蓋好，不會隨相機移動載入新區塊。**
   - 已核對：整個場景在 `Task.detached` 裡重蓋，範圍是已建的部分加 1,500 m、每邊最多 6,000 m（HANDOFF §4.1）。`Map3DMetalView.show` 再替所有 chunk 重建 GPU buffer（約 290–314 行）。
   - 影響：沿著高鐵走遠，就會走出已經蓋好的範圍。要改成跟著相機載入，需要固定的 chunk 編號、預先載入周圍一圈、背景生成、限制每幀上傳的量，以及依位元組計算的快取上限。現有的 mesh builder 和遠近分級可以沿用。
3. **真實建物和遊戲裡的城市沒有對應。**
   - 已核對：`addRealBuildings` 只避開軌道經過的格子。
   - 影響：玩家拆除、收購或改建時，真實建物那層不知道；城市成長也可能被真實建物蓋住。要做的話，得先讓每棟真實建物有固定的來源 ID，並對應到 GameWorld 的地塊，再由 GameWorld 決定畫什麼。不能在畫面那層另外加一套城市。
4. **列車每幀都重新配置 buffer。**
   - 已核對：`Map3DMetalView` 第 415、426、502 行，列車方盒、車廂 instance 和接地陰影每一幀都 `makeBuffer`，再排序、`flatMap`。
   - 人車已經用三份輪流的 buffer（第 337 行），列車也可以照做。HANDOFF §4.1 已經記過這點。
5. **MapLibre Native 在 iOS 上不支援它的 3D 地形。**
   - 那份報告引用的是 [MapLibre 的 terrain 支援表](https://maplibre.org/maplibre-style-spec/terrain/)，本 session 沒有另外核對。
   - 這是第 5 節「不換成 MapLibre」的另一個理由。
6. **實機該量什麼。** 量測項目：
   - P50／P95／P99 幀間隔
   - 繪製指令的 CPU 時間、GPU 時間
   - 場景建構與上傳時間
   - 常駐與尖峰記憶體
   - 可見與常駐的 chunk 數、三角形數、draw call 數

   量測條件：同一個存檔、同一條相機路徑，分白天、夜晚、雨天各量一次。現有的 `record` 只量 draw 函式裡面，看不出整個 App 卡不卡。

   那份報告還提了一組預算（A15 以上 P95 ≤ 20 ms、圖形資源 ≤ 128 MiB 等）。這只是提案，沒有任何實測，要等量過再定。

那份報告的分階段計畫（P0–P5、約 8–14 人週）和三種方案的評分，本文不收錄。要不要做、先做哪一項，照 CLAUDE.md 交給 `NEXT_PRIORITIES` 與遊戲規劃排序。

## 7. 授權

- 開發者網站的程式**沒有附授權**。依 CLAUDE.md，沒有授權的程式只能參考想法，不能複製。上面記下的門檻數字與做法只是觀察，實作要用本專案自己的程式與數值。
- 預覽圖與影片的權利屬於作者，不放進 repo。
- OSM 資料是 ODbL；本專案的實景建物用的是 Overture（決策 239），署名照現有的 `DataSourceCredits`。

## 8. 查證邊界

- 沒有拿到 Fenn iOS App 的二進位檔或安裝包，無法確認 App 裡實際用的是哪個引擎、怎麼和 MapKit 疊在一起（第 1 節的推論）。
- 開發者的 X 動態牆抓不到，只讀到透過 API 取得的單篇貼文。
- 程式只讀了澀谷的建物、夜景、入口三個模組與巴黎的入口，沒有實際執行。
- 第 5 節的效能沒有任何實機數字。

## 來源

- App Store：Fenn（id6761315757）的描述與版本紀錄 — https://apps.apple.com/us/app/fenn-life-organizer/id6761315757
- TechCrunch, “Social maps app Zenly rolls out its own maps”（2022-05-18）— https://techcrunch.com/2022/05/18/social-maps-app-zenly-rolls-out-its-own-maps/
- Charly Delaroche 的 X（簡介、2026-09-27 的「Controllable 3D airplane in Apple Maps」與社群註記）— https://x.com/Nal_uh/status/2104228282824806457
- 開發者的公開 3D 場景（場景清單 `scenes.json`；澀谷 `/shibuya`、巴黎 `/paris`）— https://3dscenes.qualityf2p.workers.dev/
- Fenn 官網 — https://fenn.chat/
- Apple Developer Forums 708503（MapKit 沒有加入自訂 3D 的 API）— https://developer.apple.com/forums/thread/708503
- munim-maps（在 MapKit 上疊透明 Metal 層）— https://github.com/munimtechnologies/munim-maps
