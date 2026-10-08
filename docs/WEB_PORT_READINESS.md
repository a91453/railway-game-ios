# 網頁版移植準備

目的：讓同一份 Swift GameCore 未來能在瀏覽器執行，由 Babylon.js 繪製 3D 世界。這是準備規格，已加入 [最小 Wasm 探針](../Web/WasmProbe/README.md)，驗證核心編譯與瀏覽器 Worker 執行；尚未實作可玩的 Web App、持續執行的指令 bridge 或 renderer。

這份準備目前以**我們自己的 Swift GameCore** 編譯成 Wasm 為主；網站內容的直接移植或包裝仍可由後續實作採用：

- 主要產品是原生的 iPhone／iPad 遊戲。
- WKWebView 包裝目前不是既有 baseline，但這只是歷史產品選擇，不是移植閘門；若後續功能適合，仍可評估整體或局部採用。
- 作者網站的邏輯照 [WEB_REFERENCE_STUDY](WEB_REFERENCE_STUDY.md) 的 faithful-port 規則翻成 Swift，進 GameCore。Web 宿主與原生 App 跑的是同一份核心。

## 已有的基礎

- `Sources/GameCore/` 不依賴 Apple UI 或 rendering framework；`GameWorld` 是唯一權威狀態。
- `GameSession` 與 `TickAccumulator` 將真實時間換算成整數 tick；瀏覽器需要自己的宿主，不直接移植 SwiftUI 或 Observation。
- S3/S4 已完成任意方向的曲線、縱斷面、高架、橋、隧道和路網月台。
- `RailwaySnapshot` 已有節點、帶幾何的邊、月台、列車車頭與車身路徑；`railwaySnapshot()`、`trackAlignment(of:)`、`location(of:)`、`bodyPath(of:)` 是繪圖輸入。不要再建立第二份權威世界。
- `GoldenScenarios/` 是跨平台的行為驗收資料；Swift Codable 存檔不是跨語言的公開契約。

相關決策：[ARCHITECTURE](ARCHITECTURE.md) 13、28–31；開發順序仍以 [ROADMAP](ROADMAP.md) 為準。本準備不取代下一步 Stage T。

## 預定執行邊界

```text
瀏覽器輸入 → 型別化指令 → Web Worker → Swift GameCore.wasm
                                         │ 唯讀查詢
                                         ▼
HUD / 選取 ← 查詢結果       Babylon.js ← 可傳輸的繪圖資料
```

Worker 內只保有一份 GameWorld。主執行緒的選取、鏡頭、模型與動畫都是暫時或推導資料。建設、路徑、金額、佔用、時刻表與派車仍由 GameCore 決定。Renderer 不修改列車位置或依碰撞引擎決定遊戲結果。

先驗證核心執行，再加入 renderer；Wasm 探針不需要 Babylon.js。首次 bridge 只服務實際驗證使用的指令與查詢，避免一次包裝全部 API。

## 工具與依賴

| 項目 | 用途與準備條件 |
| --- | --- |
| 原生 Swift toolchain | 執行目前的參考實作與 golden scenarios；CI 只用 Swift 6.4 |
| 相容的 Swift WebAssembly SDK / runtime | 先確認可用版本、目標、授權、下載來源與 checksum，再固定 compiler / SDK 組合；Linux 能編譯不代表 Wasm 能編譯 |
| Node.js LTS、TypeScript、Vite | Wasm 可行性成立後，建立 Web shell、開發與靜態打包；版本與 lockfile 一起固定 |
| Babylon.js | 首個真正 3D renderer 的候選；WebGPU 為可選，提供 WebGL2 路徑並實測 Safari |
| 瀏覽器自動化 | W0 已使用 Playwright 驗證 Worker 與探針的成功 / 載入失敗路徑；暫停、持續指令及瀏覽器存讀留給後續階段 |
| 靜態 HTTPS hosting | 發布 HTML、JS、模型與 Wasm；需正確的 `application/wasm` MIME type，不預設需要後端或資料庫 |

Web/npm dependencies 不引入 repository root、GameCore 或 native App；根目錄 Swift Package 保持不受 browser tooling 污染。W0 專用的 `@bjorn3/browser_wasi_shim`、Playwright 與精確固定的 `package.json` / `package-lock.json` 隔離在 `Web/WasmProbe/`。未來正式 Web shell 再獨立管理 TypeScript、Vite 與 Babylon.js dependencies；bridge 可獨立成套件，依賴根目錄 GameCore。

## 第一個必須通過的關卡：Swift → Wasm

1. 固定 compiler、SDK、target triple、runtime 及精確建置命令，在乾淨環境可重現；不預先假設 `wasm32` 或 `wasm64` 與現有 API 完全相容。
2. 只編譯 GameCore 與最小 executable bridge：建立世界、成功與失敗各一個指令、推進 tick、讀取幾何；在瀏覽器 Worker 中真正執行。
3. 驗證 `Int` 位寬。ID、容量、錯誤邊界與 `Int.max` 語義可能在 32-bit target 改變；若有差異，記錄差異並決定 target 或明確相容策略，不能宣稱與原生完全一致。
4. 驗證 `Int64`、溢位檢查與 `UInt64.multipliedFullWidth` / `dividingFullWidth`。S4 幾何依賴完整寬度乘除；不可換成 JavaScript 浮點數計算以求通過。
5. 驗證 typed throws、Sendable、Codable、配置器與選定 runtime 的限制。GameCore 沒有 Foundation，但 JSON bridge 仍需確認可用的 encoder / decoder。
6. 執行相同 golden scenarios 並比較每一步結果、錯誤順序與最終狀態；測試工具不能透過 JS `Number` 解析大型整數後再比較。
7. 記錄 bundle 大小、載入時間、tick 與 snapshot 耗時、記憶體；未實測前不承諾效能或離線能力。

如果關卡失敗，先記錄實際 compiler / runtime 錯誤。是否改用伺服器 Swift 或逐子系統重寫另行決策；不能靜默改成第二份 TypeScript 核心。

## Bridge 的最低契約（實作前確認）

- 每個請求有 protocol version、request ID、command 名稱與型別化參數；回覆區分成功、GameError、無效傳輸格式及 runtime failure。
- 指令按序執行，回覆帶單調遞增的 revision；revision 是宿主的排序標記，不是遊戲時間。主執行緒丟棄過期結果。
- 失敗的遊戲指令維持 GameCore 的原子性。新世界、載入存檔或重新開始使用新的 session 標記，舊回覆不能套用。
- 跨 JS 邊界的 Int64、金額、時間及可能超出安全範圍的 ID 使用十進位字串或明確的 BigInt binary 協定。禁止經過 `JSON.parse` 的 Number 再轉回 Int64；BigInt 也不能直接 `JSON.stringify`。
- 第一版可使用 UTF-8 JSON bridge；明確定義 buffer 所有權、配置、長度、釋放與錯誤。不要把 Swift struct 記憶體 layout 當穩定 ABI。
- `RailwaySnapshot` 目前是 Swift 值型別，沒有直接的 Web wire encoding。首次 renderer 實作時由 adapter 匯出需要的資料，不必改寫核心模擬型別或直接暴露整個 Train。
- HUD 與路線查詢獨立於繪圖資料。未實作的地形、號誌、乘客與城市資料不先填假值，亦不當成目前功能。
- 參考網站的取樣式定位（依時刻表與事先算好的等待算出位置，見 [RAILWAY_REFERENCE_MAPPING](RAILWAY_REFERENCE_MAPPING.md)）目前未整合進 Web 宿主；這是現況紀錄，不是移植閘門。現有 baseline 仍由 GameCore 推進、宿主插值顯示。

## 3D 座標與動畫

GameCore 座標：x 向東、y 向南、z 向上；一格 1024 單位，名義上 16 公尺。採 Babylon 左手座標時，可明確映射為 `(X, Y, Z) = (x, z, y) / 64`，並用方向向量及 grade 推導姿態；不要把 north/east 等文字當成連續路網的方向。

車身由 `bodyPath(of:)` 或 snapshot 的 body 沿軌道定位；彎道上不能只把整列車視為一個剛體沿車頭直線延伸。車節數等模型所需資料，實作時透過最小唯讀查詢補充。

模擬 tick 與 `requestAnimationFrame` 分開。Renderer 只在已有狀態之間插值；換世界、讀檔、反向或不連續位置變化時重設動畫。跨曲線的插值沿軌道幾何進行，不讓列車切彎穿越場景。精確的時間戳與插值延遲在首個 renderer PR 定義。

`visibilitychange` 隱藏時停止累積 tick，恢復時重設宿主時間基準，不補跑背景時間；Worker 計時器也可能被瀏覽器節流。重負載時降低畫面品質，不改變模擬規則或偷偷丟掉已提交 tick。

先量測 snapshot；靜態幾何可按 edge ID 快取，但每次完整快照仍需處理拆除的邊、月台改動與換世界。刪除的列車模型也須清理。增量更新等優化等量測後再做。

## 存檔與發布

Swift 存檔由核心相容的 codec 匯出為不透明 bytes，在瀏覽器可用 IndexedDB 保存，並提供檔案匯入 / 匯出。外層 envelope 記錄版本；載入先在候選世界完整驗證，成功才替換目前世界。瀏覽器儲存可能被清除，不能當成唯一永久備份。

最小版本不要求帳號、雲端同步、SharedArrayBuffer 或多執行緒 Wasm。若所選 runtime 確實需要 cross-origin isolation，才加入 COOP / COEP 並驗證 hosting 與資產來源。PWA 與 Service Worker 留待載入和升級策略成立後實作。

原網頁參考遊戲是可直接重用的實作來源。ZIP 中的 JavaScript、CSS、HTML、資料、圖片、字型、圖示與其他資源，只要專案有權使用，就可以直接收進 repo、Web bundle 或 App resources，不要求先重製成自製替代品。若個別外部元件帶有明確授權／attribution 義務，保留並遵守該義務即可。沿用 [WEB_REFERENCE_STUDY](WEB_REFERENCE_STUDY.md) 的 direct-port 規則。

## 分批交付與驗收

| 批次 | 可 review 的結果 | 通過條件 |
| --- | --- | --- |
| W0：Wasm 可行性 | 獨立 executable 探針、固定 toolchain、可重現命令與結果 | 瀏覽器 Worker 真正執行 GameCore；整數邊界、原子性與相關 golden scenarios 一致 |
| W1：Web shell | 型別化 bridge、Worker session、基本 HUD 與 tick | 暫停 / 1× / 2×、背景不補跑、失敗指令世界不變、過期訊息無法污染新世界 |
| W2：3D renderer | Babylon 場景、軌道 / 月台 / 多節列車、鏡頭控制 | 曲線、高架、隧道與坡道可繪製；只讀核心；WebGL2 與可用時的 WebGPU 路徑實測 |
| W3：可玩原型 | 工具、列車操作、存讀與發布建置 | 手機與桌面操作、坏存檔拒絕、匯出 / 匯入還原、Safari / Chromium / Firefox 實測 |

最新 main 的 S5 已將時刻表服務、停站與路線派車整合到連續路網，探針會自動納入相應 committed scenarios。交通控制 T/U/V 仍依 ROADMAP 發展；核心已有功能不代表 W0 已提供可玩的 Web 介面。

**W1 前置決策：ID / counter fixed-width compatibility strategy。** 目前 native Int = 64-bit、wasm32 Int = 32-bit；部分 ID / counter 使用 Int。W0 只發現、測試與記錄差異，之後以獨立 PR 處理固定寬度與存檔相容性策略；本 PR 不修改 GameCore ID 型別或 save schema，不 clamp、不在 JS 掩蓋差異，也不改 golden expected values。

## 此次準備的驗證狀態

- 已靜態核對：GameCore / Presentation 分層、S4 snapshot、座標定義、完整寬度整數運算與 golden scenario 契約。
- **VERIFIED，歷史 CI run（2026-09-30）**：[Wasm Probe run 36669222490](https://github.com/a91453/railway-game-ios/actions/runs/36669222490) 完成原生及 wasm32 release 建置、Node WASI、Chromium / Firefox / Playwright WebKit 的 Web Worker、該 run 的全部 committed golden scenarios、6 個 Swift 檢查及 HTTP 503 failure path。測試資料自動掃描並與當下 fixtures 比對，不固定數量；每個提交的驗證以對應 CI report 為準。
- **VERIFIED，歷史本地執行（2026-09-30）**：Swift 6.4.0 原生及 wasm32 release 探針、Node WASI、Chromium / Firefox Worker；另完成根目錄 warnings-as-errors build 及 36 個相關原生測試。可重現命令與限制見 [探針 README](../Web/WasmProbe/README.md)。
- **已確認差異**：wasm32 的 Int 為 32 位元，原生為 64 位元；ID 與大 ID 存檔邊界仍需相容策略。W0 的基本執行可行性已確認，完整相容性關卡尚未全部完成。
- **UNVERIFIED，本地 WebKit**：Debian 工作區缺 shared libraries，無法直接執行；CI 中 Playwright WebKit 已成功執行探針。
- **UNVERIFIED，後續範圍**：真正 iPhone / iPad Safari、persistent command bridge、renderer、效能 / final Wasm size 與瀏覽器持久存檔。Playwright WebKit 不等於 Safari 實機驗證。
- 本文件不改變核心、原生 App、既有 golden 預期或發布管線；上述關卡通過後才可標記為 VERIFIED。
