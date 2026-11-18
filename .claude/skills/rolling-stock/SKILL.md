---
name: rolling-stock
description: 3D 地圖裡的列車：配方放哪、近景與遠景、塗裝帶、發光頂點、預算、雜湊、用 tools/train-models 檢查與拍圖、怎麼給作者看。做或改列車（Map3DTrainShell、Map3DTrainSets、各車配方、Map3DModelPack）的外型、塗裝、編組、遠景版時先讀。Use before adding or changing a train in the native 3D map (Map3DModelPack, Map3DTrainSet, a car recipe in Sources/GamePresentation) — car shape, livery, formation, far version, budget — or when judging whether a train looks right. The web CityView's trains.js is in the appendix.
---

# 3D 地圖的列車（原生 Metal）：程式規則

遊戲的 3D 是自己寫的 Metal。列車是 `Sources/GamePresentation` 裡的 Swift 配方，輸出三角形：一個三角形一個顏色（頂點色）、塗裝帶用 alpha、發光用旗標，沒有貼圖與 UV。

**造型、塗裝、亮窗與玻璃怎麼畫、車頂零件、給作者看的方式、作者自製模型與工作室 GLB 轉進遊戲的做法、新車的水準、網頁版附錄**是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/rolling-stock.md`（同節號）。**做或改車之前先讀那一份**；這裡只留程式結構、預算、雜湊與工具。做或改模型照 [model-look](../model-look/SKILL.md)。

## 2. 配方放哪

- **模型包**：`Map3DModelPack.standard`（`Map3DModels.swift`）。App 第一次開 3D 前把它整包建好、CPU 與 GPU 各留一份，所以**遊戲不畫的靜態展示模型**（單元、整列、角色，沒有 set 接它們）放 `Map3DModelPack.studies`，只給工具與 `hashes.lock.json` 讀（審查 K1-1）。`standard` 的模型數與總頂點數由 `Map3DModelPackSizeTests` 釘住（決策 782 起不算註冊車，見 §2.1）：手寫進 `standard` 的車要改那兩個數，並在 PR 寫多了多少；註冊車只在 PR 寫。每個模型有名字、`vertices`（三個一組，各帶這個三角形自己的平面法線）、`minimum`／`maximum`。座標：**+x 車頭、+y 左、+z 上、軌面 z = 0、公尺、車廂中心 x = 0**。
- **程式放樣的車**：`Map3DTrainShell`（`Map3DTrainStyle` 的 cab／car／panto）。每款專用車有自己的配方檔：`Map3DEMU800`、`Map3DEMU900`、`Map3DEMU500`、`Map3DEMU3000`、`Map3DTEMU1000`／`2000`、`Map3DC341`、`Map3DE500`、`Map3DN700SG`、`Map3DTrainShapeRefresh`（700T、E200）…
- **編組**：`Map3DTrainSet`（`Map3DTrainSets.swift`）。一個 set 有 key、近景的 head／middle／tail／panto／centre／single、`far`（遠景 set 的 key）、`ownLengths`、`cycle`（中間車的循環）。模型名字照 `set-<key>-<單元>`，遠景 `set-<key>Far-<單元>`。`Map3DTrainSet.byKey` 是全部。
- **接進營運**：`Map3DModelPack.modelIndex(forType:carIndex:count:)`、`layout(forType:count:)`；`Map3DTrains` 擺實例。只加模型、沒接 set，合併後不會在遊戲裡出現。

### 2.1 新車一律用註冊表（決策 782）

以前每款車都要改 `Map3DScene.swift`（色票）、`Map3DTrainSets.swift`（`all`、`nearOnly`）、`Map3DShowcase.swift`、`hashes.lock.json`、`Map3DModelPackSizeTests`、`Map3DModelPackLockTests`、`Map3DTrainSetTests`，兩款同時做一定衝突。現在**新車只新增自己的檔**，兩款可以同時做：

1. `Sources/GamePresentation/Map3D<車>.swift`（照 `Map3DMTRAirportLine.swift`）：`Unit`、`meshPalette`（與 `glb_to_swift.py --materials` 同順序）、`model(_:far:)`；同一個檔裡寫
   - `extension Map3DPalette { public static let … }`：這款車自己的色票（不要加進 `Map3DScene.swift`）；
   - `extension Map3DTrainSet { static func …(far:) }`：它的 set；
   - `static let registration = Map3DTrainRegistration(id: "<車>", sets: [近, 遠, …], showcase: [Map3DShowcase.Entry(…)], triangles: …, length: …)`：set 依「近、遠」排；有遠景 set 的自動算進 `nearOnly`；`showcase` 是列車展示的列；`triangles`／`length` 是 `Map3DTrainSetTests` 對它每節車的範圍（寬、高、燈照共通規則）。
2. `Sources/GamePresentation/Map3DTrainRegistryList.swift` 最後加**一行** `Map3D<車>.registration,`。這個檔設了 `merge=union`（`.gitattributes`），兩個分支各加一行時 git 會兩行都留，不會衝突；`Map3DTrainRegistryTests` 會擋忘了加或加了兩次。
3. `tools/train-models/locks/<id>.json`：`run.sh OUT --lock tools/train-models/hashes.lock.json` 會把註冊車的模型雜湊、燈組數（`lampCount`）與燈的摘要（`lamps`）寫進這個檔，`hashes.lock.json` 一行都不會變。在 Mac 上算的雜湊與 `lamps` 可能和 Linux 差最後一位，照 CI 失敗訊息填（`Map3DModelPackLockTests.testEveryModelIsAsLocked`／`testEveryRegisteredTrainIsAsLocked` 會印出正確值）。
4. `Tests/GamePresentationTests/Map3D<車>Tests.swift`：只寫這款車特有的事（編組順序、行李車沒窗…）。
5. `docs/decisions/<N>.md`、`docs/art/<資料夾>/`。

`Map3DModelPackSizeTests`、`Map3DModelPackLockTests` 的數字與摘要只算手寫的車，加註冊車**不用改**；註冊的 set 一律接在 `Map3DTrainSet.all` 最後（手寫的之後），所以前面的模型都不會移位。要接到真實路線（`Map3DRealTrains`、`set(forKey:count:locked:)`、`byType`）時才會改到共用的表，那是一格一格的改，和別款車通常不在同一行。

## 3. 近景與遠景

- 近景：500 m 內（`Map3DTrainSet.reach(of:)`），一節一個實例。
- 遠景：500–900 m，**同一款車一節換一節**（`Map3DModelPack.model(_:forType:count:at:)`、`farModel(of:forType:count:)`），900 m 外是方塊。弱的裝置、卡的時候換得早（決策 417 的 `nearerFarModels`）。
- **新的精細車一定帶遠景版**（417 規則 1）：同樣的造型、塗裝、編組、燈，少細節。做法照 420：頭十圈留六圈、鼻蓋列數減、腰帶分段減、車輪 8 邊、每側一片長玻璃，拿掉輪轂、側樑、冷氣頂蓋與小窗。遠景版與近景同一個框（長度、車頂、貼地），顏色是近景顏色的子集，塗裝帶與燈還在。
- 一節超過 20,000 個三角形的車再加一層中間版，只給 lower 級（417 規則 2）。自動簡化器（`Map3DMeshSimplifier`，420）只給沒有配方的網格，而且只用 50 %；有配方的車用配方做遠景版。
- 每加一款精細車，跑 `Map3DMotionBudgetTests.testWhatTheMapKeepsInMemory` 量模型包的記憶體，寫進 PR（417 規則 3）。

## 4. 引擎替配方做的事（細節在私有那份 §4）

- 頂點 alpha 小於 1 的地方畫線的顏色（塗裝帶）。
- 帶發光旗標的三角形夜裡從裡面亮（`Map3DVertex.glows`）；頭尾燈、客室窗由 `Map3DTrainLights` 每格決定（決策 449），窗只認標成 `trainGlass` 的面（`Map3DTrainMaterial.marksOwnGlass`），沒標面的舊車才照顏色猜。新車加進 `Map3DTrainOwnGlassTests.studioCars`。
- 遮蔽陰影（決策 439）、車窗反光與不鏽鋼光澤（決策 450）、方向幕（決策 436）、影子（決策 232）都由 pack 或場景加，配方不畫。不鏽鋼車要加進 `Map3DTrainMaterial.stainlessSets`。
- 遊戲兩面都畫（`setCullMode(.none)`）：共面或相距不到 1 cm 的重疊面會閃爍。

## 5. 預算與雜湊（規則，數字在 `tools/train-models/budgets.json`）

- 近景一節 ≤ 20,000 個三角形；十二節一列 ≤ 240,000；遠景一列 ≤ 120,000，一節少於近景的一半（420、432）。
- 一節的實例數不變：整列用實例畫，重點是單節的三角形數與頂點資料（遠景版三角形約 0.1–0.4 MB 一列，420 量過）。
- **雜湊**：每個頂點所有欄位的 FNV-1a（`Map3DEMU800IntegrationTests.hash`）。改了別款車、或改了共用的函式，不該動的模型雜湊就會變：`hashes.lock.json` 抓這個。刻意改的，在 PR 逐項說明並更新鎖；Swift 測試也釘（`Map3DFarSets420Tests.testTheNearTarokoIsUnchanged` 的做法）。
- 面數是 CPU／GPU 的帳，不是美術的帳：實機幀數 UNVERIFIED，等 TestFlight 的除錯數字（417）。

## 6. 新工具 `tools/train-models/`

```sh
tools/train-models/run.sh OUT --tag after                 # 匯出：.m3dmodel、manifest（三角形、框、雜湊、near/far 對）
node tools/train-models/check.mjs OUT [--new-set key]     # 預算與雜湊，紅就是 exit 1
node tools/train-models/render.mjs OUT --time both        # 七向圖，日與夜，遊戲的模型光
node tools/train-models/viewer.mjs OUT/index.html OUT     # 離線預覽頁；兩個資料夾就並排
```

**一款新車的順序**：①照建模手冊做配方；②`run.sh --ids <新模型>`；③`render.mjs` 看七向（先看黑色剪影、白模，再看上色）；④`check.mjs --new-set <key>`（預算、遠景版、雜湊）；⑤把新模型加進鎖（`run.sh OUT --lock tools/train-models/hashes.lock.json`），註冊車（§2.1）只應該多出 `locks/<id>.json`，`hashes.lock.json` 一行都不該變，變了就是動到別款；⑥跑 `swift build --build-tests -Xswiftc -warnings-as-errors` 與該車的測試；⑦給作者看。不要再開新的 `tools/<車>/` 資料夾；舊資料夾沒有的專用驗收（GLB 打包、逐車的門窗／正面稽核）才放進車自己的目錄，並在 `tools/train-models/README.md` 的對照表加一行。

**改前／改後**（改了既有車的外觀，例如夜間亮燈、遮蔽烘焙、玻璃反光）：在 main 的 worktree 匯出到 `before`（`--tag before`）、在分支匯出到 `after`，各自 `render.mjs`，`viewer.mjs 頁 before after`。路線圖第 1–3 項的 PR 用同一個工具，`renderer.js` 的 `features` 旗標就是為它們留的。

**材質（決策 450）**：`render.mjs OUT --features 1` 會畫車窗反光與不鏽鋼光澤（`export.swift` 把玻璃寫在 M3DM flags bit 1、不鏽鋼寫在 bit 2，manifest 的 `lighting` 帶天頂色、陽光色、太陽露出多少；每款的 `glassTriangles`、`steelTriangles` 也在 manifest）。不加旗標（`--features 0`）就是沒有材質的樣子。因為材質不改顏色，同一次匯出各拍一次就是改前／改後，不用另開 main 的 worktree。預覽沒有 `u` 的遮蔽，被遮住的面映得和開闊的一樣多，所以比遊戲稍亮。

網頁版（`Web/CityView`）用的 `measure.cjs`、`preview.cjs` 留在這個資料夾，用法在私有那份的附錄。

## 7. 驗證

照 CLAUDE.md 寫 VERIFIED／UNVERIFIED：Linux 的 WebGL 預覽不是 Metal；靜態模型合併後要接 set 才會在遊戲出現；真機的 Metal、效能、動畫 UNVERIFIED。大型成品放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`）。
