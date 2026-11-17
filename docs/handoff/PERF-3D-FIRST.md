# PERF-3D-FIRST（2026-11-17）

## 進度

- 做到哪：根因修好（場景從 `Map3DModelCatalog` 取模型的位置與大小，不再等整包模型），分支 `claude/perf-3d-first` 已推；正在跑 release 量測（前後對照、模型包同時在做）。
- 已驗證：Linux 上 `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`Map3DModelCatalogTests`（3）、`Map3DModelPackLockTests`、`Map3DModelPackSlimTests` 通過；目錄與模型包的名字、順序、大小逐位元相同。
- 下一步的第一個指令：`MAP3D_BUILD_SAVE=<存檔> MAP3D_BUILD_WITH_PACK=1 swift test -c release -Xswiftc -enable-testing --skip-build --filter GamePresentationTests.Map3DSceneBuildTimeReportTests/testReportOfASave`（`=wait` 是修之前的等法）。

## 派工

- 遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed 派工（NEXT_PRIORITIES §29.18 第 2 項，2.55 分，效能 bug）；實作 session_01JMHz9YukbhK9SrgZCqr1Xw，雲端 Linux，分支 `claude/perf-3d-first`。
- 決策 820（`docs/decisions/820.md`）。GameCore、存檔版本、golden schema、`SaveFixtures/`、`ReplayFixtures/` 不動。
- 這個 session 壓縮一次，照規定只做完這張票，不接新工作。
