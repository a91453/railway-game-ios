---
name: economy-balance
description: 經濟與平衡怎麼量、怎麼判：改票價、成本、需求、城市成長、稅、貸款、子公司、挑戰目標之前與之後，用只在要求時才跑的報告測試量出數字，對照決策裡寫下的目標，給出 HEALTHY／CONCERNS／CRITICAL／NOT ASSESSED。Use before changing any GameCore or GamePresentation rule or constant that moves money, ridership or city growth, or when judging whether the game's balance looks right.
---

# 經濟與平衡的量測

改到錢、運量、城市成長的規則（`FareRules`、各種成本、需求、城市、稅、貸款、子公司、觀光、
挑戰目標、`GameWorld.startingBalance`……），PR 要附「改之前」與「改之後」的數字，並說出哪個目標
因此變了。這份寫下用哪一把尺量、怎麼比、怎麼下判定。

做法取自 Donchitos/Claude-Code-Game-Studios 的 `balance-check` skill 與 `economy-designer`
agent（MIT，`be8993b`，授權全文在同目錄的 `LICENSE`）。保留的是它的三個好規則：沒有資料就說
「沒有量」，不能當作通過；每個數字都對照一個寫下來的目標；判定照最壞的那一項。它的
`project.yaml`、GDD、`design/registry/`、逐步問作者的流程都不適用：這裡目標寫在決策與測試裡，
決定由 session 自己做（CLAUDE.md 的 Workflow，五個角度）。

## 1. 先找目標，找不到就是 NOT ASSESSED

先列出這次要判的數字，每個都要有一個寫下來的目標。目標只從這幾個地方來：

| 目標 | 在哪裡 |
| --- | --- |
| 第一條線的造價與回本天數（4–10 天；示範地圖 7–10 天） | `Tests/GamePresentationTests/NewGameBalanceTests.swift`（決策 46、137） |
| 各決策「量到的」「平衡」段落 | `grep -n "BalanceReportTests\|量到的\|平衡（量過的）" docs/ARCHITECTURE.md`（決策 46、73、137、139、145、157、174、179、181、207……） |
| 挑戰的目標日 | 決策 86、145（`ChallengeReportTests`），劉銘傳：決策 153 |
| 還沒解決的觀察 | ROADMAP 的平衡待觀察表；`docs/research/NEXT_PRIORITIES_2026-10-12.md` §5 第 5 項「抑制現金滾雪球」 |

- 一個數字在這些地方都沒有目標：寫 `no stated range — not judged`，不要自己訂一個再說它過了。
- 需要的報告沒跑（太久、這個容器跑不了）：那一段寫 **NOT ASSESSED — NO DATA**，說缺什麼、
  用哪個指令補。**NOT ASSESSED 是正確的答案，不是失敗**；沒量卻寫「健康」才是錯的。

## 2. 選一把尺

都是 `Tests/GamePresentationTests/` 裡設了環境變數才跑的報告測試。它們什麼都不斷言，把 Markdown
表印到 stdout。debug build 太慢，一律用 release：

```sh
swift build -c release -Xswiftc -enable-testing --build-tests
BALANCE_REPORT=30 swift test -c release --skip-build \
  --filter 'BalanceReportTests/testALineBetweenTwoTowns$'
```

`--filter` 是正規表示式：不加 `$` 的話，`testALineBetweenTwoTowns` 也會跑
`testALineBetweenTwoTownsWithMaterials`。量過（2026-10-15，Linux 雲端容器，4 核心）：第一次 release
build 約 9 分鐘；之後兩鎮之間的線 10 天不到 4 秒。

| 報告 | 環境變數 | 量什麼 |
| --- | --- | --- |
| `BalanceReportTests` | `BALANCE_REPORT=<天>` | 沒有玩家操作的新遊戲逐日：現金、票收、營業利益、稅、回本、每日旅次、服務圈人口、土地與城市。14 個情境：第一條線、兩鎮之間、全開一年、子公司、景點、飯店、城市委託、距離、建材、貨運、購地、示範地圖、公司評等 |
| 同上的開關 | `BALANCE_NO_REALISTIC=1`、`BALANCE_NO_CITY_DEMAND=1`、`BALANCE_NO_MATERIALS=1`、`BALANCE_RANK_DEMO=1` | 關掉寫實運轉（決策 207）、城市需求（139）、建材（157）再量，和決策之前比 |
| `ChallengeReportTests` | `CHALLENGE_REPORT=<種子數>`，`CHALLENGE_SEEDS`、`CHALLENGE_ONLY`、`CHALLENGE_PLAY`、`CHALLENGE_RUN_ON`、`CHALLENGE_TRACE` | 沙盒挑戰三種玩法各在第幾天達標。一個種子超過一小時，用 `CHALLENGE_SEEDS` 分開跑 |
| `LiuMingchuanReportTests` | `LIU_REPORT=1`，`LIU_PLAY`、`LIU_TRACE` 等 | 劉銘傳挑戰 |
| `RealWorldExpansionReportTests` | `BALANCE_REPORT=<天>` | 實景地圖購地的門檻 |
| `HighSpeedReportTests` | `BALANCE_REPORT=1` | 高鐵需求對真實十二站 |
| `RunTimeRealismReportTests` | `REALISM_REPORT=1` | 遊戲列車的時間對真實（寫實度的尺，不是經濟） |
| `NewGameCampaignTests` | `NEW_GAME_CAMPAIGN=<步數>` | 全開新遊戲的指令與時間 campaign（正確性，不是數字） |

只量這次改到的情境；全部跑一輪要好幾個小時。

## 3. 前後怎麼比

1. 同一個情境、同樣的天數、同樣的環境變數，量兩次：改之前（PR 的 base）與改之後。
2. 改之前用 worktree 量，不要切換工作中的 branch：
   `git worktree add <scratchpad>/base origin/main`，在那裡 release build 一次再跑同一個指令。
3. 兩份表存在 scratchpad，逐列 diff。PR 只貼這次要判的列（第 1、7、30 天之類），不貼整張表。
4. 每個數字標 **VERIFIED**（在哪裡跑的：Linux 雲端容器、release、哪個 commit）。沒跑的寫
   **UNVERIFIED** 與原因。

## 4. 看什麼

照 `balance-check` 的經濟一節與 `economy-designer` 改寫成這個遊戲的項目：

- **錢從哪來、往哪去**：每天的票收、觀光、商業、子公司（水龍頭）對營運費、折舊、利息、稅
  （水槽）。每一種收入都要說出對應的支出，以及長期是盈餘還是赤字。
- **帳要對得上**：各線損益加總等於公司帳（決策 179）。
- **回本天數**：第一條線仍在目標範圍內。
- **後期滾雪球**：第 60、180、360 天的現金對起始資金的倍數，和改之前比是更快還是更慢。
- **一面倒的選擇**：有沒有一種做法在所有情況都比其他好（例如某個站距、某種車、永遠不借錢）。
- **加了反而變差**：加線、加站、加車之後運量或利潤變少（NEXT_PRIORITIES §2 第 7 項的第 (3) 點）；
  遇到要當 bug 查，不是平衡。
- **挑戰還贏得了嗎**：最省的玩法還能不能在目標日前達標，最強的玩法會不會太早。
- **範圍的兩端**：改一條曲線或一個係數，要寫它在這次影響範圍兩端的實際數值（最小的鎮與最大的
  都市、第 1 天與第 360 天），不是只寫中間。

## 5. 判定

照最壞的那一項，先符合的就是：

- **CRITICAL**：出現一面倒的選擇、挑戰贏不了或第一天就贏、某種收入沒有對應的水槽而無限增長、
  帳對不上。
- **CONCERNS**：有數字超出目標範圍，但調參數修得好。
- **NOT ASSESSED**：缺資料，或有數字沒有目標可比（寫出是哪一個）。排在 HEALTHY 前面：量到問題
  比沒量到有用，沒量到又比「看起來沒事」誠實。
- **HEALTHY**：每個數字都對過目標，都在範圍內，沒有一面倒的選擇。

PR 裡的格式：

```
### 平衡：<情境>
判定：<HEALTHY / CONCERNS / CRITICAL / NOT ASSESSED>
量測：<報告與環境變數>，release，<容器>，base <commit> → head <commit>（VERIFIED）

| 數字 | 目標（出處） | 改之前 | 改之後 | 判 |
| --- | --- | --: | --: | --- |
```

## 6. 數字動了之後

- **golden 變了**：照 `GoldenScenarios/README.md` 逐值說明理由，絕不為了過測試改期望值。
- **replay 的 checksum 變了**：那是行為改變，PR 要說明，不能重錄了事（`ReplayFixtures/README.md`）。
- **該跑的 shard**：`NewGameBalanceTests` 與 `GoldenScenarioTests` 在 `campaigns-8`，經濟的
  property campaign 在 `campaigns-6`（`EconomyPropertyTests`）與 `campaigns-9`
  （`EconomySecondHalfPropertyTests`）：
  `.github/scripts/swift-shards.sh run campaigns-8`。分配以 `swift-shards.sh` 的 `classes_of` 為準。
- **決策**：把新的「量到的」段落寫回那個決策，含指令、天數、commit。
- **五個角度**：玩家、鐵道迷、開發、美術、音樂各一行理由（和真實鐵路無關就寫「鐵道迷：無」，和聲音無關就寫「音樂：無」）。
- **玩家看的字**：畫面只說玩家得到什麼，不寫係數、內部單位或怎麼算的（`docs/UI_THEME.md`）。

## 7. 已知的坑

- debug build 跑示範地圖 60 天要很久；release 也要約 4 分鐘。先跑小情境。
- `BALANCE_NO_*` 會改世界的開關；和舊數字比之前，確認舊數字是在哪個開關下量的。
- 和決策 174 以前的數字比，要記得當時沒有觀光。
- 報告的情境是「沒有玩家操作」的世界：它量的是規則，不是玩家實際會怎麼玩。玩家的感受看
  `docs/research/PLAYER_FEEDBACK.md`。
