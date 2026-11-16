# DEADLOCK-NET（2026-11-16）

- 派工：遊戲規劃（作者問「新路線很常遇到的死結怎麼改善」）。session `session_01JMHz9cM6fpK8jvZkiW19kw`，雲端 Linux，分支 `claude/deadlock-net`。
- 決策 805（`docs/decisions/805.md`）。存檔版本 107 不動（108 沒有取）；golden schema 不動；golden、replay 與既有的存檔 fixture 一個值都沒變。
  新增一個存檔 fixture：`SaveFixtures/v107-terminal-platform-wait.json`。
- 根因報告：`docs/research/DEADLOCK_ROOT_CAUSES_2026-11-16.md`。

## 做了什麼

- **A（安全網）**：管制關著時，互等成圈的列車認得出來（`deadlockedTrains()`、`routeWaits()` 不再回空的），地圖用現有的死結標記、泡泡與卡片文字點名；
  每個整分鐘每一圈放一列先走（只免「誰先」的規則，不免「前面有車」）。不存狀態。沒有圈的世界逐位元不變（25 個世界的雜湊和 `main` 相同）。
- **B（診斷）**：管制開著的死結全部在終點或航廈的月台（出發時要停的月台沒有被訂下來，空車與收班的車開進去停著），沒有一個在機廠咽喉。
  對策 D 解得了，C 與 E 目前沒有對得上的案例。

## 還留下什麼

1. **對策 D1**（有車正要進的月台，閒置的車與空車不停進去）：解機捷舊線簡＋控的十列互等、擬實每晚坑口站的死結、航廈站白天的一分鐘死結。
   會動 golden 與 replay（管制預設開著）。驗收材料：`TerminalPlatformWaitTests`（做完後把 `testTwoTrainsMeetHeadOn…` 反過來）。
   五方（我的估計）：玩家 4、開發 2、美術 1、鐵道迷 4、音樂 1，加權約 2.6。
2. **對策 D2**（出發時就選定並訂下要停的股道）：解羅瓦涅米備用車擋夜車的一分鐘。在 D1 之後。可能要新存檔版本。
   五方：玩家 2、開發 2、美術 1、鐵道迷 3、音樂 1，加權約 1.85。
3. 擬實坑口站半夜那一列，占著機場第一航廈月台的是哪一列沒有確認（報告第 2 節，UNVERIFIED）。做 D1 時先確認。
4. HEALTH-132 §6 第 1 項（機捷、文湖簡＋控沒發的班變多）這次沒有重跑，NOT ASSESSED。
5. 「誰也不能放」的圈（每一列都被前車或已在軌道上的對向車擋著）目前沒有例子；遇到時只點名、不解。

## 怎麼重現

- 管制關著的圈：`swift test --skip-build --filter SpacingRingTests`（用 `passesHeldTrains` 把決策 801 之前的規則開回去）。
- 管制開著的十列互等：`swift test --skip-build --filter TerminalPlatformWaitTests`。
- 25 個世界的雜湊：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CHECKSUM=1 swift test --skip-build --filter DepotReturnReportTests`，
  兩個建置各跑一次，比 `checksum` 那幾行（一次約一小時）。
