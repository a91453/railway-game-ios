# 原生 3D 現況核對：哪些已做、下一步（2026-11-05）

> 類型：只讀研究與差異追蹤。§1–11 的基準是 `main` `aaa3fa6`（2026-11-05）；§12 的結論以 `main` `02c41d8`（同日稍晚）重新核對。
>
> 不修改的範圍：App、GameCore、渲染器、資產、依賴、存檔、golden schema、決策編號。
>
> 本篇對照 [`FENN_3D_WORLD_STUDY_2026-10-19.md`](FENN_3D_WORLD_STUDY_2026-10-19.md)（已合併 PR [#824](https://github.com/a91453/railway-game-ios/pull/824)）的建議與目前的程式，記下已經做完、不該再排的項目，以及接下來的候選。外部 App 與網站的技術查證不在本篇。

## 1. 10/19 研究的建議與 `main` 現況的修正（讀現在的程式）

| 項目 | 10/19 研究中的說法 | 2026-11-05 `main` 查到的實作 | 本輪結論 |
| --- | --- | --- | --- |
| 色調映射 | Metal 還沒有色調映射，建議 ACES 與 bloom | 決策 [349](../decisions/349.md) 已實作（`Sources/GamePresentation/Map3DGrade.swift`；`RailwayGameApp/Views/Map3D/Map3DShaders.metal` 的 `map3dFinish`）：<br>• Khronos PBR Neutral 的**肩部**；<br>• 局部調色；<br>• 貼地薄霧。<br>決策刻意**不用 ACES／AgX**，以免中間色與夜景變樣 | **色調映射已做**，不要重做，也不要整套換成 ACES。bloom 是另一個後製議題，決策 349 仍列為後續 |
| 場景載入 | 開一次 12 km 場景，不跟著鏡頭移動 | `Sources/GamePresentation/Map3DStreaming.swift` 已有：<br>• 512 m 的 chunk；<br>• 移動方向前方先蓋；<br>• 5×5 分塊與保留策略。<br>決策 [358](../decisions/358.md) 接上實景地圖的鏡頭；決策 [368](../decisions/368.md) 再改成近處完整、遠處 coarse | **實景地圖的串流已做**。不要再把「鏡頭串流」當新功能；應該針對真實壓力與車站附近的突跳做驗收 |
| 實景建物的樣子 | 實景建物缺店面與屋頂設備 | `Sources/GamePresentation/Map3DRealBuildings.swift` 的 `addRealBuilding`：<br>• 依 `RealKind` 選外牆、一樓商店、窗格、屋頂；<br>• 屋頂有水塔、頂樓加蓋或設備；<br>• far 的矩形另外用 box 表示；<br>• 以世界座標當種子，結果固定 | **程序化的立面、店面與屋頂已經有了**。依建築面積分級可以當美術品質的對照，不要再開一個重複的生成器 |
| 手機降級 | 另外加一個手機的 lite 等級 | 已有三套機制：<br>• `Sources/GamePresentation/Map3DQuality.swift`：自動、省電、高畫質、關；<br>• `Map3DMotionBudget.swift` 與決策 [417](../decisions/417.md)：動態街景、列車遠景模型、降像素的階梯；<br>• 決策 [460](../decisions/460.md)：低記憶體策略 | **已經比單一的 lite 等級分得更細**。要量的是現有階梯在實機上的畫質與退化點，不是多加選項 |

補充：`Map3DRealBuildings.swift` 目前把建物分成 shophouse、house、flats、office、industry、civic、temple、transport，不只是舊研究寫的「只依用途換顏色」。這次沒有做互動測試，所以不宣稱實景建物已經和 `GameWorld` 的改建、收購完全一致。

## 2. 針對《沿線》的下一步：不換引擎

### P0：不改功能，先建立可比較的手機基準

- 量測條件：同一存檔、同一機種、同一鏡頭路徑。
- 量測場景：白天密集的實景城市、夜間車站商圈、跟車進出站（含地下與高架）。
- 記錄：
  - `Map3DMetalView.Stats` 的 FPS、CPU 與 GPU 時間、draw calls、三角形數、畫質階梯；
  - 峰值記憶體、閃退、截圖。
- 「自動」「高畫質」「省電」三組各測一次。效能預算以這些實測為準。
- 先檢查決策 [349](../decisions/349.md)、[417](../decisions/417.md)、[460](../decisions/460.md) 的限制。沒有實機結果之前，不預告效能提升。

### P1：獨立 PoC：車站樓層與剖面顯示

- **先在既有的 `Map3DScene`、`Map3DSeeThrough` 上研究展示方案**：選一個樓層時，顯示站廳、月台、地面，隱藏上方的遮擋。營運、路線與 GameCore 都不改。
- PoC 先用一座資料明確的原生車站。要處理月台、軌道、列車的可見性，並標明樓層資料是實測還是推估。研究階段只留下接口與驗收草案，不在本 PR 實作。
- 要驗的風險：
  - 透明與隱藏的繪製順序；
  - 穿透車站的遮擋；
  - 鏡頭回正；
  - iPhone 小畫面上的可讀性；
  - 鏡頭移動時 chunk 的更替。

  這些都要用原生測試確認。

### P1：夜景 bloom 值不值得 GPU 成本

- bloom 目前還不是原生功能，也不是改一個 shader 就有：
  - 現在的 `bgra8Unorm` 與逐 fragment 的 PBR Neutral 肩部，可能提早把亮部截掉；
  - 真正的 HDR bloom 要重新檢視亮度來源、render target、額外的 pass、記憶體與省電降級。
- 先做離線或實機的 A/B 對照，現有的夜窗、招牌、車燈配色都不變，比較三種：
  1. 沒有 bloom；
  2. 輕量貼片；
  3. 低解析度 bloom。
- 讓作者選樣子，再看高畫質負不負擔得起。**不要替換現有的 Neutral 色調映射。**

### P2：建築與地標的製作成本

- 以目前的 `Map3DRealBuildings.swift`、`Map3DBuildings.swift`、`Map3DSurfaces`、`Map3DModelFile` 為基線，列出「透天、公寓、辦公、站前商店」的素材變體清單，先評估新的款式能不能由既有零件與立面規則組出來。
- 大型地標與多樓層的特殊建物才考慮手工模型，並沿用既有的 GLB → 原生模型管線。
- 要研究自訂壓縮格式的話，先量 App 大小、解碼時間、RAM、draw calls，並核對現有 meshoptimizer 的工作。沒有數字就不更換。

## 3. 研究導入排序（五方）

| 候選 | 玩家 | 鐵道迷 | 開發 | 美術 | 音樂／音效 | 建議 |
| --- | --- | --- | --- | --- | --- | --- |
| 手機場景基準 | 減少卡頓與閃退 | 跟車與到站不中斷 | 可以用現有的 Stats；先量才知道瓶頸 | 讓效果比較公平 | 無 | **先做（量測）** |
| 車站剖面與樓層 PoC | 看得清地下與立體車站 | 月台與軌道的層位正確 | 要測遮擋、深度、鏡頭；不動營運 | 多層結構更好讀 | 無 | **選一站試做** |
| 夜景 bloom 對照 | 夜景比較有氣氛（待實測） | 不能讓號誌變模糊 | 多一個 pass，有記憶體風險 | 補足現有的燈光效果 | 無 | **先 A/B，再決定** |
| 全面換引擎或新格式 | 沒有直接價值 | 可能破壞既有路網幾何 | 大規模重構，沒有瓶頸證據 | 容易讓風格不一致 | 無 | **不建議** |

## 4. 可驗收的後續任務（本次沒有改程式）

1. **基準**：為現有的原生 3D 準備三組可重播的場景，在 iPhone 與 iPad 上量 FPS、GPU P50／P95、峰值 RAM、繪製指令數、三角形數，並記下當下的畫質階梯。用同一段鏡頭軌跡做 A/B。
2. **樓層 PoC**：
   - 交付一座車站「地面、站廳、月台」切換的示意，以及不改 `GameWorld` 的資料契約；
   - 驗收：站體遮擋正確、列車仍看得到、回到一般模式後沒有殘留；
   - iPhone 橫向與 iPad 都要看過。
3. **夜景 PoC**：
   - 在不改色調映射的前提下，比較貼片與低成本 bloom；
   - 量額外 render target 的佔用與 GPU P95，並測省電與發熱降級；
   - 沒量過之前，不宣稱 60 FPS 或畫質代價。
4. **避免重工的清單**：每次開實作 PR 之前，先查決策 349、358、368、417、460 與實際的 `main`，避免再排入色調映射、分塊串流、程序化店面與屋頂、裝置分級。

排序見 §12.7（已寫進 `NEXT_PRIORITIES_2026-10-12.md` §24.6）。本篇不修改 `docs/HANDOFF.md`。

## 5. 來源、驗證與未驗證事項

- **VERIFIED（本輪靜態查核）**：
  - 讀過本 repo `main` 的 `Map3DRealBuildings.swift`、`Map3DGrade.swift`、`Map3DShaders.metal`、`Map3DStreaming.swift`、`Map3DQuality.swift`、`Map3DMetalView.swift`；
  - 讀過決策 349、358、368、417、460；
  - 讀過已合併的 [#824](https://github.com/a91453/railway-game-ios/pull/824)。

  這裡的 VERIFIED 只代表**確實讀過來源**，不代表跑過測試。
- **UNVERIFIED（本輪）**：
  - iPhone 與 iPad 上真實的 GPU／CPU 用量與 bloom 負荷；
  - 本 repo 的 Swift build 與 UI 測試。
- **授權**：OSM、Overture 與其他地理資料，各自依來源的授權處理（見本 repo 的 `DataSourceCredits`）。

## 6. 3D 場景技術資料流：已實作與尚待驗證的邊界

這一節把分散在原生程式與工具中的技術整理成一條可驗證的資料流；**只描述本專案現況與可行方案，不推定任何未取得原始碼的實作方式**。

| 階段 | 目前可從程式確認的行為 | 下一步要驗的問題 |
| --- | --- | --- |
| 地理資料→局部座標 | `Map3DRealBuildings.swift` 對 `CityTileArea` 的點轉換為 `RealWorldFrame` 中的世界位置；`Map3DGeometry.swift` 使用場景原點附近的公尺座標（x 東、y 上、z 南） | 高度／樓層的來源和缺值處理、跨分塊接縫、來源座標精度；不可把推估高度說成實測值 |
| 建築輪廓→可繪幾何 | `addRealBuildings` 依用途分 `RealKind`，將多邊形牆面與含孔洞屋頂交給幾何建造；店面、窗格、女兒牆、屋頂設備按類別與尺寸加入 | 不規則輪廓的效率、沿街朝向、遊戲改建／收購與來源建物的對應；這次沒有驗互動 |
| 決定論的外觀 | `addRealBuilding` 以固定世界座標與 `map3DRandom` 作種子；配色和立面選擇不依場景原點重新抽樣 | 重新載入、換相機中心、分塊重蓋時同一棟是否仍有相同外觀 |
| 距離與細節 | `Map3DScene.Chunk` 有 `mesh`、`far`、`farBoxes`、`close`、`coarse` 等資料；遠景長方形可轉 box instance，複雜輪廓保留幾何 | 過渡距離、遠近切換外觀、不同機型三角數與峰值記憶體 |
| 視野串流 | `Map3DStreaming.swift` 的實景路線使用 512 m chunk、移動方向預建與周圍保留；近處補完整細節、遠處簡化 | 高速跟車、突然跳站、長時間移動、記憶體警告時是否會重覆建立或留下過量場景 |
| GPU 繪製 | `Map3DMetalView.swift` 使用 Metal 頂點／實例／陰影等管線；靜態場景與動態列車分開 | CPU→GPU 上傳峰值、draw call、列車動態 buffer、遮擋與透明排序，不能只看模型檔大小 |

**界線：** 程序化建築、地形與場景分塊已存在；「每一個地理位置都可生成完整高品質建物」、「真實建物已可隨玩家改建完整替換」、「所有多樓層內部皆有資料」均不能從上述程式直接推出。

## 7. 模型輸入、離線轉換與原生檔案格式

### 7.1 現有工具是兩條不同的入口（原始碼已核對）

| 項目 | 現有能力 | 已知限制 |
| --- | --- | --- |
| 靜態幾何橋接 `tools/glb-to-m3dmodel/bridge.mjs` | 讀取 GLB 或 `.gltf + .bin`；以 `@gltf-transform/core`、extensions 與 meshoptimizer 解開 `EXT_meshopt_compression`、`KHR_mesh_quantization`；可用節點白名單保留祖先轉換、設定朝向／公尺比例、記來源 SHA-256 | 僅限**無貼圖、無骨架、無動畫、無形變**的靜態三角網格；拒絕 sparse accessor、其他擴充、材質貼圖槽與不合法外部 buffer；不是通用 3D 載入器 |
| 貼圖烘色入口 `tools/glb-to-m3dmodel/convert.mjs` | 既有 GLB 模型可將可支援的 PNG／JPEG 貼圖取樣、烘為平塗三角形顏色、限制最多八色，並處理方向與比例 | 對圖片格式、glTF 擴充及來源記錄有明確限制；貼圖烘色會失去細小窗框／字樣的解析度，不適合無條件套在所有地標或列車上 |
| 格式驗證 `tools/gltf-validate/` | Khronos glTF Validator 有獨立檢查流程與 CI；與原生轉換器的幾何、來源、安全檢查分開 | Validator 合格不代表美術、座標、公尺比例、面數、原生解碼或實機效能合格 |
| 原生解碼 `Sources/GamePresentation/Map3DModelFile.swift` | 讀取 `.m3dmodel`、檢查格式版本、面數、旗標、非有限座標、來源 JSON，還原平塗三角形與法線 | 不是 GLB／glTF 執行期直接載入器；不保留原模型的材質圖、骨架動畫與共用頂點索引 |

工具允許的能力不等於所有素材都能直接使用：每批模型還必須保留來源記錄、授權依據、比例／前方、正面朝向、色票、法線與測試輸出。

### 7.2 `.m3dmodel` v1 的實際資料契約

- 檔頭 16 bytes：`M3DM`、版本 `UInt16`、保留欄位 `UInt16`、三角形數 `UInt32`、來源 JSON 長度 `UInt32`；接著是補至四位元組對齊的 UTF-8 來源記錄。
- 每面 **52 bytes**：`UInt32` 旗標 + 3 個角，每角 3×`Float32`（公尺位置）與 1×`UInt32` RGBA。旗標涵蓋夜間自發光、列車玻璃與不鏽鋼；上限是 **15,000 面／檔**（此為 `Map3DModelFile.maximumTriangles`，不是整場景的上限）。
- **不儲存法線、材質貼圖與共用頂點索引**：解碼時計算每個三角面的平面法線。故平滑車頭、弧面與銳角要以原模型的面數和法線效果做實際外觀驗收。
- 資產大小近似：`16 + 來源 JSON 對齊長度 + 52 × 面數` bytes；10,000 面約 **520 KB 幾何負載**（十進位），不含來源記錄。這不是直接等於 GPU 佔用。
- 解碼成 `Map3DVertex` 時每角為 **40 bytes**（位置 12、法線 12、顏色 4、UV／layer 12），若三角形不共用角，單面頂點數據約 **120 bytes**；10,000 面約 **1.20 MB 頂點數據**，還沒計索引、常駐場景及緩衝複本。**檔案變小不等於 RAM／GPU 自動等比變小。**

### 7.3 有名稱但尚未證成的替代格式

- 其他自訂封裝格式：**本專案沒有可讀寫、可回歸測試的格式規格或正式轉換器**，不能視為已導入的技術，更不能據此替換 `.m3dmodel`。另見 §12：遊戲裡的列車與街景模型大多由 Swift 配方在執行期組成（決策 546），不經過任何模型檔，所以換檔案格式省不到它們的記憶體。
- 新包格式若要成為候選，最少必須寫清：版本與魔數、索引／材質／法線布局、座標與單位、來源和授權、可變長區段、校驗、向後相容、錯誤回退、重建工具、離線與執行期耗時。未證明實際收益前，沿用現有管線。

## 8. 幾何壓縮與精度：各技術解決的不是同一個問題

| 技術 | 對象與原理 | 本專案現況或風險 | 驗證方式 |
| --- | --- | --- | --- |
| meshoptimizer / `EXT_meshopt_compression` | 用於 glTF 資料的編碼與解碼、幾何處理；可降低傳輸或封裝內容，簡化器亦可減面 | **離線工具已用** meshoptimizer 解碼與部分減面；`.m3dmodel` 本身並沒有因此保留 meshopt 壓縮編碼 | 相同模型逐頂點對照、實際原檔大小／新檔大小／轉檔時間；若減面，另量輪廓、顏色縫與細部遺失 |
| `Float16` 位置／UV | 每通道由 32-bit 變 16-bit，可減少部分頂點屬性所占位元組 | 原生頂點**沒有**用 half（`Map3DVertex` 全為 `Float32`／`UInt32`，§12.2 實測）；大範圍絕對公尺座標易失精度，須採局部原點／尺度，鐵軌、月台與接縫需更嚴格的幾何公差 | 對照列車／軌距／月台高度、長距離座標、chunk 邊界；以實際頂點布局計算節省量 |
| Octahedral 2×`Int16` 法線 | 把 3D 單位法線編成兩個 16-bit 分量，再由 shader 解碼 | 候選，不是已採用；需處理正反面、零長法線、量化誤差；目前檔案的面法線在解碼後重新求出 | 比較明暗、弧面與銳邊的角度偏差，再量頂點步長和 GPU 時間 |
| `UInt16` 索引 | 同一個索引由 32-bit 改為 16-bit | **單一索引範圍最多可表示 65,536 個不同頂點**，不是最多 65,536 個三角形；大 mesh 需拆批或保留 32-bit。實測模型包 846 個模型中最大的 60,597 頂點，沒有一個超過 65,535（§12.2）；城市 chunk 則不一定 | 比對索引合法性、拆批後拓樸與 draw calls，量索引緩衝大小 |
| `LZFSE`／其他封裝壓縮 | 可在磁碟／下載層壓縮已封裝的位元組，讀取時解壓 | 這一輪**沒有查到本專案的 `.m3dmodel` 使用 LZFSE 的證據**；壓縮不會直接減少展開後的頂點／GPU 緩衝，且新增解碼、峰值與跨平台維護成本 | 相同模型測檔案大小、冷啟解壓時間、峰值 RAM、失敗回退；需量實際二進位，不用猜比率 |
| Instancing 與幾何 LOD | 共用形狀／材質、不同位置作實例；遠距改成粗幾何 | **已具備** `Map3DBoxInstance`、`Map3DScene.farBoxes`、列車遠景和裝置分級；再做新系統前先量是否真的有瓶頸 | 同鏡頭的三角數、draw calls、記憶體與畫面差異（包含夜間窗格） |

**資料量不能混比：** 壓縮前後必須是「相同模型、相同節點、相同表面細節」；從複合場景挑出其中一台車後得到較小檔案，屬於資產篩選，不能全部歸功壓縮。

## 9. 場景批次、繪製成本與品質分級

- **遠景建築實例化已做**：`Map3DBoxInstances.swift` 的 `Map3DBoxInstance` 固定 88 bytes／個。相較普通方盒展開為頂點與索引的數百 bytes，可節省場景資料；GPU 管線也有對應的 box vertex 與日照深度版本。這不是所有建物都只占 88 bytes，也不代表 draw calls 必定減少（見 [決策 455](../decisions/455.md)）。
- **LOD 是場景層與模型層兩件事**：場景的 `mesh/far/close/coarse` 決定城市在什麼距離有多少細節；列車另有近遠模與品質預算。新增立面小物前，需同時檢查「哪一個距離拿掉」和「被拿掉後是否仍可辨識」。
- **實例批次的另一側成本**：增加 material／pipeline 切換、陰影 pass、半透明排序，或把每種立面拆成過多批次，都可能抵消省下的頂點。先量 `drawCalls`、CPU encoding、GPU P95，再考慮併批。
- **現有品質階梯已足夠作第一次測量**：`Map3DQuality.swift`、`Map3DMotionBudget.swift`、決策 417／460 會調整街景份量、遠模距離、繪圖像素、陰影與記憶體。應分辨掉幀來自 CPU／GPU／記憶體，而非遇到任何卡頓就盲降畫質。
- **大型場景的驗收**：同份存檔、相同鏡頭路徑，在密集站前、遠景城市、高架跟車、地下站、夜景依序收集 CPU/GPU P50／P95、場景建造與上傳時間、常駐／峰值 RAM、draw calls、三角數、visible／resident chunks，以及畫質階梯。不同機型、畫面更新率與熱狀態分開記錄。

## 10. 多樓層、遮擋與夜間光效的技術設計草案（非既有功能聲稱）

### 10.1 多樓層剖面 PoC

- **資料模型**：由展示層建立不可變的 `LevelSlice` 概念（樓層 ID、地面基準高、上下界、可見構件集合、已知／推估資料標記）；GameCore 仍只負責權威站體、月台、股道與世界狀態，不因切畫面新增另一份營運資料。
- **渲染策略**：先嘗試依樓層隱藏上層 mesh 與遮擋物，再比較剖切平面或局部透視。保留選取月台、列車與股道的深度順序；不能將全部外牆設透明就當完成剖面。
- **串流互動**：樓層選擇不應造成整座地圖重建；鏡頭移到另一個 chunk 時，已選樓層應能恢復一致。地下地形、車站雨棚與玻璃的順序要分開測。
- **驗收**：同一站切換地面／站廳／月台層可重複、截面沒有漏面，返回一般 3D 不殘留隱藏狀態；iPhone 橫向與 iPad 均可操作；先不開正式建造／營運功能。

### 10.2 夜景與後製 PoC

- **已實作** `Map3DGrade.swift` + `map3dFinish` 的 Neutral 肩部、色票收尾與薄霧；**不可改寫為全面 ACES**。目前主要色彩附件格式為 `bgra8Unorm`，過亮資訊可能在後製前被截斷。
- **候選 A：** 原有光圈／低成本幾何貼片，不加 HDR 貼圖；**候選 B：** 半／四分之一解析度亮部擷取與模糊，獨立 render pass；**候選 C：** 若真的需要保留大於 1 的亮度，再評估高動態範圍中介貼圖及與現有收尾的先後順序。
- **風險**：額外 render target 與 MSAA resolve、夜間遮擋、透明物／燈號的辨識、低功耗降級和發熱；不能只比較靜態截圖。
- **驗收**：同機型同站同時刻，保存 A/B 畫面和 GPU P95／峰值 RAM；低畫質／省電不得因效果增加而失去可讀性，燈號與列車頭燈不可過曝成一片。

## 11. 可執行研究任務與驗證界線

| 順序 | 任務 | 必須交付的證據 | 不要做 |
| --- | --- | --- | --- |
| P0 | 盤點三種具代表性的現有模型（車、建物、站體）從 GLB、離線轉換到 `.m3dmodel` 的同內容檔案大小與解碼中間量（§12 改列 P2：`.m3dmodel` 只有 11 個檔、約 540 KB，記憶體大頭在執行期組成的模型包） | 原始與輸出 SHA、面數、色數、來源記錄、轉換時間、RAM／GPU 頂點量估算 | 不引入新格式、不混入不同內容模型做壓縮比 |
| P0 | 以目前程式重放密集城市與高架／地下跟車 | CPU/GPU P50、P95、建 scene／upload 用時、記憶體、draw calls、triangles、畫質階梯 | 不把 Linux 幾何測試當 iPhone Metal 實測 |
| P1 | 離線試 `Float16`、Oct16、16-bit 索引與封裝壓縮各一個變體 | 同幾何逐頂點與畫面差異、量化公差、檔案大小、解碼時間、繪製時間、峰值記憶體 | 不一次更換正式 `.m3dmodel` 規格；無證據不宣稱節省百分比 |
| P1 | 單站樓層／剖面 PoC | 地面／站廳／月台狀態、遮擋／選取／列車可見性測試，對 `Map3DSeeThrough` 的增量設計 | 不先改 GameCore 或保存格式 |
| P1 | 夜間貼片 vs 輕量泛光 | 同場景畫面與 GPU／RAM A/B、低畫質回退 | 不改既定色調映射；不能先假定額外 pass 可免費承擔 |

**VERIFIED（靜態查核）**：`Map3DModelFile.swift`、`Map3DGeometry.swift`、`Map3DBoxInstances.swift`、`Map3DRealBuildings.swift`、`Map3DScene.swift`、`Map3DStreaming.swift`、`Map3DMetalView.swift`、`tools/glb-to-m3dmodel/README.md` 與 `bridge.mjs`、`convert.mjs`、`tools/gltf-validate/README.md`，以及決策 349、358、368、417、455、460、467 的目前可讀內容。

**UNVERIFIED（未實際執行）**：本輪沒有在機器上跑 Swift／Node 的轉檔或測試、沒有新增測試樣本，也沒有做 Metal 真機／視覺 A/B。所有 Byte 數的公式是由既有格式定義算得的理論載荷，不是新的現場效能量測。

**資料與授權**：維持現有來源／署名追溯；外來未附明確可重用許可的程式、模型與圖像不直接匯入。本段只記錄通用工程技術和本專案已核對的實作。

## 12. 最終技術結論與開發優先順序

> 以 `main` `02c41d8` 的程式為準重新核對（2026-11-05）。本節只提方案，不改程式；要開工的項目各自開實作 PR。

### 12.1 結論

- **原生 3D 的架構已經夠成熟，不需要再引進新的渲染技術或換格式。** Metal 管線、實景建物、程序化城市、分塊串流、遠景實例、品質分級、色調映射、陰影都已做完並有決策與測試。
- 剩下的不是「缺技術」，是**現有功能的四個缺口**：
  1. 列車與街景模型包的記憶體（CPU 留一份、頂點格式寬）；
  2. 實景建物沒有近景細節；
  3. 夜景只有自發光顏色，沒有光暈；
  4. 沒有任何實機數字。
- 要讓城市更完整、更好看、又少做手工模型，最划算的是**把既有的近景細節與立面規則接到 196 萬棟實景輪廓上**，而不是做更多單棟模型。

### 12.2 現有能力：十五項完成度

狀態只用五種：已完成／部分完成／尚未實作／不建議導入／尚待驗證。行號為 `main` `02c41d8`。

| # | 項目 | 狀態 | 依據（程式或決策） | 一句話判斷 |
| --: | --- | --- | --- | --- |
| 1 | Metal 原生渲染 | **已完成** | `RailwayGameApp/Views/Map3D/Map3DMetalView.swift`、`Map3DShaders.metal`；決策 229–244 | 不換引擎 |
| 2 | 2D／3D 座標轉換 | **已完成** | `RealWorldFrame`；`Map3DGeometry.swift`（x 東、y 上、z 南）；決策 358 讓 3D 跟著實景地圖的鏡頭 | 3D 裡的點選由 BUILD3D-2（#1637）做，不另開 |
| 3 | OSM／地理資料建物 | **已完成**（高度來源尚待驗證） | `Map3DRealBuildings.swift:48` `addRealBuildings`；決策 386、389（1,964,819 棟輪廓，`taiwan_buildings.pmtiles` 29.6 MB） | 高度缺值時的推估要標明是推估 |
| 4 | 程序化道路、地形、城市 | **已完成** | `Map3DBuildings.swift`（決策 235 地塊、385 沿街面）、`Map3DStreets.swift`、`Map3DRealGround.swift`、`Map3DRoadMarkings.swift`、`Map3DShopStreet.swift` | 不重做 |
| 5 | 立面、窗、屋頂、材質 | **部分完成** | `Map3DRealBuildings.swift:129` `addRealBuilding`：8 種 `RealKind` 的外牆、店面、窗格、屋頂設備；程序化地塊另有近景細節（決策 267）。**實景輪廓沒有近景層**（檔內沒有 close／detail） | 缺口 2，見前三名第 2 項 |
| 6 | GLB／glTF → `.m3dmodel` | **已完成** | `tools/glb-to-m3dmodel/`（bridge、convert）、`Map3DModelFile.swift`、`tools/gltf-validate/`；遊戲內 11 個檔、約 540 KB | 執行期 glTF 載入器**不建議導入** |
| 7 | meshoptimizer、減面、壓縮 | **部分完成** | 離線：bridge 用 meshoptimizer 解碼，`tools/meshy-props` 用 `MeshoptSimplifier`；Swift QEM `Map3DMeshSimplifier`（決策 420） | 執行期的 meshopt 編碼**不建議導入**（見 12.2 實測） |
| 8 | Float16、Oct、UInt16、封裝壓縮 | **尚未實作** | `Map3DGeometry.swift:17` `Map3DVertex` 40 B（全 `Float32`／`UInt32`），索引 `UInt32` | 只對模型包做，見 P1 |
| 9 | 實例、併批、draw calls | **已完成**（每幀緩衝待改） | `Map3DBoxInstances.swift`（88 B／棟，決策 455）；列車同型連續畫（`Map3DMetalView.swift:589`、`:1202`、`:1241`）。但盒子、影子、車廂、玻璃**每幀新建 `MTLBuffer`**（`:1029`、`:1033`、`:1041`、`:1075`） | 小修：比照 `lifeBuffers`（`:957`）用三份輪替 |
| 10 | 串流、LOD、剔除 | **已完成** | `Map3DStreaming.swift`（512 m chunk，決策 358）；遠處 coarse（決策 368）；`mesh/far/farBoxes/close/coarse`；chunk 的視錐剔除（`Map3DCamera.sees`，`Map3DMetalView.swift:546`） | 改建後只重蓋經過的區塊已排在 BUILD3D-3，不另開 |
| 11 | Shader、PBR、陰影、色調映射 | **已完成** | 決策 349（PBR Neutral 的肩部、調色、薄霧）、357（日照陰影圖） | 全套 PBR 貼圖材質與 ACES **不建議導入** |
| 12 | Bloom、夜間照明、後製 | **部分完成** | 夜窗、招牌、車燈有自發光旗標（`Map3DTrainLights.swift`、`.m3dmodel` 旗標）；色彩附件 `bgra8Unorm`（`Map3DMetalView.swift:433`），沒有 HDR、沒有 bloom | 缺口 3，見前三名第 3 項 |
| 13 | 車站樓層、剖面、遮擋 | **部分完成** | `Map3DSeeThrough`（alpha-to-coverage 透視，`Map3DMetalView.swift:325`）、`Map3DUnderground.swift`（決策 394）、`trackCover.openings`；沒有選樓層 | P2，跟 STATIONEXP-2 的 3D 那半一起看 |
| 14 | iPhone／iPad 效能、記憶體、分級 | **部分完成** | `Map3DQuality.swift:109`（自動 60 fps、省電 30 fps、熱度降級）、`Map3DMotionBudget.swift`、決策 417、460；**模型包上傳在主執行緒、CPU 一直留一份**（`Map3DMetalView.swift:875` `useModels`；`docs/HANDOFF.md:759`） | 缺口 1，前三名第 1 項 |
| 15 | 授權、來源、測試、驗收 | **部分完成**（實機驗收尚待驗證） | `DataSourceCredits`；`.m3dmodel` 的來源 JSON 與 SHA-256；`Map3DModelPackLockTests`、`Map3DRealBuildingsTests`、`Map3DStreamingTests`；glTF Validator CI | 缺實機的 FPS／記憶體基準 |

**實測（本輪，Linux，Swift 6.4.0 release，4 核；在 scratch 套件讀 `main` 99b9e44 的 `Map3DModelPack.standard`）：**

| 量 | 數值 |
| --- | --- |
| 模型數 | 846 |
| 組成時間 | 1.02 s |
| 頂點數 | 6,330,858（不重複 4,861,894，76.8%） |
| 以 40 B／頂點算 | 253,234,320 B（`HANDOFF.md:759` 記的 192 MB 是決策 546 當時的量，模型包之後又變大） |
| 單一模型最多頂點 | 60,597（0 個超過 65,535，可用 `UInt16` 索引） |
| 位置絕對值最大 | 96.38 m（模型局部座標） |
| 位置改 Float16 的最大誤差 | 0.0312 m |
| u、v 絕對值最大／layer 種類 | 0.838／5 種 |
| 壓縮格式試算：位置 `Float32` + 八面體法線 2×snorm8 + RGBA8 + 3×half（24 B／頂點）+ `UInt16` 索引 | 129,347,172 B（**−49%**） |
| zlib-6：原格式／壓縮格式 | 31,041,882 B／30,089,947 B |
| lzma-6：原格式／壓縮格式 | 10,427,144 B／8,166,680 B |

**怎麼讀：**
- 模型包在執行期由 Swift 配方組成（決策 546），**沒有檔案**，所以磁碟或下載的封裝壓縮（zlib、lzma、LZFSE、meshopt 編碼）省不到任何記憶體。
- 省記憶體只有兩條路：不留 CPU 那一份，以及把頂點格式變窄。
- 位置**不建議**改 Float16：3.1 cm 的誤差在車門、月台邊與軌距上看得出來，而位置只占 12 B，維持 `Float32` 也已經是 −49%。
- 城市 chunk 的座標跨好幾公里，Float16 不適用；索引可能超過 65,535，不能直接換 `UInt16`。
- 以上是 Linux 上的大小計算；**GPU 時間與實機記憶體都 UNVERIFIED。**

**已經做好、不要再排的：**
- 程序化建築與地塊、自動城市、chunk 串流、遠景 GPU 實例、LOD、品質自動分級、色調映射與打光、GLB 轉檔。
- 這些有缺點的地方，只做下面列的小增量，不重寫。

### 12.3 缺口與五方評估

「效能」一欄是記憶體、相容與 GPU 的風險；沒有實測的不寫比例。

| 候選 | 玩家 | 鐵道與城市的真實 | 開發成本與維護 | 3D 美術 | 效能、記憶體、相容 | 判斷 |
| --- | --- | --- | --- | --- | --- | --- |
| A. 模型包：上傳移出主執行緒、不留 CPU 那份 | 開 3D 不頓、舊機較不會被系統關掉 | 無 | 小；只動 App 與 GamePresentation，模型位元不變 | 無變化 | 少一份 253 MB 的常駐（實機待量） | **P0** |
| B. 模型包的窄頂點格式（24 B） | 同上 | 無 | 中；要改列車的頂點描述與 shader 讀法 | 法線量化可能讓曲面略變，要比圖 | 試算 −49%；GPU 時間待量 | **P1**（A 合了、有實機數字後） |
| C. 每幀新建的緩衝改輪替 | 減少卡頓的可能 | 無 | 小；比照現有 `lifeBuffers` | 無 | 減少每幀的配置；收益待量 | **P1**（小） |
| D. 實景輪廓的近景細節與台灣立面規則 | 城市近看像台灣街道 | 騎樓、鐵窗、招牌、頂樓加蓋貼近真實街景 | 中；沿用既有零件與沿街面判斷，結果要固定 | 收益最大；不用手工建模 | 只在近景層，省電與低記憶體要能整層拿掉 | **P1**（前三名） |
| E. 夜景的光暈貼片（不用 HDR） | 夜景有氣氛 | 號誌、車燈不能糊成一片 | 中；不加 render target | 補足夜景 | 加透明貼片的填充率，要量 | **P1**（前三名） |
| F. 低解析度 bloom | 同上，可能更好看 | 同上 | 大；新 pass、新貼圖、與色調映射的先後 | 要作者看 A/B | 額外 render target 與發熱 | **P2**（E 之後、A/B 再定） |
| G. 車站樓層與剖面 | 看得清立體車站 | 月台層位正確 | 中～大；遮擋、選取、鏡頭 | 多層好讀 | 隱藏層不能觸發重蓋 | **P2**（跟 STATIONEXP-2 的 3D 那半） |
| H. 不動時降幀 | 省電、少發熱 | 無 | 小，但遊戲開著時列車一直在動 | 無 | 只在暫停時有用 | **P2** |
| I. 每週整個重建的場景鍵（`Map3DPreviewScreen.swift:748`） | 跨週時可能頓一下 | 無 | 和 BUILD3D-3 的局部重蓋重疊 | 無 | 待量 | 併入 BUILD3D-3，不另排 |

### 12.4 前三名

**第 1 名：MAP3D-MEM（P0，候選 A；之後 B、C）**
- 檔案：
  - `RailwayGameApp/Views/Map3D/Map3DMetalView.swift`（`useModels` `:875`；畫列車時讀 `vertices.count` 的 `:589`、`:1202`、`:1241`）；
  - `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift`（`Map3DTrainModels` `:466`、靜態模型 `:1045`）；
  - `Sources/GamePresentation/Map3DModels.swift`、`Map3DTrainLights.swift`、`Map3DTransparentGlass.swift`（這兩個會讀頂點，要先留下它們要的衍生資料）。
- 最小範圍：
  - 上傳一次 GPU 緩衝，App 期間共用；
  - CPU 只留名稱、頂點數、外框，以及燈與玻璃需要的衍生資料；
  - 上傳在背景做，主執行緒只接結果。
- 依賴：
  - BUILD3D-2（#1637）合了再開，避免同時改 `Map3DMetalView.swift`；
  - 不動 GameCore、存檔、golden。
- 完成的樣子：
  - 開 3D 時主執行緒沒有一次超過一幀的卡住；
  - 列車、燈、玻璃畫面與現在相同；
  - 實機的常駐記憶體下降（數字由作者的 TestFlight 量）。
- 測試：
  - `Map3DModelPackLockTests` 不變（模型位元相同）；
  - 新增 Linux 測試：留下的中繼資料與原模型包的頂點數、外框一致；
  - 既有 3D UI 測試照跑。
- 獨立 PR：**是**。B（窄頂點格式）與 C（輪替緩衝）各一個 PR，A 合了才開。

**第 2 名：FACADE-REAL（P1，候選 D）**
- 檔案：
  - `Sources/GamePresentation/Map3DRealBuildings.swift`（`addRealBuilding` `:129`）；
  - 沿用 `Map3DFootprints.swift` 的沿街面判斷（決策 385）、決策 267 的近景細節、`Map3DDetailKit*.swift`、`Map3DShopStreet.swift` 的零件。
- 最小範圍：
  - 只給沿街的那一面加近景層：騎樓柱、鐵窗、冷氣機、直立招牌、頂樓加蓋；
  - 依 `RealKind` 選規則；
  - 以世界座標為種子，結果固定；
  - 不新增手工模型。
- 依賴：無 GameCore；STATIONEXP-2 的 3D 那半改站體，不同檔，可前後接。
- 完成的樣子：
  - 三個固定實景街區（站前商店街、住宅巷、辦公區）近看有台灣街道的層次；
  - 遠看沒有變化；
  - 省電與低記憶體時近景層整層拿掉。
- 測試：
  - `Map3DRealBuildingsTests` 加「同輪廓、同種子，結果位元相同」；
  - 每個 chunk 近景層的三角形數不超過現有近景預算；
  - 3D 外觀按決策 482 的較高一級，由遊戲規劃 session 看過截圖才合併。
- 獨立 PR：**是**。

**第 3 名：NIGHT-GLOW（P1，候選 E；F 留到之後）**
- 檔案：
  - `Map3DShaders.metal`、`Map3DMetalView.swift`；
  - `Map3DTrainLights.swift`；
  - GamePresentation 新增一個從既有自發光旗標產生光暈貼片的函式。
- 最小範圍：
  - 只替已經會發光的東西（夜窗、招牌、車頭燈、號誌）加加法混合的貼片；
  - 不加 render target，不動 Neutral 色調映射（決策 349）。
- 依賴：建議排在 MAP3D-MEM 之後（同檔）；不動 GameCore。
- 完成的樣子：
  - 三個固定夜景（站前、高架跟車、住宅區）有光暈；
  - 紅、黃、綠號誌仍分得出；
  - 省電時關掉。
- 測試：
  - Linux 測試：貼片數與自發光來源一一對應、結果固定；
  - 實機 GPU 時間的 A/B（UNVERIFIED，要 TestFlight）；
  - 截圖給遊戲規劃 session 看。
- 獨立 PR：**是**。低解析度 bloom（F）等這個合了、作者看過 A/B 再決定。

### 12.5 延後與不做

**延後（P2）：**
- 低解析度 bloom（F）；
- 車站樓層與剖面（G）：等 STATIONEXP-2 的 3D 那半合了再看；
- 不動時降幀（H）；
- `.m3dmodel` 的同內容轉檔盤點（§11 原 P0）：只有 11 個檔，不是記憶體的大頭。

**不做：**
- 換引擎，或加執行期 glTF 載入器；
- 全套 PBR 貼圖材質，或把色調映射換成 ACES／AgX（決策 349 刻意不用）；
- 新的自訂封裝格式，或把 `.m3dmodel` 加上磁碟壓縮：省不到執行期的記憶體；
- 城市 chunk 的位置改 Float16（跨公里的座標會失準），或 chunk 索引全面改 `UInt16`；
- GPU 驅動的剔除或間接繪製：沒有瓶頸證據，chunk 視錐剔除已有；
- 大量手工建模城市建物：前三名第 2 項用規則做到；
- 沒有 A/B 就上 HDR 管線。

### 12.6 成本、風險與驗收

- **成本**：
  - 三項都只動 App 與 GamePresentation，跑 GamePresentation 那一級 CI，不佔「最多 2 個動 GameCore 的 PR」的名額；
  - MAP3D-MEM 小，FACADE-REAL 與 NIGHT-GLOW 中。
- **風險**：
  - MAP3D-MEM 漏掉某個讀模型包頂點的地方：用編譯錯誤找出所有讀取點，不留可空的頂點陣列；
  - FACADE-REAL 讓近景三角形變多：用每 chunk 預算擋；
  - NIGHT-GLOW 的透明貼片填充率：省電時關掉，並保留 A/B。
- **驗收的共同條件**：
  - 同一存檔、同一機型、同一鏡頭路徑；
  - 用 `Map3DMetalView.Stats` 記 FPS、CPU 與 GPU 時間、draw calls、三角形數、畫質階梯，另記峰值記憶體；
  - Linux 上的結果寫 VERIFIED，實機數字在作者量到之前寫 UNVERIFIED，不預告比例。

### 12.7 PR 拆分與排入目前的優先順序

排進 `NEXT_PRIORITIES_2026-10-12.md` §24.1（同一 PR 新增 §24.6）。三項都不動 GameCore，所以用「第 n 名之後」的方式插入，不擠掉作者要的功能與 bug。

| 插入位置 | PR | 內容 | 開工條件 |
| --- | --- | --- | --- |
| 6a | MAP3D-MEM-1 | 候選 A：上傳移出主執行緒、不留 CPU 那份 | BUILD3D-2（#1637）合了 |
| 6b | MAP3D-MEM-2 | 候選 C：每幀緩衝改輪替 | 6a 合了 |
| 7a | FACADE-REAL | 候選 D：實景輪廓的近景與立面規則 | 隨時可開，但不要和 STATIONEXP-2 的 3D 那半同時改 `Map3DRealBuildings.swift` |
| 13a | NIGHT-GLOW | 候選 E：光暈貼片 | 6a 合了 |
| 13b | MAP3D-MEM-3 | 候選 B：模型包的窄頂點格式 | 6a 合了，且有作者的實機記憶體數字 |
| 不排 | F、G、H、I | 見 12.5；I 併入 BUILD3D-3 | — |

`docs/HANDOFF.md:759` 那一條（`useModels` 移出主執行緒）就是 6a；本 PR 沒有改 HANDOFF，交接文字由開工的 session 或遊戲規劃 session 更新。
