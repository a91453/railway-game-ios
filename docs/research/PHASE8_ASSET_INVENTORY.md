# Phase 8 素材盤點：鐵路、城市、角色與 iOS 呈現管線

查閱日期：**2026-10-07（UTC）**。遊戲基準為 `origin/main` **`ff79f43c382ef22e35235a82ab5ca79c34be578d`**；實際 clone 的 `a91453/railway-reference-private` 為 **`f27339b9d030f9bcc8d96388134cba719e0e0d2b`**。下列參考路徑均相對於私有參考庫，不把素材本體、部署設定、密鑰或個資帶進公開 repo。

**這個 PR 只新增本文件，沒有程式、測試、golden、存檔或 workflow 變更，沒有跑任何程式檢查。** 素材計數、檔頭解析與網格大小／雜湊核對是本研究的靜態量測，不是建置或測試通過的宣稱。三個引擎的處理方式與首批選材是提案，沒有新增套件、轉換產物或正式架構決策。

已先讀 `AGENTS.md`、`CLAUDE.md`、`docs/ROADMAP.md` 的 Phase 8、`docs/research/PHASE6C_BUILDINGS_STUDY.md`，以及 [PR #172](https://github.com/a91453/railway-game-ios/pull/172)、[PR #174](https://github.com/a91453/railway-game-ios/pull/174)、[PR #179](https://github.com/a91453/railway-game-ios/pull/179) 的研究與說明。沿用「來源事實／提案／缺口／VERIFIED／UNVERIFIED」的區分；6c 研究的詳細欄位可作補充，但本文的數量與存在性重新從目前 clone 核對。

依 `CLAUDE.md`，**`Simulator/`、`Railway/`、`Ci/` 是授權的實作來源**，可以直接打包、移植或轉換；未另標授權的作者素材視為可用。只有明示第三方條款、署名或實際格式限制需要個別處理，不推論整包禁用。Simulator 已先讀 `REFERENCE_REFRESH_2026-10-07.md` 與 `SANITIZATION_REPORT.md`；台北包與鐵路清理包也先讀各自的 `00_READ_ME_FIRST.md`。

## 1. 結論與盤點口徑

可以立即取用的 3D 資料有 **1 份 TRA E201 GLB、40 份列車 LOD 網格、47 份建物遠景網格、8 份角色 GLB，以及軌道／橋梁／月台的程序幾何**。Simulator 的模型鐵道毫米尺度與 rail-3d 的公尺尺度必須分開。列車模型的台鐵／捷運車號與決策 66 的九種 `TRAIN_TYPES` 也不是同一套分類。

`rail-3d` 遠景的位置是 **`Railway/site_archive_clean/rail-3d/assets/{blender-buildings-v1,historic-buildings-v2}/<目錄>/far.mesh.bin`**。它不是 GLB，也不是遠景照片；是沒有檔頭的 24-byte 頂點三角形串列，配 `model.json` 的材質分組。列車 `blender-map-v1/*.bin` 是另一種 **40-byte** 格式，兩者不能共用錯誤的 stride。

本文件用以下前綴縮短表格；表內組合路徑就是實際完整路徑。

| 前綴 | 參考庫內路徑 |
| --- | --- |
| S | `Simulator/reference_snapshot/` |
| R | `Railway/site_archive_clean/` |
| R3 | `Railway/site_archive_clean/rail-3d/` |
| T | `Railway/taipei_gta_reference/source/` |
| C | `Ci/reference_snapshot/` |
| O | `Railway/railway_game_reference_clean/` |

大小是 `stat` 的**實際位元組**，`1 MiB = 1,048,576 bytes`；重複擷取檔也各計一次，未去重。三角形數優先由非索引串列的 stride 或 GLB accessor 計數取得；GLB 的計數不代表已解壓或目視驗證。程序式 JS 沒有固定輸出的多邊形數；沒有生成場景就不填假數字。缺檔宣告不算現存素材或 App 大小。

## 2. 素材總表

「使用類別」對到 §3 三個引擎的處理表；同格式的逐件檔案沿用該類別，完整 mesh、模板、圖示、字型明細在 §8。

| 路徑／範圍 | 類型、格式 | 檔數／內容數 | 現存 bytes | 三角形／解析度或內容 | 使用類別 |
| --- | --- | ---: | ---: | --- | --- |
| `S/models/tra-e201/tra-e201.glb` | mesh；glTF 2.0 GLB | 1 | 1,757,448 | 35,724 三角形；47,852 頂點 accessor 合計；1 mesh、12 primitives／材質，沒有貼圖、skin 或動畫 | G1 |
| `S/_next/static/chunks/2694-efba5e23a92b434e.js` | 參數／程序 mesh；JS | 1 | 35,184 | 台鐵車身、客車的程序外觀；E201 載入與縮放；非另外一包模型檔 | P1 |
| `S/_next/static/chunks/5758-131911c5f04a436f.js` | 參數／程序 mesh；JS | 1 | 104,939 | 3D 道床、枕木、鋼軌、橋、橋墩、月台、站房、跨線橋、機關庫、隧道等；三角形數依配置生成 | P1 |
| `S/_next/static/chunks/4193-d08071182eb33d9c.js` | 參數／資料；JS 常數與 catalog | 1 | 69,777 | TOMIX／KATO 軌道與結構物尺寸、商品資料、模板接點；不是實體鐵路工程規格 | P1／D1 |
| `S/_next/static/chunks/8423-2d349fd9568cd1c6.js` 的幾何模組 `14687` | 參數；JS | 1 | 10,022（整個 chunk） | 複線橋面、曲線／高架支承取樣；chunk 的其他模組不屬於素材 | P1 |
| `S/api/track-sets.json` | 資料；JSON | 1／6 套 | 7,747 | 共 101 個放置零件，含曲線、直線、轉轍器、高架組合 | D1 |
| `S/api/templates/*.json` | 資料；JSON | 9／9 模板 | 115,962 | 共 865 筆 `layout.placed`；毫米座標與旋轉，逐件見 §8.3 | D1 |
| `S/api/landing-preview.json` | 資料；JSON | 1 | 13,223 | 示範 `layout`，不是地形／模型 | D1 |
| `R3/assets/blender-map-v1/*.bin` | mesh；自訂 Float32LE | 40 | 34,564,920 | 864,123 頂點／288,041 三角形；沒有貼圖 UV、skin 或動畫 | G2 |
| `R3/assets/blender-map-v1/manifest.json` | 資料；JSON | 1 | 134,351 | 宣告 62 車型、110 mesh；只有 40 mesh 實檔，23 車型的宣告 parts 全齊 | D1 |
| `R3/assets/blender-buildings-v1/<目錄>/{model.json,far.mesh.bin}` 加 catalog／placement | mesh／資料；bin＋JSON | 46／22 建物 | 8,064,361 | far 7,756,272 bytes；107,726 三角形；22 model＋22 far＋2 共用 JSON | G3／D1 |
| `R3/assets/historic-buildings-v2/<目錄>/{model.json,far.mesh.bin}` 加 catalog／placement | mesh／資料；bin＋JSON | 52／25 建物 | 7,643,664 | far 7,251,480 bytes；100,715 三角形；25 model＋25 far＋2 共用 JSON | G3／D1 |
| `R3/blender-buildings.js` | 參數／loader；JS | 1 | 3,240 | 24-byte 頂點與 drawGroups、純色 PBR、DoubleSide | P1 |
| `R3/integration/rail-structures.js` | 參數／程序 mesh／材質；JS | 1 | 23,213 | 公尺道床、鋼軌、枕木、橋面、橋墩、隧道殼；碎石為程序 shader | P1 |
| `R3/integration/tunnel-portals.js`、`tunnel-apertures.js` | 參數；JS | 2 | 6,156 | 洞口分組、開口與地形裁切；沒有獨立隧道 GLB | P1 |
| `R3/station-catalog.js`、`station-models.js` | 資料／程序 mesh；JS | 2／12 站區 catalog | 15,716 | 站區外觀與台北站程序模型；招牌 CanvasTexture 為 1024×128，不是現存 PNG | P1／D1 |
| `R3/integration/formations.js` | 參數；JS | 1 | 9,878 | 真實／推估編組、公尺長寬；用於外觀組裝，不替換核心長度 | P1 |
| `R3/assets/wenhu-v1/wenhu.js` | loader／材質參數；JS | 1 | 2,736 | 定義 40-byte 格式；這個目錄的 `wenhu.model.json`、`wenhu.mesh.bin` 缺檔，應讀現存 blender-map-v1 | P1 |
| `T/avatars/*.glb` | mesh／內嵌貼圖；GLB＋meshopt＋KTX2 | 8 | 3,209,176 | 39,684 三角形；32 張 KTX2；兩英雄 80／81 joints，六群眾各 20；GLB 動畫皆 0 | G4 |
| `T/avatars/manifest.json` | 資料；JSON | 1 | 15,020 | 宣告 17 avatar；實有 8，另 9 avatar／LOD 與全部 17 fallback 缺 | D1 |
| `T/assets/anim-CQkLTvTS.bin` | 動畫資料；ANM1 | 1 | 439,720 | 43 clips、30 fps、19 動畫關節；需要骨架對應，非 GLB 內建動畫 | A1 |
| `T/assets/{avatar-CUFURxPX,clips-Cb5uFd0j,animator-DGt1NqrS,rig-BjRdQXtM}.js` | 參數／動畫 adapter；JS | 4 | 142,465 | rest pose、Rocketbox 骨架映射、root motion；逐件 bytes 見 §8.2 | P1／A1 |
| `T/assets/engine-DKps_Gq_.js`、`world-gYgJkZNf.js` | 城市參數／資料／程序 mesh；JS | 2 | 1,495,038 | 9 區 style、街廓、地標 proxy、擺放；world 有 43 個 site 與 1 個 postfx 依賴缺檔 | P1／D1 |
| `T/assets/site-donqi-ximen-BYSklXQx.js` | 城市程序 mesh；JS | 1 | 28,314 | 西門唐吉訶德外觀；沒有獨立建物 GLB | P1 |
| `T/assets/site-fongda-coffee-BLqPP37I.js` | 城市程序 mesh；JS | 1 | 32,315 | 蜂大咖啡外觀 | P1 |
| `T/assets/site-railway-department-park-BykCBjAy.js` | 城市程序 mesh；JS | 1 | 25,070 | 鐵道部園區外觀 | P1 |
| `T/splash/launch-*.png`、`icons/*.png`、`_favicon.png` | 圖片／圖示；PNG | 45（launch 42） | 6,132,453 | launch 多種螢幕解析度；圖示 32²、180²；不是城市貼圖 | I1 |
| `T/title/*.webp`、`icons/icon.svg` | 圖片／圖示；WebP／SVG | 7 | 1,189,248 | WebP 六張為 960×1706 到 2560×1440，SVG 408 bytes；見 §8.2 | I1 |
| `C` 非 external 的圖示／圖片 | 圖片／圖示；PNG／JPEG／WebP／SVG | 31 | 1,868,612 | 16²～1920×1200；地球圖 1774×887，逐件見 §8.4 | I1 |
| `C/external/openfreemap-tiles/sprites/ofm_f384/ofm_2x.{png,json}` | 圖示 atlas／資料；PNG＋JSON | 2／264 entries | 146,694 | PNG 1024×526、118,872 bytes；JSON 27,822 bytes；entry rect／pixelRatio 應保留 | I1／D1 |
| `C/external/` 其他圖片（不含上述 sprite） | 圖片／圖示；PNG／JPEG／WebP／SVG／ICO | 116 | 5,148,333 | 網站 UI／logo／地圖快取等；各資料夾統計見 §8.4，不是全部都要打包 | I1 |
| `C/fonts/mtr-sung.woff2` | 字型；WOFF2 | 1 | 3,316,128 | 15,174 glyphs；有第三方 copyright，未內嵌再散布條款 | F1 |
| `C/fonts/cross-platform-ui/inter-variable__q_21383692569c82f8.woff2` | 字型；WOFF2 | 1 | 352,240 | 2,937 glyphs；內嵌 OFL 1.1 | F1 |
| `C/external/scidb/` 的字型檔 | 字型；TTF／WOFF／WOFF2／EOT | 55 | 6,300,744 | Roboto、FontAwesome、Material Design Icons、pdf、iconfont、element、VideoJS；其中 2 檔為 0 bytes | F1 |
| `C/external/osm/assets/bootstrap-icons/font/fonts/*` | 字型；WOFF／WOFF2（擷取檔名沒有副檔名） | 2 | 314,332 | 每份 2,077 glyphs；不能因沒有副檔名漏算 | F1 |
| `C/external/openfreemap-tiles/fonts/{Noto_20Sans_20Bold,Noto_20Sans_20Regular}/*.pbf` | 字型 glyph 資料；MapLibre SDF protobuf | 3 | 284,969 | 223／223／256 glyphs；不是完整 TTF／OTF，逐件見 §8.5 | F1／D1 |
| `R/assets/fonts/rail-emoji.woff2`、`R/assets/tdx-logo.svg` | 字型／圖示；WOFF2＋SVG | 2 | 24,328 | 字型 13,652 bytes／27 glyphs，Noto Emoji SemiBold；SVG 10,676 bytes | F1／I1 |
| `C/external/openfreemap-tiles/styles/liberty.json`、`planet.json` | 3D 擠出參數／圖磚資料描述；JSON | 2 | 62,333 | `building-3d` 讀 `render_height`／`render_min_height`，不是現成建物 mesh | D1／P1 |
| `R/vendor/ofm-positron.json`、`R/data/taiwan_land.json` | 圖層參數／海岸資料；JSON | 2 | 85,841 | 樣式與 GeoJSON 海岸，不是 3D 地形高度 | D1 |
| `R3/terrain/manifest.json` | 資料；JSON | 1 | 2,168 | 宣告 115,975,855-byte、14 chunks 的地形檔；14 份 bin 全缺，不能計入可用地形 | D1 |
| `R3/physical/{network,metro-network,level-profiles,display-profiles,metro-display-profiles,dispatch}.json`、`R3/integration/display-profiles.json` | 3D 線形／高程／顯示資料；JSON | 7 | 34,931,602 | 來源實景路網與顯示 profile；不是 mesh，遊戲 renderer 應讀目前 GameCore 快照 | D1 |
| `O/` 全樹 | 資料／文件／函式庫；MD／TXT／JS／WASM | 16 | 10,827,511 | 沒有 mesh、貼圖、圖示或字型；WASM 10,766,083 bytes，是編譯核心，不是 3D 素材包 | D1／L1 |

與素材管線直接有關的函式庫檔案亦量測如下；它們的授權逐項見 §5，並未新增到 App。

| 路徑 | 類型／格式／檔數 | bytes | 使用類別 |
| --- | --- | ---: | --- |
| `R3/vendor/three.module.js` | 函式庫資料／JS／1 | 1,314,680 | L1 |
| `R/memories/tainan-2026-09-12/vendor/three.module.js` | 函式庫資料／JS／1（重複版本） | 1,314,680 | L1 |
| `R/vendor/maplibre-gl.js` | 函式庫資料／JS／1 | 955,078 | L1 |
| `R3/vendor/pmtiles.js` | 函式庫資料／JS／1 | 20,229 | L1 |
| `T/assets/three-DoD3b_mB.js` | 函式庫資料／JS／1 | 737,923 | L1 |
| §5 明列的 9 個台北 worker | 程序 mesh／貼圖生成器與內嵌函式庫／JS／9 | 2,372,853 | P1／L1 |
| `T/avatars/basis/basis_transcoder.js` | 轉碼器／JS／1 | 57,529 | L1 |
| `T/avatars/basis/basis_transcoder.wasm` | 轉碼器／WASM／1 | 527,333 | L1 |
| `C/external/openfreemap/_astro/maplibre-gl-worker-DttxN3zb.js` | 函式庫資料／JS／1 | 508,764 | L1 |
| `C/external/scidb/3dmol/build/3Dmol-min.js` | 3D 分子 viewer／JS／1 | 580,108 | L1 |

### 2.1 網格與動畫格式

| 資料 | 實際格式與轉換注意事項 |
| --- | --- |
| E201 GLB | glTF 2.0、沒有 required extension、沒有圖片；PBR 數值材質。POSITION bounds 聯集為 `[-8.985,0,-1.625]…[8.985,5.335,1.625]`，約 **17.97×5.335×3.25 m**，Y-up，單一無 transform node。Simulator loader 另把長度縮到 **125 mm** 的模型鐵道尺度；iOS 不應照抄那個縮放。 |
| 列車 bin（G2） | 無檔頭／indices；每頂點 **10 個 Float32LE＝40 bytes**：position 0／4／8、normal 12／16／20、color 24／28／32、gloss 36。每 3 頂點一個三角形。軸向 front +X／left +Y／up +Z；顏色按來源 sRGB shader 解讀，gloss 不是已定義的 PBR roughness。需要重建材質或自訂 shader，不把 gloss 直接叫 metallic。 |
| 建物 far（G3） | 無檔頭／indices／UV／貼圖／骨架；每頂點 **6 個 Float32LE＝24 bytes**：position xyz、normal xyz。公尺、+Z-up；`model.json.lods.far` 提供 bytes／vertexCount／triangleCount／sha256／drawGroups，47 件共 **430 drawGroups**。drawGroup 的 start／count 是頂點數，color 是線性 RGB，另有 metalness／roughness。 |
| 建物 placement | `catalog` 22／25 entries；`placement.entries[id]` 的 anchor、rotationDeg 覆寫載入初值。local-facade 與 ENU-baked 必須分辨；後者已將部件朝向烘入頂點，不能重套部件旋轉。catalog 的 `metadata` 與實際目錄可能不同，來源 loader 是 `entry.id+'/model.json'`；逐件表使用**實際目錄**。 |
| 角色 GLB（G4） | required extensions 皆為 `EXT_meshopt_compression`、`KHR_mesh_quantization`、`KHR_texture_basisu`。先解 meshopt、展開量化頂點，KTX2 ETC1S／UASTC 轉目標貼圖；保留 color／normal／mask、alpha 與色彩空間。英雄 body-color 1024²、head-color 2048×1024、hair-color 1024²；normal 512²／512×256、mask 256²／256×128。群眾 color 1536×512、normal 384×128、mask 192×64。 |
| ANM1（A1） | bytes 0–3 `ANM1`，UInt32LE JSON 長 10,852，樣本區 offset 10,860，共 214,430 Int16。header `fps=30,nk=19,per=82,rig=jie`；每幀 19 四元數×4＋位置×3＋root x/z/yaw。位置乘 1e-4 m，root x/z 乘 .001 m，yaw `/32767×4π`。43 clips 內有 idle／walk／run／sit 等；需依 avatar 骨架名稱與 rest pose retarget，再 bake，不能只轉 GLB 就得到動畫。 |

現存 40 列車與 47 建物 bin 的長度、metadata SHA-256、stride、finite Float32 已靜態核對；建物 drawGroup 總數與 vertexCount 相合。列車完成 23 個 catalog 車型的 parts 存在性核對；例如 `taichung.bin` 有檔但 `taichung-mid.bin` 缺，所以該車型不是完整可用編組。`caf.bin` 本體雖缺，五個 `caf-section-*.bin` 全齊，宣告的 CAF 分節編組仍可組成。

### 2.2 軌道、橋梁與月台參數

Simulator 尺寸以模型鐵道 **mm** 記錄。可借用造型、零件生成方法與 catalog，但它的曲線半徑、轉轍器尺寸、商品價與模型橋高度不是本遊戲的建造規則。需要原比例外觀時，先按素材族明訂模型比例再換成公尺；不能對全部檔案一律乘 150，也不能把 280 mm 直接當 280 m。

| 來源／項目 | 實值 | 建議用途 |
| --- | --- | --- |
| `S/…/5758-131911c5f04a436f.js`，TOMIX 道床 | 半底寬 9.25、半頂寬 6.6、底／頂 0.3／2.3 mm；枕木頂 2.9、長 12.4、寬 1.3、節距 4.2 mm | 取剖面與 instancing 方法；沿遊戲中心線生成。 |
| 同檔，KATO 道床 | 半底寬 12.5、半頂寬 9.6、底／頂 0.3／2.4 mm；枕木頂 2.9、長 15.2、寬 1.5、節距 5 mm | 同上，與 TOMIX 分開命名。 |
| `S/…/4193-d08071182eb33d9c.js`，module `52061`／TOMIX 3030 | 長 280、寬 38、桁架高 46、sideCenter 17、endInset 17.5、bayLength 35、預設高 58 mm | 可離線生成桁架 bridge mesh；長度官方標示，局部寬高為來源照片估計，不能稱工程測繪。 |
| 同 catalog，地方月台／站房 | 月台長 124、深 23、基面高 12.3 mm；站房外包約 248×123.4×56.3 mm；跨線橋 79×98×60.5 mm | 保留島式／側式／屋頂／候車室造型；月台實際長度與高程由快照決定。 |
| `R3/integration/rail-structures.js`，道床／軌道 | 公尺：GAUGE 1.435、RAIL_W .14、RAIL_H .2；枕木 2.5×.26×.15，節距 .65；gravel 道床頂寬 3、底寬 3.6，坡 .35、底寬上限 7 | 第一批優先採公尺版生成法；軌距是外觀參數，不能由此更改核心線間距。 |
| 同檔，橋面／橋墩 | DECK_W 5、底寬 2.8、梁深 1.8、橋面比軌頂低 .35；護欄高 .9、厚 .35；墩 1.6×2.2、墩帽 5×1.6×1.2 m | 外觀示意，不是工程精度；由 `.elevated`／`.bridge` 明確選材。 |
| 同檔＋`tunnel-portals.js`，洞口 | 半淨寬 3.2、floor -1.2、ring .65、拱 20 segments；PORTAL_DEPTH 12、WING 8 m | 只在快照 `isTunnelPortal` 畫外殼，隧道內採後備低細節。 |

來源 `rail-structures.js` 的 `VIADUCT_LIFT_M=6` 是其實景顯示門檻。**本遊戲已存 `TrackStructure`，應讀 S4 的結構欄位，不能用畫面門檻重判橋／高架。** 橋墩間距、地形碰撞與月台安全帶外觀仍要選定呈現參數；來源沒有可直接替代 S4 整數規則的完整工程資料。

## 3. 每類素材如何用在三個候選引擎

SceneKit、RealityKit、SwiftGodot 都只作呈現。SwiftGodot 是 Swift 的 Godot 綁定／嵌入路徑，素材要經 Godot 的 importer／資源流程；不是把 JS 丟給 Swift 執行。下表對應總表與逐件表的全部使用類別。

| 類別 | SceneKit | RealityKit | SwiftGodot／Godot | 建議打包判斷 |
| --- | --- | --- | --- | --- |
| G1：無壓縮 extension 的 E201 GLB | 離線讀 glTF，再輸出 `.scn` 或 USD／USDZ；也可寫 glTF loader 建 SCNGeometry。不能假設 SCNScene 直接載此 GLB。 | 離線轉 USD／USDZ，載入 Entity；保留 12 材質與公尺尺寸。 | 可經 Godot glTF importer 匯入 GLB，匯出成 Godot scene／resource 隨 PCK 打包；動態載入另驗 GLTFDocument 版本。 | 原檔可作轉換輸入；Apple 路徑需轉格式，Godot 可沿用 GLB 匯入。 |
| G2：40-byte 列車 bin | 自訂 SCNGeometrySource／Element，color、gloss 經 shader／材質 adapter；或離線轉 `.scn`／glTF／USDZ。 | 自訂 MeshDescriptor／material，gloss 要另映射；或離線 USDZ。 | 用 ArrayMesh 的 position／normal／color；gloss 放自訂 attribute 或烘成材質；也可離線標準 glTF。 | 可直接打包 bin＋manifest，但三者均需自訂 loader；想用標準 loader 就轉格式。 |
| G3：24-byte 建物 far | 自訂 SCNGeometry 與 drawGroup 材質；或離線 `.scn`／USDZ。 | MeshDescriptor 分 submesh／materials；或離線 USDZ。 | ArrayMesh 各 surface；或先轉 glTF 再 importer。 | 原 bin 可直接打包，純色材質不需要貼圖；不要因缺 GLB 而判定不可用。 |
| G4：meshopt／KTX2 角色 | 先離線解壓、解量化、轉貼圖，輸出帶 skin 的 `.scn`／USD；核對骨架與 alpha。 | 同一離線前處理，輸出帶骨架的 USDZ／USD；不能假設直接支援這三個 GLB extension。 | 固定 Godot 版本後驗其 extension 支援；首批共用先解 meshopt／Basis 的標準 GLB，經 importer 打包。 | 首批先轉，不把來源瀏覽器 Basis JS／WASM 當 Apple 材質 loader。 |
| A1：ANM1 | 自訂解碼／骨架映射，或 bake 成 SceneKit 動畫。 | retarget 後 bake 到 USD 骨架動畫／AnimationResource。 | 映射到 Skeleton3D、bake Animation／AnimationPlayer 或 GLB 動畫。 | 優先離線只輸出 idle／walk；原包可保留做研究輸入，首批不需 43 動作全打包。 |
| P1：JS 幾何／shader／常數 | 翻譯生成法，建立 SCNGeometry；或補齊依賴後離線烘焙 mesh。 | 翻譯生成法到 MeshDescriptor；Three shader 要換成目標材質。 | 翻譯到 ArrayMesh／Godot shader；或離線標準 glTF。 | 只取必要參數／生成法；不打包整個網頁 runtime、帳號或部署程式。沒有生成過的 mesh 不列成現成模型。 |
| D1：JSON／catalog／模板／圖層 | Foundation 解析或離線轉自有 manifest，交呈現層；向量建物另生成 geometry。 | 同左，資料不是 Entity 檔。 | JSON adapter／匯入工具；世界資料仍從 Swift GameCore 讀。 | 選用欄位可直接打包；Simulator 模板僅作配置樣本，不覆蓋存檔或核心路網。 |
| I1：PNG／JPEG／WebP／SVG／ICO | PNG／JPEG 可直接打包；WebP 先轉或明訂 decoder，SVG／ICO 先轉資產目錄支援的圖片。 | 同左；材質貼圖的 sRGB／linear、mips、alpha 要各自核對。 | PNG／JPEG／WebP 走 importer；SVG 可匯入成 texture，ICO 轉換；Godot 的 UI 與 SwiftUI 圖片分開。 | 圖示與標題圖可直接沿用內容；不是把 PWA 的 42 張啟動圖全部放進 iOS。sprite 用 rect 切圖或離線 atlas。 |
| F1：字型 | 原生字型轉成 TTF／OTF 供 CoreText／UI 註冊；不把 WOFF2 當 SCN mesh。PBF 只有 SDF glyph，需自訂 atlas 文字繪製或取得完整原字型。 | 同左；3D text 生成另使用字型。 | 轉 TTF／OTF 供 FontFile／Theme；EOT／web 容器不當通用 iOS 格式，PBF 不能直接當 FontFile。 | 需要才轉、保留告示；首批可用系統字型，避免引入不需要的字型與授權待補項。 |
| L1：網頁函式庫／WASM | 幾何資料可用，網頁函式庫不是 SceneKit runtime；若留 WebView 才另處理 web dependencies。 | 同左。 | Three／OpenTTD WASM 不是 Godot renderer；SwiftGodot／Godot 本身另固定版本與告示。 | 本次不新增依賴；離線工具與隨 App 發佈的 library 分開列告示。 |

共用轉換契約建議保存來源 repo SHA、完整相對路徑、來源 hash／bytes、工具版本與選項、axis／units、輸出 hash／bytes、頂點／三角形／材質／骨架／貼圖數、授權與來源。**Z-up ENU `(east,north,up)` 可一次轉到 Y-up `(east,up,-north)`**；GameCore 平面 y 向南，接快照時另明訂其到 render 軸的 adapter。法線、繞序、雙面材質一併核對，不能只旋轉 position。

首批用同一份輸入比較三個引擎的載入、材質、相機、選取、幀時間與峰值記憶體，再決定引擎。尚未做任何 importer、USDZ／SCN／glTF 轉換或 iOS 載入驗證；本文不替特定 Godot／Apple OS 版本保證 extension 支援。

## 4. 對應已有的遊戲資料

### 4.1 決策 66：九種 TRAIN_TYPES

來源是 `C/lib/app__q_c234188b7c397f91.js` 的 `TRAIN_TYPES`；遊戲現存 `Sources/GameCore/Railway/TrainType.swift`。下表「代表外觀」是呈現提案，**不是來源已定的 model→TrainType 對照，也不改容量或門數**。

| 遊戲車種 | 每節額定／門數 | 可用代表外觀與缺口 |
| --- | --- | --- |
| A | 310／5 | 可把 C321／C381 寬體外觀當試片 proxy；現有模型不是已核實的 A 型、5 門外觀，正式 A 型需補適合車身。 |
| B | 260／4 | 首批可用現存 `c321.bin`＋`c321-mid.bin` 當代表；必須標為 proxy，不以台北車號冒充來源 B 型規格。 |
| C | 200／4 | 可挑 `kaohsiung` 或機捷車身作 proxy，正式窄體 C 型外觀要確認／製作。 |
| L | 243／3 | 有 `y100` 環狀線模型，但沒有已標為 L 型的完整模型；可共用普通 rail 車身後備。 |
| D | 230／5 | `caf-section-0…4` 可展示分節外觀；不能把五分節數當 5 門，更不能把 CAF 直接認成 D 型。正式車身仍為 gap。 |
| APM | 138／2 | `wenhu`＋`wenhu-mid` 全齊，是文湖 APM 256 的代表外觀；仍需核對門配置、材質及核心尺寸。 |
| MAGLEV | 240／3 | 沒有對應現成 mesh；需做磁浮車身與外觀導軌。 |
| SKYRAIL | 140／2 | 沒有對應現成 mesh；需做雲軌車身／支承外觀。 |
| MONORAIL | 224／2 | 沒有對應現成 mesh；需做單軌車身／梁與輪組外觀。 |

沒有車種的標準車仍為每節 320、4 門，不把它偷偷改成 B。TRA E201、E200、E500、EMU800、EMU3000、TEMU2000、DR1000 等是可用的**台鐵外觀**，決策 66 並沒有相對應的台鐵車種 enum。可以作裝飾／模型比較／標準車的明示 proxy；新增正式台鐵車種與營運規格需另外設計，不在素材盤點擴充核心。

`RailwaySnapshot.Train.head` 是第一節中心的 TrackLocation，**不是車頭鼻尖**；`bodyPath(of:)` 是頭到尾的中心路徑。現存 `Train.carLength=1024`（16 m 中心間距）、`Train.length=(cars-1)×1024`，不是各模型的實體端到端總長。`formations.js` 的 20 m／23.5 m／真實編組不能覆蓋它；呈現可以沿快照中心擺車身、選定縮放與端部突出政策。若要工程尺寸參與月台停靠，交由核心另案處理。

### 4.2 S4 結構物與月台

| 遊戲權威資料／查詢 | 來源素材／生成法 → 目標呈現草案 | 比例與界線 |
| --- | --- | --- |
| `GameWorld.railwaySnapshot()`／`TrackAlignment.geometry`／segments | `R3/integration/rail-structures.js` 的道床、rails、ties → App 的軌道 mesh cache | 世界單位÷64→m；中心線、高程、曲率只讀快照，不讓 mesh 回寫 topology。 |
| `TrackStructure.surface` | 公尺 gravel 道床，或 Simulator 兩組剖面 → 地面軌道生成器 | S4 的地面高度帶 ±2 m；外觀路堤不改此規則。 |
| `.elevated` | rail-3d 箱梁、墩帽、護欄／墩 → 高架生成器 | 核心 z≥0；來源 6 m 顯示門檻不重判結構；平行股道護欄合併只作呈現。 |
| `.bridge` | rail-3d 橋面與 Simulator 3030 桁架造型 → 橋 mesh／重複部件 | 核心 z≥0；不能把 58 mm 模型預設高程當遊戲高度；橋與高架費率由核心決定。 |
| `.tunnel`、`Node.isTunnelPortal` | rail-3d 洞口／aperture、Simulator tunnel 生成法 → 洞口與低細節內壁 | 核心 z≤0；isTunnelPortal 已由隧道／非隧道相接推導。S4 clearance=512（8 m）不是素材洞半徑。 |
| `RailwaySnapshot.Platform` 的 points／height／structure、`TrackPlatform.start/end` | Simulator 島式／側式／雨棚、台北站外殼 → 月台帶／站區外觀 | 沿平的中心線生成長度，start/end÷64→m；寬、高、側別、無障礙坡道外觀目前沒有完整核心契約。站房模型不提供地下月台。 |

S4 明定 GameCore 不存橋墩、隧道壁或 mesh。以上目標都是 App／GamePresentation 的呈現草案，沒有提議把 SceneKit／RealityKit／Godot 型別放進 GameCore。

### 4.3 6c：用途 × D1–D4

目前正式資料是 `Sources/GameCore/City/Building.swift` 的 `Building {id,kind,use,density,cells}`，一個 64 m 土地格一個邏輯建物。D1–D4 已定 **2／6／18／40 層**。容量看正式決策 74–77，不從模型高度、外觀或照片重新推居民／就業。6c 研究的早期「兩項人數都要放得下」提案已被決策 74 的**只看主要用途選級**取代，本文以目前程式為準。

| 用途 | D1（2 層） | D2（6 層） | D3（18 層） | D4（40 層） |
| --- | --- | --- | --- | --- |
| 住宅 | 台北低層屋／程序屋頂作外觀來源；容量 56／12 | 公寓程序外觀；168／36 | 住宅塔樓程序外觀；504／108 | 高層住宅需整理變體；1120／240 |
| 商業 | 店面／蜂大咖啡風格；16／72 | 西門商店程序外觀；48／216 | 商場／mixed-use 程序外觀；144／648 | 商業塔樓變體待做；320／1440 |
| 辦公 | 小辦公 proxy；8／84 | 普通辦公程序外觀；24／252 | 大樓程序外觀；72／756 | 高塔外觀可參考信義 style；160／1680 |

表內容量順序為**居民／就業**；外觀欄均是提案。台北 `engine` 九區的樓層範圍是河濱 0、士林 3–8、西門 4–12、萬華 2–6、中正 4–14、中山 5–16、松山 5–14、信義 10–40、大安 5–14，可以作區域風格來源，**不是現成三用途×四密度模型 catalog**。第一版以 12 個程序 proxy 明確對齊密度即可；同一邏輯格可畫多個小外觀，居民與容量仍只有一份。

47 份 rail-3d far 是特定站房／地標／歷史建物，不是 12 種一般城市容量建物。101、總統府、山佳站可作裝飾或獨立地標；不能因外觀高 508 m 就給居民容量。`existingStock` 依目前核心資料顯示為 D4／特別後備，不裁人口，也不再從素材推容量。城市擺放的 fine footprint／旋轉／碰撞與核心佔格分開；普通建物只讀 `GameWorld.buildings`，正式地標 ID／位置 adapter 仍需後續實作。

## 5. 授權與署名清單

這一節記錄**實際檔案標示**、可核對的上游條款及採用時的工作。相同條款的檔案合列，但逐件路徑／檔名都可在下表或 §8 找到。只離線取作者幾何、沒有將函式庫發佈進 App 時，不應把工具依賴誤算成 App 必帶的網頁 runtime。

| 檔案／明示標示 | 條款／證據 | 我們要做的事 |
| --- | --- | --- |
| `T/avatars/{jie,wen,student-m,student-f,casual-m,casual-f,elder-m,elder-f}.glb` 及 `T/avatars/manifest.json` | **Microsoft Rocketbox，MIT，Copyright (c) 2020 Microsoft**；八份 GLB asset.copyright 與 manifest 均明記；manifest 指 `CREDITS.md / LICENSE-ROCKETBOX.txt`，兩檔在快照都缺 | 轉換後保留來源角色／頭部映射及 copyright；發佈前補正確 MIT 全文與 credits。MIT 要保留 copyright／permission notice，不要求開源整個 App，也不是需要重買模型。 |
| §8.1 中標「ODbL」的 `model.json`，及兩個 `{blender-buildings-v1,historic-buildings-v2}/placement.json` | 模型 `sources[].license`／`footprintReference.license`、placement.sources 中明示 **ODbL-1.0**；授權針對 OSM 輪廓／資料來源，不概括把所有作者外觀 mesh 改成 ODbL | 保留每件 source／OSM ID／用途與輪廓；顯示「© OpenStreetMap contributors」和 ODbL 連結。若公開散布衍生輪廓資料庫，提供相應資料並履行 share-alike；不用此義務推論 GameCore 程式必須開源。 |
| `C/external/openfreemap-tiles/planet.json`、`styles/liberty.json`、`sprites/ofm_f384/ofm_2x.*`；`C/external/osm/copyright/index.html` | planet.attribution 明列 **OpenFreeMap、© OpenMapTiles、Data from OpenStreetMap**；OSM copyright 頁明列 ODbL | 使用相應底圖／資料時保留完整 attribution。sprite 的 atlas 有資料描述但沒有逐圖示授權全文，採用時補確切 sprite 來源／條款，不能用 ODbL 當所有圖示的通用圖像授權。 |
| `R3/vendor/three.module.js`、`R/memories/tainan-2026-09-12/vendor/three.module.js` | 檔頭 **MIT、Copyright 2010–2024 Three.js Authors**；R3 revision 170 | 複製／隨 App 或轉換工具散布時帶 MIT 全文、copyright。取自己生成的 mesh 不等於要在 App 帶整個 Three.js。 |
| `T/assets/{atlasWorker-B8bbVoYM,atlasWorker-BiyGkkc_,bodyWorker-5BH0DlL0,buildWorker-BPjJt4Vl,charWorker-CMbjchSu,figureWorker-BtaIpxG6,paintWorker-BRX03GCZ,paintWorker-omaNBQOP,peopleWorker-iseFJOiU}.js` | 九檔內嵌註解 **MIT、Copyright 2010–2026 Three.js Authors** | 沿用 worker／內嵌 Three 部份時保留 MIT；這是本次補查的明示條款，不能沿用舊研究「所有 T bundle 未見告示」的概括說法。 |
| `R/vendor/maplibre-gl.js`、`C/external/openfreemap/_astro/maplibre-gl-worker-DttxN3zb.js` | 檔頭 **BSD-3-Clause**；分別指向 v5.9.0／v6.11.2 LICENSE | 採 web renderer／複製程式碼才帶 copyright、三條條件與免責全文；不以作者／組織名稱背書產品。SceneKit 等原生 loader 不需這些 JS。 |
| `C/fonts/cross-platform-ui/inter-variable__q_21383692569c82f8.woff2` | 字型 name 13 **SIL OFL 1.1**；Copyright 2016 The Inter Project Authors | 可轉容器／嵌入，附 OFL／copyright；不可單獨出售字型，修改時核對 reserved font names，字型衍生仍用 OFL。 |
| `R/assets/fonts/rail-emoji.woff2` | name 0 **Copyright 2013 Google LLC**、family Noto Emoji SemiBold；沒有內嵌 license 欄。另查 [Noto Emoji LICENSE](https://github.com/googlefonts/noto-emoji/blob/e20cbc2bbec1926686be9f9bee7d1d2cfa1fea0e/LICENSE) 為 OFL 1.1 | 若採此 subset，確認其與上游的對應／修改記錄，附正確 OFL／copyright，依 reserved names 規則處理；不是看到 Google 字樣就臆測 Apache。 |
| §8.5 的全部 `Roboto` WOFF／WOFF2 | name 14 指 **Apache License 2.0**；非憑新版本 Roboto 的記憶替舊檔換授權 | 轉換時保留字型 copyright、Apache 全文；若有 NOTICE 帶相應內容，標明修改，不能刪字型 name 告示。 |
| §8.5 的五份 FontAwesome 字型＋`C/external/scidb/_nuxt/img/fontawesome-webfont.912ec66.svg` | 內嵌 **Copyright Dave Gandy 2016** 與 `fontawesome.io/license/`；[Font Awesome v4.7.0 README](https://github.com/FortAwesome/Font-Awesome/blob/a3fe90fa5f6fac55d197f9cbd18e3f57dafb716c/README.md#license) 區分 font **OFL 1.1**、CSS **MIT**、文件 **CC BY 3.0** | 採這批 v4 字型／SVG-font時附 OFL／copyright；CSS 才套 MIT，文件才套 CC BY。上游說不強制另行畫面署名不代表可移除 license。 |
| `C/fonts/mtr-sung.woff2` | 內嵌 **DynaLab Inc. 1992–2000／Fourth Bus Co., Ltd copyright**，沒有 license 13／14 | 這是具體第三方字型條款 gap；正式再散布／轉換前補明確授權依據。首批沒有字型需求，用系統字型即可；此 gap 不擴張成作者其他素材禁用。 |
| §8.5 的 `pdf.*` 字型、`C/external/scidb/_nuxt/img/pdf.367cd90__q_e3b0c44298fc1c14.svg` | Copyright (C) 2021 original authors @ fontello.com；未列所組合 glyph 的授權 | 選用才追 glyph 來源／對應 license，保留既有 copyright；不能把 Fontello 工具名稱當成所有 glyph 的授權。 |
| `C/external/osm/assets/application-8fde0d498d8283e4544851368e912b7d89ca18fdc2b08ce5aa29d171ac6462cb.js`、`screen-auto-ltr-8b4e63f576c073470dfef2e67493e55cdf7b79e0a014de1031cf51e19a0cd2e3.css` | 內嵌 OpenJS／Bootstrap／其他元件 copyright；Bootstrap 與 Icons 明記 **MIT** | 若複製內嵌元件，逐元件保留 MIT／copyright。兩個無副檔名的 Bootstrap Icons font 見 §8.5，需補它們對應版的 MIT 全文。 |
| `C/external/osm/assets/turbo-c17cce38062be94687ab3e688cf14213be635ee2b55e63d9d5778659fab0c27b.js` | Copyright © 2026 37signals LLC，快照未提供全文條款 | 只有採該函式庫才補對應版 license；首批不需網站導航 runtime。 |
| `C/external/scidb/3dmol/build/3Dmol-min.js` | 內嵌 library 註解 **MIT AND Zlib**／MIT，另有 OpenJS／JS Foundation copyright | 採原檔或其中函式時保留各元件告示；Zlib 不可誤稱來源、修改版需標示，不刪告示。這是分子 viewer，不是本遊戲既定 renderer。 |
| `C/external/scidb/_nuxt/d885093.js` 的 Quill CSS 部份 | 註解明列 **Copyright (c) 2014 Jason Chen／2013 salesforce.com**；未在該註解找到全文條款 | 若複製該部份，補確切 Quill 版本的授權／告示並保留 copyright；不能把整個混合 bundle 推定為單一 license。 |
| `S/_next/static/chunks/polyfills-42372ed130431b0a.js`、`C/external/scidb/_nuxt/3858ee3.js`、`C/external/usersnap-res/widget-assets/js/entries/globalSetup/5db1532558c74f3c.js` | 分別有 **core-js 3.38.1／3.41.0／3.49.0 LICENSE 連結**，bundle 非完整 license 檔 | 若散布 polyfill 補對應版全文／copyright；首批原生 renderer 不打包。 |
| `C/external/gtm/{gtag/js__q_184e80205777262b,gtag/js__q_af5d8faf1bc13c41,gtm__q_97a6cb77122ae4ca}.js` | 內嵌 Closure 部份 **Apache-2.0** 與 Google copyright，並非整個 analytics bundle 的授權結論 | 若取部份 code 保留對應 license／NOTICE；素材首批無需 analytics。不能由一段 Apache 註解替所有服務腳本背書。 |
| `C/external/osm-matomo/matomo.js` | 明列 **BSD-3-Clause**／原授權連結 | 若散布帶條款、copyright／免責；首批不需要網站追蹤程式。 |

作者自己的 E201、列車／建物外觀、Simulator 程序造型、台北 site／動畫、圖示沒有另列限制時，依 `CLAUDE.md` 可用。來源 model 的 `sources`／攝影網址是外觀參考，**不是收錄照片貼圖**；47 建物的 `sourcePhotosIncluded`／`operatorLogoIncluded` 都為 false。保留來源 metadata，不從參考網址自行下載照片或把它當已有授權的 texture。

個別仍需補的項目：`T/avatars/basis/*`、`T/assets/avatar-CUFURxPX.js` 的 meshopt／Basis 依賴、`T/assets/three-DoD3b_mB.js`、`R3/vendor/pmtiles.js` 沒有找到完整逐元件告示；Material Design Icons／element／iconfont 等字型沒有內嵌完整使用條款，Noto Sans PBF 也只有 family／range／glyph，需補對應字型版的條款。`C/icons8-*` 與其 hsr 子目錄明確有來源品牌檔名，`C/external/flaticon/512/2776/2776067.png` 也有第三方來源路徑，但快照未提供對應取得方案／逐圖示授權；採用時核對實際方案與署名，不把檔名當 licence，也不預設必須買新授權。這些具體項不影響未標第三方條款的作者素材。

`O/binary_reference/railway_core_15_3.wasm` 可辨認 OpenTTD，但快照未帶其完整授權與對應原始碼，不應把它誤列為作者自有 mesh；若日後真的散布這個編譯核心，另核對該版本上游條款及 source-offer 等義務。此次素材計畫完全不需要它。SwiftGodot／SwiftGodotKit 在 `Railway/SWIFT_GIS_GAME_REFERENCE_STUDY.md` 標 MIT；正式選用還要釘版本、Godot runtime 與傳遞第三方告示，這次沒有新增它們。

既有 MapKit 背景沿決策 50 保留 Apple 標誌／法律連結；不擷取 Apple 3D 建物或地形轉成可保存的自有模型。這是特定背景資料使用界線，不阻止本文盤點的作者模型覆蓋在背景上。

## 6. App 大小估計

以下估**素材增量**，不是已有 IPA 的完整大小。沒有本次 Release archive，因此以 `B` 表示目前 App 的實際產物大小；SceneKit／RealityKit 系統 framework、SwiftGodot／Godot 內嵌 runtime 的打包成本不能混進素材 bytes。`G` 表示選定 Godot 版本實際加入的 runtime／資源增量，現在未量測。

| 打包策略與精確口徑 | 原檔 bytes／MiB | 對 App 的估計 |
| --- | ---: | --- |
| **全部現存圖像／字型／mesh 素材**：E201；blender-map-v1 全 41 檔；兩組建物全 98 檔；8 avatar＋manifest＋ANM1；T 全 52 圖片；C 全 148 圖片、59 字型檔（含 2 無副檔名與 2 空檔）、3 字型 PBF；R 字型／SVG；sprite JSON。未去重，不含 JS、模板、WASM 或缺檔 | **80,906,741／77.159 MiB** | 原格式 bundle 約 `B＋77.159 MiB` 的素材基準。這不是所有檔案已能原生載入；格式轉換後應以輸出 manifest 重算。 |
| **字面上把五個 snapshot／source 樹全部塞進去**（含 HTML、JS、API、快取、WASM，僅供成本對照） | **213,369,911／203.485 MiB** | 約 `B＋203.485 MiB` 原檔成本；不建議，內容有大量非素材與重複擷取，而且不應把部署資料帶入 App。 |
| **§7 首批鐵路試片的 6 份輸入檔**：E201、c321／c321-mid、fleet manifest、101 的 model＋far（試片原點擺放，不加地理 placement） | **4,106,745／3.916 MiB** | 原始素材增量約 `B＋3.916 MiB`；生成軌道／橋／月台／12 城市 proxy 的程式與實際輸出另計。 |
| 首批另加一名群眾：student-m GLB、全 ANM1、avatar manifest | **4,753,429／4.533 MiB**（含上一列） | 若只 bake idle／walk，不必帶全 ANM1；精確節省量待轉換後量。 |

全部素材 77.159 MiB 的分項是 E201 1,757,448、列車包 34,699,271、兩建物包 15,708,025、角色／manifest／動畫 3,663,916、T 圖片 7,321,701、C 圖片 7,135,817、C 字型 10,283,444、C 字型 PBF 284,969、R 字型／SVG 24,328、sprite JSON 27,822 bytes，加總可重算；內嵌 KTX2 已含在 GLB，不再加一次。缺 47 near、70 fleet mesh、角色 fallback 與 115.976 MB 地形不在合計。模板／生成參數採 §3 的匯入／程式 adapter，沒有用整個 JS 原檔預估原生程式大小；若另打包來源七份實景路網／profile JSON，原檔再加 34,931,602 bytes（33.313 MiB），但既有遊戲快照已提供自己的路網，首批無此需求。

**轉換後的規劃估計（UNVERIFIED）**：先替首批原生素材預留 **5–10 MiB**，全部素材預留 **80–160 MiB**，是約 1–2 倍原檔的暫時空間預算，**不是量測或上界**。USDZ、SCN 序列化、glTF 頂點解量化、mips、ASTC 與圖片重編碼都會改大小，不能以網頁 KTX2 壓縮量推 IPA 或 GPU 佔用。SceneKit／RealityKit 的估算寫成 `B＋轉後素材`；SwiftGodot 寫成 `B＋轉後素材＋G`，不可省略 G 後聲稱較小。

IPA 壓縮下載量、App thinning 後裝置量、安裝後檔案量與 GPU 記憶體是四種不同數字。只讀檔頭能確認角色貼圖尺寸，不能保證 iOS GPU 峰值。正式 Phase 8 試片應固定引擎／OS／工具，回報輸出 bytes、archive／IPA 素材差額與實機記憶體，再收斂預算。

## 7. 建議首批與缺口

### 7.1 最少一組試片

首批用**同一場景**比較三種引擎：一列可轉彎的 B 代表車、E201 材質模型展示、地面→高架→橋→隧道口、島式／側式月台、12 個用途×密度 proxy，以及一份真正的建物 far。

| 選材／後續產物 | 用途、來源與要證明的事 |
| --- | --- |
| `S/models/tra-e201/tra-e201.glb` | 無壓縮 GLB→Apple USDZ／SCN、Godot importer 的共同基準，驗 12 材質、Y-up、公尺 bounds；僅模型展示，不新增台鐵核心車種。 |
| `R3/assets/blender-map-v1/{c321.bin,c321-mid.bin,manifest.json}` | B 代表外觀，驗 40-byte color／gloss、頭／中／尾鏡向、沿中心路徑擺車；幾何 proxy 不更改容量／門數。 |
| `R3/assets/blender-buildings-v1/taipei101-landmark-v1/{model.json,far.mesh.bin}` | 真正 24-byte 建物、5 drawGroups、13,716 vertices／4,572 三角形；先擺試片原點，驗 Z-up→Y-up、線性 RGB／PBR、縮放與剔除。保留其 OSM source 標示。 |
| rail-3d 公尺軌道／橋面／洞口參數；Simulator 桁架／月台造型 | 以 S4 snapshot 生成，驗結構與洞口正確、月台 start/end 對齊；不需要下載缺檔或打包網頁 chunk。首批雨棚與橋墩可用簡單重複部件。 |
| 三用途×四密度的原生程序 proxy | 2／6／18／40 層，外觀選色與屋頂可取台北 style；驗 BuildingID／cells／密度變更後呈現替換，不另生人口。 |

若引擎比較需要 skin／貼圖壓縮，再加 `student-m.glb` 與 ANM1 的 idle／walk 兩段，補 Rocketbox MIT 全文。角色、全部標題圖、全部字型、全部 47 far 都不是最小鐵路試片必要項。第二批才加山佳站與總統府比較歷史低層／大量分組，沿用 6c 研究的代表選材。

### 7.2 缺口與自己要做的部分

| 缺口／定位證據 | 處理方式 |
| --- | --- |
| 110 個 fleet mesh 宣告只有 40 實檔，70 缺；62 車型只有 23 個 parts 全齊；缺清單見 §8.1 | 先用齊全車型；不足中間車可做明示低細節後備，不能宣稱已取得完整原車庫。 |
| 47 個建物皆缺 `near.mesh.bin`、宣告的 near／far GLB 共 94 份缺；`.blend`、sourceSnapshot／hero thumbnails 未收錄 | far 已足以開工。近看先用 far；必要時自己做 near／補來源，不能把 101 far 放大就稱原近景。 |
| 台北 world 缺 43 site＋1 postfx，content 缺 4 build＋1 register；source 沒有城市建物 GLB | 取現存 proxy／三個 site 的參數，補依賴後才離線烘焙；先自製 12 種用途密度的可控程序外觀。 |
| 9 avatar／LOD 與 17 fallback 缺；8 GLB 全無動畫 | 只選現存 avatar；解 ANM1／骨架 retarget，自己做所需 LOD。發佈前補缺的 MIT 全文。 |
| `R3/terrain/manifest.json` 的 14 chunks 全缺；Ci 語意 PMTiles、外部完整 3D 建物回應未收錄 | 試片用原生平面／簡單地形；背景可沿既有 MapKit，不把缺檔宣告算成已有地形 mesh。 |
| 九車種沒有完整對應 A／B／C／L／D／磁浮／雲軌／單軌外觀；台鐵車號不是 TRAIN_TYPES | 自製缺的車身與特殊梁／導軌外觀；先保留共用 proxy，正式車種／營運規則另案。 |
| 月台寬／側別／軌面到月台面高度、車身端部超出中心的政策、橋墩分布與隧道內壁沒有完整 iOS 契約 | 在呈現規格明訂，讀現有 S4 centerline／height／structure；若影響營運或建造合法性才交核心負責者設計。 |
| iOS 載入器、材質／shader、座標 adapter、來源與輸出 manifest 不在參考庫 | Phase 8 自己做轉換／小型 loader；分塊、可見剔除、LOD、普通建物 instancing 只影響呈現。 |

後續實作的驗收提案：以相同快照量測最低目標 iPhone／iPad 的冷載入、幀時間、峰值記憶體與模型數；核對軸向／bounds／材質／車身／月台／洞口；換引擎或 LOD 後遊戲 digest 不變。這些都尚未跑，不在本 PR 聲稱通過。

## 8. 逐件量測明細

### 8.1 rail-3d 列車與建物

以下 bin 都是每件 1 檔；列車類型 G2、建物 G3，格式與三引擎用法見 §2.1／§3。表格由現存檔頭／manifest／metadata 靜態量測整理。

目錄：`R3/assets/blender-map-v1/`；每列 mesh／Float32LE、G2。

| 檔名 | bytes | 頂點 | 三角形 |
| --- | --- | --- | --- |
| `c321.bin` | 960,000 | 24,000 | 8,000 |
| `c321-mid.bin` | 919,200 | 22,980 | 7,660 |
| `c381.bin` | 960,000 | 24,000 | 8,000 |
| `c381-mid.bin` | 917,760 | 22,944 | 7,648 |
| `wenhu.bin` | 960,000 | 24,000 | 8,000 |
| `wenhu-mid.bin` | 832,800 | 20,820 | 6,940 |
| `airportlocal.bin` | 960,000 | 24,000 | 8,000 |
| `airportlocal-mid.bin` | 950,160 | 23,754 | 7,918 |
| `airportexpress.bin` | 959,880 | 23,997 | 7,999 |
| `airportexpress-mid.bin` | 914,400 | 22,860 | 7,620 |
| `y100.bin` | 960,000 | 24,000 | 8,000 |
| `y100-mid.bin` | 966,960 | 24,174 | 8,058 |
| `taichung.bin` | 959,880 | 23,997 | 7,999 |
| `kaohsiung.bin` | 959,760 | 23,994 | 7,998 |
| `kaohsiung-mid.bin` | 945,120 | 23,628 | 7,876 |
| `dr1000.bin` | 960,000 | 24,000 | 8,000 |
| `dr3100.bin` | 959,880 | 23,997 | 7,999 |
| `dr3100-mid.bin` | 918,960 | 22,974 | 7,658 |
| `emu800.bin` | 959,760 | 23,994 | 7,998 |
| `emu800-mid.bin` | 925,680 | 23,142 | 7,714 |
| `temu2000.bin` | 960,000 | 24,000 | 8,000 |
| `temu2000-mid.bin` | 977,280 | 24,432 | 8,144 |
| `emu3000.bin` | 960,000 | 24,000 | 8,000 |
| `emu3000-mid.bin` | 1,008,720 | 25,218 | 8,406 |
| `700t.bin` | 959,880 | 23,997 | 7,999 |
| `700t-mid.bin` | 1,262,880 | 31,572 | 10,524 |
| `e200.bin` | 960,000 | 24,000 | 8,000 |
| `mingri.bin` | 959,880 | 23,997 | 7,999 |
| `e500.bin` | 959,760 | 23,994 | 7,998 |
| `e1000.bin` | 960,000 | 24,000 | 8,000 |
| `blue.bin` | 946,920 | 23,673 | 7,891 |
| `juguang.bin` | 960,000 | 24,000 | 8,000 |
| `ppcoach.bin` | 960,000 | 24,000 | 8,000 |
| `bluecoach.bin` | 959,760 | 23,994 | 7,998 |
| `mingricoach.bin` | 959,760 | 23,994 | 7,998 |
| `caf-section-0.bin` | 300,240 | 7,506 | 2,502 |
| `caf-section-1.bin` | 78,720 | 1,968 | 656 |
| `caf-section-2.bin` | 183,840 | 4,596 | 1,532 |
| `caf-section-3.bin` | 96,240 | 2,406 | 802 |
| `caf-section-4.bin` | 300,840 | 7,521 | 2,507 |

宣告缺的 **70 個 mesh ID**（對應 `<ID>.bin`，不是已存在的檔）：

`c301`、`c301-mid`、`c341`、`c341-mid`、`c371`、`c371-mid`、`val256`、`val256-mid`、`sanying`、`sanying-mid`、`taichung-mid`、`haifeng`、`haifeng-mid`、`shanlan`、`shanlan-mid`、`emu500`、`emu500-mid`、`emu600`、`emu600-mid`、`dr2700`、`emu100`、`emu100-mid`、`emu1200`、`emu1200-mid`、`emu700`、`emu700-mid`、`emu800r`、`emu800r-mid`、`emu900`、`emu900-mid`、`temu1000`、`temu1000-mid`、`e300`、`e400`、`r200`、`r20`、`r100`、`r150`、`r180`、`dhl100`、`dl25`、`dl38`、`dl39`、`dl45`、`alicoach`、`hinoki`、`fushen`、`xuyue`、`ck124`、`dt668`、`ct273`、`danhai`、`danhai-section-0`、`danhai-section-1`、`danhai-section-2`、`danhai-section-3`、`danhai-section-4`、`ankeng`、`ankeng-section-0`、`ankeng-section-1`、`ankeng-section-2`、`ankeng-section-3`、`ankeng-section-4`、`caf`、`citadis`、`citadis-section-0`、`citadis-section-1`、`citadis-section-2`、`citadis-section-3`、`citadis-section-4`。

parts 全齊的 **23 個車型 ID**：`c321`、`c381`、`wenhu`、`airportlocal`、`airportexpress`、`y100`、`kaohsiung`、`dr1000`、`dr3100`、`emu800`、`temu2000`、`emu3000`、`700t`、`e200`、`mingri`、`e500`、`e1000`、`blue`、`juguang`、`ppcoach`、`bluecoach`、`mingricoach`、`caf`。其餘只代表宣告仍在；不把缺檔的 byteLength 算進預算。

目錄：`R3/assets/blender-buildings-v1/`；每列 **model.json（資料，D1）＋far.mesh.bin（mesh，G3）各一檔**，無外部貼圖。ODbL 欄表示此 model 的 sources／footprintReference 明示條款；placement 的來源另在 §5 列出。

| 實際子目錄 | 名稱 | model bytes | far bytes | 三角形 | groups | model 來源標示 |
| --- | --- | --- | --- | --- | --- | --- |
| `banqiao-v1/` | 板橋車站 | 15,816 | 210,384 | 2,922 | 12 | ODbL |
| `cksmh-landmark-v1/` | 中正紀念堂 | 5,642 | 309,240 | 4,295 | 4 | ODbL |
| `hsinchu-hsr-v1/` | 高鐵新竹・六家 | 9,466 | 220,176 | 3,058 | 6 | ODbL |
| `hsinchu-tra/` | 新竹車站 | 5,914 | 201,312 | 2,796 | 5 | 作者素材；model 未另標 |
| `hualien-v1/` | 花蓮車站 | 25,641 | 306,648 | 4,259 | 20 | ODbL |
| `kaohsiung-main-v1/` | 高雄車站 | 16,146 | 1,269,144 | 17,627 | 13 | ODbL |
| `nangang-v1/` | 南港車站 | 18,937 | 325,296 | 4,518 | 15 | ODbL |
| `nanshan-plaza/` | 臺北南山廣場 | 5,871 | 670,752 | 9,316 | 5 | 作者素材；model 未另標 |
| `national-concert-hall/` | 國家音樂廳 | 5,803 | 581,328 | 8,074 | 5 | 作者素材；model 未另標 |
| `national-theater/` | 國家戲劇院 | 5,782 | 582,624 | 8,092 | 5 | 作者素材；model 未另標 |
| `shinkong-landmark-v1/` | 新光摩天大樓 | 5,915 | 42,912 | 596 | 4 | ODbL |
| `sunyatsen-landmark-v1/` | 國父紀念館 | 6,404 | 366,912 | 5,096 | 5 | ODbL |
| `tainan-hsr-v1/` | 高鐵臺南・沙崙 | 14,413 | 252,144 | 3,502 | 10 | ODbL |
| `taipei-dome/` | 臺北大巨蛋 | 5,117 | 306,576 | 4,258 | 4 | 作者素材；model 未另標 |
| `taipei-main-v1/` | 臺北車站 | 7,245 | 209,952 | 2,916 | 5 | ODbL |
| `taipei101-landmark-v1/` | 台北101 | 6,562 | 329,184 | 4,572 | 5 | ODbL |
| `taitung-v1/` | 臺東車站 | 16,129 | 227,016 | 3,153 | 11 | ODbL |
| `taoyuan-hsr-v1/` | 高鐵桃園・A18 | 9,374 | 151,128 | 2,099 | 6 | ODbL |
| `tower85-landmark-v1/` | 高雄85大樓 | 4,335 | 85,248 | 1,184 | 2 | ODbL |
| `tra-taichung-v1/` | 臺鐵臺中 | 10,824 | 454,608 | 6,314 | 8 | ODbL |
| `xinwuri-complex-v1/` | 新烏日・高鐵臺中 | 18,949 | 449,784 | 6,247 | 15 | ODbL |
| `zuoying-complex-v1/` | 左營・新左營 | 9,451 | 203,904 | 2,832 | 6 | ODbL |

目錄：`R3/assets/historic-buildings-v2/`；每列 **model.json（資料，D1）＋far.mesh.bin（mesh，G3）各一檔**，無外部貼圖。ODbL 欄表示此 model 的 sources／footprintReference 明示條款；placement 的來源另在 §5 列出。

| 實際子目錄 | 名稱 | model bytes | far bytes | 三角形 | groups | model 來源標示 |
| --- | --- | --- | --- | --- | --- | --- |
| `beimen-old/` | 北門驛 | 9,127 | 57,456 | 798 | 7 | 作者素材；model 未另標 |
| `changhua-roundhouse/` | 彰化扇形車庫 | 10,127 | 316,224 | 4,392 | 5 | ODbL |
| `checheng-wood/` | 車埕木業展示館 | 8,468 | 182,016 | 2,528 | 5 | ODbL |
| `chiayi-sawmill/` | 嘉義製材所 | 18,095 | 437,040 | 6,070 | 14 | ODbL |
| `dounan-warehouses/` | 斗南站北側倉庫群 | 26,804 | 71,712 | 996 | 24 | ODbL |
| `erjie-granary/` | 二結穀倉 | 8,053 | 74,880 | 1,040 | 4 | ODbL |
| `guanshan-old/` | 關山舊站（里壠驛） | 9,344 | 76,896 | 1,068 | 6 | ODbL |
| `hexing-old/` | 合興舊站房 | 8,991 | 26,352 | 366 | 6 | ODbL |
| `hsinchu-prefecture/` | 新竹州廳 | 7,712 | 401,616 | 5,578 | 5 | ODbL |
| `hualien-railway/` | 花蓮港出張所及武道館 | 21,868 | 182,304 | 2,532 | 17 | ODbL |
| `jingtong-coal/` | 菁桐站與選洗煤場 | 18,059 | 119,952 | 1,666 | 14 | ODbL |
| `longtian-warehouses/` | 隆田儲運站與倉庫群 | 33,126 | 87,984 | 1,222 | 30 | ODbL |
| `luodong-forest/` | 羅東林場檢車庫與竹林站 | 12,241 | 97,920 | 1,360 | 9 | ODbL |
| `presidential-office/` | 總統府 | 10,406 | 2,988,936 | 41,513 | 7 | ODbL |
| `qiaotou-sugar/` | 橋頭糖廠 | 26,975 | 425,520 | 5,910 | 23 | 作者素材；model 未另標 |
| `qidu-old/` | 七堵舊站 | 10,982 | 41,760 | 580 | 7 | ODbL |
| `railway-department/` | 鐵道部廳舍及八角樓 | 13,151 | 536,400 | 7,450 | 10 | ODbL |
| `red-house/` | 西門紅樓 | 9,163 | 180,720 | 2,510 | 6 | ODbL |
| `shanjia-old/` | 山佳舊站 | 10,194 | 37,584 | 522 | 6 | ODbL |
| `shengxing/` | 勝興站 | 11,827 | 68,256 | 948 | 8 | ODbL |
| `taian-old/` | 泰安舊站 | 18,784 | 119,520 | 1,660 | 12 | ODbL |
| `taichung-prefecture/` | 臺中州廳 | 9,585 | 403,056 | 5,598 | 5 | ODbL |
| `takao-old/` | 舊打狗驛與北號誌樓 | 17,136 | 150,480 | 2,090 | 14 | ODbL |
| `taoyuan-warehouse/` | 桃園車站舊倉庫 | 8,427 | 89,712 | 1,246 | 6 | ODbL |
| `zhutian-old/` | 竹田舊站 | 13,508 | 77,184 | 1,072 | 9 | ODbL |

### 8.2 角色與圖片

目錄：`T/avatars/`；每件一份 G4 mesh／貼圖 GLB，皆有 Rocketbox MIT／Microsoft copyright，動畫皆 0。

| 檔名 | bytes | 三角形 | joints | KTX2 張數 | KTX2 bytes（manifest） | 原角色／頭部 |
| --- | --- | --- | --- | --- | --- | --- |
| `casual-f.glb` | 217,792 | 4,792 | 20 | 3 | 159,299 | Female_Adult_03／Female_Adult_03 |
| `casual-m.glb` | 198,600 | 3,709 | 20 | 3 | 155,441 | Male_Adult_09／Male_Adult_09 |
| `elder-f.glb` | 214,948 | 4,452 | 20 | 3 | 162,739 | Female_Adult_14／Female_Adult_11 |
| `elder-m.glb` | 189,592 | 3,490 | 20 | 3 | 148,000 | Male_Adult_03／Business_Male_02 |
| `jie.glb` | 981,936 | 6,732 | 80 | 7 | 892,164 | Male_Adult_10／Male_Adult_10 |
| `student-f.glb` | 204,264 | 4,380 | 20 | 3 | 154,311 | Female_Adult_01／Female_Adult_11 |
| `student-m.glb` | 191,944 | 3,517 | 20 | 3 | 149,395 | Male_Adult_01／Business_Male_02 |
| `wen.glb` | 1,010,100 | 8,612 | 81 | 7 | 899,856 | Female_Adult_04／Sports_Female_02 |

動畫 adapter 四檔（P1／A1，JS）逐件大小：`T/assets/avatar-CUFURxPX.js` **112,468 bytes**；`T/assets/clips-Cb5uFd0j.js` **2,708 bytes**；`T/assets/animator-DGt1NqrS.js` **26,675 bytes**；`T/assets/rig-BjRdQXtM.js` **614 bytes**，合計 **142,465 bytes**。

六名群眾都各有 color／normal／mask 三張 KTX2；兩名英雄各七張，所以共 32 張。貼圖尺寸見 §2.1，沒有外部角色貼圖另外漏算。

| 路徑（每列一檔、I1） | bytes | 解析度／格式 |
| --- | --- | --- |
| `T/title/loader-1600.webp` | 181,686 | 1600×900 |
| `T/title/loader-portrait.webp` | 177,946 | 960×1706 |
| `T/title/menu-1600.webp` | 171,522 | 1600×900 |
| `T/title/menu-2560.webp` | 325,032 | 2560×1440 |
| `T/title/menu-phone.webp` | 168,866 | 1600×738 |
| `T/title/menu-portrait.webp` | 163,788 | 960×1706 |
| `T/icons/icon.svg` | 408 | SVG 向量 |

`T/splash/launch-*.png` **42 檔**，合計 **6,117,588 bytes**；解析度以檔名與 PNG header 逐件核對，寬 750–2868、高 750–2868 pixels。 `T/icons/apple-touch-icon.png` 10,436 bytes／180×180。 `T/icons/favicon-32.png` 1,069 bytes／32×32。 `T/_favicon.png` 3,360 bytes／128×128。

### 8.3 Simulator 模板

目錄：`S/api/templates/`；每列資料／JSON、D1；寬高為來源模型配置 mm，不是 GameCore 世界尺寸。

| 檔名 | bytes | placed 數（與 trackCount 相符） | 配置寬×高 |
| --- | --- | --- | --- |
| `6iVmgT0F7hgLgi1YeKSM.json` | 3,601 | 26 | 900×600 |
| `7NGoRWUr9yO9ZRGreg6O.json` | 10,007 | 77 | 1900×930 |
| `CPulwUOXzfjYdbS9MLQd.json` | 14,893 | 113 | 2631×1623 |
| `L6Tl85gHS9smTk30ClIY.json` | 8,689 | 66 | 1550×800 |
| `Nxq1plIzDmWIf5VQjyFQ.json` | 11,117 | 85 | 3450×500 |
| `auaj9yocnK8TeNsQCkMB.json` | 9,478 | 74 | 2100×1100 |
| `eqcIxVJ7upGAcQOCeFov.json` | 4,369 | 33 | 1200×650 |
| `h3GtjwK14GDMP5NlnONG.json` | 13,326 | 109 | 1800×900 |
| `zMMTOyxdWfmJ2W6iqFV3.json` | 40,482 | 282 | 5200×2100 |

### 8.4 Ci 圖示／圖片

目錄：`C/`；每列圖片／圖示 I1、1 檔，格式由副檔名標示。

| 相對 C 的路徑 | bytes | 解析度／viewBox |
| --- | --- | --- |
| `entry-save-map.jpg` | 687,445 | 1920×1200 |
| `entry-save-map__q_19c120673871f637.webp` | 99,012 | 1280×800 |
| `entry-save-map__q_3fb978b8ca32a42a.jpg` | 687,445 | 1920×1200 |
| `hsr-control-icons/icons8-user-64.png` | 624 | 64×64 |
| `hsr-train-icons/icons8-clock-96.png` | 1,143 | 96×96 |
| `hsr-train-icons/icons8-get-off-bus-100.png` | 1,917 | 100×100 |
| `hsr-train-icons/icons8-get-on-bus-100.png` | 1,373 | 100×100 |
| `icons8-airplane-landing-48.png` | 539 | 48×48 |
| `icons8-airplane-tail-fin-50.png` | 765 | 50×50 |
| `icons8-airplane-take-off-48.png` | 555 | 48×48 |
| `icons8-airport-48.png` | 409 | 48×48 |
| `icons8-arrow-down-26.png` | 202 | 26×26 |
| `icons8-arrow-down-26__q_9a1e0309b06837b1.png` | 202 | 26×26 |
| `icons8-data-transfer-48.png` | 325 | 48×48 |
| `icons8-flight-48.png` | 588 | 48×48 |
| `icons8-route-50.png` | 595 | 50×50 |
| `icons8-search-48.png` | 659 | 48×48 |
| `line-info-high-speed-train__q_d55ccade1a8d0414.png` | 321 | 24×24 |
| `line-info-route__q_d55ccade1a8d0414.png` | 533 | 48×48 |
| `public/metro-auto-arrangement.png` | 427 | 30×30 |
| `public/voyager/earth__q_c943592ea4d07e9e.webp` | 378,820 | 1774×887 |
| `public/voyager/generic-city__q_21383692569c82f8.svg` | 1,307 | viewBox 0 0 300 300 |
| `quota-icons/rail-platform.png` | 465 | 50×50 |
| `station-icon-apply-lines__q_d55ccade1a8d0414.png` | 287 | 24×24 |
| `station-icon-copy__q_d55ccade1a8d0414.png` | 183 | 24×24 |
| `station-icon-paste__q_d55ccade1a8d0414.png` | 435 | 64×64 |
| `station-icon-residential__q_d55ccade1a8d0414.png` | 476 | 48×48 |
| `station-icon-scenic__q_d55ccade1a8d0414.png` | 464 | 48×48 |
| `station-icon-shopping__q_d55ccade1a8d0414.png` | 306 | 30×30 |
| `station-icon-waiting__q_d55ccade1a8d0414.png` | 172 | 16×16 |
| `station-metric-unlock__q_d55ccade1a8d0414.png` | 618 | 64×64 |

其餘圖片依來源資料夾彙總（I1；含已單列的 OpenFreeMap sprite，**勿重複加總**）：

| 路徑範圍 | 檔數 | bytes | 解析度範圍 |
| --- | --- | --- | --- |
| `C/external/amap-01/` | 2 | 11,898 | 點陣寬 256–256、高 256–256 |
| `C/external/amap-02/` | 1 | 4,792 | 點陣寬 256–256、高 256–256 |
| `C/external/amap-03/` | 1 | 7,067 | 點陣寬 256–256、高 256–256 |
| `C/external/amap-04/` | 2 | 19,412 | 點陣寬 256–256、高 256–256 |
| `C/external/flaticon/` | 1 | 14,235 | 點陣寬 512–512、高 512–512 |
| `C/external/openfreemap/` | 6 | 235,299 | 點陣寬 48–2406、高 48–1000 |
| `C/external/openfreemap-tiles/` | 1 | 118,872 | 點陣寬 1024–1024、高 526–526 |
| `C/external/openmaptiles/` | 31 | 2,570,057 | 點陣寬 16–2691、高 16–791 |
| `C/external/osm/` | 25 | 629,521 | 點陣寬 13–400、高 12–256 |
| `C/external/pangaea/` | 1 | 3,210 | 點陣寬 64–64、高 64–64 |
| `C/external/scidb/` | 46 | 1,652,842 | 點陣寬 10–2560、高 6–680 |

### 8.5 字型逐件清單

字型都是 F1，沒有多邊形或圖片解析度，以 glyph 數記錄。授權欄表示檔內可讀標示與 §5 的對應處理，沒有標示不等於全面禁用；外部第三方字型逐件保留來源。相同字型的 web 容器是重複散布檔，不把 glyph 數加成不同字。

| 路徑（每列一檔，F1） | bytes | family | glyphs | 條款／署名標示 |
| --- | --- | --- | --- | --- |
| `C/external/osm/assets/bootstrap-icons/font/fonts/bootstrap-icons-a4b4c37fb90f2582f099ab3c34870aa3badb59098220f722c971fd5744bbdb__7d45712bb889d19d` | 180,288 | bootstrap-icons | 2077 | 來源 CSS MIT；需版本對應 |
| `C/external/osm/assets/bootstrap-icons/font/fonts/bootstrap-icons-d58dbdc0232480708b000373bb9f5be99101ea5a95df6a9ef080912f105887__fb3d4a8a3903e57c` | 134,044 | bootstrap-icons | 2077 | 來源 CSS MIT；需版本對應 |
| `C/external/scidb/_nuxt/fonts/VideoJS.46ac662__q_e3b0c44298fc1c14.eot` | 6,952 | VideoJS | 33 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/element-icons.535877f.woff` | 28,200 | element | 281 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/element-icons.732389d.ttf` | 55,956 | element | 281 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/fontawesome-webfont.674f50d.eot` | 165,742 | FontAwesome | 707 | 授權連結／copyright；§5 OFL |
| `C/external/scidb/_nuxt/fonts/fontawesome-webfont.674f50d__q_e3b0c44298fc1c14.eot` | 165,742 | FontAwesome | 707 | 授權連結／copyright；§5 OFL |
| `C/external/scidb/_nuxt/fonts/fontawesome-webfont.af7ae50.woff2` | 77,160 | FontAwesome | 707 | 授權連結／copyright；§5 OFL |
| `C/external/scidb/_nuxt/fonts/fontawesome-webfont.b06871f.ttf` | 165,548 | FontAwesome | 707 | 授權連結／copyright；§5 OFL |
| `C/external/scidb/_nuxt/fonts/fontawesome-webfont.fee66e7.woff` | 98,024 | FontAwesome | 707 | 授權連結／copyright；§5 OFL |
| `C/external/scidb/_nuxt/fonts/iconfont.1f7e7c7.ttf` | 1,700 | iconfont | 2 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/iconfont.832edac.ttf` | 4,160 | iconfont | 4 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/iconfont.8cd199f.ttf` | 2,592 | iconfont | 7 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/iconfont.9749bc9.eot` | 4,328 | iconfont | 4 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/iconfont.9b79313.woff` | 1,820 | iconfont | 7 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/iconfont.c6c7bc6.woff` | 2,912 | iconfont | 4 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/iconfont.d88896d.eot` | 2,760 | iconfont | 7 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/materialdesignicons-webfont.026b7ac.woff` | 587,984 | Material Design Icons | 7431 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/materialdesignicons-webfont.1d7bcee.woff2` | 403,216 | Material Design Icons | 7431 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/materialdesignicons-webfont.6e43553.ttf` | 1,307,660 | Material Design Icons | 7431 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/materialdesignicons-webfont.8ced95a.eot` | 1,307,880 | Material Design Icons | 7431 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/materialdesignicons-webfont.8ced95a__q_e3b0c44298fc1c14.eot` | 1,307,880 | Material Design Icons | 7431 | 未內嵌完整條款 |
| `C/external/scidb/_nuxt/fonts/pdf.06fc6a2.woff2` | 12,976 | pdf | 100 | Fontello authors copyright；gap |
| `C/external/scidb/_nuxt/fonts/pdf.7928efb.woff` | 15,728 | pdf | 100 | Fontello authors copyright；gap |
| `C/external/scidb/_nuxt/fonts/pdf.8acc3f5.ttf` | 28,792 | pdf | 100 | Fontello authors copyright；gap |
| `C/external/scidb/_nuxt/fonts/pdf.fde29d4.eot` | 28,940 | pdf | 100 | Fontello authors copyright；gap |
| `C/external/scidb/_nuxt/fonts/pdf.fde29d4__q_e3b0c44298fc1c14.eot` | 28,940 | pdf | 100 | Fontello authors copyright；gap |
| `C/external/scidb/_nuxt/fonts/roboto-latin-100.5cb7edf.woff` | 20,368 | Roboto Thin | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-100.7370c36.woff2` | 15,808 | Roboto Thin | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-100italic.f8b1df5.woff2` | 17,008 | Roboto Thin | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-100italic.f9e8e59.woff` | 21,704 | Roboto Thin | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-300.b00849e.woff` | 20,348 | Roboto Light | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-300.ef7c663.woff2` | 15,784 | Roboto Light | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-300italic.14286f3.woff2` | 17,448 | Roboto Light | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-300italic.4df3289.woff` | 22,204 | Roboto Light | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-400.479970f.woff2` | 15,736 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-400.60fa3c0.woff` | 20,268 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-400italic.51521a2.woff2` | 17,324 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-400italic.fe65b83.woff` | 21,952 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-500.020c97d.woff2` | 15,872 | Roboto Medium | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-500.8728489.woff` | 20,464 | Roboto Medium | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-500italic.288ad9c.woff` | 22,020 | Roboto Medium | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-500italic.db4a2a2.woff2` | 17,316 | Roboto Medium | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-700.2735a3a.woff2` | 15,816 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-700.adcde98.woff` | 20,356 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-700italic.81f5786.woff` | 21,588 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-700italic.da0e717.woff2` | 17,020 | Roboto | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-900.9b3766e.woff2` | 15,712 | Roboto Black | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-900.bb1e4dc.woff` | 20,392 | Roboto Black | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-900italic.28f9151.woff` | 22,304 | Roboto Black | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/_nuxt/fonts/roboto-latin-900italic.ebf6d16.woff2` | 17,520 | Roboto Black | 248 | Apache 2.0 連結／copyright |
| `C/external/scidb/social-share/fonts/iconfont.eot` | 9,580 | iconfont | 17 | 未內嵌完整條款 |
| `C/external/scidb/social-share/fonts/iconfont.ttf` | 9,296 | iconfont | 17 | 未內嵌完整條款 |
| `C/external/scidb/social-share/fonts/iconfont.woff` | 6,364 | iconfont | 17 | 未內嵌完整條款 |
| `C/external/scidb/social-share/fonts/iconfont__q_e3b0c44298fc1c14.eot` | 9,580 | iconfont | 17 | 未內嵌完整條款 |
| `C/external/scidb/static/iconfont.ttf` | 0 | 空檔 | — | 無內容，不能使用為字型 |
| `C/external/scidb/static/iconfont.woff` | 0 | 空檔 | — | 無內容，不能使用為字型 |
| `C/fonts/cross-platform-ui/inter-variable__q_21383692569c82f8.woff2` | 352,240 | Inter Variable | 2937 | OFL 1.1／copyright |
| `C/fonts/mtr-sung.woff2` | 3,316,128 | MTR Sung／華 | 15174 | DynaLab／Fourth Bus copyright；gap |
| `R/assets/fonts/rail-emoji.woff2` | 13,652 | Noto Emoji SemiBold | 27 | Google copyright；§5 上游 OFL |

MapLibre 字型 glyph 分塊（F1／D1，PBF；以 protobuf 欄位量測，**不是完整字型**）：

| 路徑 | bytes | glyphs | 單 glyph 寬／高上限 |
| --- | --- | --- | --- |
| `C/external/openfreemap-tiles/fonts/Noto_20Sans_20Bold/0-255.pbf` | 81,170 | 223 | 23／24 pixels |
| `C/external/openfreemap-tiles/fonts/Noto_20Sans_20Regular/0-255.pbf` | 76,580 | 223 | 22／24 pixels |
| `C/external/openfreemap-tiles/fonts/Noto_20Sans_20Regular/256-511.pbf` | 127,219 | 256 | 28／27 pixels |

## 9. 查閱與驗證邊界

**VERIFIED（雲端 Linux，靜態盤點）**：clone／讀取上述提交、規則、Phase 8 與指定研究 PR；以 `rg --files`／`rg` 找素材、license／copyright／來源欄位；在 repo 外用 Prettier 3.6.2 展開指定 JS；以 Python 讀 JSON、GLB header／accessors／skin、KTX2 header、ANM1 header、圖片檔頭、字型 name／glyph 表（FontTools 與 Brotli）與 PBF glyph 欄位，量測 bytes／數量／解析度；核對 87 份 bin 的大小／stride／SHA-256／finite floats、建物 drawGroup 計數與缺檔。另讀上游 Noto Emoji LICENSE 與 Font Awesome v4.7.0 README，以文件連結中的提交固定本次證據。

**UNVERIFIED**：沒有跑任何程式檢查、Swift 建置或測試、golden／replay、CI、Xcode、iOS Simulator／實機、網頁場景、Three.js／Blender runtime 或三種候選引擎；沒有解 meshopt／Basis、生成 mesh、retarget、轉 USDZ／SCN／標準 glTF、實測 archive／IPA／GPU／效能，也沒有逐件目視模型。沒有下載缺少的模型、地形、site、外部照片或完整圖磚；沒有對每個未標條款的 vendor 做上游全面審核。

文件提交時只核對 Git 的檔案差異與空白格式，確認唯一新增檔為 `docs/research/PHASE8_ASSET_INVENTORY.md`。靜態素材量測與文件差異核對不代替程式或 iOS 驗證。
