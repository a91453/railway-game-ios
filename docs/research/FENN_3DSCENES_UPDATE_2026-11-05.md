# 3D Scenes / Anywhere：Fenn 3D 技術增量研究（2026-11-05）

> 類型：只讀研究與差異追蹤；基準：`main` `aaa3fa6`（2026-11-05）。不修改 App、GameCore、渲染器、資產、依賴、存檔、golden schema、決策編號。
> 前置研究：[`FENN_3D_WORLD_STUDY_2026-10-19.md`](FENN_3D_WORLD_STUDY_2026-10-19.md)（已合併 PR [#824](https://github.com/a91453/railway-game-ios/pull/824)）。本篇僅記錄新場景可證的介面能力，以及 10/19 研究對目前程式碼已不適用的描述；不重貼原始研究。

## 1. 證據等級與存取限制

- **A｜2026-11-05 可重新核對**：網站公開 HTML／文字與本專案 `main` 上的原始碼、決策文件（下附具體路徑）。
- **B｜10/19 既有研究**：PR #824 當時讀取公開 JS 得出的細節；此輪沒有重新取得 JS，保留為「先前已查證、這次未重新驗證」，不能冒充本次實測。
- **C｜推論／未驗證**：3D Scenes 的不同場景是否共用同一引擎、Anywhere 原生 App 是否共用網頁素材、所有城市是否由 OSM 自動建模、實際手機 FPS／峰值記憶體。
- 網站首頁和指定路徑可用文字擷取確認標題與功能提示，但本輪無法執行 WebGL／WebGPU；網頁資料工具不能展開 JS 場景，執行環境直接請求網域時 DNS 失敗。**沒有嘗試繞過存取限制**，也未取得他人的原始碼或二進位檔。
- `https://anywhere.fenn.chat/credits` 及 `https://anywhere.fenn.chat/assets/Globe-ATTRIBUTION.txt` 本輪無法重新開啟；不要把先前對話對 Metal／GLBP 的敘述升級為本輪已確認的事實。

## 2. 3D Scenes 展示了什麼（A：公開頁面自述，不等於底層實作證據）

| 公開入口 | 站點能證實的能力 | 《沿線》可研究的問題 | 本輪不能推論 |
| --- | --- | --- | --- |
| [首頁](https://3dscenes.qualityf2p.workers.dev/) | 標示「Real-time · in the browser · WebGL2」；推薦桌面，手機有 lighter tier；列出多類場景 | 如何制定視覺規格／降級驗收 | 不能據此認定所有子場景只用 WebGL2（舊研究說巴黎有 WebGPU 路徑） |
| [Paris](https://3dscenes.qualityf2p.workers.dev/paris)、[NYC](https://3dscenes.qualityf2p.workers.dev/nyc) | 首頁描述各約 1 km² stylized city tile | 高密度都市在遠景如何看得清、色彩如何統一 | 無法從頁面量得三角形、資產大小或 GPU 費用 |
| [Shibuya](https://3dscenes.qualityf2p.workers.dev/shibuya) | 首頁描述約 500 m tile、霓虹夜景；子頁顯示互動 3D 初始化 | 站前商圈與夜間高對比 | 不能以此推出 Anywhere 原生 App 的建築產線 |
| [LAX](https://3dscenes.qualityf2p.workers.dev/lax)、Changi（首頁） | 首頁描述機場、floors、route、live traffic | 大型交通設施的樓層／動態資訊展示 | 不能確認其航班資料來源、室內模型幾何或授權 |
| [YC Pier 70](https://3dscenes.qualityf2p.workers.dev/yc) | 子頁有 lower／1／2／3 樓控制；官方說建築外觀參考公開紀錄、房間位置與部分樓層為推估 | 車站地下層、站廳、月台、地面層的切換與註明不確定資料 | 此為解讀性模型，不能把內部配置當作實測建築圖 |
| [Silo](https://3dscenes.qualityf2p.workers.dev/silo) | 子頁宣稱 144 levels、cut open | 剖面／遮擋與層級瀏覽的視覺模式 | 不代表每層都有完整可玩幾何，也與真實建築資料無關 |

10/19 的詳細 JS 觀察仍以 [舊研究 §3](FENN_3D_WORLD_STUDY_2026-10-19.md#3-讀程式看到的做法澀谷threejs-webgl) 為準：澀谷 OSM、程序化牆與屋頂、實例窗；巴黎 Rust/wgpu+WASM。**這些是前次紀錄，非本輪取得的原始碼。** 網站未公開適合移植到本遊戲的授權，不能複製其程式、貼圖、模型或資料包。

## 3. 10/19 舊結論與 `main` 現況的修正（A：讀現在的程式）

| 項目 | 10/19 研究中的說法 | 2026-11-05 `main` 查到的實作 | 本輪結論 |
| --- | --- | --- | --- |
| 色調映射 | Metal 尚無色調映射，建議 ACES／bloom | `Sources/GamePresentation/Map3DGrade.swift` 與 `RailwayGameApp/Views/Map3D/Map3DShaders.metal` 的 `map3dFinish`：決策 [349](../decisions/349.md) 已實作 Khronos PBR Neutral **肩部**、局部調色與貼地薄霧；決策刻意**沒有用 ACES／AgX**，以免中間色與夜景變樣 | **色調映射已做，不應重做／整套換 ACES**；bloom 是分開的後製議題，決策 349 仍列為後續 |
| 場景載入 | 開一次 12 km 場景，不隨鏡頭移動 | `Sources/GamePresentation/Map3DStreaming.swift` 已有 512 m chunk、移動前方優先、5×5 分塊與滯留策略；決策 [358](../decisions/358.md) 接上實景地圖相機；決策 [368](../decisions/368.md) 進一步做近處完整、遠處 coarse | **實景地圖串流已做**。不要再把「增加 camera streaming」當新功能；應針對真實壓力／車站突跳做驗收 |
| 實景建物表現 | 實景建物缺店面／屋頂設備 | `Sources/GamePresentation/Map3DRealBuildings.swift` 的 `addRealBuilding` 依 `RealKind` 選外牆、商店一樓、窗格、屋頂；屋頂包含水塔、頂樓加蓋或設備，far 的矩形另走 box 表示，且以世界座標種子確定化 | **程序化立面、店面與屋頂已有實作**。Fenn 式「建築面積分級」可做美術品質對照，不宜再開一個重複生成器 |
| 手機降級 | 要仿 Fenn 設手機 lite tier | `Sources/GamePresentation/Map3DQuality.swift`：自動、省電、高畫質、關；`Map3DMotionBudget.swift` 與決策 [417](../decisions/417.md)：動態街景、列車遠模、降像素的階梯；決策 [460](../decisions/460.md) 增加低記憶體策略 | **已比單一 mobile/lite 分檔更細**，需量現有階梯在真機的品質與退化點，而非盲加選單 |
| 可直接移植 Fenn 資料／模型 | 外部程式可參照 | 10/19 研究 §7 明載網站**沒有使用授權**，僅能讀做法；本作已有 `Map3DModelFile.swift`／`tools/glb-to-m3dmodel/` 的原生模型產線 | **不抄幾何／shader／資料包**；不因 GLBP 等名詞直接新增格式或依賴 |

補充：`Map3DRealBuildings.swift` 當前對 building kind 的細分含 shophouse、house、flats、office、industry、civic、temple、transport，不只是舊研究寫的「純用途顏色」。不同場景內的真實資料是否與 `GameWorld` 改建／收購完全一致，這次沒有做互動測試，不宣稱已解決。

## 4. 針對《沿線》的增量機會：不換引擎

### P0：不改功能，先建立可比較的手機基準

- 使用同一存檔、同一機種／相機路徑，量白天密集實景城市、夜間車站商圈、跟車進出站（含地下／高架），記錄 `Map3DMetalView.Stats` 的 FPS、CPU/GPU 時間、draw calls、三角形、畫質階梯；另取峰值記憶體、崩潰與截圖。
- 測「自動／高畫質／省電」三組，不用外部網站「高達 200 萬三角」的舊數字當作本遊戲效能預算。
- 先審現有 [決策 349](../decisions/349.md)、[417](../decisions/417.md)、[460](../decisions/460.md) 的限制。沒有實機結果前不得預告效能提升。

### P1：獨立 PoC —— 車站樓層／剖面顯示

- 借鏡 YC 的 lower／1／2／3 樓、Silo 的剖面視覺，**先在既有 `Map3DScene` / `Map3DSeeThrough` 上做展示方案研究**：選樓層時，顯示站廳／月台／地面，隱藏上方遮擋，但不更動營運、路線與 GameCore。
- PoC 先用一座資料明確的原生車站；處理月台、軌道、列車可見性，標記樓層資料實測或推估。研究階段只留下接口與驗收草案，不在此 PR 實作。
- 應驗的風險：透明／隱藏的排序、穿透車站遮擋、鏡頭回正、iPhone 小畫面可讀性、相機移動時區塊更替，不能用 YC 的 UI 截圖取代原生測試。

### P1：夜景 bloom 是否值得 GPU 成本

- **目前與 10/19 最大的視覺差異是 bloom 尚非已驗證的原生功能**，但它不是只改一個 shader 就有：現有 `bgra8Unorm`、逐 fragment 的 PBR Neutral 肩部可能提早截光；真正 HDR bloom 需要重新檢視亮度來源、render target、額外 pass、記憶體與省電降級。
- 先設離線／真機 A/B 對照：現有夜窗、招牌、車燈配色不變，比較無 bloom、輕量貼片、低解析度 bloom；讓作者選視覺，再看高畫質是否負擔得起。**不要替換現有 Neutral 色調映射**。

### P2：建築與地標製作成本

- 以目前 `Map3DRealBuildings.swift`、`Map3DBuildings.swift`、`Map3DSurfaces`／`Map3DModelFile` 為基線，建立「透天／公寓／辦公／站前商店」的素材變體清單，先衡量新增款式能否由既有零件與立面規則得到。
- 大型地標、多樓層特殊建物才考慮手工模型；仍使用既有 GLB→原生模型管線。若想研究自訂壓縮格式，先測 App 大小、解碼、RAM、draw calls，並核實授權及現有 meshoptimizer 工作，沒有數字不更換。

## 5. 研究導入排序（五方）

| 候選 | 玩家 | 鐵道迷 | 開發 | 美術 | 音樂／音效 | 建議 |
| --- | --- | --- | --- | --- | --- | --- |
| 手機場景基準 | 減少卡頓與閃退 | 跟車與到站不中斷 | 可用現有 Stats；先量才知道瓶頸 | 讓效果比較公平 | 無 | **先做（量測）** |
| 車站剖面／樓層 PoC | 看清地下與立體車站 | 月台／軌道層位正確 | 需測遮擋、深度、相機；不動營運 | 多層結構更易讀 | 無 | **選一站試驗** |
| 夜景 bloom 對照 | 夜景較有氛圍（待實測） | 不能讓號誌變模糊 | 多 pass 與記憶體風險 | 補現有燈光效果 | 無 | **先 A/B，後決定** |
| 全面換引擎／新格式 | 沒有直接價值 | 可能破壞既有路網幾何 | 大規模重構，無瓶頸證據 | 易造成風格不一致 | 無 | **不建議** |

## 6. 可驗收的後續任務（本次無程式更動）

1. **基準**：針對現有原生 3D 收三組可重放場景與 iPhone/iPad 的 FPS、GPU P50／P95、峰值 RAM、渲染指令、三角形、當下畫質階梯；同一段相機軌跡 A/B。
2. **樓層 PoC**：提供一座車站的「地面／站廳／月台」切換示意與不改 `GameWorld` 的資料契約；站體遮擋、列車仍可見、回到正常模式不殘留；iPhone 橫向與 iPad 各檢視。
3. **夜景 PoC**：不改原色調映射的前提下比較貼片與低成本 bloom，測量額外 render target 占用與 GPU P95；測試省電與熱降級；未測前不聲稱 60 FPS 或品質成本。
4. **避免重工清單**：每次開實作 PR 前先查 `[349, 358, 368, 417, 460]` 相關決策與實際 `main`，避免再次排入色調映射、分塊串流、程序化店面屋頂、裝置分級。

**這次沒有提議建立新引擎或直接複製 Fenn 來源。** 由原本遊戲規劃／主要 Claude Code session 決定是否排入優先清單；不修改 `docs/HANDOFF.md` 或共享優先清單，以免與其他 session 同時寫入。

## 7. 來源、驗證與未驗事項

- **VERIFIED（本輪靜態查核）**：公開站點 [首頁](https://3dscenes.qualityf2p.workers.dev/)、[YC](https://3dscenes.qualityf2p.workers.dev/yc)、[Silo](https://3dscenes.qualityf2p.workers.dev/silo) 的可讀文字；本 repo `main` 的 `Map3DRealBuildings.swift`、`Map3DGrade.swift`、`Map3DShaders.metal`、`Map3DStreaming.swift`、`Map3DQuality.swift`、`Map3DMetalView.swift` 及決策 349、358、368、417、460；前次已合併 [#824](https://github.com/a91453/railway-game-ios/pull/824)。VERIFIED 在此只代表**確實讀取來源**，不代表執行測試。
- **UNVERIFIED（本輪）**：3D Scenes 的 JavaScript、GLB／WASM 資源或其執行畫面；個別頁面實際的 three.js／wgpu 使用狀態；Anywhere iOS 內部 renderer 與 3D Scenes 的程式共用情形；在 iPhone/iPad 上的真實 GPU/CPU、bloom 負荷；本庫 Swift build／UI test。
- **授權**：3D Scenes 的程式未見可移植授權，所有場景只作行為和視覺研究；不匯入任何第三方私有素材。OSM／Overture 與其他地理資料各依自己來源及授權處理（參見本庫 `DataSourceCredits`）。
