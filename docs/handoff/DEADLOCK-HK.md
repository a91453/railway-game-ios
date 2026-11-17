# DEADLOCK-HK（2026-11-17）

- 派工：遊戲規劃（作者回報：香港地圖 60 倍速，第 1 年 1 月 2 日 02:20 畫面「5 死結」，南港島綫 2、6、10 與東涌綫 2、3、4、9）。session `session_01JMHz9asWDNkcGEygYRFQdt`，雲端 Linux，分支 `claude/deadlock-hk`。
- 決策 816（`docs/decisions/816.md`）。存檔版本 107 不動；golden schema 77 不動；`GoldenScenarios/`、`ReplayFixtures/`、既有 `SaveFixtures/` 一個值都沒變。新增兩個存檔 fixture。
- **session 壓縮兩次，依規定停手**：草稿 PR 開了、沒有自己轉 ready，也沒有等 CI。接手的人看下面「還留下什麼」。

## 做了什麼

- **根因**（已驗證）：擬實規則第一天丟班兩個方向不一樣多（南港島綫金鐘 7 班、海怡半島 5 班；東涌綫東涌 3 班、香港 1 班），收班時一端的車比股道多（金鐘 7 列 5 股、東涌 6 列 5 股）；港鐵各線沒有機廠，閒置車沒有規則會動，多出來的車停在正線中途站等到清晨。不是 135 → 136 進來的（135 與當時的 main 結果相同）。
- **修法**：`resolveDeadlock` 最後一招（排在決策 808 之後）。`Sources/GameCore/Railway/RunDepot.swift`：`runTrainToAnotherEnd(in:memo:)`、`endsWithRoom(of:besides:for:)`，`pullOutBerths` 多一個條件；`Sources/GameCore/World/GameWorld.swift`：`runTrainLeavingAFullEnd`。只送去路線的兩個端點。
- **回歸測試**：`Tests/GameCoreTests/FullEndWithoutDepotTests.swift`（3 個）與 `SaveFixtures/v107-full-end-south-island.json`、`v107-full-end-tung-chung.json`。
- **健康報告的世界**：`DepotReturnReportTests/testHongKong`（要 `DEPOT_RETURN_REPORT=1`）預設世界 `hk-sil-tcl`；`DEPOT_RETURN_ONLY=hk-sil`、`hk-tcl`、`hk-airport`、`hk`（六線全買）；`DEPOT_RETURN_SPEED=x60`；`DEPOT_RETURN_SIMPLE=1` 換簡化規則。
- 已併 `main`（`eb69904`，含決策 810）一次。

## 驗證（Linux，debug 建置）

- VERIFIED：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨（併 main 之後）。
- VERIFIED：`swift test --skip-build --filter 'GoldenScenarioTests|ReplayFixtureTests|SavedGameTests|NightTerminalBerthTests|TerminalPlatformWaitTests|FullEndWithoutDepotTests'` 71 個測試、1 個略過、0 失敗（併 main 之後）。
- VERIFIED：`FullEndWithoutDepotTests` 放到 135 版（沒有修法）會紅：2 個測試、10 個斷言。
- VERIFIED：`python3 -I tools/golden-checks/doc_numbers.py --check` 通過（`docs/OVERVIEW.md` §2 的存檔 fixture 個數 111 → 113）。
- 量到的數字在決策 816 §4：兩線新局兩晚的死結 469 → 11 分鐘；第二天沒發的班 14 → 12（740 班裡），**誤點的班 438 → 477**（多 39 班，沒有往下查）。作者的存檔併 main 之後重放：南港島綫 1 分鐘內解開，東涌綫仍到 05:54。
- UNVERIFIED：整輪測試與 25 個 HEALTH 世界（留給 CI；有機廠的世界條件上碰不到這一招，但沒有整輪重跑雜湊）。
- UNVERIFIED：iOS、實機。作者的畫面要在下一個 TestFlight 版本開擬實規則的香港新局看收班後。

## 還留下什麼

分數在 `docs/research/NEXT_PRIORITIES_2026-10-12.md` §29.17，說明在決策 816 §5、§6。

1. **PR 還是草稿**：CI 綠了之後，在 #2118 留「可合併、#NNNN、head <完整 SHA>」並轉 ready（這個 session 停手了，沒做）。CI 紅了就修。
2. **作者存檔那一晚的東涌綫仍等到 05:54**（HK-NIGHT-PARKED）：存檔在 02:33，過夜車已停在奧運、九龍的上行正線，空車路訂不到。新局沒有這個問題。
   作者的存檔在私庫 `a91453/railway-assets-private` 分支 `claude/report-deadlock-hk-1117` 的 `problem-reports/2026-11-17-deadlock-hk/`，**不要提交進這個公開庫**（規劃的交代；要做成 fixture 只能提交轉出來的指令與檢查碼，檔名與內容不帶遊戲名稱）。
   重播：取出存檔的 `game` 物件存成檔，`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_ONLY=hk DEPOT_RETURN_FROM=<檔> swift test --skip-build --filter DepotReturnReportTests/testHongKong`。
3. **擬實規則下南港島綫、東涌綫大量誤點與丟班**（HK-LATE-RUNS）：不平衡的來源，沒有動。
4. **6.2 秒卡頓**（STALL-0229）：裝置上沒量。Linux 上作者的存檔、135 版：`deadlockedTrains()` 14 ms、`situationAlerts()` 19 ms、60 倍速 600 tick 共 9.2 秒、最慢一個 tick 165 ms，沒有重現。
5. **下載的香港地圖包沒被採用**（HK-PACK-INCOMPLETE）：`MapPackDownloads` 的檢查說裝置上那一包少 `airfields.json` 或大小不符；內建那一包 15 個檔都對。和死結無關，沒有往下查（下載的那一包怎麼做出來、怎麼送到裝置還沒看）。
6. 香港各線的車廠資料（HK-DEPOTS）；簡化規則或沒有閉塞區間時的同一種不平衡（等觸發）。
7. 規劃 05:10、05:20 的訊息要的兩件事：重放作者的存檔做了（上面）；**HEALTH-136 那幾格（機捷有乘客擬實、文湖簡化加管制）沒有重量**，session 停手了。這一招的條件是沒有機廠的路線，台灣的世界碰不到，但沒有用雜湊確認。
8. 找過什麼：參考庫與外部專案這次都沒有搜尋（修法接在這個專案自己的決策 808 後面）；接手做第 2、3、6 項的人照 CLAUDE.md 先找。
