# PRE-LAUNCH-DEBUG：0.6.0 上架版送審前的發版例行 debug

規劃3「上架前 debug 檢查」串（分支 `claude/project-thread-tqlxm0`），2026-11-27 凌晨（台灣）。
接 `docs/handoff/POST-148-CI-DEBUG.md`。存檔版本、決策編號、golden schema：都不動。這一串沒有改任何程式。

## 結論

main `c5a6892`（#2770 合併後）沒有找到遊戲的 bug：新功能測試與五組時刻表體檢在本機全過。
找到一個 CI 的風險：#2765 把台灣高鐵加進 `taiwan-metro-realistic` 體檢以後，這組在本機要 49 分鐘，
而 `ci.yml` 的 `timetable-checkup` job 上限是 60 分鐘（之前約 15 分鐘）。CI 機器慢一點就會逾時變紅，
夜間完整測試紅了就不符合發版條件。修正：把上限調高（另一張小 PR，見「下一步」1）。
上架前剩「完整 run 證明」：送審用的 commit 的夜間（或手動）`ci.yml` 和 full lane 都綠。

## 查了什麼

### main 的 CI（看過的 run）

| run | commit | 結果 | 原因 | 現況 |
|---|---|---|---|---|
| 夜間 `ci.yml` 45733575677、手動 45805083341 | `8174381`→`f1da01c` | 紅 | 只有香港時刻表體檢（#2727 普查人口，決策 1008） | 預算已在 `f163ea9` 改；本串在 `c5a6892` 本機重跑兩組都過（下表） |
| full lane `ios-build.yml` 45805119006 建置 job | `f1da01c` | 紅 | `MapInteractionTests.testTheTrackOptionsShowWhetherTheyAreOn` | #2760 已修（合於 13:41 UTC），待下一次 full lane 證明 |
| 同 run 的 iPad 教學 job | `f1da01c` | 紅 | `TutorialUITests.testTraditionalChineseTutorialNavigation` 超過 8 分鐘：每一次點按前「Wait for com.apple.springboard to idle」都等滿 60 秒（模擬器的系統畫面一直不閒），不是 App 的錯；`testTheLineStepLeavesTheLinesPanelUsable` 第一次失敗、重試過（flaky） | 沒動。下一次 full lane 若同樣卡在 springboard，再看 iPad 模擬器開機後是否有系統彈窗或要不要先關掉動畫 |
| push `ci.yml`：#2765、#2768、#2766、#2756、#2751 | | 綠 | | #2769、#2773 是被新 push 取代（cancelled），#2772、#2770 本串結束時還在跑 |

### 本機（Linux，Swift 6.4，main `c5a6892`）

- VERIFIED：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨。
- VERIFIED：新功能相關測試全過（0 失敗）：`ThsrSaleTests`、`LineAcquisitionTests`（高鐵收購）、`Map3DLandmark*`、`Map3D{Fukuoka,HongKong,Taipei,SunMoon}LandmarksTests`、`StationLandmarkNamingTests`（22 件地標、32 km 分區預算）、`CatalogLineStockTests`、`CatalogTrackFilterTests`、`RollingStockCatalogTests`、`Map3DHighSpeedSetsTests`、`Map3DTHSR700TTests`、`Map3DKyushuN700Tests`、`Map3DKyushu800Tests`、`KyushuShinkansenTests`、`NishiKyushuShinkansenTests`、`Map3DC341IntegrationTests`、`Map3DEMU800IntegrationTests`（型錄、選擇車種）、`HighSpeedDemoTests`（高鐵渡線）、`SavedGameTests`、`ReplayFixtureTests`、`GoldenScenarioTests`、`Map3DModelPackLockTests`（舊存檔、重播、模型鎖）。
- VERIFIED：夜間才跑的時刻表體檢（`TIMETABLE_CHECKUP=1`，和 ci.yml 的 `timetable-checkup` 同一個指令）：

| 組 | 結果 | 重點數字（不發／誤點／出庫誤點／尖峰間隔） |
|---|---|---|
| hong-kong-simple | 過 | EAL_LMC 0/36/0/+7、SIL 0/80/1/+6、TCL 與 TCL+AEL+DRL 1/67/7/+19 |
| hong-kong-realistic | 過 | EAL_LMC 0/15/0/+7、SIL 0/68/0/+6、TCL 0/11/1/+6、TCL+AEL+DRL 0/11/1/+5 |
| taiwan-metro-simple | 過 | trtc:BR 6/181/29/+8、tymc:A 13/92/9/+31（老問題，決策 968） |
| branch-lines-and-rovaniemi | 過 | 支線、羅瓦涅米全 0；福岡三線兩種規則 0/0/0/+4（預算 +4，貼邊）；淡海輕軌 V+VB simple 0/1/0/+7 |
| taiwan-metro-realistic | 過，但很慢 | thsr_sched:THSR 0/38/9/+12（預算 0/38/9/+12）、trtc:BR 0/150/0/+7、tymc:A 1/5/2/+4；**整組 2,944 秒（49 分）**，台灣高鐵一條就 2,103 秒 |

香港數字和 `POST-148-CI-DEBUG.md` 的表一模一樣，表示 #2765（高鐵收購）、#2768／#2769（地標）、拆分 PR 都沒有再動到香港。

### 沒有做的

- 模擬器或實機畫面：沒有開模擬器看。高鐵收購畫面、地標外觀、型錄、選擇車種會不會卡、高鐵渡線閃不閃，Linux 只能證明邏輯與資料；畫面留給 full lane 的 UI 測試和 Chien 實機（清單在記憶「發版後提醒 Chien 實機看」）。
- 舊模型刪除 #2776（配方 700T、#1103 蒸汽機車、CT273 替身）還沒合，是清查串的；PR 說存檔只存車種鍵、舊鍵早已轉新車。合併前它自己的 CI 會跑 `SavedGameTests`。

## 下一步

1. `ci.yml` 的 `timetable-checkup` 的 `timeout-minutes: 60` 調到 90（第二張 PR 已改；若沒合到，接手的人照做）。之後可以考慮把台灣高鐵拆成自己的一組體檢，讓它和捷運平行跑。
2. 等夜間 `ci.yml` 與 full lane 跑在 main 上（cron 17:37／18:17 UTC，常延遲數小時；main 若一直在合拆分 PR，就由統籌串挑送審 commit 手動各跑一次）。
3. 看 full lane 的 iPad 教學 job：若 `testTraditionalChineseTutorialNavigation` 又是 springboard 等 60 秒、超過 8 分鐘，開一張 CI 單（不是 App bug），先別擋送審。
4. 福岡尖峰間隔 +4 剛好等於預算，下次重鋪福岡地圖包時要手動跑一次體檢（決策 582「後來」已記）。
5. 地圖包（11-27 補）：上架版改回不內建。本機內測 0.6.0 (152.1.1) 只帶 `pack.json`，作者 iPhone 上下載、刪除後重新下載都正常，所以 `CARRY_MAP_PACKS` 預設改成 NO、`testflight.yml` 的 `carry_map_packs` 與本機腳本預設都改成 `no`（DEBUG-150「進度」）。送審時「素材包」要附上六包現行版本。
