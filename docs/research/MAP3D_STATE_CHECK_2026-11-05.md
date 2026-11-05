# 原生 3D 現況核對：哪些已做、下一步（2026-11-05）

> 類型：只讀研究與差異追蹤。基準是 `main` `aaa3fa6`（2026-11-05）。
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

要不要排進優先清單，由遊戲規劃或主要的 Claude Code session 決定。本篇不修改 `docs/HANDOFF.md` 或共用的優先清單，以免和其他 session 同時寫入。

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
