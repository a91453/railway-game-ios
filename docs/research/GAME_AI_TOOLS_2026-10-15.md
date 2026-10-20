# 遊戲引擎與 AI 工具：作者列出的 16 個專案能幫《沿線》什麼

日期：2026-10-15。基準：`railway-game-ios` main `b498425`。
讀者：作者，以及之後做經濟平衡、無頭模擬、3D 城市、配樂的 session。

> 2026-10-16：作者再列的動態設計與 3D 工具（30 個）在 [MOTION_3D_TOOLS_2026-10-16.md](MOTION_3D_TOOLS_2026-10-16.md)；它也記了第 3 節候選的現況與補充的做法。

> 2026-10-20：作者轉來的另外 8 個工具與 mattpocock/skills 的評估在第 6 節；這次用上的是改寫成 `.claude/skills/diagnosing-bugs/` 的查 bug 流程。

作者 2026-10-15 列出 16 個「對我現在製作的幫助最大」的專案。這份逐一看它們做什麼、授權准不准、
放到這個遊戲上有沒有用，再把能直接用的先用上。

- **這次就用上的**：Claude-Code-Game-Studios（MIT）的 `balance-check` 與 `economy-designer`，
  改寫成本 repo 的 skill `.claude/skills/economy-balance/`（第 2 節）。
- **其他的**：寫成之後的候選（第 3 節）。只有需要作者同意的才列為等作者（第 4 節）。
- **不動的**：GameCore、GamePresentation、App、存檔版本、golden、replay、ARCHITECTURE 決策號碼。
  這次只加一份文件與一個 skill。

## 0. 一頁摘要

《沿線》不是用 Unity、Unreal、Godot 做的。它是三塊：
- Swift 的決定論核心 `GameCore`，Linux 上可以測；
- SwiftUI App；
- 網站上的 Three.js 3D 城市 `Web/CityView/`。

所以引擎外掛本身都裝不上來。能帶過來的是它們的**做法**：怎麼讓 AI 跑遊戲、看結果、照規矩改。

| # | 專案 | 是什麼 | 授權（輸出能不能放進全球上架的 App） | 結論 |
| --: | --- | --- | --- | --- |
| 1 | [Donchitos/Claude-Code-Game-Studios](https://github.com/Donchitos/Claude-Code-Game-Studios) | Claude Code 的「遊戲工作室」範本：49 個 agent、74 個 skill、hook | MIT | **採用**：`balance-check` 改寫成 `economy-balance`（這次）。另有兩個候選（第 3 節） |
| 2 | [Natfii/UnrealClaude](https://github.com/Natfii/UnrealClaude) | 在 Unreal 編輯器裡開 Claude Code，加一個本機 MCP 橋 | MIT | 只取想法：依需要載入的文件（按號碼讀一個決策） |
| 3 | [ChiR24/Unreal_mcp](https://github.com/ChiR24/Unreal_mcp) | 一個 MCP 工具通 400 多個 Unreal 編輯器功能 | MIT | 只取想法：不認得的參數就拒絕；錯誤附下一步；每個指令回一張收據 |
| 4 | [kevinpbuckley/VibeUE](https://github.com/kevinpbuckley/VibeUE) | Unreal 的工具組與 36 個 skill 包；情境測試、每幀時間 | MIT | 只取想法：3D 城市的每幀量測（CPU 還是 GPU 卡） |
| 5 | [quodsoler/unreal-engine-skills](https://github.com/quodsoler/unreal-engine-skills) | 31 個 Unreal 的 skill | MIT | 只取想法：skill 的寫法（「問題是…→去哪一節」的路由表、`references/`） |
| 6 | [prajwalshettydev/UnrealGenAISupport](https://github.com/prajwalshettydev/UnrealGenAISupport) | Python MCP 伺服器經 socket 控制 Unreal，加上各家 LLM API 的包裝 | MIT | 沒有可用的：GameCore 是純 Swift 函式庫，不需要 socket 橋 |
| 7 | [NVIDIA/Audio2Face-3D](https://github.com/NVIDIA/Audio2Face-3D) | 語音轉 3D 臉部動畫 | SDK MIT；模型是 NVIDIA Open Model License | 不適用：站長是 2D 的鳥（決策 122），遊戲沒有語音 |
| 8 | [IvanMurzak/Unity-MCP](https://github.com/IvanMurzak/Unity-MCP) | Unity 的 MCP：跑測試、截圖、讀 log，也能當 CLI | Apache-2.0 | 只取想法：測試結果預設只回失敗；log 從游標往後讀；同一個操作也能當 CLI 用 |
| 9 | [Unity-Technologies/ml-agents](https://github.com/Unity-Technologies/ml-agents) | 強化學習工具組 | Apache-2.0 | 只取想法：觀察、動作、遮罩、獎勵的結構，用來做腳本化的玩法比較（第 3.3 節）。不訓練神經網路 |
| 10 | [Coding-Solo/godot-mcp](https://github.com/Coding-Solo/godot-mcp) | Godot 的 MCP：無頭執行、讀 debug 輸出、單一的操作分派腳本 | MIT | 只取想法：一個無頭入口，「操作＋JSON」進、JSON 出（第 3.1 節） |
| 11 | [ubisoft/ubisoft-laforge-chord](https://github.com/ubisoft/ubisoft-laforge-chord) | 從貼圖推出 PBR 材質 | Ubisoft ML License（只限研究，copyleft） | **不能用**：`LICENSE:28-29`「Commercial use is strictly prohibited」 |
| 12 | [ace-step/ACE-Step-1.5](https://github.com/ace-step/ACE-Step-1.5) | 文字生音樂；不到 4 GB VRAM；Apple Silicon 可用 MLX | 程式 MIT；HF 權重 MIT，模型卡說生成的音樂可以商用 | **候選，等作者**：當離線配樂工具（第 4 節） |
| 13 | [Tencent-Hunyuan/HunyuanVideo-Foley](https://github.com/Tencent-Hunyuan/HunyuanVideo-Foley) | 由影片＋文字生音效 | Tencent Hunyuan Community License | **不能用**：`LICENSE:34` 禁止在歐盟、英國、南韓使用或散布 Output，App 是全球上架 |
| 14 | [Tencent-Hunyuan/Hunyuan-GameCraft-1.0](https://github.com/Tencent-Hunyuan/Hunyuan-GameCraft-1.0) | 可用鍵盤操控的遊戲影片生成 | 同上的地區限制 | **不能用**：地區限制；還要 24–80 GB 的 GPU |
| 15 | [SkyworkAI/Matrix-Game](https://github.com/SkyworkAI/Matrix-Game) | 即時「神經算繪」的世界模型（第 4 版把低多邊形畫面畫成寫實影片） | MIT／Apache-2.0 | 只取想法：遊戲邏輯留在引擎、畫面另外算，和 GameCore 是唯一權威同一個分法。要 A100 80 GB，權重只有三個場景 |
| 16 | [Claude 外掛市集的 Unity 外掛](https://claude.com/marketplace/plugins/unity)（[unity-agent-plugin](https://github.com/Unity-Technologies/unity-agent-plugin)） | Unity 官方的 Claude Code skill 集（UI、2D、內購、在地化、多人……） | Unity Companion License：只限依賴 Unity 的專案 | 不適用：《沿線》不是 Unity 專案，授權不涵蓋；只取想法 |

**三句話**：
- 對這個遊戲最直接有用的是 #1：它有一套「量了才說」的平衡流程。這個 repo 本來就有量測工具
  （`BalanceReportTests` 等），缺的是流程，這次補上。
- 引擎外掛（#2–#6、#8、#10、#16）共同的做法是**讓 AI 能無頭跑遊戲、拿到結構化的結果**。
  《沿線》的 GameCore 已經能無頭跑，但只能透過報告測試、印 Markdown。做一個「操作＋JSON」的入口
  是下一個值得做的（第 3.1 節）。
- 生成模型裡只有 ACE-Step 的授權乾淨；騰訊兩個有地區限制，Ubisoft CHORD 只限研究。
  ACE-Step 要加依賴，也要改決策 219 §2.2（聲音全部自己合成），所以等作者。

## 1. 怎麼查的

- 16 個 repository 都淺 clone 到 session 的 scratchpad（不進 repo），讀 README、授權、主要原始碼。
  模型權重沒有下載。HF 上的權重授權用 HF 的頁面查。
- 外掛市集的 Unity 外掛：讀了市集頁面，clone 它的原始碼 repo（`cf6b2da`），看了授權。
- 對照這個 repo 的：
  - `CLAUDE.md`、`docs/OVERVIEW.md`；
  - `docs/research/RAILWAY_SOUND_2026-10-14.md`、`tools/audio/README.md`；
  - `tools/meshy/`；
  - `.claude/skills/` 的三個 skill；
  - `Tests/GamePresentationTests/*ReportTests.swift`；
  - `Web/CityView/`、`Web/WasmProbe/`；
  - ARCHITECTURE 決策 46、122、137、145、161、163、179、181、219。
- 參考庫：`a91453/railway-reference-private` 這次不需要。這份研究是外部工具，不是移植參考庫的
  功能。參考庫的音樂池與 `regionAudio` 已在 RAILWAY_SOUND 盤點過。

## 2. 這次做的：`economy-balance` skill

**來源**：Claude-Code-Game-Studios（`be8993b`）的
- `.claude/skills/balance-check/SKILL.md`
- `.claude/agents/economy-designer.md`

兩者都是 MIT。授權全文放在 `.claude/skills/economy-balance/LICENSE`，SKILL.md 開頭寫明出處。
和決策 161 對 Meshy 官方 skill 的做法相同。

| 來源的部分 | 本 repo 的對應 |
| --- | --- |
| Insufficient input：沒資料就是 `NOT ASSESSED — NO DATA`，不能當通過 | 原樣保留（§1）。這個 repo 的報告測試沒設環境變數會**略過**。略過不是通過，這條規則正好對上 |
| Phase 3：從 `design/registry/entities.yaml` 與 GDD 讀目標 | 目標改從 `NewGameBalanceTests` 的斷言、ARCHITECTURE 各決策「量到的」段落、挑戰的目標日讀（§1 的表） |
| Phase 2：讀 `assets/data/` | 改成跑 release 的報告測試（§2 的表：8 個報告、它們的環境變數） |
| Phase 4 經濟：水龍頭與水槽、累積的預測、無限迴圈、沒人買的東西 | 票收、觀光、商業、子公司對營運費、折舊、利息、稅；後期滾雪球；各線損益加總對公司帳；「加線反而少載」（§4） |
| `economy-designer`：曲線要寫影響範圍兩端的實際數值 | 原樣保留（§4 最後一點） |
| Phase 5：判定照最壞的一項；NOT ASSESSED 排在 HEALTHY 前面 | 原樣保留（§5），加上 PR 用的表格格式 |
| Phase 6：用 AskUserQuestion 問作者下一步 | **拿掉**：作者 2026-10-14「我不再做決定」，改成四個角度各一行理由（CLAUDE.md Workflow） |
| `/propagate-design-change` | 改成 golden、replay、shard 與決策段落的規矩（§6） |

**不重複的地方**：這個 repo 已經有量測工具，但沒有一份文件說
- 改經濟時用哪一把尺；
- 前後怎麼比；
- 數字要對照哪個目標。

所以各決策的「量到的」段落格式不一，有的寫 debug、有的寫 release，有的沒寫 commit。
`docs/research/NEXT_PRIORITIES_2026-10-12.md` §1 第 7 條「數字先量再說」是原則，這個 skill 是它的做法。

**沒有拿的**（CCGS 其餘的 skill 與 agent）：
- 它自己的框架（`project.yaml`、`production/`、stories、sprints、GDD、ADR）：工作登記 #231、
  ARCHITECTURE 決策與 golden 已經做同樣的事，而且更嚴。
- 引擎專家 agent：引擎不同。
- 發版流程：TestFlight 是作者的。
- `run-and-observe`：它要開視窗截圖，Linux 上開不了 App。CLAUDE.md 的 VERIFIED／UNVERIFIED、
  `website-screenshots.yml` 已經是同一個原則。

## 3. 之後的候選（不需要作者同意，照 NEXT_PRIORITIES 排程）

### 3.1 無頭模擬的入口：操作＋JSON 進、JSON 出

**來源**：
- godot-mcp 的單一分派腳本（`godot --headless --script godot_operations.gd <operation> <json>`）；
- Unity-MCP 的「同一個工具也能當 CLI」；
- Unreal_mcp 的拒絕不認得的參數、每個指令回收據。

**現況**：無頭跑 GameCore 只能用報告測試。它們印 Markdown，不能讀任意存檔，也不輸出 JSON。
問題回報的指令紀錄（決策 193）只能重播，不能「讀這個存檔、走 30 天、給我經濟數字」。

**做法**：

1. 一個新的可執行 target（例如 `Sources/GameSim/main.swift`），依賴 GamePresentation，
   不是 GameCore，因為 GameCore 不用 Foundation。它有這些操作：
   - `new-game --seed`
   - `load <save.json>`：經 `SavedGame` 解碼與遷移
   - `apply <commands.json>`
   - `advance --days`
   - `dump --sections economy,stations,lines,city`
2. 每個指令回一張收據（錢的變化、新的 ID）。不認得的選項就拒絕，並列出可用的選項。
3. 不用 MCP：Claude Code 的 Bash 就是呼叫端，包一層 MCP 要加 SDK 依賴。

**成本**：改 `Package.swift` 會跑一次完整的 CI 層，也要一個 ARCHITECTURE 決策號碼（開工時在 #231 取）。

**四個角度**：
- 玩家：間接。玩家回報的存檔能直接量，修得更快。
- 開發：很大。平衡、問題回報、文件數字都能用同一個入口查。
- 美術：無。
- 音樂：無。

### 3.2 3D 城市的截圖與每幀量測腳本

**來源**：
- Unity-MCP 的截圖工具；
- VibeUE `PerformanceService.frame_timing()` 的 CPU／GPU 判定。

**現況**：
- `.claude/skills/rolling-stock/preview.cjs` 已經用預裝的 Playwright Chromium 開 CityView、截圖。
- `Web/CityView/performance.md` 引用的 `_bench.mjs`、`_prof.mjs`、`_fid.mjs` 不在 repo 裡。

**做法**：把 `preview.cjs` 推廣成一個腳本：
- 輸入：固定的幾個鏡頭位置；凍結 `__app.clockTime` 與變體。
- 輸出：PNG，加上 `renderer.info` 的 draw call 數與每幀毫秒（JSON）。

**依賴**：沒有新的，用預裝的 Playwright（`NODE_PATH`，不下載）。

**四個角度**：
- 玩家：網站的 3D 城市更順。
- 開發：效能改動有前後數字。
- 美術：每次改外觀都有同一組截圖可比。
- 音樂：無。

### 3.3 腳本化玩法的比較框架

**來源**：ml-agents 的 `Agent`（`CollectObservations`、`OnActionReceived`、
`WriteDiscreteActionMask`、`AddReward`、`DecisionRequester.DecisionPeriod`）。只取結構，不訓練。

**做法**：在 `Tests/GamePresentationTests/` 加一個 `Policy`：

| 部分 | 內容 |
| --- | --- |
| 觀察 | 世界的摘要 |
| 動作 | `PlayerCommand` |
| 動作遮罩 | 在世界的副本上試，丟錯就去掉。值語意加上失敗不留痕，所以很便宜 |
| 決策頻率 | 每 N 個遊戲日決定一次 |
| 獎勵 | 營業利益、運量、挑戰目標 |

`ChallengeReportTests` 的三種玩法（`linked`、`longTrains`、`grown`）搬到這個框架上。之後新的玩法
（例如「只蓋車站不加車」「一直借錢」）就能和舊的並排比，找一面倒的選擇（`economy-balance` §4）。

**不做的**：
- 神經網路推論進 GameCore：會破壞決定論，也違反不用 Foundation 的規則。
- 自我對戰與 Elo：GameCore 沒有對手公司。

**四個角度**：
- 玩家：挑戰與難度更準。
- 開發：平衡從「一個情境」變成「幾種玩法」。
- 美術：無。
- 音樂：無。

### 3.4 文件數字的一致性檢查

**來源**：CCGS `consistency-check` 的「先 grep，再對照登錄表」。

在這個 repo，登錄表就是程式本身。2026-10-15 查到 `docs/OVERVIEW.md` §2 已經落後：

| 項目 | OVERVIEW §2 寫的 | 程式裡的 |
| --- | --- | --- |
| 存檔版本 | 56 | 61（`Sources/GameCore/World/SavedGame.swift:325`） |
| golden schema | 72 | 74（`Tests/GameCoreTests/GoldenScenario.swift:54`） |
| golden 個數 | 76 | 77 |

做法是一個小腳本，或者 `economy-balance` 旁邊再一個 skill，比對這些數字，再對照 #231 的登記。
OVERVIEW 由規劃 session 維護，這次只記下差異，不改。

## 4. 等作者決定的

**ACE-Step 1.5 當離線配樂工具**（加依賴，也要改決策 219 §2.2）。

授權（VERIFIED，2026-10-15 讀過）：
- 程式 MIT。
- HF 上 `ACE-Step/Ace-Step1.5` 的模型卡：`license: mit`，「You can strictly use the generated
  music for commercial purposes」，訓練資料是授權曲、免版稅與公有領域曲、MIDI 合成的音訊。
- repo 的 `README.md:297` 請使用者「clearly disclose AI involvement」：要在資料來源畫面註明，
  和 Meshy 一樣（決策 161）。
- 春節 LoRA 是 OpenRAIL-M，不用。

**和現在的衝突**：
- 決策 219 定的是 MML Studio → 《沿線》樂譜 → 自己的合成器。§2.2 明確不用音色庫，以保留預告片的音色。
- `tools/audio/make_game_audio.py --check` 要求重新產生的檔案逐位元相同。生成的音檔做不到，
  只能把 WAV 當資產提交，`manifest.json` 記 prompt、種子、模型雜湊與 SHA-256。
- 每段循環要剪成剛好 1,843,200 個取樣（38.4 秒）。

**建議只用在第三階段的地區與時段配樂**。到站鈴與音效照舊自己合成。

| 角度 | 理由 |
| --- | --- |
| 玩家 | 地區與時段的配樂更豐富 |
| 開發 | 多一個大的 Python／PyTorch 離線依賴；CPU 可跑但慢（這個容器沒有 GPU） |
| 美術 | 可能和「小模型」的柔和聲音識別不合，要先聽過 |
| 音樂 | 音質高，但控制力不如樂譜；要在 C 大調五聲的鈴聲旁邊聽過才知道合不合 |

**另外的選擇**：
- 不用，照決策 219 全部由 MML Studio 作曲：零依賴，但作曲的人力是瓶頸。
- 只拿它的輸出當作曲的草稿，由人改寫成 MML：沒有出貨的 AI 音檔，但多一道人工。

**對 mml-tools**：16 個專案裡沒有一個輸出 MML 或 MIDI，對六軌 MML 工作台沒有直接幫助。
ACE-Step 的輸出是音訊，最多當編曲的參考。

## 5. 驗證

**VERIFIED**（這個容器，Linux）：
- 16 個 repository 的授權檔與上面引用的行號；
- ACE-Step HF 模型卡的授權與商用句子；
- `economy-balance` §2 列的測試類別、環境變數、`swift-shards.sh` 的 shard 分配，都在 `b498425` 查過存在。
- §2 的 release 指令實際跑過：`swift build -c release -Xswiftc -enable-testing --build-tests` 552 秒；`BALANCE_REPORT=10 … --filter 'BalanceReportTests/testALineBetweenTwoTowns$'` 3.4 秒，印出兩鎮之間的線（造價 $1,228,400，第 8 天回收 101%）。

**UNVERIFIED**：
- 沒有執行任何模型，這個容器沒有 GPU。
- ACE-Step 的速度與音質，以及它在 iPhone 喇叭上和鈴聲合不合，要作者同意後再試。
- 第 3 節的候選都還沒做。

## 6. 2026-10-20 補充：8 個測試與工具專案、mattpocock/skills

基準：`main` `b368ce7`。作者轉來另一個 AI 列的 8 個 GitHub 專案（附 9–10 分的適用分數），
再加上 [mattpocock/skills](https://github.com/mattpocock/skills)。這節逐項對照 repo 的現況。
授權讀的是各 repository 的 `LICENSE`；工具本身都沒有裝起來跑。

### 6.1 8 個專案

| 專案 | 授權 | 結論 | 理由 |
| --- | --- | --- | --- |
| [mapbox/pixelmatch](https://github.com/mapbox/pixelmatch) | ISC | **候選，等作者**（npm 依賴） | `tools/map3d-preview/` 現在把 `main` 與分支的圖上下拼起來給人看；它能多給一張差異圖與「改了幾 % 像素」。只在開發機，不進 App |
| [google/or-tools](https://github.com/google/or-tools) | Apache-2.0 | **候選，等作者**（Python 依賴），用途要換 | 參考庫已經在用：`Railway/taiwan-rail-reference-clean/source/scripts/optimize_physical_dispatch.py` 的 CP-SAT 替每班選股道、排待避（決策 296 查過，不是車組運用）。可用的是離線的「量尺」：高鐵示範一天的車輛運用最佳解，對照決策 296「下一步」第 1 點的規則差多少。不進 GameCore |
| [KhronosGroup/glTF-Validator](https://github.com/KhronosGroup/glTF-Validator) | Apache-2.0 | 候選，不急 | 能接在 `tools/glb-to-m3dmodel` 前面查規格。Meshy 試做公車排在實機量完 3D 幀時間之後（HANDOFF），到時再加。它不檢查這個遊戲自己的限制（無貼圖、面數），兩種檢查都要留 |
| [realm/SwiftLint](https://github.com/realm/SwiftLint) | MIT | 不做 | 已經用 `-warnings-as-errors`；多一個 CI job 與依賴，換來的不多 |
| [cashapp/AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) | Apache-2.0 | 不做 | HANDOFF 記的 VoiceOver 缺口是「時鐘 600 倍時會不會卡」，快照量不到。要查無障礙，先用 XCTest 內建的 `performAccessibilityAudit()`，不加依賴 |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | MIT | 不做 | CLAUDE.md：UI 測試不截圖、不比圖，畫面由作者在實機看；又要 macOS runner（全帳號 5 台，full lane 一次佔 4 台）。排版邏輯照舊放進 GamePresentation 用 Linux 測（例如 `TutorialCardPlacementTests`）|
| [MobilityData/gtfs-validator](https://github.com/MobilityData/gtfs-validator) | Apache-2.0 | 現在不做 | 世界版參考庫的 GTFS 已經轉好，沒有新的 GTFS 匯入 |
| [getsentry/sentry-cocoa](https://github.com/getsentry/sentry-cocoa) | MIT | 不做 | 把玩家的資料送到第三方，又加依賴。NEXT_PRIORITIES 第 8 項已排 Apple 自帶的 MetricKit 與 OSSignposter |

### 6.2 mattpocock/skills

MIT，`5beb35b`。給 Claude Code、Codex 等的 skill 集，主張「小、可改、可組合」。

**不整包裝**：
- 它的設定流程會建 `GLOSSARY.md`、`docs/adr/` 與 issue tracker 的標籤。這裡已有編號的 ARCHITECTURE 決策、
  `docs/HANDOFF.md` 與 #231，兩套會打架。
- `handoff` 把交接寫進 `/tmp`；這裡交接一定要進 `main` 的 `docs/HANDOFF.md`。
- `git-guardrails-claude-code` 擋 `git push`；session 要推分支開 PR。
- plugin 裝在使用者那一層，雲端 session 與 Codex、Gemini 都讀不到；放進 `.claude/skills/` 才大家都有。

**逐個看**：

| skill | 結論 |
| --- | --- |
| `diagnosing-bugs` | **採用**，改寫成 `.claude/skills/diagnosing-bugs/`（這次）。它的十種「做出會變紅的指令」換成這個 repo 已有的：`--filter`、`PROPERTY_REPLAY`、問題回報重播（決策 193）、GameSim（決策 260）、批次對逐分、`swift-shards.sh`、map3d-preview、cityview-benchmark |
| `writing-for-agents` | 只取想法：「去讀某某文件」的那句話寫法決定 agent 會不會去讀。CLAUDE.md 416 行、ARCHITECTURE 13,003 行時有用；要整理 CLAUDE.md 時再照它檢查一次 |
| `tdd` | 不拿：「新的測試在舊規則下會失敗」已經是這裡的習慣 |
| `research` | 不拿：`docs/research/` 已經是同一件事 |
| `grill-me`、`grilling`、`grill-with-docs`、`to-spec`、`triage`、`wayfinder`、`to-tickets` | 不拿：都靠反覆問作者或 issue tracker 推進，和作者 2026-10-14「我不再做決定」相反 |
| `domain-modeling`、`codebase-design`、`improve-codebase-architecture` | 不拿：ADR 與詞彙表的格式和決策紀錄重複；大規模重構違反「不做無關的重構」 |
| `handoff`、`git-guardrails-claude-code` | 不拿（上面的理由） |
| `prototype`、`code-review`、`implement`、`retro` 等 | 不拿：PR 裡留其他選項的預覽、CI 與審查已經有同樣的流程 |

**四個角度**（這次採用 `diagnosing-bugs`）：
- 玩家：間接。玩家回報的 bug 先在 Linux 變紅才修，修過的不會再回來。
- 開發：每個 bug 先有一條重跑得出來的指令，少了猜測與「當成 flake 重跑」；不加依賴、不動程式，CI 不跑 Swift。
- 美術：無。
- 音樂：無。

**沒選的另兩個**（預覽留給作者）：
- pixelmatch 接 map3d-preview：3D 美術改動有數字可比；要加 npm 依賴，等作者。
- OR-Tools 車輛運用量尺：最接近模擬深度；要加 Python 依賴，而且 `claude/hsr-train-rostering` 正在做同一件事的規則，
  等它合併後量尺才有東西可比。

**VERIFIED**（這個容器，Linux）：8 個專案的授權檔；參考庫的 CP-SAT 腳本；skill 引用的測試類別、環境變數
（`PROPERTY_REPLAY`、`PROBLEM_REPORT`、`TRAFFIC_TIMING_REPORT`、`TICK_REPORT`）與 GameSim 指令在 `b368ce7` 都存在。
**UNVERIFIED**：8 個工具都沒有安裝或試跑；skill 還沒有在真的 bug 上用過。
