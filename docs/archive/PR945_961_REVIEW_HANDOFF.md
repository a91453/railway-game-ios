# 交接：PR #945–#961 審查 C 組

Session：session_01VVzExSvZcTej5eCqxdUEpY。遊戲規劃 session_014rYHMtmqA5bEMkBBuKu6PV 派工，日期 2026-10-22。作者原話：「派審查C從945看到最新」。

- 審查基準：`main` **8687e37**。文件 PR 從 **61d11c16** 開分支。
- 範圍：已合併進 main 的 #945–#961。#960 等於 #949，#961 等於 #957，所以兩組各看一次。另外查了合進非 main 分支的 PR 有沒有漏掉或重複。#959、#962、#963 不在範圍內。
- 上一輪：[PR873_910](PR873_910_REVIEW_HANDOFF.md)（A 組）、[PR911_944](PR911_944_REVIEW_HANDOFF.md)（B 組）。
- 存檔版本、決策編號、golden schema 都**不動**。GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 兩個 PR：
  - [#974](https://github.com/a91453/railway-game-ios/pull/974)：GameCore，C1。
  - 這份文件所在的 PR：CI 腳本、文件檢查、素材文件，C2–C6、C10、C11。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）與 python3。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 看過的 PR | **17**：#945–#958、#960、#961，另外 #951 |
| 新發現 | **12**：P2 四個（C1–C4），P3 八個（C5–C12） |
| 已修 | **8**：C1–C6、C10、C11 |
| 沒修，交出去 | **4**：C7、C8、C9、C12，見第四節。另外有一個決策號相撞，也在第四節 |

讀 diff 的工作分給幾個子代理：3D 車輛、CI 流程、存檔修正。子代理的發現都由本 session 再讀程式確認過。能寫成會紅的測試或腳本的，先寫出來再修。

## 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| [#945](https://github.com/a91453/railway-game-ios/pull/945)、[#951](https://github.com/a91453/railway-game-ios/pull/951) | 遊覽車與低地板公車接上 `Map3DStreetLife`。看了五款公車的選型（5% 公車池裡分 30／35／20／10／5）、`isBus`、進出路端的長度。也看了三角形數，以及外殼的法線方向（所有外殼的體積都是正的，所以沒有翻面）。#951 沒有合併提交，因為它的 head 已經在 main 上 | C7、C8、C11（P3） |
| [#946](https://github.com/a91453/railway-game-ios/pull/946) | 商用套件 | C9、C10（P3） |
| [#947](https://github.com/a91453/railway-game-ios/pull/947) | UI 測試固定 seed，用 `launcher.newGameOptions.seed` 設定 | 無問題 |
| [#948](https://github.com/a91453/railway-game-ios/pull/948) | CI 流程。`ios-full-lane.yml` 的 push paths-ignore | C5（P3） |
| [#952](https://github.com/a91453/railway-game-ios/pull/952) | 決策 329：swift-build 或 swift test 在任何測試開始前被訊號殺掉時，再跑一次。測試本身當掉還是紅 | 無問題。決策 329 可以把「只有 swift-pm 本身被殺才重跑」寫得更清楚 |
| [#953](https://github.com/a91453/railway-game-ios/pull/953) | `full_lane_watch.py`：full lane 轉紅、新的 job 轉紅、轉回綠時在 #231 留言 | C2、C3（P2），C6（P3） |
| [#950](https://github.com/a91453/railway-game-ios/pull/950) | 前一輪的修正：DayPassCard 的 `sellable`、架空線電桿的 `inStreet` | 無問題 |
| [#955](https://github.com/a91453/railway-game-ios/pull/955) | A 組 P1 的修正：環線一律平均發車；拆站拆掉整條買下的線時，資產一起註銷 | 新的存檔不會再壞。但修正前存下的壞存檔還是讀不回：**C1（P2），已修** |
| [#956](https://github.com/a91453/railway-game-ios/pull/956) | A3 快取的 `holds`、A4 的 `headwayHours`、A5 色帶的切法 | 無問題 |
| [#954](https://github.com/a91453/railway-game-ios/pull/954)、[#961](https://github.com/a91453/railway-game-ios/pull/961)（＝#957） | 綠色三節輕軌、通勤車模型 | C12（P3） |
| [#958](https://github.com/a91453/railway-game-ios/pull/958) | 預覽圖搬到私有庫。看了連結和 `town-preview/preview.cjs`。指到私有庫的路徑本來就不是這裡的檔案 | 沒有斷掉的連結 |
| [#960](https://github.com/a91453/railway-game-ios/pull/960)（＝#949） | 中巴。內容和 #949 相同 | 歸在 C7、C8、C11 |

**合進非 main 分支的 PR**：
- #942、#949、#957 都合進了過時的分支：base 是另一個還沒合併的 PR 的分支。後來分別由 #951、#960、#961 補進 main。
- 比對 main 上的 `Map3DStreetLife.swift` 和 `docs/HANDOFF.md`：沒有漏掉的段落，也沒有重複的段落。
- 再搜尋所有已合併、base 不是 main 的 PR。比較舊的 #259–#339 內容都已經在 main 上（歷史改寫過）。
- 根因是素材交接提示與各 skill 叫 session 疊在未合併的 PR 上：C4。

## 三、修了的

### C1（#955）修正前存下的壞存檔還是讀不回，P2，已修（#974）

- **重現**：`BrokenSaveRepairTests`，在 main 8687e37 上兩個測試都紅。
  - #955 之前，交錯發車或兩端發車的路線改成環線，會留著原本的發車方式；#955 之後的解碼器會拒絕這種存檔。
  - #955 之前，拆站拆掉整條買下的線，會留下沒有主人的 `acquiredLine` 資產；`CompanyAccounts` 的驗證也會拒絕。
  - 79.1 的玩家只要做過其中一件事，存檔就讀不回。
- **修法**：照 `passengerRouteBalances.removeAll` 的前例，在讀檔時修好。
  - `ServiceLine.init(from:)`：環線的發車方式改成 `.even`，清掉 `endLastDispatch` 和 `opensPair`。這和現在把路線改成環線時做的事相同。
  - `GameWorld.init(from:)`：拿掉主人不在 `lines` 裡的 `acquiredLine` 資產。損失不再記一次帳；收購紀錄留著。
- **玩家**：舊存檔讀得回來，路線照常跑。
- **鐵道迷**：環線沒有端點，本來就只能平均發車。
- **開發**：不升存檔版本，因為格式沒變，只是讀檔時多修兩種壞資料；golden、fixture、replay 都不動。
- **美術**：無。
- **音樂**：無。

### C2（#953）重跑轉綠的 full lane 不會說「綠了」，P2，已修

- **重現**：`full_lane_watch.py --selftest` 新加的情境。
  - GitHub 重跑 workflow_run 時，id 和 created_at 都不變，只有 `run_attempt` 加一。
  - 原本的程式拿前一個不同的 run 來比；那個 run 是綠的，所以 attempt 2 轉綠時判斷成「一直是綠的」，不留言。
- **修法**：`run_attempt > 1` 時，讀 `/attempts/{n-1}`。前一次是紅的，就拿它來比，它失敗的 job 也算進這次紅色連續裡（`/attempts/{n-1}/jobs`）。

### C3（#953）重跑較舊的 full lane 會在 #231 報過時的消息，P2，已修

- **重現**：selftest 的情境。main 最新的 full lane 是紅的時候，重跑一個較舊的 lane，轉綠後會留言「綠了」。
- **修法**：`newer_full_lanes()` 找出比這個 run 新、已經完成的 full lane。有的話只印一行，不留言。

### C4 叫 session 疊在未合併的 PR 上，P2（流程），已修

- **內容**：
  - `docs/art/VEHICLE_ASSET_HANDOFF_PROMPT.md`、四個公車 skill 和 `tools/*/README.md` 都寫「以未合併的 #94x 分支為 base，合併後再轉 main」。
  - #942、#949、#957 就是這樣合進過時的分支，要再開 #951、#960、#961 補。
- **修法**：都改成「PR 一律以 main 為 base；依賴的 PR 還沒合併就等它合併，或把需要的部分一起帶進來」，並寫出這三次的經過。

### C5（#948）`ios-full-lane.yml` 漏了 `full-lane-watch.yml`，P3，已修

push 的 paths-ignore 補上這一行。補了之後，它和 `ios-build.yml` 的 pull_request paths-ignore 完全相同（逐行比過）。

### C6（#953 的決策 329）`doc_numbers.py` 抓不到三種錯，P3，已修

- 漏抓的三種：
  - `docs/decisions/0329.md`（有前導零）；
  - 不是數字的檔名；
  - 寫在 ARCHITECTURE 裡、號碼 ≥ 329 的決策標題。
- 現在三種都算差異。selftest 加了 3 個情境。
- 「還沒進決策索引」的提示只看 329 以前的號碼，因為 329 起不進索引。

### C10（#946）沒在用的商用套件產生器寫死作者的 Windows 路徑，P3，已修

- `generate_commercial_kit.mjs` 的預設輸出是 `C:/Users/…/antigravity/…`。
- 改成必須給輸出目錄，沒給就印用法並以 2 結束。也註明 `rebuild.sh` 不跑它。
- `export.sh` 用的是 `tools/station-kit/package.mjs`，不跑這三個檔（`generate_commercial_kit.mjs`、`mesh-builder.mjs`、`tools/commercial-kit/package.mjs`）。要不要刪交給商用套件的作者，本 PR 只拿掉個人路徑。

### C11（#945、#949）skill 與 README 裡的公車比例過時，P3，已修

- shuttle、low-floor、coach 的 skill 和 README 都還寫當時的比例，例如「35% 既有公車」。
- 每處都在原文後補一句現在的比例，指向 `Map3DStreetLife.addVehicles`，原文保留，作為當時的紀錄。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| C7 | #945、#960 | P3 | 相鄰兩輛公車可能重疊。`busSpacing` 是 17（實際間距 18.75 m），起點有 0.4 倍間距的抖動，所以最近只隔 0.6 × 18.75 = 11.25 m；兩輛遊覽車要 13.19 m 才不重疊。`Map3DCoachBusTests` 用的 perHundred 是 5，真實道路最多 4。在 37.6 m 的路上試了 60000 個 seed，86 對相鄰公車都沒有重疊；要把 perHundred 調到不實際的 5.8 才重疊 | 現在的道路不會發生；修法有兩種，選哪個是街景設計 | 3D session_01ShaLWGSyEn9fYcNjS8j5Gz（`Map3DStreetLife` 在它手上）：前一格已經是公車就不放公車；或把 `busSpacing` 調到 0.6 倍間距 ≥ 最長的公車 |
| C8 | #945、#949、#960 | P3 | 三角形數超過決策 317 與 MESHY 規格的約 1,500：低地板 2,212、遊覽車 2,884、中巴約 2,516。30 輛公車約 65k，原本估 48k。交接提示寫 1,500–3,000，但沒有決策記下這個改變。決策 317 裡的比例與塗裝說明也過時了 | 要先決定預算，或要不要做簡化版 LOD；實機幀數還沒量 | 3D session，或決策 331 的作者：在決策裡寫下公車的三角形預算，並更新決策 317 的說明 |
| C9 | #946 | P3 | `docs/art/commercial-kit-2026-10-21/README.md` 列了 36 個零件名，只有 2 個和 `Part.name` 相同；也提到一個沒有零件用到的天花板掛點 | 要對照作者的設計意圖，不是單純改字 | 商用套件的作者 |
| C12 | #954、#961 | P3 | 輕軌與通勤車模型放在 `Map3DModelPack.standard`，會建 GPU 緩衝。輕軌已經由 #962 用到；通勤車在接上之前都是白建的 | 等接上通勤車就沒事；要不要先拿出來是 3D 的排程 | 3D session_01ShaLWGSyEn9fYcNjS8j5Gz |
| — | #963（範圍外） | — | **決策 332 被用了兩次**：main 上的 `docs/decisions/332.md` 是運具轉移；#963「用我的位置」也用 332 | 不是本輪範圍內的 PR | 遊戲規劃：請 #963 改用 333（或當時最大號 + 1） |

另外記下兩件，不算發現：

- **既有，不是回歸**：`removeStation` 拆掉高鐵線時，不呼叫 `refreshLandDemand` 和 `abandonUnservedPassengers`；`removeLine` 會呼叫。
- **A8**：A 組的 A8（有班次的路線保留發車方式）由 session_01QiPq4nZdq5bVS9MZ4rkr4L 在修，同樣改 `ServiceLine` 的解碼器。已經用 send_message 通知它 #974 也改了 `init(from:)`；兩個 PR 誰後合，誰就要處理衝突。

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（#974） | **VERIFIED**，乾淨 |
| `BrokenSaveRepairTests` | **VERIFIED**：在 8687e37 上兩個都紅，修了之後都綠 |
| `BrokenSaveRepairTests`、`DispatchPatternTests`、`LineAcquisitionTests`、`SavedGameTests`、`ReplayFixtureTests`、`GoldenScenarioTests` | **VERIFIED**，87 個，0 失敗，1 個本來就略過 |
| `python3 -I tools/ci-watch/full_lane_watch.py --selftest` | **VERIFIED**，含 C2、C3 的新情境 |
| `python3 -I tools/golden-checks/doc_numbers.py --selftest`、`--check` | **VERIFIED**：selftest 19 個情境都過；`--check` 0 差異 |
| `node --check tools/commercial-kit/generate_commercial_kit.mjs` | **VERIFIED** |
| C7 的重疊模擬（60000 個 seed） | **VERIFIED**，由子代理在 Linux 上跑；腳本沒有提交 |
| iOS 的建置、UI 測試、實機幀數 | **UNVERIFIED LOCALLY**，交給 `ios-build.yml`。兩個 PR 都不改 App 的程式 |
