# TRACK-GAUGE

## 進度

- 做到哪：一張 PR 做完 GameCore 與介面（決策 970、存檔 114），分支 `claude/project-thread-nqfbdv`。
- 已驗證：見 PR 說明（本機 `swift build --build-tests -Xswiftc -warnings-as-errors` 與碰到的測試類別）。
- 下一步：下面「還留下什麼」。

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
