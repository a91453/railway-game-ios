# PERF-3D-FIRST（2026-11-17）

## 進度

- 做了什麼：建 3D 場景不再等整包模型（`Map3DModelCatalog`，決策 820）；問題回報的 3D 建造那一行多寫最慢的三步。Draft PR 已開，等 CI。
- 已驗證（Linux）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；相關 89 個測試通過（`Map3DModelCatalogTests`、`Map3DSceneBuildLogTests`、`Map3DModelPackLockTests`、`Map3DModelPackSlimTests`、`Map3DRoadMarkingTests`、`Map3DSceneryPropsTests`、`Map3DRealGroundTests`、`Map3DSceneRebuildTests`、街景人車、公車、行人號誌）；release 量測見決策 820 的表（作者存檔 9.1–10.0 秒）。
- 下一步的第一個指令：作者用含決策 820 的 build 第一次開 3D，看問題回報的「建造」與「最慢」。

## 派工

- 遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed 派工（NEXT_PRIORITIES §29.18 第 2 項，2.55 分，效能 bug）；接手規劃 session_01JMHz9ZJWaKh8kjuNDLtvar。實作 session_01JMHz9YukbhK9SrgZCqr1Xw，雲端 Linux，分支 `claude/perf-3d-first`。
- 決策 820（`docs/decisions/820.md`）。GameCore、存檔版本 107、golden schema、`SaveFixtures/`、`ReplayFixtures/` 不動；場景的位元組不變（目錄與整包模型逐位元相同）。
- 這個 session 壓縮一次，照規定只做完這張票，不接新工作。

## 還留下什麼

- **UNVERIFIED**：手機上的建造時間（目標 15 秒內）；App 那一行改動（`Map3DPreviewScreen.swift` 傳 `slowest:`）只有 macOS CI 編得到。
- 2D 的 6.2 秒停頓沒查到成因：列在 §29.27 第 1 項（2.15，等觸發）。
- 場景本身再快：§29.27 第 2 項（2.10）。量法：

  ```sh
  MAP3D_BUILD_SAVE=<存檔> MAP3D_BUILD_RUNS=2 swift test -c release -Xswiftc -enable-testing \
      --filter GamePresentationTests.Map3DSceneBuildTimeReportTests/testReportOfASave
  ```

  `MAP3D_BUILD_WITH_PACK=1` 讓整包模型同時在另一條執行緒做（App 捏近 3D 時的情況），`=wait` 是修之前的等法；`MAP3D_BUILD_FOCUS`、`MAP3D_BUILD_AT`、`MAP3D_BUILD_MIDDLE` 換焦點；`MAP3D_BUILD_PACK=1` 跑 `testReportOfThePack`（配方、目錄、整包的時間）。release 從頭編約 30 分鐘。
- 作者的存檔在 `a91453/railway-assets-private` 的 `problem-reports/2026-11-17-deadlock-hk/`，不進這個 repo。
