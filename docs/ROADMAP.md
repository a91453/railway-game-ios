# Roadmap

各階段只是方向，實際範圍會依前一階段的成果調整。Phase 1、Phase 2A、Phase 2B 與 Phase 3 的 Stage I、J、K、L（GameCore 路徑搜尋）、M（讓 App 操作列車的最小畫面）、N（停站、以車站為目的地）已實作；Phase 3 的列車模擬核心到此告一段落。Phase 4（時刻表）進行中：Stage O（時刻表的資料契約）、Stage P（依時刻表到達、停留、出發的一次性服務）、Stage Q1（折返與重複運行）、Stage Q2a（服務路線的資料與推導）、Stage Q2b（自動派車）、Stage Q3（區間車與停站模式）與 Stage R（服務與時刻表畫面）已實作，Phase 4 到此告一段落。Phase 4.5 的 Stage S1（軌道資源）、Stage S2（車站設施）、Stage S3（連續軌道幾何）、Stage S4（立體鐵路與結構物）與 Stage S5（路網上的營運）已實作，Phase 4.5 到此告一段落。Phase 4.6 的 Stage T（進路預約）已實作。之後依參考的對照（[RAILWAY_REFERENCE_MAPPING.md](RAILWAY_REFERENCE_MAPPING.md)）排順序：Phase 4.7 的 W1（行駛曲線的計算核心，純計算、還沒接到列車）已實作；接著是 G1（第一個能玩的經營閉環），其中 G1a（需求、釋出、排隊與守恆）、G1b（上下車與容量）與 G1c（票價、帳本與畫面）已實作，G1 到此告一段落；接著是 W2：W2a（時間改用秒）已實作；第二版內部 TestFlight 之前插入的 L1（繁體中文，見[跨階段議題](#跨階段議題)）已實作；W2b（停站、上下車與誤點）與 W2c（行駛曲線接到行程與移動）已實作。2026-10-02 作者決定，U、V 之前先做 [Stage C](#stage-c--已完成核心的操作畫面)：補上已完成的核心還沒有的操作畫面，讓所有功能都能在實機上測試；C1（任意角度的建造）、C2（營運與乘客的設定畫面）與 C3（性能）已實作。C2 合併之後，作者再決定鐵軌全部改用路網、車站與土地自由擺設，並分成空白與實景兩種遊戲模式；之後的順序見[目前的優先順序](#目前的優先順序)：F1 全面路網（已實作）→ C4 測試輔助（已實作）→ [G1d 經濟平衡](#g1d--經濟平衡-)（已實作）→ C5 最小教學（已實作）→ E1 大地圖（已實作）→ 環線（已實作，2026-10-03 作者要求）→ E2 空白／實景（已實作，實機確認）→ [F3 移除 GameCore 的方格](#stage-f--全面路網與自由擺設)（2026-10-03 作者決定提前，已實作）→ F2 線間距（已實作）→ F3d 拿掉殘留的方格語意（已實作）→ U-min（U1 通過後釋放、U2 站間跟車已實作）→ V（V1 避占用選路、V2 死結偵測與解除已實作；E3 MapLibre 視需要）。2026-10-07 起 Phase 6 的 6a（土地，決策 72）、6b（運量由土地推導，決策 73）、6c-1（城市建物、容量表與初始化，決策 74）、6c-2（容量接上成長、自動升級，決策 75）與 6c-3／6d（地價與城市圖層，決策 76）已實作。2026-10-08 補上三個編輯功能：復原（#203、#205，決策 82，移植 MapBuilder 的 `handleUndo`）、路線編輯（#208，決策 80：把車站自動排入既有路線、反轉站序、複製路線）與轉乘群組（決策 81，存檔版本 15）。同一天開始全島地圖（研究 `docs/research/WHOLE_TAIWAN_MAP.md`）：步驟 B 的第一個 PR（決策 88，存檔版本 18）放大世界的上限、在實景選點加「全台灣」（本島加澎湖），土地在蓋站時展開車站 2 公里內的部分；第二個 PR（決策 89）是全島縮小時的畫面：站名依路線等級出現、城市圖層在背景算、空的全島地圖開在整個島；之後是步驟 C 的城際需求與高鐵。目前 App 的地圖畫面是原型：連續路網的俯視投影（F1 起不畫格線；F3 起沒有方格的軌道與車站；F3d 起世界沒有格子；2026-10-08 起改用 App 圖示的畫風，並沿軌道畫出路線、共線區段與轉乘群組，決策 84），不是最終的 renderer（見 Phase 8）。

2026-09 研究了作者提供的網頁版交通經營遊戲（[WEB_REFERENCE_STUDY.md](WEB_REFERENCE_STUDY.md)），依結果調整了之後的階段：

- Stage Q 拆成 Q1–Q3；
- 新增 Phase 4.5（交通控制；之後再拆成 4.5–4.7，見下一段）；
- Phase 5 拆成 5A–5G；
- Phase 6–8 與跨階段議題補上吸收的做法。

作者提供的網頁程式、快照、資料與素材都是可直接移植的來源：能原樣重用就重用，需要 Swift／GameCore 調整時再轉譯，不再要求直接移植／調整實作與資料或把來源排除在版控之外。Stage／Phase 是工作拆分，不是來源功能的移植閘門；一個完整功能需要跨 Stage 相依時，可以一起搬。

另外研究了真實的鐵道時刻表（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)）。逐班時刻、快慢車、時段班距、單線交會、停站時間、原始時刻表與即時資料都可以直接成為遊戲資料或模擬輸入；若要維持 deterministic 存檔，可把外部即時狀態在明確時點轉成已記錄的世界輸入／情境資料。第一個真實藍本情境的候選仍是平溪線。

2026-09 再詳讀了時刻表資料的實體鐵路層（股道拓樸與轉轍器、單雙線、整列車的資源預約、班表綁定實體路徑、待避與交會、行駛曲線、月台與編組）。兩份參考剛好分層：網頁遊戲是經營層，時刻表資料是鐵路的物理層。所以原本的 Phase 4.5 拆成三段：

- Phase 4.5：實體鐵路（S1 軌道資源、S2 車站設施）；
- Phase 4.6：交通控制（T 進路預約、U movement authority、V dispatcher）；
- Phase 4.7：列車動態（W 行駛曲線）。

順序不變：先完成 Phase 4 的 Q3 與 R，再進 Phase 4.5。

S2 之後確定了產品方向：「以 deterministic 模擬核心為基礎的 360° 3D 鐵道城市建造遊戲」。交通控制若建立在北東南西的方格上，之後換成任意方向的鐵軌與立體交叉時就要重寫，所以先把鐵路核心拆成 topology、geometry、rendering 三層（ARCHITECTURE 決策 28），在 Phase 4.5 補上兩個 Stage（S3、S4），之後再加上 S5，把既有的營運系統接到新的路網上：

- Phase 4.5：S1 ✅ 軌道資源、S2 ✅ 車站設施、S3 ✅ 連續軌道幾何、S4 ✅ 立體鐵路與結構物、S5 ✅ 路網上的營運；
- Phase 4.6：T ✅ 進路預約、U movement authority、V dispatcher；
- Phase 4.7：W 行駛曲線。

舊的 Stage T（PR #31）建立在 S3/S4 之前的方格上，暫停、不合併；新的 T 在 S5 之後重新寫在泛用的 topology 上（見 Stage T），概念上取代了 PR #31。

S5 是 S3/S4 與既有 O–Q 營運系統（operational system）之間的 bridge：停站、時刻表、折返與重複、路線、派車與服務模式都在路網上運作，而且方格與路網是同一套程式。T 之後不需要重新處理時刻表、路線與月台的 grid-specific migration。

## 目前的優先順序

**2026-10-02 作者決定**（C2 合併之後，實機測試的回饋）：

- **鐵軌全部改用路網，車站與土地也自由擺設**，不再以方格為單位（[Stage F](#stage-f--全面路網與自由擺設)）。
  - 現在方格與路網兩套鐵軌並存：路網可以直接蓋在方格軌道上面、兩邊不相接，列車也不能從一邊開到另一邊（GameCore 的「路網不和方格互動」），實機上很混亂。
  - 路網已經能做方格能做的一切：轉轍器是一個節點接多條邊，平面交叉是共用的節點；另外還有任意角度、高架與隧道。
  - 方格在 GameCore 暫時保留為相容層（舊存檔與 golden），移除另外決定。
- **遊戲分成空白與實景兩種模式**（[Stage E](#stage-e--大地圖與實景模式)）。實景以真實地圖當背景，先用 MapKit；不夠用時再加 MapLibre。
- **地圖要大**：約 16 公里見方（當時 `GridMap` 的上限 1024 格 × 16 公尺；F3d 起是 `WorldBounds.maximum`，2^20 世界單位），新遊戲當時只有 32 × 24 格（約 512 × 384 公尺）。

綜合之前的順序（Stage C、Phase 4.6 的 U 與 V、Phase 5–8）與這次的決定，依相依關係、對實機測試的價值與成本排成：

| 順序 | 工作 | 內容 | 為什麼排在這裡 |
| --- | --- | --- | --- |
| 1 | **F1 全面路網** ✅ | 車站可以放在任意座標；App 只用路網建造，拿掉方格的軌道與車站工具，地圖不再畫格線 | 實機上最混亂的地方；它改變建站的方式，C4 的示範地圖要用新的方式蓋 |
| 2 | **C4 測試輔助** ✅ | 存檔與讀檔（含存檔版本欄位）；開始畫面（新遊戲、繼續、讀檔、教學入口）；Release 版也能開示範地圖，用路網重做 | 每次開 App 都要重蓋路網，是目前測試成本最高的地方，而且工作量小；「繼續」與「讀檔」就是存檔功能 |
| 3 | **C5 最小教學** ✅ | 照 `Ci/` 的導覽移植內容步驟，改成觸控：做了才前進，可以略過、從選單重開 | 外部 TestFlight（#56）的測試者需要它；它教的工具流程在 E1、E2 不會改 |
| 4 | **E1 大地圖** ✅ | 約 16 公里見方；只畫畫面內的部分；雙指縮放 | 要能蓋幾公里長的線，才看得出 W2c 的加減速；作者回報地圖太小 |
| 4b | **環線** ✅ | 路線可以設成環線：列車從最後一站接回第一站，兩個方向各一半；示範地圖改成環線與一站多月台 | 2026-10-03 作者測試時發現環狀的軌道跑不成環線（決策 22 只有兩端折返）；E2 之前做，E2 的開局不動示範地圖 |
| 5 | **E2 空白／實景** ✅ | 開新遊戲時選模式；實景用 MapKit 當背景，地圖中心的經緯度跟著存檔 | 需要 E1 的大地圖與 C4 的存檔；和 E1 是同一套畫面，接著做 |
| 5b | **F3 移除 GameCore 的方格** ✅ | 方格的鐵軌、方格上的列車位置與方格車站從 GameCore、測試與 App 拿掉；分 F3a（golden 搬到路網）、F3b（測試搬到路網）、F3c（刪除）三步，不改任何遊戲行為 | 2026-10-03 作者決定提前（決策 51）：U-min、V 會大改的移動、預約與停站正是帶著方格分支的共用函式；方格留著，之後每一步都要顧兩種軌道 |
| 6 | **F2 線間距** ✅ | 平行的軌道靠得太近時拒絕（F2a）；太近的兩段軌道上的列車互相排斥（F2b） | 新的 GameCore 規則，會改到差分 campaign 的參考模型；沒有其他工作依賴它；排在 U-min 之前 |
| 6b | **F3d 拿掉殘留的方格語意** ✅ | 世界是世界單位的範圍（`WorldBounds`）；`GridMap`、`GridPosition`、`MapTile`、`Station.position` 拿掉；票價與需求用兩站的點之間精確的距離；一格 1024 拆成各自用途的常數；選取是點與實體；存檔版本 6 | 2026-10-04 作者決定（決策 54）：F3c 之後只剩「一格」的世界、票價的量化與選取；U-min、V 之前清掉，之後的規則只看連續的世界 |
| 7 | **U-min** ✅ | movement authority：U1 通過後釋放 ✅（決策 55）→ U2 站間跟車 ✅（決策 56） | 處理多台車的跟車，等玩家能蓋長的線、放多台車時才用得上；建立在共用的軌道模型上，晚做不用重寫 |
| 8 | **V** | 待避、交會與月台分配：V1 避占用選路 ✅、V2 死結偵測與解除 ✅ | 依賴 T、U |
| 9 | **Phase 5–7** | 在 G1 上深化乘客、城市與公司；實景模式的真實人口需求 | 建立在 G1 與 E2 上 |
| 10 | **Phase 8** | 真正的 3D renderer | 城市與建物會改變畫面上要畫的東西，先做它們再做 3D，避免重做；E2 的實景模式可以先用 MapKit 的地形與 3D 建築當立體背景 |
| — | **E3 MapLibre**（視需要） | MapKit 不夠用時加入，照 `Ci/` 的做法 | 不佔固定的位置：E2 實測之後確定需要時才插入 |

**排序的考量**：

- **F1 先於 C4**：F1 保留方格車站作相容層，所以先做 C4 也不會產生存檔遷移；但 F1 改變建站的方式，C4 的示範地圖用 F1 之後的方式蓋才不會重做，而 F1 也是實機上最混亂的地方。
- **C5 緊接 C4、在 E1 之前**（2026-10-02 作者交給 Claude Code 決定）：教學教的是建造與營運的工具流程（路網、月台與車站、列車、路線、運量、速度），E1 改的是縮放與相機、E2 改的是背景與開局，所以這些步驟不會因為它們重寫，E1、E2 只各補自己的一步。開始畫面在 C4 就有教學入口；外部 TestFlight（#56）的測試者沒有教學會卡住。
- **E1 與 E2 連著做**：兩者是同一套畫面。E1 要把「世界座標換成畫面座標」抽成相機：空白模式由我們的相機決定，實景模式由 MapKit 的相機決定，E2 才不用重寫畫面。（E2 實作時改成兩種模式都由我們的相機決定、Apple 地圖跟著它，畫面一樣不用重寫，見決策 50。）
- **F2 排在 E2 之後**（不是緊接 C4）：沒有其他工作依賴它；E1 之前地圖小，也很難蓋出長距離的平行線。代價是 C4 之後的存檔可能已有太近的平行軌道，而淨空規則在讀檔時也會檢查（S4 的做法），所以 F2 要決定舊存檔怎麼處理，例如只檢查新版本的存檔（C4 加入的版本欄位）。
- **U-min、V 在畫面工作之後**：它們處理多台車的跟車與待避，要等玩家能在大地圖上蓋長的線、放多台車才用得上；它們建立在方格與路網共用的軌道模型上，晚做不用重寫。
- **F3 提前到 F2 之前**（2026-10-03 作者決定，決策 51）：E2 之後方格只剩相容層，但它的分支在移動、預約、停站這些共用函式裡，大部分的測試也建在方格上；U-min、V 正要大改這些函式，先拿掉方格，之後的規則與差分模型只寫路網一份。F2 的淨空規則也只需要看路網的邊。
- **3D 仍在最後**：作者回報「不是 3D」。真正的 3D renderer 工作量大，畫面要畫的城市與建物在 Phase 6 才會出現；實景模式先用 MapKit 的地形與 3D 建築補上立體感。

**2026-10-03**：C5 之前插入 G1d 經濟平衡（已實作）：新遊戲的價格與資金、城市的基準票價、經營模式的運量由城市決定（見 [G1d](#g1d--經濟平衡-)）。同時定下教學與相機的介面（C5 的第 0 步，[UI_INTERFACES.md](UI_INTERFACES.md)），讓其他代理的畫面工作可以並行。

**2026-10-09 玩家體驗**（作者的評估：「把『我蓋了一條鐵路』變成『因為我蓋了這條鐵路，一座城市真的開始發展』」）：開放測試前先補四項，GameCore 都不動：教學的第一條線走路線面板的一步配車並等到第一筆車資（決策 125）、城市自己的建物畫在一般地圖上（決策 126）、設定頁的版本與回報問題（決策 127）、建站時說出腹地與站長講城市成長（決策 128）。之後再看：城市長高的速度（平衡報告的待觀察第 5 項，2026-10-10 由決策 129 處理：站前長得快、九成滿就改建）、成長動畫、住商工的需求閥（RCI）、地形高度（決策 124）、建物出售與旋轉（P0-D）。

**TestFlight**：F1 與 C4 都合併之後，發一版內部 TestFlight，做完整的一輪實機測試（任意角度的路網、乘客與票價、存檔與讀檔、開始畫面、示範地圖）。C5 合併之後再邀請外部測試者。

## Phase 1 — GameCore foundation ✅

- Swift 6 Swift Package、與 rendering 分離的模擬核心
- 地圖、鐵軌、車站、最小列車模型
- 整數金額經濟、deterministic 遊戲時鐘
- Codable、XCTest、Linux CI

## Phase 2 — Native app prototype UI（cloud-first）

原本假設 Phase 2 以 M4 iPad 上的 Swift Playgrounds 為主要開發環境，但目前使用的 Swift Playgrounds 環境在執行專案程式碼之前的 prewarm / runtime 階段就會失敗，因此改為不需要 Mac、也不依賴 Swift Playgrounds 的流程：

```
Claude Code Cloud (Linux) → GitHub → GitHub Actions（Linux 測試、macOS 以 Xcode 編譯）→ 內部 TestFlight → 在 iPhone / iPad 實機上檢視
```

驗證分層：

1. Claude Code Cloud（Linux）：原始碼開發、GameCore `swift build` / `swift test`
2. Linux CI：只用 Swift 6.4（warnings as errors 的 build 與全部測試，campaign 不減量、分成平行 shard）；2026-10-05 起拿掉 Swift 6.0 job
3. macOS CI：XcodeGen 產生專案，以真正的 Xcode / Apple SDK 編譯原生 SwiftUI App
4. 實機人工檢視：內部 TestFlight（原本的手動 Visual Smoke Simulator 截圖已移除；人工檢視不是自動化的回歸測試）

Swift Playgrounds 只是可選環境，不是必要的開發或驗證步驟。

### Phase 2A — Cloud iOS build pipeline ✅

- 根目錄 `CLAUDE.md`（Claude Code 專案規則）
- 最小原生 SwiftUI App（iPhone / iPad、iOS 17+），連結 GameCore 並顯示地圖尺寸、現金、遊戲時間與速度
- XcodeGen spec（`RailwayGameApp/project.yml`），產生的 `.xcodeproj` 當時不進版控（Xcode Cloud onboarding 起改為提交，見下）
- macOS 自動編譯驗證（`ios-build.yml`），不需簽章
- 手動 Visual Smoke workflow（`visual-smoke.yml`，iPhone / iPad Simulator 截圖）：當時加入，之後已移除（改由內部 TestFlight 在實機人工檢視）

### Phase 2B — Prototype UI ✅

- 以 SwiftUI `Canvas` 顯示 `GameWorld` 的 grid（尺寸由世界決定），可捲動、縮放；空地 / 鐵軌 / 車站以不同形狀區分
- 點選 tile 選取，顯示座標與內容
- 工具：選取、鋪軌（N / E / S / W 開關、常用形狀與旋轉選擇連接方向）、建站（可編輯的預設名稱）、拆軌
- 所有建設都經由 `GameWorld` 指令；`GameError` 在 Presentation 層轉成玩家看得懂的訊息
- HUD：現金、遊戲時間（`Day 1 · 08:30`，只是顯示換算）、暫停 / 1× / 2×
- `GameSession`（新的 `GamePresentation` target）持有唯一的 `GameWorld`，並把真實時間換算成整數 tick 呼叫 `advance(ticks:)`；背景時停止、不補跑
- iPhone 直向 / iPad 直向版面當時已以 Visual Smoke 截圖確認（該 workflow 已移除）；橫向版面（側邊欄）只經過編譯
- GameCore 未修改：時間顯示換算放在 Presentation 層；拆除車站延後（見下）

延後項目：拆除車站（GameCore 尚無指令；2026-10-08 決策 83 補上）、拖曳連續鋪軌、軌道相鄰連接檢查（Phase 3 Stage I 已提供唯讀的連通查詢；鋪設時仍不要求相接）、存檔。

### 發佈管線 — 內部 TestFlight

讓 App 能以內部 TestFlight 安裝在實機上。這是發佈管線的準備，不改變遊戲開發範圍（Phase 3 照原計畫進行）。

- **Repository readiness ✅**（PR #8）：
  - XcodeGen 產生的 Xcode 專案與 shared scheme 提交進版控，`ios-build.yml` 檢查它與 `project.yml` 一致；
  - Release Archive、iPhone / iPad、自動簽章設定、臨時 App Icon（0.3.0 起換成作者提供的圖）；
  - 未簽章的 Release 裝置 Archive（`release-archive.yml`）。
- **GitHub Actions → 內部 TestFlight 基礎設施：已實作，真實執行驗證到上傳 App Store Connect**：
  - `testflight.yml`：只能從 `main` 手動觸發；preflight → Archive（預設 `adhoc`）→ App Store distribution 匯出 IPA → 檢查 → 上傳；
  - `testflight-checks.yml`：只用假值的腳本測試、macOS dry run、合成 IPA 檢查。
  - 手冊：[TESTFLIGHT_GITHUB_ACTIONS.md](TESTFLIGHT_GITHUB_ACTIONS.md)。
- **真實 Apple 簽章與上傳：VERIFIED（到上傳為止）**：Apple Developer Program、Team API key 與 environment 已就緒。第 1 次真實執行（`automatic`）在 Archive 失敗，因為新團隊沒有已註冊裝置、Apple 無法產生開發描述檔；第 2 次（`adhoc`）Archive、App Store distribution 匯出、IPA 檢查、上傳與清理全部成功，所以預設改為 `adhoc`。細節與 run 網址見 [TESTFLIGHT_GITHUB_ACTIONS.md](TESTFLIGHT_GITHUB_ACTIONS.md)。
- **尚未驗證**：App Store Connect processing、Missing Compliance 與 TestFlight 安裝到裝置（沒有 repository 層級的證據）。
- **第二版（0.2.0）**：G1（第一個能玩的經營閉環）與 W2a 之後，先完成 L1（繁體中文），再由作者從 `main` 執行 `testflight.yml`。要在實機上看的：經營與路線面板、速度選單與 1×／10×／60× 的手感、中文排版。
- **第三版（0.3.0）**（2026-10-03，作者要求）：版本號改為 0.3.0，App 圖示換成作者提供的圖（取代臨時圖示）。由作者從 `main` 執行 `testflight.yml`；`CFBundleVersion` 仍由 workflow 決定。
- **第四版（0.4.0）**（2026-10-07）：上次實機測試以來最大的玩法改變，所以升一個次版本號。內容有 Phase 6 的土地、運量由土地推導、城鎮成長、建物升級、地價與城市圖層（決策 72–78），示範地圖改用土地決定運量、實景資料背景載入（1a），以及 App 圖示風格的配色與地圖優先的畫面（#187、#190）。數字已由無頭模擬量過（[2026-10-07 平衡報告](#phase-6--city-simulation)），實機要看的是手感與畫面看不看得懂，以及報告「待觀察」表的三項：城市長得夠不夠快、短線是否太好賺、回本後現金是否滾太快。由作者從 `main` 執行 `testflight.yml`。
- **Xcode Cloud onboarding：deferred**。手冊保留：[XCODE_CLOUD_ONBOARDING.md](XCODE_CLOUD_ONBOARDING.md)；啟用時需要一次 Mac／Xcode 操作。
- **之後**：外部 TestFlight 與 App Store 上架另行規劃。

## Phase 3 — Train simulation

拆成依序進行的小 Stage，每個 Stage 一個可 review 的 PR。

### Stage I — Derived Track Connectivity ✅

- `TrackDirection.opposite`；`GameWorld.connectedNeighbors(of:)`（固定北、東、南、西順序）與 `isConnected(_:to:)`
- 連通每次由地圖直接推導：雙向出口才相接；懸空出口可以鋪設；每格鐵軌是一個互通節點；車站不是鐵軌；沒有 graph cache（ARCHITECTURE 決策 10）
- `buildTrack` 與地圖解碼一致，只接受四個方向的 bit（rawValue 1…15）
- Golden scenario schema v2：唯讀的觀察步驟與 `track-connectivity.json`

### Stage J — Train Position ✅

- `TrainPosition`：`atNode(tile, heading:)`（任何朝向，死路與孤立鐵軌也可以）與 `onLink(from:to:offset:)`（兩格相接鐵軌之間，方向由端點推導）；未放置是 `Train.position == nil`
- 每條相鄰連結固定 1024 個抽象單位（`TrainPosition.linkLength`，`Int64` offset）；端點一律用 `atNode`，`onLink` 限 `0 < offset < 1024`，不做正規化
- `GameWorld`：`train(id:)`、`placeTrain(_:at:)`、`unplaceTrain(_:)`、`reverseTrain(_:)`（原地反向，兩次還原）；新購列車未放置；放置、取下、反向免費
- 列車所在節點或連結兩端的鐵軌拒絕拆除（`trackInUse`）；其他鐵軌照常可拆，取下列車後也可拆
- 存檔：未放置的列車不寫 `position`，舊存檔讀成未放置；壞資料，以及節點不在鐵軌格、連結兩端不相接的位置，一律拒絕
- Golden scenario schema v3：列車指令、結果與最終狀態的列車位置，以及 `train-position.json`
- 列車不會移動；App 沒有放置列車的介面（ARCHITECTURE 決策 14）

### Stage K — Train Movement Kernel ✅

- `TrainMovement`：`rate`（`Int64`，每遊戲分鐘的邏輯單位）、`continuation`（之後依序要進入的節點）與 `cursor`（已開始進入的項數；用完後存成空清單）；未放置的列車一律 idle
- `GameWorld`：`setTrainMovementRate(_:to:)`、`setTrainContinuation(_:to:)`（整份驗證後原子替換，空清單即清除）；`reverseTrain` 清空 continuation 並保留 rate，`unplaceTrain` 重設為 idle
- 純整數距離 kernel：先走完目前連結再依 continuation 前進，一步可跨多條連結；恰好抵達存成 `atNode` 且不消耗下一項；不選路、不折返
- `advance(ticks:)`：每個基本步長依 `TrainID` 順序移動列車、再推進一分鐘；2× 執行兩個基本步長；沒有列車能再改變時，時鐘直接跳過剩餘分鐘（精確捷徑）
- 前方鐵軌被拆時在最後可達節點等待，補回後下一步自動續行，等待期間的距離不累積
- `advance(ticks:)` 改為 `throws(GameError)`：先檢查倍速乘法與時鐘容量，溢位就整批拒絕（`clockOverflow`）；`GameClock.advance(ticks:)` 同樣檢查
- 存檔：idle 不寫 `movement`，舊存檔讀成 idle；等待修復中的世界可以存讀；壞資料一律拒絕
- Golden scenario schema v4：移動指令、`train` 觀察、最終狀態的列車 movement，以及 `train-movement.json`
- App 仍沒有放置或指定路徑的介面，列車移動只由測試與 golden fixture 驗證（ARCHITECTURE 決策 15）

### Stage L — Route / Pathfinding ✅（GameCore）

- `GameWorld.route(from:to:)`：唯讀查詢，回傳可直接交給 `setTrainContinuation` 的節點清單，或 `nil`
- 最少連結數、不立即折返（可繞圈掉頭，不會 reverse）；同長時依出口方向的北、東、南、西順序決定，結果與鋪設順序和平台無關
- 對 (節點, heading) 做 breadth-first search，只走訪可達鐵軌，不建立 graph 或快取；Stage K 的移動契約不變
- Golden scenario schema v5：`route` 觀察與 `train-route.json`（ARCHITECTURE 決策 16）
- 尚未做：多個途經點、以車站為目的地（Stage N）；App 的操作畫面見 Stage M

### Stage M — 最小畫面整合 ✅（App）

原本「最小畫面整合（尚未排定）」的項目，排在停站之前成為 Stage M；原本的 Stage M（停站）順延為 Stage N。

- App 的「Train」工具：購買列車、放置在選取的鐵軌格（選朝向）、設定 rate、把列車送到選取的鐵軌格、反向、取下；每個操作都是一個 `GameWorld` 指令
- 送出：`GameSession` 以 `route(from:to:)` 從列車目前的位置求路，在同一次呼叫中原封不動交給 `setTrainContinuation`；沒有路徑時世界不變
- 推進沿用 Phase 2B 的 game loop（HUD 的暫停 / 1× / 2×），沒有第二個推進入口
- 顯示 GameCore 記錄的位置、剩餘 continuation 與 rate；地圖在列車的權威位置畫出列車，每個 tick 跳一步，沒有插值
- GameCore 未修改（ARCHITECTURE 決策 17）

### Stage N — Station Stop ✅

- 車站仍然不是鐵軌；車站正北、正東、正南、正西的鐵軌格是它的月台（不需要朝向車站的出口，可以同時屬於多個車站），每次由地圖推導：`GameWorld.platforms(of:)`
- 以車站為目的地：`route(from:toStation:)`，用 Stage L 的搜尋把每個月台都當作目的地（最少連結、同長時北、東、南、西），在第一個月台結束，結果可直接交給 `setTrainContinuation`
- 停站：列車在月台格中心、沒有剩下的 continuation 時停在該站（`stationsStoppedAt(by:)`，依 ID 遞增）；由位置、continuation 與地圖推導，不存成狀態、存檔格式不變。經過月台、出發中（即使 rate 0）、等待修復都不是停站
- 沒有新指令或新錯誤；移動 kernel、Stage I–L 的契約不變（Stage L 的路徑 digest 不變）
- App：Train 工具選取車站格時送到該站（GameCore 求路後原封不動提交），並顯示列車停在哪些車站
- Golden scenario schema v7：`platforms`、`routeToStation`、`stationStops` 觀察與 `station-stop.json`（ARCHITECTURE 決策 18）
- 尚未做：停留時間、時刻表與服務模式（Phase 4）、乘客、拆除車站（2026-10-08 決策 83 補上）、月台容量

順序調整的理由：route / pathfinder 產生的路徑，必須是列車移動核心真的能執行的東西。先確立列車位置與移動延續的契約（J、K），路徑搜尋（L）才有明確的輸出形式可以對準；反過來做，路徑的表示方式會先把位置與移動的設計鎖死。

## Phase 4 — Timetable

和 Phase 3 一樣拆成依序進行的小 Stage，每個 Stage 一個可 review 的 PR。先確立時刻表是什麼資料（O），再讓它控制列車（P、Q），最後才做畫面（R）。

### Stage O — Timetable Foundation ✅

- `Train.timetable`：依序的 `ScheduledStop`（車站、排定的到達與離開）；陣列順序就是停靠順序，新購列車是空的
- 時間是開局以來的絕對遊戲分鐘（`GameTime`，與時鐘同一尺度）；沒有日曆、時區或字串時間
- 驗證：時間從分鐘 0 起不倒流（`0 ≤ arrival ≤ departure ≤ 下一站的 arrival`），每站都是存在的車站；允許停留 0 分鐘、相等的邊界、重複的車站與已過去的時間；不檢查路線、行駛時間或列車位置
- `setTrainTimetable(_:to:)`：整份原子替換、`[]` 清除、免費；錯誤依序 `unknownTrain` → `invalidTimetable` → `unknownStation`（第一個不存在的車站）
- 放置、取下、反向、移動指令與時間都保留時刻表；**不執行**：`advance` 不讀它，不發車、不求路、不改 rate，Stage I–N 的行為與 property digest 不變
- 存檔：空時刻表不寫 key（舊存檔讀成空、沒有時刻表的存檔格式不變）；壞資料一律拒絕，不排序或修正
- Golden scenario schema v8：`setTrainTimetable` 指令、`invalidTimetable` / `unknownStation` 結果、`timetable` 觀察、最終狀態的列車 `timetable`，以及 `train-timetable.json`（ARCHITECTURE 決策 19）
- GamePresentation 只加上兩個新錯誤的訊息；App 沒有修改

### Stage P — Dwell / Arrival / Departure ✅

- `Train.execution: TimetableExecution?`：執行進度是權威狀態，`.waitingAtStop(i)` / `.travellingToStop(i)`，`i` 是時刻表索引（不是車站 ID，因為車站可以重複）
- `startTrainService(_:)`：明確啟動，列車必須停在第一站的車站；從第 0 站開始，不依時間跳站；錯誤依序 `unknownTrain` → `trainServiceActive` → `noTimetable` → `trainNotPlaced` → `trainNotAtFirstStop`。`stopTrainService(_:)` 只結束自動化（`unknownTrain` → `trainServiceNotActive`），不清時刻表、不改位置、rate 或 continuation
- 一次、有限的服務：依時刻表順序跑到最後一站一次；不循環、不折返、不產生下一班
- 每個基本步長：`T` 的出發 → 移動 → 時鐘 `T + 1` → `T + 1` 的到達；每步最多移動一次
- 排定出發時刻是閘門：可以晚走，不會早走；不加最短停留，零停留合法，晚到的列車下一步就走；arrival 不是閘門
- 已停在下一站的車站（重複的車站、共用月台）時零距離到達；沒有路就等待並在之後重試；最後一站停到排定出發才結束
- 服務擁有 continuation：`setTrainContinuation`、`reverseTrain`、`unplaceTrain`、`setTrainTimetable` 在執行中是 `trainServiceActive`；`setTrainMovementRate` 仍可用
- `advance` 的捷徑改為事件感知：沒有變化時只跳到下一個服務出發時刻；`advance(n)` 仍等於 n 次 `advance(1)`
- 存檔：有服務時寫 `"execution"`，沒有時不寫（舊存檔讀成沒有服務）；壞資料一律拒絕，不修正
- Golden scenario schema v9：服務指令、四個新結果、`execution` 觀察、最終狀態的列車 `execution`，以及 `train-service.json`（ARCHITECTURE 決策 20）
- GamePresentation 只加上四個新錯誤的訊息；App 沒有修改

### Stage Q — Service Pattern / Automatic Dispatch

拆成三個依序的 PR。參考遊戲的兩種模式營運方式不同（[網頁參考研究](WEB_REFERENCE_STUDY.md#結論)的結論 1）：

- 捷運以「時段 × 上線列車數」營運，班距由系統推導；
- 高鐵用逐班的時刻表，並能自動產生班次與回程。

Q 把前者展開成後者：服務模式產生具體、有限的班次，交給 Stage P 的執行核心去跑。Stage P 的契約都不變：排定出發是閘門、每步最多移動一次、沒有路就等待。

#### Q1 — 折返與重複運行（單一列車）✅

- **折返**：停靠站的屬性 `ScheduledStop.reverses`。服務離開這一站時，先讓列車原地反向，再求路到下一站；找不到路時整次出發都不發生，也不反向。Stage P「沒有路就等待、不自動反向」的規則不變。
- **重複**：`setTrainTimetable(_:to:repeatingEvery:)` 設定週期（`Train.timetablePeriod`）。
  - 跑完最後一站後，接著跑下一輪的第 0 站；第 `k` 輪的時刻是時刻表的時刻加上 `k × 週期`，由規則推導，不展開。
  - 週期至少 1 分鐘，而且重新開始時時間不倒流。
  - 時刻超出 `Int64` 的輪次不存在，服務在最後一輪之後結束。
- **執行進度**：`TimetableExecution` 帶著第幾輪（`cycle`），存檔。
- **開始**：重複的服務從第一站出發時刻不早於現在的第一輪開始，列車準時出發；一次性的服務照 Stage P。
- **一個出發段最多一整輪**：每台列車在一個出發段最多離開時刻表站數那麼多站，所以誤點的列車不會在一步裡無限繞圈。
- **存檔**：`period`、`reverse`、`cycle` 只在用到時寫入，舊存檔讀成一次、不折返、第 0 輪；壞資料一律拒絕。
- **Golden scenario schema v10**：新增 `reverse`、`repeat`、`cycle` 與 `train-repeat.json`；既有的 fixture 只加上中性的值（ARCHITECTURE 決策 21）。
- **不動的部分**：GamePresentation 只更新 `invalidTimetable` 的訊息；App 沒有修改。
- **留給之後**：停止服務後從指定的站續跑；取消落後的班次。

#### Q2 — 路線服務模式與自動派車

和 Stage O、P 一樣拆成兩步：先建立資料與推導（Q2a），再派車（Q2b）。規則移植自網頁參考遊戲的捷運模式，改成整數分鐘（ARCHITECTURE 決策 22）。

##### Q2a — 服務路線的資料與推導 ✅

- **`ServiceLine`**（有自己的 `LineID`）：
  - 依序停靠的車站，列車到兩端都原地折返；
  - 計算行程用的 `rate`；
  - 營運時間：06:00–24:00，最晚到次日 06:00，也可以全天；
  - 尖峰、離峰、低峰各要跑幾台列車。
- **服務日**：世界的 `ServiceDay`，預設是參考遊戲的時段（07–10 時與 16–20 時尖峰、00–07 時與 21 時起低峰，其他離峰），可以用 `setServiceDay` 修改。
- **推導**（不存檔）：
  - 服務等級；
  - 行程：從第一站的月台出發，依序求路、在終點折返、回到第一站，取來回時間最短的起點；
  - 最多列車數：以最短班距 2 分鐘計算；
  - 實際列車數與班距。
- **路線是計畫資料**：不派車、不影響任何列車。
- **存檔與 golden**：存檔只在有值時寫入，golden scenario schema v11 新增 `service-line.json`。
- **App 沒有修改。**

##### Q2b — 自動派車 ✅

- **指派**：`assignTrain` 把列車交給路線，由路線設定它的時刻表、啟動它的服務；`unassignTrain` 取回時，列車跑完這一趟。路線的列車不能手動設定時刻表或啟停服務（`trainOnLine`）。
- **目標班距**（真實時刻表研究的結論）：各等級可以設定目標班距，由系統算出需要幾台車，多出的時間讓列車在第一站等；沒有設定的等級照舊用列車數推導班距。
- **派車**：每分鐘在出發之前，營運中、該等級有列車、距上次派車已過一個班距、跑車中的列車少於該等級的列車數時，路線讓停在第一站、能開完來回的列車跑一趟來回。一趟就是一份一次性的時刻表，由 Stage P、Q1 的服務執行。
- **依時段增減**：
  - 增車只能用停在第一站的列車；
  - 減車時，多出的列車跑完這一趟，回到第一站就停下（參考遊戲的「到終點站後退出」）。
- **一天**：`GameTime.minuteOfDay`，一天是 1440 分鐘；平日與週末的差別留待之後。
- **存檔與 golden**：只在用到時寫入；golden scenario schema v12 新增 `line-dispatch.json`（ARCHITECTURE 決策 23）。
- **已知限制**：Phase 4.6 之前，同一段鐵軌上的列車互不阻擋，和現在一樣會重疊；只從第一站派車。

#### Q3 — 區間車與停站模式 ✅

- **服務模式**（`LinePattern`）：路線除了自己的全線站站停服務，還可以有其他模式。模式以停靠站的索引（`calls`，至少 2 個、嚴格遞增）表示：連續的索引是區間車（短程折返），跳過的索引是快車通過的站。快慢車的標示只從 `calls` 看出來，是規劃資料。
- 每個模式有自己的列車數或目標班距、列車與上次派車，從自己的第一個停靠站派車，時刻表只列出停靠的車站。
- **容量**：每段鐵軌每天每個方向最多 720 班（最短班距 2 分鐘）。各服務依序（路線自己的最先）以 `⌈1440 ÷ 班距⌉` 佔用經過的每一段（快車也算進通過的站），放不下的服務減少列車數。路線自己的服務永遠不會被削減，沒有模式的路線和 Q2 完全相同。
- **覆蓋**：路線自己的服務永遠跨越全線；某等級沒有列車經過的區段由 `lineSegmentLoads` 推導（負載為 0），不拒絕指令。
- **指令**：`addLinePattern`、`removeLinePattern`；列車數、目標班距與指派加上 `pattern` 參數。
- **存檔與 golden**：只在有模式時寫入；golden scenario schema v13 新增 `line-patterns.json`（ARCHITECTURE 決策 24）。
- **已知限制**：列車互不阻擋，快車會穿過慢車，真正的待避、超越屬於 Stage V；不同路線共用鐵軌時的容量要等 Phase 4.5。

### Stage R — 服務與時刻表畫面 ✅

- **路線面板**（HUD 的「Lines」按鈕，半高的 sheet，地圖仍可操作）：
  - 每條路線的停靠站與目前的服務等級（尖峰、離峰、低峰或停駛）。
  - 選定路線的每個服務（自己的服務與各模式）：種類與兩端（站站停、區間車、快車）、停靠與通過的站、各等級設定的列車數與目標班距、推導出的實際列車數與班距（「3 trains · Every 4 min」）、指派與行駛中的列車數。
  - 各等級沒有服務經過的區段（覆蓋缺口）。
  - 操作：各等級的列車數、目標班距、全天或 06:00–24:00 營運、新增與刪除區間車或快車、指派選定的列車、刪除路線；在地圖上依序選車站建立新路線。
- **列車面板**：所屬的路線與服務、目前或下一個停靠與時刻、早到或誤點（和排定時刻比較後推導，不存檔）；取回路線的列車、啟動或停止自己的時刻表。
- **地圖的細節分級**：縮小到每格 20 點以下時只畫鐵軌線、車站標記與列車，不畫格線、道碴與車站圖示。
- 每個操作都是一個 `GameWorld` 指令；文字與推導都在 GamePresentation（可在 Linux 測試），畫面不保存第二份權威狀態。
- **留給之後**：逐站編輯時刻表的畫面、班次預覽的時刻列表、拖曳時隱藏覆蓋層。

## Phase 4.5 — Physical railway

多台列車要共用鐵軌，先要有可以佔用的資源，而且要知道鐵軌實際怎麼接、車站有幾股、多長。這一層參考真實時刻表資料的實體鐵路層（[TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md) 的「實體鐵路層」），放在交通控制之前。和 Phase 3、4 一樣，每個 Stage 一個 PR。

### Stage S1 — 軌道資源 ✅

- **轉轍器與平面交叉**：新增兩種鐵軌。轉轍器的 stem 接到每條支線，支線之間不互通；平面交叉只能直行。原本的鐵軌行為不變，所以既有存檔、路徑與 golden 值都不變。路徑、continuation 與移動遵守同一條轉向規則（`exits(from:facing:)`）。
- **區段**：兩個分岔點之間相連的一串鐵軌，沒有分岔點的環狀線是一個區段；由地圖推導、不存檔（`trackSections()`；路網的版本 `networkSections()` 在 F3c-1 加入，移植參考的 `trackGroups`，F3c-3c 起只剩它）。
- **單線與雙線**：兩站之間不共用連結的路徑數（`parallelTracks`、`lineTrackCounts`），1 是單線、2 以上是雙線。F3c-1 起也數路網：路徑不共用任何一段軌道（一條邊，在兩站的月台處切開）。
- **佔用資源**：鐵軌格（節點）與相鄰鐵軌之間的連結；平面交叉是一格，兩個方向共用。唯讀查詢：每台列車佔用的資源、互相衝突的列車。
- 之前所有 Stage 的 property digest 不變；golden scenario schema v14 新增 `track-resources.json`（ARCHITECTURE 決策 26）。
- **留給之後**：建造轉轍器與平面交叉的畫面。

### Stage S2 — 車站設施 ✅

- **多格車站**：`extendStation` 讓車站長到旁邊的空格，每格都有月台。`platformTracks` 把月台依鐵軌相接分組，每組是一條月台股道，格數就是月台長度。
- **列車長度**：1 到 16 節，每節一格，只能在列車不在軌道上時設定。車頭後方的車身記錄在 `trail`，移動時跟著走，反向時車頭移到車尾，車身下的鐵軌不能拆。佔用資源包含車身。
- **停站**：長列車到站時沿月台延伸，整列都在月台邊時才算整列停妥（`stationsBesideWholeTrain`）。月台比列車短時，路線在第一站折返後無法再派出它，要把車站加長。
- **畫面**：車站工具可以切換成「長大」；列車不在軌道上時可以設定節數；地圖沿車身畫出整列車；月台太短時停站文字會說明。
- 之前所有 Stage 的 property digest 不變；golden scenario schema v15 新增 `station-facilities.json`（ARCHITECTURE 決策 27）。
- **移到 5A**：依車站等級決定規模的預設值。這屬於把真實時刻表轉成情境的工具，不在 GameCore 裡。

### Stage S3 — 連續軌道幾何 ✅

S3 分成兩個里程碑：S3A 讓 `RailwayNetwork` 成為唯一的鐵路資料與資源的基礎，S3B 在它上面加上連續幾何（ARCHITECTURE 決策 29）。

- **S3A 唯一的鐵路權威**：所有鐵軌（方格的鐵軌格與連續路網）只記在 `RailwayNetwork`；`GridMap` 只剩土地（空地與車站）。舊存檔讀檔時把鐵軌格移進路網，存檔時再寫回同樣的格式，只有方格的存檔逐位元不變。沒有雙向同步。
- **S3A 資源是 span**：資源是節點或邊上的一段里程（`TrackSpan`）。邊切成不超過一格長的等分，方格的連結恰好是一個 span，所以方格的佔用不變；長邊上的列車只佔用它所在的 span。佔用只讀整數里程，不讀畫面的取樣。泛用查詢 `pathAhead(of:)` 給之後的交通控制讀列車前方的路。
- **世界座標**：方格與連續路網共用一個整數的世界座標系（x 東、y 南、z 上），一格 1024 單位；方格 (x, y) 的中心是 (1024x + 512, 1024y + 512, 0)。
- **路網**：與方格並存的節點與邊。邊是直線或整數控制點的三次 Bézier；取樣、長度（水平里程）、位置與切線都由固定的整數演算法在建造或解碼時推導一次，之後每個 tick 只用整數長度。
- **泛用的身分**：`TrackNodeID`、`TrackEdgeID`、`TrackTraversal`、`TrackResource`（節點與 span）同時表示方格（`tile`、`link`）與路網（`node`、`edge`）。節點上的轉向由切線推導（兩端方向相反、誤差 1:16 以內才相通），轉轍器、菱形平面交叉與雙交分轉轍器都由此成立；只有共用節點才相接，平面上交叉但不共用節點的兩條邊互不相干。
- **列車**：新增位置 `onEdge`，移動 kernel 支援任意邊長；車身是車頭後方經過的邊（`trailEdges`），列車長度與格數脫鉤，反向兩次一定還原。
- **路徑搜尋**：方格與路網共用同一個最短路徑搜尋；方格的結果不變。
- **畫面**：地圖以俯視的除錯投影畫出路網與上面的列車；示範地圖有一條四段曲線組成的環線。沒有建造路網的畫面。
- 之前所有 Stage 的 property digest 不變，只有方格的存檔逐位元不變；新增獨立參考模型的差分 campaign、存檔變異測試，golden scenario schema v16 新增 `continuous-track.json`（ARCHITECTURE 決策 29）。
- **留給之後**：高程與結構物（S4 ✅）、路網上的服務（S5 ✅）、spline 編輯器與建造畫面、3D renderer。

### Stage S4 — 立體鐵路與結構物 ✅

- **高程**：節點的高度在地面上下 64 公尺（4096 單位）以內。邊沿水平里程有縱斷面：固定坡度，或兩端的拋物線豎曲線（平坡、上坡、下坡與過渡由同一個整數公式得到）；坡度是有理數，最大 40‰（遊戲參數）。長度仍是水平里程，移動與路徑不讀高度。
- **結構物**：地面、高架、橋、隧道。各自有高度帶（地面 ±2 公尺、高架與橋在地面以上、隧道在地面以下）與費用倍數；GameCore 不存橋墩或隧道壁。
- **交叉**：平面上相遇的兩條鐵軌（共用節點的一格以內除外）高度差至少 8 公尺（512），是立體交叉，不共用任何資源；否則拒絕。同一高度的交叉必須共用節點，也就是 S1 語義的平面交叉。
- **隧道**：一般的邊；隧道口是隧道與非隧道的邊相接的節點，列車照常穿過。
- **多層車站**：月台是鐵路網的基礎設施（`RailwayNetwork.platforms`，不存在車站裡）：車站、一條邊、起訖里程，層由邊的高度與結構物推導。同一站可以有任意多條、直的或彎的、地面、高架與地下的月台；月台的兩端切開那條邊的 span，整列停在月台上的列車只佔用月台內的 span；整列車都在月台區間內時可以查詢。層留給 Phase 5F 的步行轉乘成本。
- **畫面查詢**：3D 的姿態（位置、方向、坡度）、3D 車身與唯讀的 `railwaySnapshot()`；renderer 只讀、不回寫。
- **畫面**：俯視 debug 投影依高度由低到高畫，隧道是虛線、高架有陰影、隧道口加圈；示範配置有跨越環線的高架與駛入隧道的列車。
- Stage I–S2 的 14 個 property digest 不變；S3 的 `network.differential` 因為同一高度的交叉被拒絕而改變（刻意的）。新增 `vertical.differential`、`save.verticalMutation`，golden scenario schema v17 新增 `vertical-railway.json`（ARCHITECTURE 決策 30）。
- **留給之後**：地形（目前地面處處是 0）、路網與方格之間的空間檢查、軌道寬度的側向淨空、路網上的服務與派車（S5 ✅）、橫向傾斜、3D renderer、建造與地下模式的畫面。

### Stage S5 — 路網上的營運 ✅

S5 是 S3/S4 的路網與 Phase 3–4 營運系統（N、P、Q1、Q2a、Q2b、Q3）之間的橋（ARCHITECTURE 決策 31）。

- **一套營運語義**：時刻表的狀態機、路線的行程、派車與服務模式只有一份實作；只在最底層依鐵軌種類分成找月台、找路、交給移動與車身幾個小 adapter。沒有方格與路網各一份的時刻表引擎。
- **服務路徑**：`TrainPath`（依序進入的行進方向、停在最後一條的哪裡、精確的整數距離）是方格與路網共用的路。存檔的仍然只有列車的移動；路網的移動多一個 `end`，路可以停在邊的中段。
- **月台與停車位置**：路網上的停站只看 `TrackPlatform`：車頭停在行進方向上月台的末端，車身向後；只有不比列車短的月台才算，所以到站時整列車都在同一個月台上。彎道、高架與地下的月台規則相同。
- **以車站為目的地**：到停車位置的最短精確距離，同樣短時依邊的編號逐步決定，與建造順序、字典或記憶體位置無關。
- **精確距離**：一段的分鐘數是整數距離除以路線的速度、無條件進位（例如 8,300 + 21,470 + 3,200 = 32,970，而不是 3 × 1024）。
- **N、P、Q1、Q2a、Q2b、Q3 都在路網上運作**：停站與整列停妥、時刻表的到達停留出發、終點折返與重複、路線的行程與容量、自動派車、區間車與快車。長列車折返時車頭移到車尾，仍在同一個月台上。
- **拆除月台**：服務正在使用的月台不能拆（`trainServiceActive`）。
- **畫面**：列車工具可以把路網上的列車送往車站；列車面板顯示路網上的路；地圖畫出路網上的月台；示範配置的環線有兩個月台，路線 Circle 在兩站之間往返派車。
- 之前的 16 個 property digest 全部不變，只有方格的世界與 S3、S4 的路網存檔逐位元不變。新增 `service.network` 差分 campaign 與 `save.networkServiceMutation`，golden scenario schema v18 新增 `network-service.json`（ARCHITECTURE 決策 31）。
- **留給之後**：列車之間的阻擋、進路預約、movement authority 與 dispatcher（T、U、V）；行駛曲線（W）；方格與路網之間的連接；建造路網、月台與路線的畫面。

## Phase 4.6 — Traffic control

要讓多台列車真正共用鐵軌、待避與交會，就需要這一層，這也是與《A列車》的深度差距最大的地方。兩個參考網站要分開看（2026-09 對私有 repo 重新確認，細節見 [RAILWAY_REFERENCE_MAPPING.md](RAILWAY_REFERENCE_MAPPING.md)）：

- `Ci/` 的交通經營遊戲沒有號誌、閉塞或待避站，快慢車也彼此「看不見」。
- `Railway/` 的股道網站沒有號誌或固定閉塞，但有這些：
  - 同向待避與單線交會（在瀏覽器裡對時刻表推估）；
  - 排定的等待（`scheduled-hold`，由建置腳本事先算好）；
  - 股道與月台的指派；
  - 同股道的跟車距離。

**之後的實作順序**（依實際的相依關係，不是字母順序；T 已實作）：

1. W1 ✅：行駛曲線的計算核心，照 `buildProfile` 翻譯。參考最完整，也不依賴其他 Stage。
2. **G1** ✅：第一個能玩的經營閉環（見下面的 [G1](#g1--第一個能玩的經營閉環)）。G1a ✅、G1b ✅、G1c ✅。
   - T 已經保證兩台車不會同時用同一段軌道，乘客不需要 U。
   - `Ci/` 的參考在乘客、需求與票價上最完整。
3. **W2**（見下面的 [Stage W](#stage-w--行駛曲線)）：W2a 時間改用秒 ✅ → W2b 停站、上下車與誤點 ✅ → W2c 曲線接到行程與移動 ✅。
   - W2a 之後先做 L1（繁體中文，決策 38），發第二版內部 TestFlight（0.2.0），再做 W2b（2026-10-02 作者決定）。
   - **2026-10-01 作者決定 W2 先於 U-min。** 第三份參考（[RailwayCore 參考包](RAILWAY_REFERENCE_MAPPING.md#railwaycore-參考包)）把停站與誤點列為 P0，這也是 G1 目前最明顯的缺口；W2 先做，U-min 就直接建立在最終的移動方式上。
4. **C**：已完成核心的操作畫面（見下面的 [Stage C](#stage-c--已完成核心的操作畫面)）。C1 ✅、C2 ✅、C3 ✅、C4 ✅、C5 ✅。
   - **2026-10-02 作者決定**：U-min 之前，先讓已完成的核心都有畫面、都能在實機上測試。
   - 為什麼排在 U-min 之前：路網、高程與月台的核心在 S3–S5 就完成了，App 卻只能在方格上鋪軌，Release 版的新遊戲完全沒有路網；車站也從來沒有需求，所以 App 裡沒有乘客、也沒有票價收入。W2c 的加減速在方格上幾乎看不出來（一格 16 公尺），要能鋪幾公里長的線才看得到。U-min、V 建立在方格與路網共用的軌道模型上，晚做沒有重寫的風險，而且它們處理多台車的跟車與待避，等玩家能蓋長的線、放多台車時才用得上。
5. **F、E**（2026-10-02 作者決定，見[目前的優先順序](#目前的優先順序)）：F1 全面路網 ✅ → C4 ✅ → C5 最小教學 ✅ → E1 大地圖 ✅ → 環線 ✅ → E2 空白／實景 ✅ → F3 移除方格 ✅ → F2 線間距 ✅（E3 MapLibre 視需要）。
6. U-min：movement authority 的最小穩定契約。建立在 T 上；參考只有畫面層的跟車距離，授權規則大部分是 gap。U1（通過後釋放）✅ → U2（站間跟車）✅。
7. V：待避與交會。它的推估要用 W1 的曲線；實際放行由 T、U 保證。
8. 在 G1 上深化乘客、城市與公司（Phase 5–7）。

### Stage T — 進路預約 ✅

T 建立在 S3–S5 統一好的 `RailwayNetwork`、`TrainPath`、`TrackTraversal`、`TrackResource`（節點與 span）與 `TrackPlatform` 上，方格與路網是同一套程式（ARCHITECTURE 決策 32）。舊的 Stage T（PR #31）建立在方格上，沒有合併；新的 T 保留了它的語義，但沒有沿用它的程式，概念上取代了它。

- **交通控制**：`GameWorld` 的開關。GameCore 的新世界預設關閉（之前所有 Stage 的行為與存檔不變），App 的新遊戲開啟。開啟時兩台列車需要同一段軌道就拒絕（`trainsShareTrack`），關閉一定成功並清除所有預約。
- **整條進路一次取得**：列車出發（服務、路線派車）或拿到新的路（手動的路、放置、反向）之前，一次取得從車尾到路的終點整列車會碰到的每個節點與 span；拿不到就一點都不拿（`trackReserved`，阻擋者是編號最小的列車）。預約存檔，是權威狀態；走到路的終點時釋放。
- **span 的分界**：與佔用是同一條規則，落在分界上時兩邊都算，所以停在分界上的列車與它的預約之間沒有縫。長列車從車尾預約，停車位置在邊的中段時只預約到那裡。
- **交會點與限界**：經過轉轍器、平面交叉的進路在共用的節點衝突；停在交會點 1024 以內的列車也持有那個節點；立體交叉不共用資源，互不衝突。
- **服務與派車**：路被佔用時服務原地等待（不折返），每步重試；路線的列車取不到路時不派出、不改上次派車；派出的列車同一步就出發。`trainHoldingRoute(of:)` 回答它在等哪一台列車。
- **基礎設施**：預約中的鐵軌不能拆，持有的邊不能加減月台（span 的切法不變），被持有的交會點不能加邊；不相干的建設照常。
- **畫面**：路線面板有交通控制的開關，列車面板顯示「Waiting for <列車> to clear the route」，示範配置讓 Local 在 Hill 等主線上的列車讓出路。
- 新增 `traffic.reservation` 差分 campaign（新的 CI shard）與 `save.trafficMutation`，每個 campaign 都檢查交通控制的不變量；golden scenario schema v19 新增 `traffic-reservation.json`。
- **留給之後**：通過後逐段釋放與 movement authority（U）；單線上兩端互等、時刻表造成的循環等待、繞路、待避、交會、月台分配與快車優先（V）。

### Stage U — Movement authority

- 列車只能進入預約到的資源，通過後釋放。
- **U1 ✅ — 通過後釋放**（ARCHITECTURE 決策 55）：
  - 交通控制下，列車每次移動之後，預約只留下它從現在的位置還需要的部分（佔用、車頭還要走過的路與它們碰到的限界）；車尾離開的軌道立刻釋放，走到路的終點時全部釋放。授權仍照 T 一次取得到下一個停靠點，所以授權終點就是路的終點，W2c 的曲線本來就在那裡停下。
  - 效果：後車不必等前車走完整條路，前車的車尾一離開後車需要的軌道就能出發（站間的閉塞：從「兩個站間一台」變成「一個站間一台」）。通過的邊可以拆、加減月台。
  - 以秒批次推進仍然精確：批次在等待中的出發需要的軌道空出來的那一秒結束。
  - 存檔格式不變；U1 之前的存檔裡已經走過、還預約著的軌道照樣讀取，列車下一次移動時釋放。
  - 只有 `traffic-reservation.json` 的五個預期值改變（Down 早一分鐘出發，逐值說明在 GoldenScenarios/README）；`traffic.reservation` 的 digest 從 `9BFD8C82046796A3` 變成 `58747680E8B1D600`（預約在移動時變小），其他 campaign 不變。
- **U2 ✅ — 站間跟車**（ARCHITECTURE 決策 56）：
  - 交通控制下，服務出發時路被行駛中的前車持有，而前車一定會讓出（它停靠的地方不在後車的路上，或它從那裡不折返、繼續開往下一站），就跟車出發：只預約到前車持有的軌道之前 400 m（25,600 單位，參考的 `BLOCK_GAP_KM`）。站著、要折返或結束服務的前車照舊要等它讓出整條路，所以部分取得不會在單線上造成新的死結。
  - 移動不超過預約（授權終點），到那裡停下；每一秒在出發之前延長，前車離開它的路之後取得剩下的全部。後車還沒預約到的路，別的列車不能插進來。
  - 以秒批次推進仍然精確：批次也在跟車可以延長的那一秒結束。
  - 存檔版本 7（行駛中的列車的預約可以只到路的一部分）；新的 golden `train-following.json`，27 份既有 fixture 都沒有改變；差分 campaign `traffic.following`，移到新的 CI shard `campaigns-9`。
  - 留給之後：依煞車曲線在授權終點前減速、對向與循環等待的死結（V）、畫面上的授權範圍。
- T 已經準備好：存檔的 `Train.reservation`（依資源順序）、`pathAhead(of:)`、`TrackSpan`、佔用與限界的 helper，以及移動之後釋放走完的路的那一處（決策 32 第 16 點）。U 只加上授權的檢查與逐段釋放，不需要重新設計預約、路、月台或存檔。
- 決策 20 已經預留了接點：「沒有路就等待、之後再試」與「拿不到 authority 就等待」語義相同，所以時刻表與執行進度的契約不需要重寫。

### Stage V — Dispatcher：待避、交會與月台分配

- **V1 ✅ — 避占用選路與月台分配**（ARCHITECTURE 決策 57）：交通控制下的服務出發與路線派車就緒判斷，依序嘗試預設路整條取得、預設路 U2 跟車、到同站任何停車位置的避占用最短路整條取得、等待。每一步避開其他列車的 span、限界節點、妨礙與跟車 claim；替代路新增借用的 traversal 不得逆向使用執行中服務從所在位置往後的路，以及有已放置列車的路線／服務模式／雙向環線的預設路（2026-10-04 融合 #103 與 V2 的版本，見決策 57「融合」）；與時間無關，保留單線共用的預設走廊，計畫快取僅存在單次 advance；沿用平手順序；替代路最多比預設路長 400 m。替代路照自己的距離重算行駛曲線與離站距離；批次在替代路可取得的那一秒重試。
  - 2026-10-04 作者要求以最佳選擇定案：先跟車再改月台、繞路上限 400 m（決策 57 的理由）。
  - 手算測試：兩端對向列車在雙月台交會站各走一個月台、到對面；最近月台被占用時改走另一個；無替代路時 U2 跟車或等待；派車就緒、部分邊、限界與妨礙、平手順序及關閉交通控制；前車在動時先跟車；超過 400 m 的替代路不走。
  - 獨立鬆弛模型、`traffic.occupiedRouting`（原六組單線與兩組雙線＋渡線，再加兩段之外對向服務／未營運路線兩組，10 case × 4 seed，逐步比較整個狀態、不變量、存讀；新的 `campaigns-10`）；短 schema 30 golden `single-track-meet.json`。V1 本身不改存檔版本。
- **V2 ✅ — 死結偵測與解除**（ARCHITECTURE 決策 58）：只互相等待的列車是死結（`deadlockedTrains()`）。每個整分鐘，調度把死結裡依 ID 第一台能送的服務送到途中某站的待避站（現在能整條取得、不逆向、全程不超過預設路加 400 m、停在那裡能讓另一台出發），它在那裡等到續行的路空出再走；解不開時列車面板顯示死結。存檔版本 8（開往或停在待避站的服務）。
  - 手算測試、參考模型逐秒比較、`traffic.deadlock`（8 case × 4 seed，新的 `campaigns-11`）、golden `single-track-passing.json`、版本 8 存檔 fixture。
  - **Deferred**：事前規劃的排定交會與待避推估（`inferMeetPassTimes`、`planSameDirectionOvertakes`）、需要換向的折返與調車解法、單線區段的路線容量（決策 22）、畫面顯示授權範圍與地圖上的死結標示。

- **V3 — 已實作，驗證結果見 PR**（ARCHITECTURE 決策 59）：直接翻譯四份參考中網站的交會／待避演算法；交通控制下推導 1800 秒內單線交會（每次 ≤300 秒）及 25 km 內同向待避（30 秒＋煞停時間的領先、最多 600 秒等待），先交會、最多八輪待避、每次重算該車交會。只在有排定的站用 RailwayCore §7 選路成本，停車走待避月台線、通過走名義正線。
  - 解除需要對方實際到站／通過加 margin，誤點繼續等待；V1／V2 保留。計畫不存檔，版本 9 只記必要實際事件並遷移舊檔；沒有修改 Station／ScheduledStop。列車面板新增英語／繁體交會與待避文字。
  - 手算／逐秒比較／誤點／門檻／ID 平手／存讀；schema 31 的兩份新短 golden、兩份版本 9 fixture；獨立差分 `traffic.scheduledMeets`（12 case ×4 seeds、1,728 操作），新增 `campaigns-12`。既有 campaign 未縮小，既有三種 fixture JSON 未修改。
  - 2026-10-05 修正（決策 59 第 11–13 點）：排定路線只在能整條取得時採用，否則照沒有計畫的規則（重複來回的服務不再永久停住）；不等等不到的車（V2 看得到）；計畫每一步從列車狀態推導（推進切法不影響結果）；待避站續行改走替代路時恢復最快曲線。
  - 2026-10-05 CI 時間：#111 合併後 `campaigns-9`、`campaigns-12` 超過 20 分鐘被取消。計畫推導不再做結果用不到的工作（結果不變）；`traffic.following` 移到 `campaigns-13`，`traffic.scheduledMeets` 的後半 case 移到 `campaigns-14`。
  - **V4 Deferred**：每段路徑／股道／月台指定與單線容量重算（決策 22）。需要換向的折返／調車、地圖授權範圍與死結標示、E3 也不在 V3。

- **V4a — 已實作，驗證結果見 PR**（ARCHITECTURE 決策 60）：對齊私有參考 `25229af`，同向待避在選站與重建前檢查股道時窗（到站前／出發後各 30 秒），所有同站服務的已知進出路線組合都必須留有可停股道；較早待避優先，同時到站取 TrainID。從玩家路網 berth、span 與限界資源推導，不以台鐵站名／OSM id 為規則輸入；實際換到全列不妨礙其他車進出的停車位置，偏好拿不到仍回 V1／V2。
  - 存檔 9／schema 31 不變，既有三種 fixture 不改；新增手算、三車差分 case（原 18 case 不縮減，新增 case 18–23，在 campaigns-15–18）及實景猴硐另一股待避驗收（名義走廊的限制見決策 60）。
  - #116 已由作者合併；合併後安全 berth 全域成本／平手修正由 V4b 承接。StartSaveFlow Menu 觸控修正已由作者獨立合併 #119，V4b 不再帶該 diff。

- **V4b — 作者已合併 #120／#123；全套 Swift／Apple gate 通過，full-lane UI 仍待驗**（ARCHITECTURE 決策 61）：路線本線／區間車共用逐段有向 walk 與月台偏好，不加進 ScheduledStop／Station。指定不可用退 V1／V2，整條授權才採用；接入名義進出、方向保護、派車與待避後續行。路線面板可逐向設定自動／月台／固定股道。
  - 存檔 10（9→10 缺省空偏好遷移）／schema 32，新增短 golden、v10 save、實體路徑 replay，既有三種 fixture 檔案未修改。
  - traffic.lineRoutes 4 個單列車 case×4 seeds×20 步＋2 個雙列車 case×4 seeds×45 步（680 步），比完整狀態與批次＝逐秒，campaigns-19；新增實景猴硐指定月台實際停靠與 GameSession 設定／清除驗收；新 UI 測試留 full lane。
  - 已整合 main `d2de3d5`（#117／#118／#119）。WIP 的 fastPassed 失敗已按手算事件時窗修正：精確驗證 478 秒進入 edge 3、600 秒抵達終點及慢車續行；CI 與 Apple 檢查結果見 PR，未執行的不稱為通過。
  - #120 首輪 Apple 跨模組存取失敗已修正；作者合併的是 50da302，後續新 UI test 的選項查找失敗，改明確 ID／觸控／等待並移獨立 full-lane class，修正後 full runtime 尚未驗證。Swift 全套 779 項曾通過，但 CI 時間需要重分配，完整保留 Economy 12 case 並分 campaigns-1／20，未拉 timeout 或縮減原操作；後續修正由同分支的另一 draft PR 驗證，最新狀態見 STAGE_V_HANDOFF.txt。
  - V4c → V4d → V4e 各一分支／draft PR，前階段由作者合併後從新 main 開工：單線容量；中途換向與倒進側線；地圖授權範圍與死結標示。

- **V4c — 已實作，驗證中**（ARCHITECTURE 決策 62）：從作者合併 #123 後 main `18ff248` 開工；控制啟用時，以玩家 parallelTracks／可放最長列車的兩股交會站推導單線 block，完整名義往返占用推導最大 count／headway。本線與區間車共用每天 block 86400 秒預算，保持原服務順序與雙線／關閉控制行為。來源未有直接最大公式，保守改寫與 gap 明列。
  - SavedGame 10 不變，derived 無新 saved 欄位；schema 33，只新增 single-track-capacity golden，既有三種 fixture 不改。手算 281 秒／5 分鐘往返：無控制 2 列／3 分鐘，單線控制 1 列／5 分鐘；requested 4 保留。
  - 新 `line.singleTrackCapacity` 6×4×24＝576 步，比每步完整模型／計畫／不變量／存讀與批次＝逐秒；新增平溪 demo 容量驗收，原實景驗收保留。
  - #123 CI 全 780 項、iOS build／gate 與 localization 已通過；SaveMutation 732 秒，原 14 項完整保留分 campaigns-3／21，新容量 campaign 放22，不改 timeout。最新 checks／未驗 UI 限制見 handoff／PR。
  - 作者合併此段後才從新 main 開 V4d（中途換向／倒進側線），再合併才做 V4e（地圖 movement authority／死結互等）。

- **衝突用排定的等待解決**：在某一站多停，讓對向或後面的車先過，而不是讓列車互穿。
- **T 留下的死結**：T 只保證不會「拿一半、等另一半」；單線上兩端的列車各自等對方、時刻表造成的循環等待、兩台站著的列車各自擋住對方，都由 V 解決（決策 32 第 15 點）。
- **待避站的選擇**：後車追上前車之前，往回找一個安全間隔足夠的車站讓前車待避。
- **單線交會**：等對向車到站再開。
- **月台分配**：例如停站的列車走月台線，通過的列車走正線。
- **優先順序**：例如快車優先。
- **路徑指定**：時刻表的每一段可以指定路徑（股道、月台），同一條路線的班次共用。
- 必須在 S1、S2、T、U 之後才做，而且不寫進 `ScheduledStop` 或 `Station`（決策 20）。
- **修正路線的容量**：Q2a 的最多列車數假設上下行互不干擾，等於雙線。單線區段只能在交會站錯車，實際容量較小（真實時刻表研究的結論，例如平溪線）。有了交會之後，最多列車數要依單線區段與交會站重新推導（決策 22 的已知限制）。

## Phase 4.7 — Train dynamics

### Stage W — 行駛曲線

參考：`Railway/` 網站的 `buildProfile`、`profTimeToProg`、`profProgToTime` 與車種性能表（[對照](RAILWAY_REFERENCE_MAPPING.md#stage-w行駛曲線)）；停站與誤點另外照第三份參考（[RailwayCore 參考包](RAILWAY_REFERENCE_MAPPING.md#railwaycore-參考包)）。2026-10-01 作者決定 W2 先於 U-min，對照文件 [gap 分析](RAILWAY_REFERENCE_MAPPING.md#gap-分析)的 gap 1、2、9、10 採用建議的方案。拆成四步：

- **W1 ✅**：照原樣移植曲線本身（`RunningCurve`、`TrainPerformance`，ARCHITECTURE 決策 33）。純計算，不改變任何既有行為。
- **W2a ✅ — 時間改用秒**（gap 2、9，ARCHITECTURE 決策 37）：
  - 基本步長從一分鐘改成一秒。原因：地圖是真實比例，真實車速的列車要在接近真實時間的速度下才看得清楚；那種速度下，一分鐘的步長會讓移動一頓一頓，玩家的指令最多要等一分鐘才生效。
  - 速度：1×（真實時間，照 `Ci/`）、10×、60×（對上 `Railway/` 倍速滑桿的刻度），保留原本的 600 倍（`normal`，新遊戲的預設）與 1200 倍（`double`）。不足一秒的十分之一秒留到下一個 tick。之後在實機上調整檔位。
  - 只換單位與速度檔位，不加新玩法：列車每秒走它每分鐘 rate 的份，整分鐘加起來正好是 rate，到站也每秒判定；發車、派車、乘客與帳仍然在整分鐘處理。以整分鐘推進時，每個整分鐘的狀態與以前相同。
  - golden schema 23：時鐘可以寫成秒、新增速度名稱與 `clock-seconds.json`；其他時間欄位仍寫分鐘，讀取端換算。既有 22 個 fixture 只改版本號，預期值都沒有改變。
- **W2b ✅ — 停站、上下車與誤點**（gap 10，ARCHITECTURE 決策 39）：
  - 把「到站 → 開門 → 上下車 → 關門 → 發車」接到遊戲時間：用 G1b 已移植的 `StationDwell`（捷運 36／42 秒、車門 8／8.3 秒、Railway 的每站停站與最短停站等），取代 G1b 在離站時一次完成上下車的過渡做法（ARCHITECTURE 決策 35 第 3、9 點）。
  - `StationDwell` 是最短停站；上下車的人多時才延長，延長的部分照參考包的 `max(下車人數 ÷ 速率, 上車人數 ÷ 速率)`。速率與門數是 gap，在這一步定。
  - 驗收照第三份參考的 `02_W2_IMPLEMENTATION_CONTRACT.md`：
    - 到達、上下車、停留、發車都由模擬的步長推進，不依賴畫面；
    - 沒有乘客也有最短停站；上下車的人越多，停站依規則越長；車滿時多的人留在車站；
    - 早到的列車等到排定出發（決策 20 已有），誤點的列車做完停站就走，不多等；
    - 實際的到達與出發時刻是存檔的權威狀態，誤點由它和排定時刻算出，改成 GameCore 的查詢，取代決策 25 在畫面層的推導；
    - 停站中存檔再讀回，狀態完全相同；同一串指令得到同一個結果；
    - 列車在月台上看起來停了，不代表完成。
  - 實作：到站 8 秒後開門、下車與上車同時進行（每節 4 扇門 × 每秒 2 人，門數是 gap）、至少停 36 秒（第一站、最後一站與折返的站 42 秒）、早到等到排定出發前 9 秒才關門、關門 9 秒後出發；開著門時整分鐘釋出的人也上車；客滿離站時才記 `refused`。啟動服務與派車算到達第一站，路線的時刻表在派車 42 秒後出發。`ServiceTimes` 存檔，`lateness(of:)` 是 GameCore 的查詢，畫面顯示停站的階段。golden schema 24（時刻表可以寫秒、列車的 `times`、`serviceTimes`、`lateness` 觀察與 `station-dwell.json`）。
  - 還沒有：月台擁擠的延長、轉乘、依車種的門數與速率、`Railway/` 的每站實測停站時間。
- **W2c ✅ — 曲線接到行程與移動**（gap 1、4，ARCHITECTURE 決策 40）：
  - 路線一段的時間是路線的性能建得出曲線（`buildProfile`）的最少整秒，來回無條件進位到整分鐘規劃列車數與班距；取代路線的 rate。
  - 服務的列車在兩站之間跟著曲線走（`ServiceRun` 存檔）：照 Railway 參考的 `assignRunProfiles` 走班表給的時間，準時出發就準時到達、晚出發整段往後移；排得太緊時走最少的秒數。被擋住（rate 0、鐵軌被拆）時丟掉這段，能動時從停止狀態盡快重新出發（gap）。
  - 列車與路線各有性能（gap 4 的決定：預設 `standard`，`setTrainPerformance`、`setLinePerformance` 更換；新增 `Ci/` 的捷運列車 `metro`）。
  - golden schema 25（`performance`、`run`、行程的秒數、手算的 `service-run.json`）。
  - 還沒有：依車種選性能、限速區段與觀測曲線、曲率與坡度限速。選性能的畫面在 [Stage C3](#stage-c--已完成核心的操作畫面)。

- 站間不再等速：加速、定速、惰行、煞車組成的梯形曲線，加上速度上限；曲線半徑與坡度之後再考慮。
- 全部用整數計算，deterministic。
- 路線的行程與來回時間改由曲線推導，取代固定的 rate。
- 畫面上的平滑移動只是呈現；模擬仍以整數的基本步長前進。

## Stage C — 已完成核心的操作畫面

2026-10-02 作者決定：U-min 之前，先讓已完成的核心都有操作畫面，所有功能都能在實機（內部 TestFlight）上測試。每一步一個 PR；開工時照規則讀三份參考，有可以移植的做法就照搬（[對照](RAILWAY_REFERENCE_MAPPING.md#stage-c1任意角度的建造畫面)）。

**盤點**（2026-10-02，`main` 的 `ae8cf93`）：GameCore 已完成、App 卻沒有畫面的功能。

| 功能 | GameCore | 之前的 App | 補在 |
| --- | --- | --- | --- |
| 任意角度的路網：直線與三次 Bézier 的軌段 | S3 `buildTrackNode`、`buildTrackEdge` | 沒有；只能在方格上鋪軌，Release 的新遊戲沒有路網（示範地圖只在 Debug） | C1 ✅ |
| 高程、結構物（地面、高架、橋樑、隧道）、豎曲線 | S4 | 沒有 | C1 ✅ |
| 拆除路網 | S3 `removeTrackEdge`、`removeTrackNode` | 沒有 | C1 ✅ |
| 路網上的月台與車站 | S4、S5 `addTrackPlatform`、`removeTrackPlatform` | 沒有 | C1 ✅ |
| 把列車放到路網上 | S3 `placeTrain(_:at: .onEdge)` | 只能放在方格上 | C1 ✅（放到車站的月台） |
| 車站需求（種類、每日旅次） | G1a `setStationDemand` | 沒有：App 裡的車站從來沒有需求，所以沒有乘客，也沒有票價收入 | C2 ✅ |
| 列車自己的時刻表（逐站的到達、出發、折返、重複） | O、P、Q1、W2b `setTrainTimetable` | 只能啟動、停止已有的時刻表 | C2 ✅ |
| 路線的停靠站 | Q2a `setLineStops` | 只能建立、刪除路線 | C2 ✅ |
| 尖峰、離峰、低峰的時段（服務日） | Q2a `setServiceDay` | 沒有 | C2 ✅ |
| 轉轍器、平面交叉（方格） | S1 `buildTurnout`、`buildCrossing` | 沒有 | C2 ✅ |
| 唯讀資訊：區段與單雙線、佔用衝突、每對車站的需求、乘客帳 | S1 `trackSections`、`lineTrackCounts`、`occupancyConflicts`；G1a `hourlyDemand`、`passengerLedger` | 沒有 | C2 ✅ |
| 列車與路線的性能 | W2c `setTrainPerformance`、`setLinePerformance` | 沒有（W2c 也還沒有畫面） | C3 ✅ |
| 存檔與讀檔 | `GameWorld` 的 `Codable` | 沒有：每次開 App 都是新遊戲 | C4 ✅ |
| 示範地圖 | — | 只在 Debug | C4 ✅ |
| 開始畫面（新遊戲、繼續、讀檔） | — | 沒有：App 一打開就是新遊戲 | C4 ✅ |
| 教學 | — | 沒有 | C5 ✅ |

已經有畫面的：方格的鋪軌、建站與擴站、拆軌；列車的購買、放置、派送、速率、節數、反向、移出；路線與區間車、各時段的列車數與目標班距、營運時間、指派；交通控制的開關；經營模式、票價、帳本與報表；速度與暫停。

拆成五步（C5 在 2026-10-02 加入）：

- **C1 ✅ — 任意角度的建造**（ARCHITECTURE 決策 41）：
  - 「路網」工具的三種模式：鋪設、月台、拆除。
  - 鋪設：點起點、點終點，預覽曲線、長度、高度與費用（在丟棄的世界副本上執行同樣的指令），確認後建造；終點變成下一段的起點，一段接一段地畫。點在既有節點附近就接上它。
  - 照 `Ci/` 的建造模式：位置自由、不對齊格線；新的一段順著原本的線平順地延伸；轉彎超過 90 度、或新節點離另一端不到 22 公尺時拒絕。
  - 結構物、新節點的高度（每 2 公尺）、平順曲線的開關、緩和坡度（兩端的豎曲線）。
  - 月台：點軌道，月台以那裡為中心、依節數決定長度；所屬車站預設是兩格內最近的車站，或在月台中點下方的格子建新車站。
  - 拆除：點軌段拆掉它，兩端沒有其他軌段的節點一起拆。
  - 列車工具：車站在路網上有月台時，把列車放到月台上，依朝向決定行進方向。
  - 每個操作都是 `GameWorld` 指令；幾個指令組成的操作在世界的副本上全部成功才生效。GameCore 沒有修改。
- **C2 ✅ — 營運與乘客的設定畫面**（ARCHITECTURE 決策 43）：依作者指示先做車站需求。
  - **車站運量**：檢視列選到車站時打開運量面板，照 `Ci/` 的 `#panel-station-flow-adjust`：住宅區、辦公區、購物中心、景點四種預設（換預設時保留日運量）、日運量（沒有運量時從 10,000 開始，100 到 1,000,000）、複製、貼上、套用到整條路線；進站與出站的每小時長條圖；往返各站的每日旅次、候車與乘客帳。
  - **列車自己的時刻表**：照參考包的時刻表概念（起點、每站的行駛與停留，以到達與出發顯示）；加入停靠站、每次一分鐘移動到達或出發（之後的停靠站一起移動）、折返、刪除、清除、重複週期、開始與停止服務。
  - **路線停靠站與服務日**：停靠站的插入、刪除、上下移動；服務日各時段的等級、開始時間、刪除、拆分與標準服務日；各等級的時段照 `Ci/` 的 `metroServiceSlotTimeRanges` 顯示。
  - **方格的轉轍器與平面交叉**：軌道工具的選單選一般、轉轍器（與共用端）或平面交叉。
  - **唯讀資訊**：區段、經過選取格的區段、共用軌道的列車；路線相鄰停靠站之間的單雙線。
  - 還沒有：運量的自訂曲線與樞紐、時刻表的自動填入行駛時間（都需要 GameCore 或參考沒有的資料）。
- **C3 ✅ — 性能**（ARCHITECTURE 決策 42）：W2c 合併之後，作者要求一起做，所以排在 C2 之前。
  - 列車與路線各有性能選單：Railway 參考的預設，以參考配對的車名命名（區間車、自強、太魯閣、高鐵等），加上捷運；以及 `Ci/` 建線畫面的「設計時速」（60 到 200 km/h）。
  - 路線面板顯示以它的性能規劃的各段時間與來回時間；列車面板顯示正在走的行駛（秒數、距離、預計到達）。
  - 自訂加速度與減速度、依車種的容量（`Ci/` 的 `TRAIN_TYPES`）還沒有。
- **C4 ✅ — 測試輔助**（ARCHITECTURE 決策 45；[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-c4存檔開始畫面與示範地圖)）：
  - 存檔與讀檔，含存檔版本欄位與 migration（跨階段議題；`Ci/` 有本機存檔，`#screen-save-load-ui`）：GameCore 的 `SavedGame`（版本 1），每個版本在 `SaveFixtures/` 留一份回歸存檔；自動存檔（離開前景、回到開始畫面、每 15 分鐘），玩家自己的存檔、匯出與匯入。
  - Release 版也能開示範地圖；示範地圖用路網重做（F1 之後 App 不再用方格建造）：地面的 1 號線與高架的 2 號線，中央一座兩個月台的車站。
  - 開始畫面：新遊戲、繼續（最近的存檔）、讀檔、示範地圖與匯入；照 `Ci/` 的首頁（`home.title`「城市设计师」，可以切換介面語言；iOS 的語言在「設定」）。教學的入口跟著 C5 加入；E2 在開始畫面加上「實景地圖」（✅，決策 50）。
  - 另開一局之前先把自動存檔另存，上一局不會被蓋掉（`Ci/` 重新開始前另存草稿）。
- **C5 ✅ — 最小教學**（排在 C4 之後、E1 之前，見[目前的優先順序](#目前的優先順序)；2026-10-02 作者決定加入，範圍與時機交給 Claude Code）：
  - 照 `Ci/` 的捷運導覽移植（`tutorial.step.0`–`11`，`startTutorial`、`showTutorialStep`、`tutorialOnAction`、`tutorialStepActionDone`）：玩家實際做了那一步才前進，可以上一步、下一步、略過，也能從選單重開。
  - 移植內容步驟（開始建線、放置車站與節點、確認建設路線、開始列車營運、控制模擬、導覽結束），並調整成觸控與這個 App 的工具：路網的鋪設與月台、列車、路線的上線列車數、車站運量、速度。`Ci/` 的滑鼠與鍵盤快捷鍵步驟若有可用價值也可轉成觸控操作或其他對應互動。
  - 每一步做完了沒，由世界狀態推導（GamePresentation，可在 Linux 上測試）；醒目標示與步驟卡是 App 的畫面（可以交給其他代理，見 `AGENTS.md` 的分工）。
  - E1 加入縮放與平移的步驟（✅，第三步 `map.move`，決策 48）；E2 沒有加步驟：教學在空白的新遊戲上進行，模式在開始畫面就選了（決策 50）。
  - **步驟與完成條件 ✅**（2026-10-03，ARCHITECTURE 決策 47，[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-c5最小教學)）：`Tutorial.standardSteps` 十步，照一條線從無到有的順序：路網工具、鋪設軌道、第一座車站、第二座車站、建立路線、購買並放置列車、開始營運（指派列車並設定上線列車數）、乘客（運量）、控制時間、結束。
    - 完成條件全部由世界與 session 的現在推導；要求「蓋了什麼」的條件比較的是這一步第一次出現時的世界，所以示範地圖或從選單重開時，每一步也要做一次。
    - 沒有修改 GameCore、golden 與存檔。路線與車站面板是 sheet，步驟只框「路線」按鈕，面板裡的操作用文字說明。
    - 參考的滑鼠與鍵盤快捷鍵步驟（`tutorial.step.2`、`3`、`5`、`6`、`8`、`9`）目前沒有一對一觸控對應；需要時可改成觸控操作或其他 App 互動後移植。
  - **第 0 步 ✅ — 介面先行**（2026-10-03，[UI_INTERFACES.md](UI_INTERFACES.md)）：先定教學的資料（`Tutorial`、`TutorialStep`、`TutorialGoal`、`TutorialTarget` 與 `GameSession` 的上一步、下一步、略過、從頭開始）與三個示範步驟，App 上的控制項都標好識別碼，讓教學畫面（CX-5）可以和 C5 的內容同時做。
- **不在 C**：
  - 側向淨空（平行的軌道靠得太近時拒絕）是新的 GameCore 規則，會改到差分 campaign 的參考模型，不是「已完成核心的畫面」；排為 F2（S4 的留給之後）。
  - 方格的去留：2026-10-02 作者決定鐵軌全部改用路網（F1），方格只留作相容層，移除另議（F3）。
  - 曲線半徑的限速、真正的 3D renderer（Phase 8）。

## Stage F — 全面路網與自由擺設

2026-10-02 作者決定（C2 合併之後）：鐵軌全部改用路網，車站與土地也自由擺設，不再以方格為單位。每一步一個 PR；開工時照規則讀三份參考，PR 附對照表。`Ci/` 的建造模式本來就沒有格子（C1 已對照）。

- **F1 — 全面路網** ✅（ARCHITECTURE 決策 44；[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-f1全面路網)）：
  - GameCore：車站可以不佔方格，放在世界座標的任意一點，月台仍在路網的邊上（S4、S5）。既有的方格車站與方格規則不變，舊存檔與 golden 的預期值不變。golden schema 26（`buildStationAt`、手算的 `free-station.json`）。
  - 車站的規模改由月台的數量與長度表示；S2 的多格車站只留在相容層。
  - App：新遊戲只用路網。拿掉方格的「軌道」「車站」工具（拆除改由路網工具負責），路網的月台工具在月台旁建自由的車站，取代 C1 的「月台中點下方的格子」；地圖不再畫格線，方格只剩地圖的邊界。車站改以 ID 選取：點地圖時選觸控範圍內最近的車站，列車工具與新路線都用選取的車站。
  - C2 加的方格轉轍器、平面交叉與方格的單雙線資訊，隨方格工具一起從 App 拿掉；路網上對應的做法（節點上的多條邊、共用節點）在 C1 已經有。
- **F2 — 側向淨空** ✅（排在 E2 之後、U-min 之前）：平行的兩條邊中心線距離小於線間距時拒絕（S4 的留給之後）。線間距照參考，開工時查（三份參考都沒有，見 F2a）；會改到差分 campaign 的參考模型。淨空規則在讀檔時也會檢查，所以要決定 C4 之後的舊存檔怎麼處理（例如只檢查新版本的存檔）。
  - **F2a — 線間距的規則** ✅（ARCHITECTURE 決策 52；[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-f2線間距)）：三份參考都沒有線間距的規則，所以自訂：同一高度（高差不到 512）的兩條邊中心線至少相距 256（4 公尺，參考最寬的車 3.38 公尺加上餘裕），比這近的兩點沿著軌道必須在 32768（512 公尺）以內，也就是同一個交會點分開的軌道（轉轍器、連續轉轍器、平面交叉）；以每 64 一個檢查點到另一條邊取樣折線的精確整數距離、與沿路網的最短路判斷。太近的新邊拒絕（`trackTooClose`，在 `trackConflict` 之後），會留下太近的邊對的拆邊也拒絕（`tracksWouldBeTooClose`）。舊存檔：存檔版本 5，版本 1–4 讀檔時把太近的邊對記成豁免（`spacingExemptions`），之後新的邊一律檢查，拆掉其中一條、或新的邊把它們接近時移除那一對；版本 5 的清單必須正好是太近的邊對。golden schema 29（`trackTooClose`、`tracksWouldBeTooClose`、手算的 `track-spacing.json`；既有的預期值都沒有改變），差分模型另寫一份（`ReferenceSpacing.swift`），新的 campaign digest（因為新的拒絕而改變的七個）：`kernel.differential` 979D0F645263D10F、`network.differential` 522C11BB06DE8425、`network.sections` 16AFAA5E7E07D5B3、`vertical.differential` BD3B629EC84212B4、`timetable.differential` F41C31663544055D、`service.repeating` 15D8F1630F6569A4、`traffic.reservation` 1EF91C7C3C40FE2E；其他十個不變，重播 fixture 也不變。
  - **F2b — 太近的兩段軌道上的列車互相排斥** ✅（ARCHITECTURE 決策 53）：平面上不到 4 公尺、沿軌道超過 512（8 公尺）的兩點（轉轍器分開之前、連續轉轍器之間、F2 之前的豁免邊對），所在的 span 互相妨礙；交通控制下列車不能取得妨礙別台持有的軌道（`trackReserved`、`trainsShareTrack`），會讓兩台已持有的軌道變成互相妨礙的拆邊也拒絕。妨礙是路網的推導資料，蓋邊、拆邊、加減月台時只重算附近的邊對。golden：新增手算的 `track-fouling.json`；`traffic-reservation.json` 的 South 月台移到支線分開之後（原本的位置會讓兩台互相等待），預期值的改變逐一說明。campaign digest 只有 `traffic.reservation` 改變（1EF91C7C3C40FE2E → 9BFD8C82046796A3，開交通控制時因共用軌道被拒絕 113 → 119 次），其他十六個不變，重播 fixture 也不變。
- **F3 — 移除 GameCore 的方格** ✅（2026-10-03 作者決定提前到 F2、U-min 之前，ARCHITECTURE 決策 51；盤點見 [F3_GRID_INVENTORY](research/F3_GRID_INVENTORY.md)）：方格的鐵軌、方格上的列車位置與路徑、方格車站，以及相關的 golden、測試與差分模型。完整移除、不改任何遊戲行為（票價照舊以點車站底下的格算距離；一格 1024 單位不變）；手做、含方格內容的舊存檔在 F3c 之後拒絕。
  - **F3a — golden 搬到路網**（GameCore 不動）：4 份只用方格車站的改成點車站 ✅；12 份規則和軌道無關的在路網上重寫，預期值的變化逐一說明 ✅（[GoldenScenarios/README](../GoldenScenarios/README.md#f3fixture-搬到路網schema-不變)）；只有一部分能搬或只屬於方格的 9 份，能表達的規則寫成路網的 golden ✅（六份 `network-*.json`），方格的原檔留到 F3c。
  - **F3b — 測試搬到路網**（GameCore 不動）：只把方格當布景的單元測試搬到路網 ✅（F3b-1，預期值的變化與暫時沒改的地方見 [F3_GRID_INVENTORY §7](research/F3_GRID_INVENTORY.md#7-f3b-進度)）；路網的世界產生器、campaign 與存檔變異 campaign ✅（F3b-2，新的 digest 與改了的量下限在 §7.3）；方格本身是主題的 campaign 留到 F3c。移植參考的 desync 重播：五份 [`ReplayFixtures/`](../ReplayFixtures/README.md)，F3c 必須原樣重播 ✅（F3b-3）。
  - **F3c — 刪掉方格** ✅：GameCore、GamePresentation 與 App 的方格程式，golden schema 28，`Web/WasmProbe`。
    - **F3c-1 — 方格才有的查詢先有路網版** ✅：區段（`networkSections()`，移植參考 `topology.js` 的 `trackGroups`）與單雙線（`parallelTracks` 也數路網）；路線面板的單雙線在路網世界不再一律是「方格上沒有軌道」。細節與暫時沒有改的地方見 [F3_GRID_INVENTORY §8](research/F3_GRID_INVENTORY.md#8-f3c-進度)。
    - **F3c-2 — GamePresentation 與 App 不再用方格** ✅：方格工具、方格選取與文字、方格繪圖與「選取北邊的格子」的 VoiceOver 動作拿掉；放置方向改成 GamePresentation 自己的 `CompassHeading`；列車只放在、只送到車站。GameCore 不動。
    - **F3c-3a — 只有方格測試測到的規則，先在路網上測** ✅：移動、位置、選路、停站、節數、單雙線與交通控制共 25 個路網測試（`NetworkRuleTests` 與 `TrafficControlTests` 的新段落），對照表與暫時沒有改的地方見 [F3_GRID_INVENTORY §8.5](research/F3_GRID_INVENTORY.md#85-f3c-3a只有方格測試測到的規則先在路網上測)。GameCore 不動。
    - **F3c-3b — 刪掉方格的測試與 fixture** ✅：方格是主題的單元測試、campaign、存檔變異與八份 golden 刪掉，`free-station.json` 拿掉方格的步驟（餘額 2200 → 2400），`traffic.reservation` 只剩路網（新的 digest），其餘用到方格車站的路網測試改成點車站。GameCore 不動。見 [F3_GRID_INVENTORY §8.7](research/F3_GRID_INVENTORY.md#87-f3c-3b刪掉方格的測試與-fixture)。
    - **F3c-3c — 刪掉 GameCore 的方格** ✅：方格的型別、case、指令、查詢、錯誤與存檔格式拿掉，手做的方格存檔拒絕並說明原因；golden 執行器、差分模型與 campaign 支援一起拿掉方格。fixture 仍是 schema 27，所有 golden、存檔與重播 fixture、campaign digest 都不變。見 [F3_GRID_INVENTORY §8.9](research/F3_GRID_INVENTORY.md#89-f3c-3c刪掉-gamecore-的方格)。
    - **F3c-4 — golden schema 28 與 `Web/WasmProbe`** ✅：fixture 拿掉只能是 `[]` 的 `tracks`、`trail`、`continuation`，其他內容逐一不變；`Web/WasmProbe` 不用改。見 [F3_GRID_INVENTORY §8.11](research/F3_GRID_INVENTORY.md#811-f3c-4golden-schema-28)。
  - **F3d — Remove residual grid semantics（拿掉殘留的方格語意）** ✅（2026-10-04 作者決定，排在 F2b 之後、U-min 之前；ARCHITECTURE 決策 54；[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-f3d拿掉殘留的方格語意)）：
    - 世界 → 連續的世界座標 → 節點／邊／曲線 → 車站的點與月台 → 列車在邊上的位置。世界只有 `WorldBounds`（世界單位，半開區間），驗證、相機、MapKit 框、新遊戲大小、越界檢查與存讀檔都用它。
    - `GridMap`、`GridPosition`、`MapTile`／`TileType`、`Station.position`、`TrainPosition.linkLength`、`WorldCoordinate.tileSize` 拿掉；舊存檔的格只在解碼器裡讀（`LegacyGrid`）。
    - 票價與需求用兩站的點之間精確的距離（Ci 的 `stationDistanceM` 也不量化）；golden 的車站都在格子中心，所以沒有預期值改變。
    - 一格 1024 拆成 `Train.carLength`、`RailwayNetwork.spanLength`、`ConstructionCosts.trackPricingLength`、`MapScale.referenceLength`，比例只有 `WorldCoordinate.unitsPerMetre`（64），數值都不變。
    - GamePresentation 以點與實體選取（`selectedPoint`、`selectStation`、`tapMap`）；VoiceOver 說公里。
    - 存檔版本 6（`"bounds"`），版本 1–5 的地圖讀成 1024 倍的範圍；golden schema 30（`worldWidth`、`worldHeight`、`outOfBounds` 帶點）。
    - 接下來：**U-min（已完成）→ V**。

## Stage E — 大地圖與實景模式

2026-10-02 作者決定：遊戲分成空白與實景兩種模式，地圖要大。

- **E1 ✅ — 大地圖**（ARCHITECTURE 決策 48；[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-e1大地圖)）：
  - 新遊戲的地圖從 32 × 24 格放大到 1024 × 1024 格（`GridMap` 的上限，每格 16 公尺，約 16 公里見方；F3d 起是 `WorldBounds.maximum`，數值不變）；示範地圖搬到地圖中央。E1 之前的存檔照舊是 32 × 24。
  - 只畫畫面內的部分、依縮放分級顯示細節、雙指縮放與平移（Phase 8 原本列的效能手段，提早做）：CX-4（PR #69–#71）照第 0 步的相機介面做好。效能設定只影響呈現，不影響模擬結果。
  - 「世界座標換成畫面座標」抽成相機（`MapProjection`、`PlanCamera`，第 0 步，[UI_INTERFACES.md](UI_INTERFACES.md)）：空白模式由我們的相機決定，E2 的實景模式原本設想由 MapKit 的相機決定（E2 改成由我們的相機帶著 Apple 地圖，決策 50），E2 就不用重寫畫面。
  - **存檔版本 2**：地圖只記、只存不是空地的格子。改之前 16 公里的空地圖存檔 13.6 MB、編碼 3.6 秒（Linux debug），改之後幾百位元組；版本 1 的存檔照舊讀得進來，`SaveFixtures/` 多一份版本 2。GameCore 的規則、golden 與 property digest 都沒有改。
  - **相機**：打開遊戲時對準已建的路網與車站（參考的 `fitBounds`），沒有東西時在地圖中央；縮放按鈕每次 × 2（參考的一個縮放等級）。
  - **教學**：第三步「移動與縮放地圖」，玩家捏合、拖曳或按縮放按鈕才前進（參考的教學沒有這一步，文字照它說明畫面的縮放與移動）。
  - 還沒有：相機不存檔（每次打開都對準已建的部分）；車站與節點的觸控查找沒有空間索引。
- **環線 ✅**（2026-10-03 作者要求；ARCHITECTURE 決策 49；[參考對照](RAILWAY_REFERENCE_MAPPING.md#環線)）：
  - 路線可以設成環線（`Ci/` 的 `isRing`）：列車從最後一站接著開回第一站、從不折返，依 ID 順序輪流走內環與外環；一圈是各段加上每站 1 分鐘，每個方向跑列車數的一半、各自派車；列車數是偶數；乘客搭兩個方向都可以，只要這一圈會到。
  - golden schema 27（手算的 `ring-line.json`）、差分模型重寫一次環線的規則；**存檔版本 3**（舊 build 會把環線當成兩端折返，所以說「較新版本的存檔」），`SaveFixtures/` 多一份版本 3。
  - 路線面板的「環線」開關；環線的列車數每次加減 2，顯示每個方向的列車數與班距。
  - **示範地圖**：Central 在地圖正中央，地面的 Line 1 與高架的 Line 2 在 Central 上下交會；環狀線繞 Central 經過西、北、東、南四站，內外兩圈軌道各給一個方向，每站三個月台（一站多月台、不同高度）。建造後剩 $ 708,800，夠教學在旁邊蓋第一條線。
  - 列車停在路線經過的第一個合適的月台；指定月台是 Stage V。還沒有：環線快車、列車沿一圈連續繞行（參考的時間相位）、乘客走較短的方向。
- **實機回饋的修正**（2026-10-03，環線的 TestFlight）：
  - iPhone 直向的地圖固定佔 HUD 以下的一半高度，控制項在下面捲動（iPad 直向本來就這樣）。原本地圖拿控制項剩下的高度，列車狀態、載客這些每分鐘變長變短的文字會改變地圖的高度，地圖的內容跟著上下飄移；控制項比剩下的空間高時還會疊在一起。
  - HUD 的時間在大字型下會被截成「第 2 日 · 07…」：放不下時時間自己一行。
  - 選取工具點列車就選到它（車頭或車身在觸控範圍內，最近的一列），檢視列顯示列車、停在哪站、載客與路線；列車工具點列車改選那列車，保留要送去的車站。手指下（觸控範圍的一半內）有車站時選車站，所以點車站的標記永遠選到車站。
  - 時刻表每一站的加減與「在此折返」至少 44 點高，不再疊在一起。
- **E2 ✅ — 空白／實景兩種模式**（ARCHITECTURE 決策 50；[參考對照](RAILWAY_REFERENCE_MAPPING.md#stage-e2實景地圖)）：
  - 開始畫面的「新遊戲」是空白地圖；新的「實景地圖」打開選點的畫面：Apple 地圖上畫出 16 公里的方框，下面是 64 個地點（`Railway/` 的 11 個台鐵主要車站與 `Ci/` 的 53 座城市）與搜尋。玩家把地圖移到想要的地方，按「在這裡建造」，地圖中心就是世界的錨點。
  - GameCore 只多一個地理錨點（`GeoAnchor`：地圖中心的經緯度，整數的千萬分之一度），沒有規則讀它；模擬只用世界座標，deterministic 不受影響。**存檔版本 4**（舊 build 會丟掉錨點，所以說「較新版本的存檔」），`SaveFixtures/` 多一份版本 4。
  - 遊戲裡 Apple 地圖畫在鐵路下面，跟著遊戲的相機（平面、北朝上）；手勢、縮放與教學和空白地圖相同。左下角選地圖的樣式（地圖、衛星（含標示）、衛星）。
  - 讀過 Apple 的 MapKit 條款（Apple Developer Program License Agreement 的 Attachment 6）：Apple 的標誌與法律聲明放在地圖底部一條遊戲不蓋的帶子裡；搜尋結果不存，只存玩家停下來的地圖中心；地點清單用參考自己的資料。
  - 還沒有：地圖旋轉與傾斜、3D 建築與地形；中國大陸的 GCJ-02 換算（E3 時處理）；沒有網路時的提示；依城市的票價基準與真實人口（Phase 5、6）。
  - 畫面層的「地圖背景」（`AppleMapBackground`）只在 App；E3 可以換成 MapLibre，不動 GameCore。
  - 實機：2026-10-03 作者在 TestFlight 上確認可以使用。
- **台灣的真實鐵道 ✅**（2026-10-05，作者要求從私有 repo 直接移植；ARCHITECTURE 決策 50；[參考對照](RAILWAY_REFERENCE_MAPPING.md#實景地圖的台灣鐵道與車站)）：
  - 實景地圖照 `Railway/` 網站畫出台灣的鐵道路線與車站（台鐵、高鐵、阿里山林鐵、各地捷運與輕軌，網站的原檔），在道路之上、地名之下；顏色一律是官方色：捷運與輕軌用各線的官方路線色（營運機構官網或 TDX），台鐵、高鐵與阿里山林鐵統一用公司色（作者要求不用網站的代表色、不自製）；地圖樣式選單的「真實鐵道」選自動、淡化（預設）或隱藏。
  - 選點的畫面多了全部 544 個車站，依系統分組，打字時即時比對站名。
  - 資料來源與授權的畫面（開始畫面、地圖樣式選單）：交通部 TDX（政府資料開放授權條款第 1 版）與 OpenStreetMap（ODbL 1.0）；地圖底部顯示短標示。
  - 只動 App 與 GamePresentation：GameCore、golden 與存檔都沒有改。
  - **實景示範地圖 ✅**（作者要求，方便之後測功能）：開始畫面的「實景示範地圖」把平溪線、宜蘭線（四腳亭–三貂嶺）與深澳線照真實路線蓋成遊戲的軌道，四台列車開局就在跑；單線加瑞芳、猴硐、三貂嶺、十分的待避線，可以直接測 V3 的交會與待避、之後的 V4。
  - **依最近的真實車站替新車站命名 ✅**：在實景地圖上建新站時，依 5 公里內最近且未使用的真實車站建議中／英文站名。
  - 還沒有：真實鐵道只在台灣；玩家自己沿真實路線自動建造（實景示範地圖的擬合可以重用）；示範地圖的雙線。
- **E3 — MapLibre**（視需要，不佔固定的位置）：E2 實測之後，MapKit 不夠用時（例如每座城市都要 3D 建築、自訂樣式、離線圖磚）才加入。
  - **第一步 ✅**（決策 97，2026-10-08 作者：底圖先換 OSM）：地圖樣式選單多一個「OpenStreetMap」，MapLibre Native 6.31.0 畫 OpenFreeMap 的 Positron／Dark，標籤用玩家的語言，真實鐵道照舊畫在上面；預設仍是 Apple 地圖，實機確認後再決定。之後：傾斜與 3D 建築、地形、隱藏軍事設施的標示、選點畫面也換成 OSM。
  - `Ci/` 用的就是 MapLibre 加 OpenFreeMap 的圖磚（中國用高德），3D 建築用 fill-extrusion。
  - MapLibre Native 是 BSD 2-Clause 授權，免費，要在 App 裡附上授權聲明；iOS 有 SwiftUI 的包裝。
  - OpenFreeMap 的公開服務免費、不用註冊或金鑰、不限次數、可以商用，要標示「© OpenMapTiles Data from OpenStreetMap」；沒有服務保證。
  - 這是新的第三方依賴，加入時要寫進 ARCHITECTURE。
- 實景模式的真實人口與起訖需求屬於 Phase 5A 與 Phase 6，資料來源依 [WEB_REFERENCE_STUDY](WEB_REFERENCE_STUDY.md#來源與使用方式) 的規則。

## G1 — 第一個能玩的經營閉環

插在 T 與 U 之間（2026-09 決定）。目標：玩家蓋一條線，就能因為有人搭車而賺錢。它不是完整的 Phase 5–7，而是從中各取最小的一片，之後在它上面深化。

```
車站的需求 → 起訖（OD）與整數釋出 → 車站排隊 → 列車上下車 → 抵達 → 票價收入 → 現金
```

- **需求來源**（5A 的最小版）：車站依類型（住宅、辦公、商業、景點）套用每小時的需求曲線。照 `Ci/` 的 `buildStationFlowPresetCurves` 翻譯；這還不是城市模擬。
- **起訖與整數釋出**（5B）：保留餘數，讓一天的總量完全精確；同時發生的釋出依 (tick, 起點, 迄點) 排序。乘客守恆的稽核從這裡開始。
- **路徑**：只坐同一條路線，不做轉乘與多條路線的選擇（5C、5F 延後）。
- **車站排隊**（5D 的最小版）：依路線、方向與目的地分組，先進先出；有收容上限，超過的人記入溢出計數。
- **上下車與容量**（5E）：列車停在車站時上下車，在 `advance` 每個基本步長的固定階段執行；容量 = 輛數 × 每輛定員；記錄被拒絕上車的人數。
- **票價與收入**（5G 的最小版）：單一票價或依距離分段，以 `Money` 整數計算。
- **帳本**（Phase 7 的最小版）：每一期只結算一次，各類別加總精確等於總額。G1 只有票價收入與營運成本兩類。
- **畫面**：車站的候車人數、列車的載客、收支。
- **依賴方向**：遵守 ARCHITECTURE 的「GameCore 內部的依賴方向」。乘客只讀車站、路線、服務、停站與執行進度的查詢，不讀軌道、預約或列車的移動。
- **參考**：每一部分開工前照規則讀 `Ci/` 的相關程式，PR 附對照表。城市的土地使用與成長是 gap：`Ci/` 的需求來自真實人口資料與伺服器算好的起訖，伺服器的程式不在快照裡。人口資料依 [WEB_REFERENCE_STUDY](WEB_REFERENCE_STUDY.md#來源與使用方式) 的規則可以匯入，但 G1 先不做。
- **預計拆成幾個 PR**：
  - G1a ✅：需求、釋出、排隊與守恆（ARCHITECTURE 決策 34）；
  - G1b ✅：上下車與容量（ARCHITECTURE 決策 35）；
  - G1c ✅：票價、帳本與畫面（ARCHITECTURE 決策 36）。
- **不做**：城市成長、轉乘、路徑選擇、貸款、依等待時間重新選路。票價彈性原本不做，但參考有完整的公式（`metroFareDemandPenaltyForFare`），依「能移植就移植」在 G1c 一起移植，只在玩家設定過票價時生效。

### G1a — 需求、釋出、排隊與守恆 ✅

照 `Ci/` 的 `buildStationFlowPresetCurves`、`metroSpawnPassengersFromDispatchRuntime` 與 `_metroAdmitDispatchPassengers` 移植，全部改成整數（ARCHITECTURE 決策 34）。

- **需求**：`setStationDemand` 設定車站的類型（住宅、辦公、商業、景點）與每天的旅次（0 到 1,000,000），`nil` 清除；免費。
- **每天與每小時的旅次**：起點一天的旅次分給同一條路線能到、自己有需求的車站，依它們的旅次；再依一天的形狀（參考的 `PEAK_FACTOR`）× 起點的出發曲線 × 迄點的到達曲線分到 24 小時。兩次都用最大餘數法，合計完全精確。參考的基數是伺服器算好的 OD，快照裡沒有，這是 gap。
- **釋出**：每個基本步長一開始，每一對依這一小時與下一小時內插釋出這一分鐘的份，保留不到一人的餘數（存檔）；任何連續 1440 分鐘正好釋出一天的旅次。同時發生的依（分鐘、起點、迄點）的順序。
- **排隊**：依路線、方向、迄點與分鐘成組，先來的在前；一站最多 4000 人（參考的 500 × 8），放不下的記進溢出。
- **守恆**：每一站 `released = 等車 + overflowed + abandoned`；路線刪除或改停靠而不再載某一組時，那一組記進 `abandoned`。存檔驗證、每個 campaign 的不變量都檢查。
- **沒有需求時行為不變**：既有 golden 的預期值與 property digest 不變；golden schema v20 新增 `setStationDemand`、`invalidStationDemand`、四種乘客的觀察、最終狀態的 `passengers`，以及手算的 `station-demand.json`。
- **還沒有**：上下車（G1b）；票價、帳本與畫面（G1c）。

### G1b — 上下車與容量 ✅

照 `Ci/` 的 `updateTrainAtStation`、`metroResolveTrainAlighting`、`allocateSeats` 與 `getMetroTrainOperationalCap` 移植，全部是整數（ARCHITECTURE 決策 35）。

- **容量**：每輛 352 人（參考 6 輛 1920 人的每輛 320 人 × 營運超載 1.1），`Train.capacity` = 輛數 × 352。
- **時機（過渡做法，W2b 已取代：ARCHITECTURE 決策 39）**：列車每離開時刻表的一站處理一次，先下車、再上車；停站期間來的人都搭得上。派車與出發之後、移動之前的固定階段。這不是永久的語義：W2 以已移植的秒級停站規則取代。
- **停站時間的規則（純計算）**：`Ci/` 與 `Railway/` 兩邊找到的停站、車門、高鐵停站分鐘與觀測停站的規則都移植到 `StationDwell`（捷運 36 秒、終點 42 秒、車門 8／8.3 秒、預設 25 秒、最短 15 秒等），每一個都和參考的 JavaScript 在 Node 執行的結果比對過；還沒有接到 `advance`。
- **下車**：坐到這一站的人下車，記進起點的 `arrived`。
- **上車**：只有路線的列車；那一站等它的路線與方向、迄點是它到下一次折返前會停的站的人，下車站遠的先上，同一迄點先來的先上，最多到容量；上不去的人數記進那一站的 `refused`（次數）。pattern 不停的站的人繼續等。
- **提早結束**：離開路線的列車照舊載到迄點，但不再載新的人；它的服務被停止時，車上的人記進 `abandoned`。
- **守恆**：每一站 `released = 等車 + 車上 + arrived + overflowed + abandoned`；存檔驗證、每個 campaign 的不變量都檢查。
- **沒有需求時行為不變**：既有 golden 的預期值與 property digest 不變；golden schema v21 新增 `riders` 觀察、帳本的 `riding`、`arrived`、`refused`、最終狀態的 `riders`，以及手算的 `boarding.json`。
- **gap**：`refused` 與起點的守恆（參考沒有）；依乘客人數、上下車速度或車門決定停站時間的規則兩邊都沒有（`Ci/` 的 `BOARDING_RATE`、`TRAIN_DWELL_TIME` 只有定義、沒有被讀取，以原值保留）；轉乘（5F）與環狀線不做。
- **還沒有**：票價、帳本與畫面（G1c）。

### G1c — 票價、帳本與畫面 ✅

照 `Ci/` 的捷運經濟舊路徑（`metroEconomyAccrueHourlyFare`、`metroEconomyAccrueDeparture`、`metroEconomySettleHourlyIfNeeded`、`metroEconomySettleDailyForEndedDay`、`metroFareDemandPenaltyForFare`）移植，全部是整數美分（ARCHITECTURE 決策 36）。

- **模式**：新的世界是自由模式（不收、不記，之前的行為與存檔完全不變）；App 的新遊戲是經營模式。
- **票價**：均一（預設 5 美元）或依兩站直線距離分段（編輯器的預設 5 段），0 以下收 5 美元；上車時依迄點收，四捨五入到整美元。
- **結算**：每個整點結算營運與維修，每個午夜結算前一天的能源與人事；餘額可以變成負數。帳本保留 50 列，每日的帳保留 720 天（兩年，讓年報表的上期完整），報表有日、週、月、年的本期與上期。
- **需求**：設定過票價時，每對車站的旅次乘上票價的影響。
- **畫面**：HUD 的美元餘額開啟經濟面板（模式、票價、最近一小時、報表、帳本）；檢視器顯示每站依路線方向的等車人數，列車控制顯示載客率。
- **golden**：schema v22 新增 `setEconomyMode`、`setFareRules`、`invalidFareRules`、`tripFare`、`accounts`、`financeReport` 觀察、最終狀態的 `accounts`，以及依規則獨立計算的 `economy.json`；既有 fixture 的預期值不變。
- **gap 與之後**：開局資金（參考的 `economy.js` 不在快照裡；G1d 已訂）、配額建設（需要決定）、高鐵與航空的結算、賠償與退票、貸款。

### G1d — 經濟平衡 ✅

2026-10-03 核對經濟的平衡（作者交給 Claude Code 決定做法，ARCHITECTURE 決策 46，[對照](RAILWAY_REFERENCE_MAPPING.md#g1d經濟平衡)）。G1c 的公式照參考的舊路徑都對，但開局資金、建設價格、補貼都在快照沒有的經濟引擎裡，所以示範地圖一天就賺開局資金的 29 倍、儲存同樣的 $ 5 票價乘客剩 1%。

- **更正移植**：車站數改成每條路線各算一次；0 元的票價對需求算基準（1000‰）。
- **城市的基準票價**：公司有自己的基準（參考依城市換），App 的新遊戲是標準票價 $ 5，所以預設與儲存同樣的票價都不改變需求。
- **車廂收費**：每加一節收 `ConstructionCosts.car`。
- **新遊戲的價格**：開局 $ 3,000,000；地面軌道每公里 $ 100,000、車站 $ 200,000、列車 $ 150,000、每加一節 $ 40,000；合理的第一條線約 10 個遊戲日回本。
- **經營模式的運量**：照參考，只有自由模式能改；經營模式的新車站由城市給住宅區每天 10,000 人次；經營只能切到自由，不能切回。
- **還沒有**：參考的經濟引擎（作者能補上時照原樣移植）、城市人口決定的運量（Phase 5）、每節容量與候車上限照參考（另外處理）、配額。

## Phase 5 — Passenger simulation

G1 先做了 5A、5B、5D、5E、5G 的最小版；這個 Phase 在它上面深化。

乘客以群組（例如 `{ 起點, 迄點, 時段, 人數 }`）儲存，而不是一人一個物件。所有數量都是整數，每個 Stage 都有自己可以獨立測試的 deterministic 契約。

**2026-10-06 跨站步行與新遊戲啟用（決策 65）**：兩站相距不到 450 m（`station_transfers.json` 的條件）可以步行轉乘，時間是 4 分鐘加每 80 m 一分鐘；App 的新遊戲改用 `.network`，示範地圖的乘客在 Central 與環線之間換車。路徑計畫共用路徑圖、改用堆積、以衍生路徑圖為鍵記住每對 OD 的選擇。仍缺：站內通道／同月台分級成本、封站 operationMode、資料明確 pairs 匯入（列為 gap）。

**2026-10-06 R1（來源轉乘常數與封站）**：轉乘常數改用 `Ci/` 來源值並集中在 `PassengerTransferRules`：同站換線 12 分鐘、跨站依 ≤20／≤50／≤250 m 分級（15 分鐘 × 0.8／0.8／1.2／1.7）、步行 5 km/h、實際換車 max(120 s, 步行)；車站營運狀態 normalFlow／flowControl／closed（只在非 normalFlow 時存檔，存檔版本仍為 11）；網路計畫只在輸入改變時重算。R2（原生，來源無公式）：`.network` 的選路權重加入擁擠（BPR 0.15×負載^4，上限 2；供給 = 班次 × 列車容量，預設 6×352），OD 需求超過 30 廣義分鐘按比例遞減。城市成長沒有消費者（Phase 6），列為 gap。R3：路線面板的「跨線乘客路徑」開關（`GameSession.setPassengerRoutingMode`），golden schema 35 的 `setPassengerRoutingMode`／`setStationOperationMode` 與 `network-passengers.json`，replay `network-economy.json`；新遊戲照 #151 預設 `.network`。

**2026-10-06 的 5F WIP（PR #142，已合併）**：已接上同 StationID 的完整旅程、換車、原起站守恆帳與 v11 存檔；需求可顯式選 `.network`。接手補上服務開／收班、尖峰與跨午夜的批量一致性、多路徑同分鐘存檔、pattern 移除時的索引移轉、軌道／月台失效、轉乘溢出、反向與環線跨圈測試。跨 StationID 步行、封站狀態與同月台／站內通道分級尚未接上，新遊戲仍是 `.direct`。尚未完成 5F，也未合併；驗證與下一步見 [PHASE5_TRANSFER_HANDOFF](PHASE5_TRANSFER_HANDOFF.md)。

- **5A — 需求來源**：在城市模擬之前，每個車站依類型（住宅、辦公、商業、景點）套用每小時的需求曲線，權重以千分比整數表示。車站等級（真實時刻表研究）決定需求與車站規模的預設值：情境轉換工具依等級決定車站的格數（Stage S2 的多格車站）。
- **5B — OD 與時段需求**：
  - 以整數釋出並保留餘數，讓一天的總量完全精確；
  - 同時發生的釋出依 (tick, 起點, 迄點) 排序；
  - 從這裡開始做乘客守恆稽核。
- **5C — 路徑選擇**：
  - 網路或服務改變時，預先計算每個 OD 的幾個路徑選項；
  - 成本以整數分鐘計算，包含候車、乘車與轉乘懲罰；
  - 分配人數用最大餘數法，以索引決定平手，不用亂數；
  - 可以在背景對世界的快照計算。
- **5D — 車站佇列**：依方向與目標分組、先進先出；有收容上限，超過的人記入溢出計數。
- **5E — 上下車與容量**：
  - 列車記錄「在哪一站下車」的人數；
  - 容量 = 輛數 × 每輛定員；
  - 記錄被拒絕上車的人數。
- **5F — 轉乘**：
  - 依距離分出轉乘的等級（同月台、步行通道），各有轉乘懲罰；
  - 同一條線裡快慢車之間的轉乘不算轉乘。
- **5G — 票價與收入**：
  - 單一票價與依距離分段的票價，以 `Money` 整數計算，並記錄收入歸屬；
  - 如果採用票價彈性，用查表，而不是浮點公式。

**2026-10-06 車種（決策 66）**：列車可以選來源 `TRAIN_TYPES` 的九種車種，容量 = 節數 × 每節額定 × 1.1，門數決定上下車速度；沒有車種是標準車。依車種的購車價格與營運成本在 Phase 7。

**2026-10-06 每週需求與事件（決策 68、69）**：新遊戲每天的旅次依來源的星期係數變化，週末依週末時段；展覽與大量人潮事件由存檔種子抽出、提前公布、提高車站需求。中斷（停駛、封站）與國定假日仍是 gap。

## Phase 6 — City simulation

**地圖方針（2026-09 決定）**：主要模式用虛擬地圖，走《A列車》「鐵路帶動城市成長」的路線。

- **虛擬地圖**：手工設計的情境地圖，加上由種子產生的地形。存檔只需要種子與玩家的修改，而且結果固定。
- **真實藍本情境**：之後可選擇加入。以真實的地形與人口為藍本，由 GameCore 以外的轉換工具產生同一種格子格式。資料來源必須能合法使用，例如政府開放資料，或標示來源的 OpenStreetMap。第一個候選（平溪線）見 [TIMETABLE_DATA_STUDY.md](TIMETABLE_DATA_STUDY.md)。
- **GameCore 不區分地圖從哪裡來。**
- **不以真實地圖為主模式的原因**：
  - 真實城市已經開發完成，「車站帶動成長」的循環會變弱；
  - 難度與情境不好設計；
  - 目前的鐵軌只有東西南北四個方向；
  - 真實資料有授權問題，也會讓離線 App 變大。
- **對之後的影響**：
  - 本 Phase 的第一步是「地形與初始城鎮」，同時決定一格代表多少距離；
  - 5A 與本 Phase 的資料模型以「土地使用格子」為準，兩種地圖都適用；
  - 是否支援八個方向的鐵軌，另外決定。
- **2026-10-02 更新**（作者決定，見 [Stage F](#stage-f--全面路網與自由擺設)、[Stage E](#stage-e--大地圖與實景模式)）：
  - 遊戲分成空白與實景兩種模式（E2）。空白仍是「鐵路帶動城市成長」的主要玩法；實景的背景是線上的 MapKit（或 MapLibre）地圖，只是畫面，不打包地圖資料，所以不會讓 App 變大。
  - 鐵軌已經是任意方向（S3、F1），上面「目前的鐵軌只有東西南北四個方向」與「八個方向的鐵軌」不再適用。
  - 車站與土地自由擺設（F1），土地使用不再綁鐵軌的方格；要用多邊形還是看不見的細網格，在本 Phase 開始時決定。車站的服務範圍改以距離計算。

**2026-10-06 城鎮成長的第一步（決策 70）**：經營模式下，服務好、可達車站多的車站每天成長（最多 1.5%／日、起點的 4 倍），沒有服務的慢慢衰退回起點。土地使用、建物、地價與產業仍待做。

**2026-10-07 6a 土地（決策 72）**：作者決定開始土地使用與建物，採用研究文件（PR #172）審查時的建議。拆成：

- **6a 土地 ✅**：64 m 的隱藏網格，每格一種用途（住宅、商業、辦公）與居民、就業；空白新遊戲由種子產生三座起始城鎮，實景新遊戲把 WorldPop 的人口分到格（沒有人口資料的地方同空白）；車站 800 m 腹地的查詢；存檔版本 12、golden schema 36。空白地圖的人口圖層畫土地，車站面板顯示腹地的居民與就業。規則還不讀土地。
- **6b 需求由土地推導 ✅**（決策 73，作者交給 Claude Code 決定）：經營模式的新遊戲每站運量由腹地的居民與就業推導（每 100 個每天 40 旅次，類型取最多的），重疊腹地依距離分；午夜服務好的車站讓腹地人口成長、往車站蓋新住宅格；實景就業由 OSM 地點換算；自由模式、舊存檔與示範地圖照舊。起始城鎮密度加倍，第一條線約 8 天回本。
- **6c 建物、容量與地價**：建物先以佔用的格表示（任意輪廓只在畫面層）；地價先即時推導、不存歷史；費用與 Phase 7 分開。研究文件 PR #174（`docs/research/PHASE6C_BUILDINGS_STUDY.md`）建議拆成三步：
  - **6c-1 城市建物、容量表與初始化 ✅**（決策 74）：一般建物由城市自動產生（沒有玩家指令），只存編號、種類（一般／既有存量）、用途、密度 D1–D4 與佔用的格，一棟一格；三種用途 × 四級密度的容量表（每層 1536 m²、居民 48 m²、就業 32 m²、2／6／18／40 層）；依主要用途的人數選最低足夠的密度，另一項不裁人，四級都放不下時為既有存量；`setCityBuildings` 開關（App 的新遊戲開啟），與 `setLand`、`foundTowns`、6b 的擴張同步；存檔版本 13、golden schema 37。成長上限仍是 400／1200。車站面板顯示 800 公尺內各密度的建物數。
  - **6c-2 容量接上成長與自動升級 ✅**（決策 75）：城市建物開啟時以建物容量取代 400／1200（居民、就業各自限制，放不下的捨棄）；`TownGrowth.Place` 的 `lastService`／`lastReached`；服務 ≥ 80%、可達 ≥ 1 站的成長中車站每晚依列、行升級腹地裡午夜開始已滿的 D1–D3 一般建物，每站 2 格、每格一天一級；存檔版本 14、golden schema 38。車站面板顯示腹地各密度的格數與昨日的服務、可達。
  - **修正（決策 77）**：滿格只看主要用途；關閉的車站不分土地、不決定地價。
  - **6c-3 即時地價 ✅**（決策 76）：`landValue(row:column:)`，用途基準 × 密度係數 ＋ 最好車站的服務（15 × S）與可達（1000 × A），夾在 $5…$500／m²；只是查詢，不存檔、不影響成長；golden schema 39。
- **6d 畫面 ✅**（決策 76）：地圖圖層表的用途、地價、腹地涵蓋三個圖層（和人口、旅次同一組，一次一個；只畫畫面內、縮小時合併區塊），點格的提示框、車站面板的腹地平均地價；實景地圖開用途圖層時底圖變淡。
- **6e 八種土地用途 ✅**（決策 91，2026-10-08 作者：「一次補完全部」）：`LandUse` 從三種（住宅、商業、辦公）擴充成研究文件列的八種：加上工業物流、學校與公共設施、觀光休閒、農業、公園。用途和密度（D1–D4）分開，城市風格（Phase 8）不在這一步。車站需求多一種 `civic`（新的學校曲線：7 點到、16 點走）；工業與農業的就業照辦公的通勤；公園沒有人，400 m 內每格地價加 $6／m²。空白地圖的城鎮在核心外抽出學校、觀光、公園與工廠，外面一圈是農地；實景把學校與觀光景點分開計算（以前併進辦公與商業）。存檔版本 20，golden schema 40（`land-uses.json`；`land-towns.json` 與 `city-buildings.json` 的城鎮值逐項改變並說明）。之後：
  - **地形與土地狀態**：海、河、山不是用途，另外一層。決策 96 以玩家的角度定了其他土地：森林與保護區不是障礙（山線要能蓋，造價看坡度與高度）；墓地不長城鎮、軌道可以付遷葬費通過；軍事區不建模。
    - **第一步：水域 ✅**（決策 105，2026-10-09）：GameCore 的地形層（`GameWorld.terrain`，每列的水格段）；實景地圖的海（OSM 海岸線，內政部的海岸線只用來核對：它畫到低潮線，潮間帶算陸地）與河湖（`natural=water` 等，魚塭除外），打包成 `taiwan_water.json`（1.875″ 格，涵蓋本島、澎湖、金門、馬祖）。水上：城鎮不擴張、不升級，玩家建物拒絕（`onWater`），水格不劃分區；鐵路與車站先不擋。全台灣地圖的水跟著區塊讀入，順序不影響結果。空白地圖先不產生水。存檔 24、golden schema 44。
    - **第二步：水岸 ✅**（決策 111，2026-10-09，參考作者給的 SimCity BuildIt 海岸截圖）：只能蓋在岸邊的漁人碼頭（商業）與遊艇港（觀光），一部分在水上、一部分在陸地；水邊 160 m 內地價加 $6／m²，劃了分區的海邊與河岸先被開發。存檔 25、golden schema 45。
    - **第三步：陡坡 ✅**（決策 115，2026-10-09）：Copernicus DEM 算出坡度超過 30%（建築技術規則山坡地不得開發的線）的乾格，併入 `taiwan_water.json`；陡坡上城市不擴張、不升級，玩家建物與分區都不行，已有的土地與鐵路照舊。存檔 26、golden schema 46。
    - **第四步：軌道與地形的高度**（設計說明 [TERRAIN_HEIGHT_DESIGN.md](research/TERRAIN_HEIGHT_DESIGN.md)，作者交給 Claude Code 以玩家的角度定案，分 H1–H3）：
      - **H1 地面高度 ✅**（決策 124，2026-10-09）：Copernicus DEM 的地面高度打包成 `taiwan_heights.dat`（1.875″，約 12 MB）；GameCore 以 1 km 區塊存 17 × 17 個 64 m 角點的整數公尺（`setGround`），任一點是整數雙線性內插，沒讀過地面的世界處處是 0 m；路網卡片寫兩端的地面海拔。還沒有規則讀它，新遊戲也還不讀入地面。存檔 27、golden schema 47。
      - **H2 規則與造價 ✅**（決策 124 的 H2，2026-10-09）：新實景遊戲與全島地圖有地面，App 在鋪軌前沿新軌道讀入區塊；節點高度相對地面；新的結構物「自動」（預設）每 16 m 分成地面、路堤、路塹、高架、橋、隧道，短段併入旁邊；過水要橋或隧道，車站不在水上；土方與墩高費跟著軌道費走。空白地圖、示範與舊存檔照舊平地。第一條線第 8 天回本，整條隧道也只晚約 1.5 天。存檔 28、golden schema 48。
      - **H3 畫面 ✅**（決策 124 的 H3，2026-10-09）：建造卡片的縱斷面（地面線、軌道線、各區段的顏色）與費用分項（軌道、土方、高架與橋、隧道、拆遷，加起來就是建造的錢）；地圖上自動軌道的路堤與路塹畫出邊坡；圖層選單多一個「高度與陡坡」（依高度著色、西北光的暈渲、陡坡斜線，點格看海拔）。不改規則，存檔與 golden 不動。
      - 之後：側邊工具列的「橋／隧道」「上／下」、隧道覆土不足的提示。
    - 之後（依序）：玩家挖湖與填海造陸、墓地的遷葬費、空白地圖由種子產生的地形。
  - **工業、公園、農地的真實資料 ✅**（決策 93）：OSM 的 `landuse=industrial`、`leisure=park`、`landuse=farmland` 以面積取樣，加進 `taiwan_places.json` 的 `zones`（`build_zone_grid.py`，來源是 Overpass 或整包 `.pbf`）。實景的 64 m 格落在分區時是公園（沒有人）、工廠（每格 30 個就業）或農地（每格 1 個就業），人口只住在其他格（決策 96 再收魚塭、果園、礦場、高爾夫球場等標籤）。商店、辦公、學校、景點也改從同一份整包檔重算（舊資料多算了廈門的地點）；存檔與 golden 不動。
- **城市建造 P0**（2026-10-08 作者插入，優先於其他城市工作）：玩家能建鐵路，卻不能親手建造城市。分三步，兩套玩法共存（親手蓋指定建物，也劃分區讓城市沿著鐵路自然成長）：
  - **P0-A 直接建築 ✅**（決策 92）：選小住宅、商店或辦公樓，點空地就蓋，地圖上立刻看得到，存檔重開仍在。自由世界座標，不綁 64 m 格；免費、還不住人。存檔 21、golden schema 41。
  - **P0-B 土地分區 ✅**（決策 98）：建築工具的「分區」模式，單點或拖曳劃設住宅、商業、辦公、工業、公共設施、觀光，以及不開發與保留地；分區另存一層（`GameWorld.zones`），不用沒有人的 `LandCell` 假裝。成長中的車站先在地價最高的空分區格蓋那種用途，沒劃分區的地方照舊；玩家建物 400 m 內的分區格地價加 $6／m²（誘導開發）；地圖多「土地分區」圖層。存檔 23、golden schema 43。之後：住商工的需求閥（RCI）、分區改變已有格的用途、圓形筆刷。
  - **P0-C 經營整合**（作者選 A 列車式並融合 SimCity，與 7b／7c 合併，`docs/research/CITY_BUILDING_STUDY.md`；先於 P0-B）：
    - **P0-C1 公司的建物 ✅**（決策 94）：經營模式下建造付樓地板 × $40 加占地 × 地價，記成 30 年折舊的資產；有車站服務時每晚住進居民與就業、帶來運量；每晚收租金、付維護與土地資產稅（損益表的「建物收支」）；建築工具可以切到拆除（付建造費的 10%）。自由模式免費。存檔 22、golden schema 42。
    - **P0-C2 收購、拆遷與預覽 ✅**（決策 95）：擋到的城市建物（格子中央 40 m 見方）以 120% 收購拆除、人搬進來，城市不再在那裡長；軌道（隧道除外）與車站穿過公司建物時付拆除費；建築工具先選建地、看虛影與費用分項，再按「建造」。存檔與 golden schema 不動。旋轉延後到有長方形建物時；出售（售價 95%，賣掉的建物留給城市）在 P0-D。

**2026-10-07 平衡報告**（作者把判斷交給 Claude Code：「對未來開發與遊戲性的最佳決定」）：不靠實機手算，改用無頭模擬量測。`BalanceReportTests`（`BALANCE_REPORT=<天數>` 才跑，release build 幾秒）逐日印出現金、營業利益、回收比例、運量、腹地人口、各密度的格、地價與服務率；以後調平衡都重跑同一張表比較前後。`main` `e7447f4` 的結果：

| 情境 | 回本 | 第 30 天現金 | 第 60 天現金 | 60 天內的城市 |
| --- | --- | --- | --- | --- |
| 第一條線（`NewGameBalanceTests` 的 3 站、448 m、1 車 4 節，$914,800） | 第 8 天 | $6.53M | $12.92M | 運量 33,787 → 64,907／日；腹地人口 84,466 → 162,267；D3 132 → 262 格，D4 第 8 天起停在 45 |
| 示範地圖（$2,291,200，跑 30 天） | 約第 8 天 | $11.64M | — | 30 天內 D4 43 → 187 格 |

判斷（都不改規則，所以沒有新的決策編號、存檔與 golden 都不變）：

1. **回本約 8 天**：合乎決策 46／73 的目標，不調。
2. **回本之後現金一直滾**（一條小線 60 天變成 4 倍）：交給 Phase 7。研究文件（PR #179）的房地產買賣、物業維護與稅、折舊就是現金的出路與再投資；先加出路，再看要不要壓成長率，免得現在調了、Phase 7 又要調回來。
3. **運量不看路線長短與能到哪裡**（800 m 內每 100 人每天 40 旅次，448 m 的線也一樣）：保留，列為 gap。改成依起訖距離與可達性的需求是較大的規則改變，等 Phase 7 之後實機看到玩家真的蓋短線圖利再處理。
4. **地價在開通那天跳約 5 倍（$29 → $151／m²）之後持平**：保留。這正是 Phase 7「先在預定站附近便宜買地、開通後增值」的玩法，研究文件也把即時地價當成交報價；租金依格的居民與就業，城市長大租金就跟著長，不必讓地價自己隨時間漲。Phase 7 實作房地產時再依量測決定要不要加入隨時間的增值。
5. **D4 在第一條線 60 天內沒有增加**：不是 bug，是速度。D3 住宅的平均填滿度 42% → 67%，最滿的一格第 60 天到 98%，所以約第 65–70 天開始出現新的 D4；試過讓放不下的成長轉給有空間的格（決策 75 第 1 項），60 天內的結果幾乎不變，所以不採用。示範地圖的城市較密，30 天內 D4 就多了 144 格。
6. **服務率約每週掉到 83–92% 一次**（第 6–7、13、28、48 天），那幾天營收跟著掉：一列車在運量尖峰載不完，是加車的訊號，不調。

**待觀察：先保留，依實機回饋決定是否修改**（作者 2026-10-07 要求：把握較低的判斷先保留，之後再看）。第 5 項已由決策 129 處理（2026-10-10），另外兩項沒有定案。每次實機測試或開始 Phase 7 時都要回頭檢查；要改時先用 `BalanceReportTests` 量測改動前後，並寫進新的決策。

| 項目 | 為什麼沒把握 | 什麼情況要改 | 可能的改法 |
| --- | --- | --- | --- |
| 第 5 項：D4 的速度 ✅（決策 129） | 開局就滿的 D3 在第 1–7 天升成 D4 之後，成長長出的新 D4 要到第 63 天，600× 下（一天約 2.4 分鐘）是真實時間約 2.5 小時；手機上的玩家可能看不到「鐵路讓城市長高」 | 作者 2026-10-10：一般玩家 1 小時內要看得到 | 已改：車站 256 m 內的站前以三倍的成長率長、九成滿就算滿。新的 D4 第 19 天出現（約 46 分鐘），第 25 天起幾乎每天；回本第 7 天（原本第 8 天）。代價是回本後的現金第 30 天多約 25%（第 2 項）。「升級先挑最滿的格」量不出差別，沒有採用 |
| 第 3 項：短線也載走 40% 的人 | 一條幾百公尺的線就能載走腹地裡的人，玩家可能在人多的地方蓋一堆超短線圖利 | 實機或平衡報告看到短線比長線好賺 | 依起訖距離與可達站數調整需求（需求模型的改變，影響 golden） |
| 第 2 項：回本後現金一直滾 | 一條小線 60 天變成約 4 倍，玩家會擴張所以實際更快；Phase 7 之前大約第 30 天以後錢就沒有意義 | Phase 7 的房地產與費用做完後，平衡報告的現金仍然一直滾 | 壓成長率、提高維護費隨規模增加，或調 Phase 7 的稅與維護 |

模擬的限制：只跑固定的一條線和示範地圖，沒有玩家操作（加車、延伸路線、改票價）。真實的擴張會讓城市與現金都長得更快。
- **示範地圖改用土地決定運量 ✅**（決策 78，2026-10-07，下一版 TestFlight 的實機測試）：空白示範地圖和經營新遊戲一樣由土地決定運量、城鎮成長與建物升級；它的五站都在 Central 附近，所以用自己的城市（新遊戲城鎮的公式，半徑 896 m、中心格 600 人）取代第一座城鎮。運量從固定的 8 萬改為土地推導的約 10.9 萬，示範路網約 7.6 天回本（原本約 15 天）。實景示範保留固定運量（平溪線的運量靠景點，土地推導每天只有約 1.4 萬）。

- residential / commercial / office
- land value
- station influence：車站的服務範圍以格子距離計算
- city growth
- 以城市的土地使用取代 5A 的車站類型需求曲線
- 事件（例如人潮激增、展覽）是獨立的一層：事先預告，亂數由存檔的種子產生

## Phase 7 — Company simulation

- revenue：分類帳，每一期只結算一次，各類別加總精確等於總額
- operating expense：人事、能源、車輛
- construction
- loans
- assets
- 是否採用參考遊戲的建設配額制，在這裡決定；在此之前維持現金經濟

**2026-10-06 貸款（決策 67）**：營運、維修、能源、人事與購車已在 G1c／G1d；這次補上貸款（$100,000 一步，最多 $5,000,000，年利率 5%，每日支付）與財報的利息、淨利。來源沒有貸款引擎，這是原生規則；折舊與資產負債表仍是 gap。

**2026-10-08 P7-1 資產、折舊、資產負債表與年度決算（決策 85）** ✅：經營模式的公司記下每條軌道邊、車站、列車與加購車廂的成本，每個經營中的午夜直線折舊（軌道與車站 20 年、車輛 10 年），拆除與減少車廂記報廢損失；報表照 `Ci/` 的財務儀表板分損益表與現金流量表（營業、投資，加上原生的籌資），資產負債表是現金、三類資產、借款與權益；每 360 天決算一次，存下該年的報表與年底的資產負債表（最多 50 年），遊戲中一年結束時自動打開年度決算。存檔版本 16，舊存檔之前蓋的東西以 0 入帳。之後是 P7-2（公司的土地與建物）與 P7-3（依車種的價格與成本）。

**2026-10-08 目標、挑戰與快轉（決策 86）** ✅：作者交給 Claude Code 依台灣玩家與耐玩性決定。目標系統在 GameCore（連通地點、每日運量、人口、高樓、年度淨利、權益），每個午夜判定，依完成天數給金銀銅牌、超過期限或連續赤字失敗，結束後繼續玩；劇本可以限制年代的車種。加上 6000× 快轉（一年約 1.5 小時）。開始畫面的「挑戰」有三個沙盒挑戰（三鎮連線、鐵道造鎮、鐵道大亨），城鎮每局隨機。存檔版本 17。下一步是台灣鐵道史的劇本：先做平溪線觀光版（實景地圖與參考庫的真實車站），再做劉銘傳鐵路（基隆—台北）與木柵線；運煤史實版等貨運（O10）。

**2026-10-08 每週挑戰（決策 87）** ✅：作者同意的順序是每週挑戰 → Game Center 排行榜與成就（TestFlight 回饋後）→ 官網排行榜（需要帳號與後端，最後）。每週一（台灣時間）換一張所有人相同的地圖，挑戰「三鎮連線」，裝置上保留每個挑戰的最佳紀錄。

**2026-10-08 台灣鐵道史：平溪線（決策 90）** ✅：第一個台灣鐵道史劇本「平溪線：天燈之鄉」，在實景示範的地圖上接手平溪線，目標是每日運量與年度淨利；每年的天燈節讓十分與平溪的需求變成 2.5 倍。存檔版本 19。之後：劉銘傳鐵路（基隆—台北）、木柵線；運煤史實版等貨運（O10）。

## Phase 8 — Advanced rendering

目前的 SwiftUI Canvas 地圖是原型：連續路網的俯視除錯投影（F1 起不畫格線）。最終的 360° 3D renderer 只讀 GameCore 的幾何查詢（`railwaySnapshot()`：世界座標、邊的中心線與縱斷面、結構物、隧道口、月台、列車的姿態與 3D 車身），不回寫，也不讓 mesh、相機或插值進入模擬。

依實際地圖大小與列車數量的效能量測，評估 SwiftUI、SpriteKit、Metal。不預先鎖定 Metal。

呈現的效能手段：依縮放層級分級顯示細節、拖曳時隱藏覆蓋層、只畫畫面內的物件。效能設定只影響呈現，不影響模擬結果。其中「只畫畫面內」與分級顯示提早在 E1 做（2026-10-02）。

E2 的實景模式可以先用 MapKit 的真實地形高度與 3D 建築當立體的背景；遊戲本身的 3D（軌道、結構物、列車）仍在這個 Phase。

## 跨階段議題

- 在地化（**L1 ✅**，ARCHITECTURE 決策 38）：繁體中文（台灣用語）與英文，跟著系統語言切換；用語以參考 `Ci/` 的簡體中文介面為來源。之後新增的畫面文字要同時寫兩種語言：GamePresentation 的文字函式接收語言，App 的字面字串要加進 `Localizable.xcstrings`。
- save/load ✅（C4，決策 45）：存檔版本欄位與 migration。第三份參考建議從一開始就有；F1 之後才做，所以存檔格式一開始就包含自由擺設的車站。
- undo/redo：利用 `GameWorld` 的 value semantics 快照
- 大型地圖與大量列車：E1 先做呈現的部分（只畫畫面內、分級顯示）；模擬的 chunking、背景計算量測後再考慮
- 新的模擬行為同時加入 `GoldenScenarios/` 情境；若日後決定移植到其他引擎，逐一子系統移植並以同一批情境驗證（ARCHITECTURE 決策 13）
- 模擬結果與裝置無關：分片或背景計算都必須得到與一次算完相同的結果，性能模式只能影響呈現（網頁參考研究）
- 隨機性：之後需要時，由存檔在世界裡的種子，以（種子, 用途, 序號）的雜湊產生，不使用系統亂數
- 整數分配一律用最大餘數法，以索引決定平手；乘客與金額的守恆寫成 property 測試
- 分析指標優先由狀態推導，只有歷史彙總才存檔


### Stage V4d 接續（2026-10-05，PR128）

- 已實作，最新 head 驗證中（決策63）：中途全列折返、V2反向倒入側線；正向優先、反向枚舉全部可用berths、完整原子預約與限界／方向保護，dead-end續行取得授權後才翻向。
- 新golden schema34（保留30–33）、save10不變；新768步campaign與實景玩家折返服務。既有fixtures／campaign量／workflow／timeout保留。
- 精確VERIFIED／UNVERIFIED狀態見PR128、接手分支`claude/takeover-and-complete-mp89w9`的draft PR及STAGE_V_HANDOFF。作者合併V4d後才開V4e：地圖上的movement authority、死結車與互等位置，保留文字。

### Stage V4e（2026-10-05，作者合併 V4d #131 後開工）

- 已實作，驗證中（決策64）：地圖畫每車 movement authority（預約軌道，選取車不調暗）、等候車與擋住它的列車之間「等的位置」（contested 軌道，黃；死結紅）、車頭到該處的虛線與等候／死結外圈；列車面板等候文字保留，地圖左上小圖例與 VoiceOver 摘要 `map.traffic`。
- GameCore 只補唯讀查詢 `contestedResources(of:)` 與一次算完的 `routeWaits()`，獨立模型與 deadlock／turnbacks campaign 每步比對；save 10、golden 34、既有 fixtures／workflow／gate／timeout 不變。新 UI 測試只在 full lane。
- V 系列至此完成；之後的號誌、預測授權、死結閃爍與同軌標籤錯位列為 gap（決策64限制）。精確 VERIFIED／UNVERIFIED 見 V4e PR 與 STAGE_V_HANDOFF。

### #100–#147 審查（2026-10-07，PR #164）

對最新 main（1768bff）中 #100–#147 留下的程式做了一次 bug 審查。以重現測試確認的三項已在 #164 修正：

- #104：關閉行車管制後可刪除待避站（passing place）停車中列車需要的月台，或在它車頭下加上目的站月台，存檔讀不回來。現在拒絕這些操作。
- #142：調慢路線性能等改變行程或容量的指令後，沒有車可搭的乘客佇列沒有清掉，存檔讀不回來。現在路線性能、路線偏好、列車派駐／撤離、建軌道與加月台後都會清掉。
- #147：真實台鐵站的月台長度被下一個非真實車站沿用。現在回到預設 4 節。

找到但尚未修正，依建議時機排列（估計時間含場景測試、獨立模型同步與本機驗證，不含 CI 等待）。「早修」的項目會被之後的功能、golden／replay fixture 與存檔固定下來，越晚修要說明的數值越多；「可延後」的項目是局部問題，等相關功能再動時一起修即可：

| 建議時機 | 來源 | 問題 | 狀態 | 估計 |
|---|---|---|---|---|
| ✅ 已修（#169） | #109 | 循環時刻表的 `trafficVisits` 只增不減，存檔與每秒排序成本隨循環增加。 | 記錄時只留目前循環與前一個循環（計畫只讀這些）；GameCore 與獨立模型同步，存檔格式、golden／replay fixture 都沒有變。 | — |
| ✅ 已修（#170） | #116 | 折返站出發後，超越排程的站內路線從到站時的 berth（朝來時方向）出發，找不到待避軌，回程從不安排超越；`scheduledBerthPath` 也以轉向前的車頭算對向方向。 | `trafficTrack`／`trafficTrackDirections` 在折返站先轉向（與 `trafficPoints` 一致），`scheduledBerthPath` 以轉向後的位置計算；獨立模型同步。golden／replay／存檔都沒有變。 | — |
| ✅ 查證非 bug（#171） | #142 | 沒有釋出計畫時，轉乘群組 `readyAt` 在批次跳過的分鐘內不上車（批次與逐分鐘結果可能不同）。 | 以 300 種起始秒數比對，批次與逐分鐘結果完全相同、乘客都到達；保留為回歸測試 `testReadyTransfersBoardTheSameInABatchAsMinuteByMinute`。 | — |
| ✅ 已修（#171） | #141 | `ja.lproj` 只有 App 名稱，語言設定為〔日文, 繁中〕的使用者會得到英文介面。 | 作者決定：日文翻譯量太大（約 257 句介面字串加約 785 句程式內中文），移除日文；以 XcodeGen 2.46.0 重新產生專案。 | — |
| ✅ 已修（#165） | #109 | `resolveDeadlock` 以 `trains[index] = granted` 提交，沒有經過 `setOff`，死結派送的出發不寫入 `trafficVisits`；獨立模型 `ReferenceDeadlock.resolveDeadlock` 有相同缺口。 | 已改為經過 `setOff`，獨立模型同步，附測試（commit `82874a1`）。 | — |
| ✅ 已修（#171） | #120/#131 | `preferredGoingOn` 在盡頭式待避軌不先翻向；獨立模型的 `goOn` 會先依 `passingExit` 翻向再套用路線偏好。 | 建場景時發現更根本的問題：路線對自己唯一的那台車也保護計畫（決策 57 (b)），單線來回的路線列車在死結時連倒入待避線都被自己的去程方向禁止，永遠解不開。改為只對候選車以外的已放置列車保護（GameCore 與獨立模型同步，決策 57 更新）；`preferredGoingOn` 依 `passingContinuation` 翻向。附逐步比對獨立模型的測試（main 上兩車永久死結）。 | — |
| ✅ 已修（#171） | #142 | 轉乘專用站的「留下」計數在紀錄刪除時歸零。 | `isEmpty` 納入 `refused`，解碼器接受只有留下計數的紀錄；附測試（main 上 7283 歸零）。 | — |
| ✅ 防護性修正（#171） | #120 | 自動出發為「到站」（距離 0）但路線偏好讓列車出發時，離站距離記為 0（影響管理模式的列車行駛距離，不是票價）。 | 目前觸發不到（需兩站月台重疊，`addTrackPlatform` 不允許）；改為依列車實際是否出發計距離，所有可達情況結果不變，避免日後共用月台等功能讓它變成真的 bug。 | — |
| ✅ 已修（#171、1a ②） | #143/#147 | 啟動時在主執行緒同步解碼約 2 MB 實景 JSON；`tra_overtake_tracks.json` 解碼失敗會丟掉整個 `stationData`。 | `tra_overtake_tracks.json` 改為單獨解碼，失敗只列為該檔的問題（#171，附測試）。1a ②：啟動時讀的 22 個檔（約 2.4 MB，含 6a 起的人口、地點格）改在背景解碼（`GameLauncher.loadRealWorldData`／`RealWorldData.load`），一次交回 MainActor；讀好前「實景地圖」「實景示範」按鈕停用並顯示讀取中，空白模式不等；人口、地點格讀不到也列在資料來源畫面。Linux 量測（release）約 160 ms。啟動速度 UNVERIFIED，留給 macOS CI 與實機 TestFlight。 | — |
| ✅ 已修（#171） | #124/#129 | 緯度 ±90° 的錨點讓 `GridCounts.cell` 溢位當機；`build_place_grid.py` 不拒絕帶 `remark` 錯誤的 Overpass 回應。 | `cell` 對非數字或遠在格外的座標回傳格外的空格，不再當機（附測試，main 上會當機）；工具拒絕帶錯誤 `remark` 或筆數少於 `out count` 的回應，不寫入快取。 | — |

修正分組（哪些要一起修）：

- **A 組，一起修（✅ 已完成：#165、#169）**：`trafficVisits` 只增不減，與 `resolveDeadlock` 不經 `setOff`（皆 #109）。兩者改的是同一份 `trafficVisits`：清理舊循環時要知道哪些 visit 之後還會被讀，而死結派送補寫的出發正是會被讀的那一種。兩者都會移動 replay checksum，放同一個 PR 只需逐值說明一次。
- **B 組，接在 A 組之後（✅ 已完成：#170）**：折返後的超越（#116）。修好後回程會安排超越、記錄更多 visit，A 組的清理規則要能涵蓋它；B 組的場景（超越等候中遇到死結派送）也是驗證 A 組 `setOff` 的現成場景。也可與 A 組合成一個「排程交通」PR。
- **可各自獨立修（#171 處理完畢，見上表；只有主執行緒載入保留紀錄）**：`preferredGoingOn` 盡頭翻向（#120/#131）；轉乘群組批次上車與「留下」計數（#142，同在上下車程式，可同一個 PR）；票價距離 0（#120）；`ja.lproj`（#141）；主執行緒載入與 `stationData`（#143/#147）；±90° 與 Overpass（#124/#129）。
