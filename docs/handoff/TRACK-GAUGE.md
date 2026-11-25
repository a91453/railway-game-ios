# TRACK-GAUGE

## 進度

- 做到哪：一張 PR 做完 GameCore 與介面（決策 970、存檔 114），分支 `claude/project-thread-nqfbdv`。
- 已驗證：見 PR 說明（本機 `swift build --build-tests -Xswiftc -warnings-as-errors` 與碰到的測試類別）。
- PR：#2671（draft），head `e8f180f` 的 CI 只有 `Swift 6.4 (Linux) / rest-1` 紅，3 個 GamePresentation 測試（2026-11-25 這串第 2 次壓縮，照規則停手，留給下一串）：
  - `Map3DTrackKindsTests.testALinesTrackIsItsTrainsKind`、`testEachKindIsDrawn`：丟出 `trainGaugeMismatch(1)`。測試在預設（1,067）軌道上放有軌距的真實車型；照 `HighSpeedTests` 的改法，鋪軌時給那台車的軌距（例如 `buildTrackEdge(from:to:gauge: .shinkansen)`），不要改規則。
  - `RollingStockSessionTests.testStaffingOrReformingWithHighSpeedSetsMakesAHighSpeedLine`（第 205–207 行）：`staffSelectedLine(type: .highSpeed)` 在預設軌道上成功，但 `reformSelectedLine(type: .highSpeed)` 把同一條線的車改成 `.highSpeed` 時被軌距擋下。先查清楚 `.highSpeed`（「High-speed set」）有沒有 `TrainGauge`：有的話派車那條路也該擋（兩條路不一致就是 bug，`staffSelectedLine` 的檢查要補），測試的 `lineWorld()` 改鋪 1,435 新幹線級；沒有的話是改車種的檢查誤擋，修 `fitsGauge`。
- 下一步：修好這 3 個、只重跑這 3 類，推上去；#2671 綠了照規則自己合（`main` 動了先併、新 head 綠了再合），接著合 `a91453/railway-assets-private-2` #467（評分狀態，guard 已綠在 `453d283`），在 #2118 回報合併並放掉號碼。其餘見下面「還留下什麼」。

## 派工與現況

- 派工：協調者第 5 任。評分：`a91453/railway-assets-private-2` `docs/priorities/GUIDEWAY-BEAM.md` 第 5 列（2.75）。作者 2026-11-24：「那在來線 跟新幹線 還有迷你新幹線呢」「都行」。
- 決策 970；存檔版本 114（113 是 JAPAN-MAP-GROW 的，決策 969）；golden schema、重播不動。

## 做了什麼（細節在決策 970）

- `TrackEdge.gauge`（`TrackGauge`：鋼軌 762／1,067／1,435／1,524 mm，限界在來線級／新幹線級），預設 1,067 在來線級，只有不是預設的才寫進存檔。
- 真實車型有 `TrainGauge`；參考車種與標準車沒有，762 以外都跑。
- 派車、改車種、手動放車、指定路徑時檢查（`trainGaugeMismatch`）；路線改道到別的軌距時拿下不合的車。
- 收購、重建、補機廠、描線、示範線照真實軌距（`TrackGauge.ofRealLine`）。
- 鋪軌工具的「軌距」選單（`chooseNetworkGauge`，App `NetworkControls.swift` 的 `gaugePicker`）；改車種時沒有合軌距的軌道會提醒（`gaugeFirstHint`）；型錄照 `runsOnTrack`（含軌距）過濾。

## 還留下什麼

1. **3D 每段依自己的軌距畫鋼軌。** `Map3DSceneTrack.swift` 現在照地區的 `look.gauge` 畫，沒看 `TrackEdge.gauge`：林鐵、七隈線（1,435）、京急（1,435）在 1,067 的地區會畫成 1,067 的軌（京急、七隈線的車輪落在軌外約 18 cm 就是這個）。改法：畫鋼軌時讀那段的 `gauge.widest`（三線軌多畫一條），`Map3DSceneKey` 要把軌距算進去。展示場景的京急、七隈線用 1.435 m，空港線、貝塚線 1.067 m。
2. **迷你新幹線的車種**：現在沒有 1,435 在來線級的真實車型（`TrainGauge.standard` 只有 `C381`）。日本地圖要做山形、秋田時加 E3、E6 系等，限界是 `.conventional`、軌距 `.standard`，就能同時跑新幹線與迷你新幹線的線。
3. **台鐵支線仍可跑標準車與參考車種**（它們沒有軌距）。若之後替收購的台鐵線換成真實車型，限制自然生效，不用再改規則。
4. **截圖**：鋪軌工具多一個選單，屬「現有畫面的小改」，依 ui-review 由這串自己看；這張沒有跑 `website-screenshots.yml`（UNVERIFIED，等作者發版後看）。
