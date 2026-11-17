# REVIEW-L27＋HEALTH-137（2026-11-17）

- 派工：規劃 session_01JMHz9caNPdHNkVjVgrCB6J（137 發版後的例行審查與健檢）。session `session_01JMHz9YJbkYec1ERxquXPKR`，雲端 Linux，分支 `claude/review-l27`，PR #2376。
- 只寫文件：GameCore、GamePresentation、存檔（107）、golden schema（77）、決策編號都不動；`GoldenScenarios/`、`SaveFixtures/`、`ReplayFixtures/` 沒有動；報告測試也沒改（香港的世界 #2347 已經加了）。

## 進度

- **做到哪**：做完了，PR #2376。這個 session 壓縮過 1 次，不再接新工作；下面「還留下的」沒有人在做。
- **已驗證（Linux release，`85507e2` 與 `19f3cc5` 各量一次）**：六組 174 格 0 失敗；機捷新線擬實沒發 2/333、5 列車死結 68 分鐘（和決策 810 §4 一樣）；香港擬實沒發 12/740、誤點 477/727、3 列車死結 11 分鐘；香港簡＋控 136 與 137 都沒發 31/740、0 死結。
- **下一步的第一個指令**（在 DEPOT-REAL 之後的 `main` 重量香港簡＋控）：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 .build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testHongKong`（先 `swift build -c release -Xswiftc -enable-testing --build-tests`；其他組的指令在 HEALTH-137「重現」）

## 做了什麼

- `docs/research/REVIEW_L27_2026-11-17.md`：`19f3cc5..85507e2` 合併的 PR 審查（21 點；P1 無、P2 一項、P3 六項）、#2340／#2347 的決定性與失敗原子性、#2363 沒有已知的玩家問題、137 發版說明逐句對照。
- `docs/research/HEALTH_137_2026-11-17.md`：136 → 137 健檢，結論 CONCERNS（香港簡＋控尖峰漏班是舊的、第一次上表；機捷擬實 1 → 2 班是 #2340 的已知代價）；HEALTH-HK 結案（`testHongKong` 已在報告測試裡）。
- `docs/research/PLAYER_FEEDBACK.md`：「0.6.0 (137)，2026-11-17」一節（#2363、#2353、#2350 等進了 137 但不在說明裡）。
- `docs/priorities/REVIEW-L27.md`：七項評分（HK-PEAK-CONTROL 2.40 起），規劃用 `doc_numbers.py --priorities` 併回。

## 還留下的

- 七項評分都還沒派（見 `docs/priorities/REVIEW-L27.md`）。第 1 列先重量，數字沒變再派人逐班查。
- 死結的數字只記錄、不修（照派工：死結歸 DEPOT-REAL，決策 829 §6 的 DEPOT-DAWN-QUEUE）。
- L28 從 #2369 起數，加上 137 之後才合併的 #2364、#2370–#2375 等。
- UNVERIFIED：iOS、Metal、實機（3D 外殼、對齊、記憶體、縱谷的樹、香港地圖包、冬季音樂）都沒看；教練報告這次沒跑（⚪）。

## 2026-11-18 接手：七項處理完（REVIEW-L27 工作串）

- 派工：新專案協調者，「照分數逐項、一項一個 PR、綠了就合」。雲端 Linux，分支 `claude/project-thread-e9ppta`（同名分支依序重開）。
- **已合併**：#2403 MAP-PACK-ONCE（第 2 列）、#2406 ELEVATED-SHELL-CHUNK（第 3 列，決策 827 後來）、#2410 SNAP-REANCHOR（第 4 列，決策 826 後來）。
- **量了、寫進評分檔**：第 1 列 HK-PEAK-CONTROL（23/732，卡在金鐘折返渡線）、第 5 列 OPEN3D-PEAK-MEM（同時只多 37 MB，不改）、新第 8 列 HK-CTRL-DEADLOCK（DEPOT-REAL 之後東涌綫的短死結，2.25）。
- **沒做**：第 6 列 VALLEY-TREES-GPU 要實機；第 7 列 NOTES-138 交寫 138 說明的那串（下面）。

### 下一步的第一個指令

香港簡＋控（release，先 `swift build -c release -Xswiftc -enable-testing --build-tests`，雲端 4 核約 33 分鐘）：

```sh
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 \
  .build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests/testHongKong
```

約 4.5 分鐘。金鐘的尖峰：加 `DEPOT_RETURN_WATCH=116820-116822 DEPOT_RETURN_WATCH_AT=金鐘 DEPOT_RETURN_WATCH_TRAINS=1,2,3,4,5,6,7,8,9,10`
（第二天 08:27；南港島綫 3、6、7、10 號都在等 4 號放開節點 56、57）。東涌綫的死結：`DEPOT_RETURN_WATCH=51900-52260 DEPOT_RETURN_WATCH_AT=東涌`（第一天 14:25–14:31）。

### 138 的說明（第 7 列）

照 [REVIEW-L27「137 的說明逐句對照」](../research/REVIEW_L27_2026-11-17.md) 的修法，加上這幾張：

- 香港地圖包：#2403 讓「下載完成後同一次開 App 就用上」；但下載本身在實機有沒有用上（決策 819）仍沒證實。手機上「設定 → 香港地圖」若顯示已下載才寫「會用」，否則不提。
- #2406 高架站外殼、#2410 鋪軌對齊：都是修小錯，玩家幾乎看不到，可以一句「修正淡水線高架站在某些鏡頭位置的外觀」「鋪軌時終點不會再停在別的軌道旁邊」。
- 香港新局的尖峰漏班（南港島綫 23 班）**還沒修**，不要寫成已改善；東涌綫的短死結（第 8 列）也還在。
- 3D 第一次開的記憶體：量過、不改，不寫。

UNVERIFIED：以上三張的實機畫面與手感；香港的數字只在雲端 Linux release 跑過一次（`main` `8a9ca6f`）。
