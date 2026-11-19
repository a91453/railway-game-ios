# TYMC-SINCE-138（2026-11-19，決策 886）

工作串「修機捷改建線又卡車」。HEALTH-140 的新項：機捷改建線新局規則（簡＋控）138 後出現死結。

- **做完**：原因是決策 850（不是 877）；決策 886 讓班次跟車的 claim 也不綁「前車出站路上、到點要開的班次」。改建線簡＋控死結 9 列 → 0，其餘 28 個世界逐分與最高倍速雜湊逐位元相同（決策 886 §4）。
- **沒做**：TYMC-A12-A13（擬實航廈站互等、舊線不動簡＋控 17:19 七列）照舊，886 §5、§6 記了這次試過的兩種寫法。
- **重現**：

```sh
swift build -c release -Xswiftc -enable-testing --build-tests
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_EMPTY_RUNS=1 DEPOT_RETURN_CHECKSUM=1 \
  DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_ONLY=tymc-rebuilt \
  .build/release/GamePresentationTests-test-runner GamePresentationTests.DepotReturnReportTests
```

一次 release 建置在雲端 4 核約 35–45 分（GameCore 一動就全部重編），一格兩天約 12 分；看某幾分鐘每列車等誰用 `DEPOT_RETURN_WATCH=<起>-<迄>`（秒）加 `DEPOT_RETURN_WATCH_TRAINS=<編號,...>`。
- **教訓**：決策表上的「雜湊不變」要看是在哪個 commit 量的；分支併 main 之後要重量一次。
