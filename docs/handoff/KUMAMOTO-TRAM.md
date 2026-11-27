# KUMAMOTO-TRAM：熊本市電 A、B 系統接進福岡地圖（交接）

## 進度

- 做到哪：資料、時刻表、車種接線都寫好了，**沒有 commit**；未完成的改動存成 patch（下面「接手」）。前一個工作串壓縮 3 次後照規則停手。
- 已驗證：轉換工具跑過（A 26 站 9.08 km、平日 246／土曜 248／日祝 247 班；B 28 站 9.33 km、134／132／132 班）；試跑排班（`STABLED_AT`、折返 180 秒、`OUT_BEFORE_FIRST` 關）A 20 組全在交通局前過夜，B 20 組在上熊本，「B after A」辛島町–上熊本 265 班 8 組；`swift build` 無錯（沒跑 `-warnings-as-errors` 與測試）。
- 下一步的第一個指令：在最新的 `main` 上 `git apply --index /mnt/project-files/kumamoto-tram/kumamoto-tram-wip.patch`（套不上就用 `kumamoto-tram-code-only.patch` 再重跑工具，見下）。

## 派工

- 派工：規劃 4 工作串「接入熊本市電和山頂纜車」，規則在 assets-2 `docs/handoff/STREET-TEMPLE-VIADUCT-TRAM-RULES.md` §5（#635 已合）。
- 前一個 session：session_01YGNNupQeXdRJTTLMvavPYm，分支 `claude/project-thread-tm8kl1`。山頂纜車那一半是 #2837（決策 1040）。
- 號碼：**決策 1041 已在 #2118 保留**；存檔版本、golden schema 不動。GameCore 會動（`TrackGauge` 多一個系統），所以 PR 跑整個 tier。

## 接手

patch 在專案共用資料夾 `/mnt/project-files/kumamoto-tram/`（底是 #2837 的 head `6a4d4121`，已合進 main 的 `bd6a1c04`）：

- `kumamoto-tram-wip.patch`：全部（含福岡地圖包合併後的檔，約 0.9 MB）。
- `kumamoto-tram-code-only.patch`：只有程式與工具（含暫存的 `tools/fukuoka-map/kumamoto-tram/`），地圖包要重跑工具產生。

重跑（輸入的雜湊記在 `tools/fukuoka-map/kumamoto_tram_sources.json`）：

```sh
# GTFS（CC BY 2.1 JP，熊本市交通局）：https://api.gtfs-data.jp/v2/organizations/kumamoto-shiden/feeds/kumamotoshiden/files/feed.zip?rid=current，解到 <gtfs>
# OSM：https://osmtoday.com/asia/japan/kyushu.pbf（整份，不裁）
python3 -I tools/fukuoka-map/build_kumamoto_tram.py <gtfs> <kyushu.pbf> tools/fukuoka-map/kumamoto-tram
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge tools/fukuoka-map/kumamoto-tram RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka
```

## 已經做的（在 patch 裡）

- `tools/fukuoka-map/build_kumamoto_tram.py`（新）：GTFS 的站與時刻（兩方向站位取平均、檢查站相連、站間時間取中位數減停站 20 秒）＋ OSM `railway=tram` 的軌道；A 紅 #E50014、B 藍 #005BAC（官方色）；軌距 1,435、DC 600 V、40 km/h。B 寫 `shares: kumamotocity:A`（辛島町以西共線），照決策 862 一起賣。
- `build_kyushu_shinkansen.py`、`build_fukuoka_rail.py`、`extract_fukuoka_runs.py`：加 `kumamotocity` 系統、來源與「B after A」。
- `tools/real-timetables/extract_metro_runs.py`（和台灣共用，預設空，別的輸出不變）：新 `STABLED_AT`（沒有機廠的線，讓車在指定站過夜，並限制各站的股數）。
- Swift：`OverseasMaps`（系統與兩條線，`.lightRail`）、`TrackGauge`（標準軌）、`Map3DOverheadLine`（架空線）、`DemoRealLines`（1 節、C 型）、`Map3DRealTrainsJapan`（先借 `klrtCitadis` 當替身）、`RealLineAcquisition`（日文線名；路面電車站 26 m 讓 `Map3DTramStop` 畫成無頂電車站；線與車的性能上限 40 km/h）。

## 還留下的

1. `extract_fukuoka_runs.py` 要設 `tool.STABLED_AT = {"kumamotocity:A": "交通局前", "kumamotocity:B": "上熊本"}`，並讓這兩條線 `OUT_BEFORE_FIRST` 關（福岡整體是開的；開著時 A 報「weekday 0: no train for 20 after positioning」）。可能要把 `OUT_BEFORE_FIRST` 改成每條線各自設。改完重跑，patch 裡的 `metro_runs.json` 是加 `STABLED_AT` 之前產的，熊本兩條線沒進去。
2. 機廠（先讀 `depot-work` skill）：OSM 有真的兩處，`RealLineDepotSite.sites(of:)` 加：
   - 大江（A，交通局前旁，`beyond` nil）：way 1086686019、1086686020、1086686021，約 32.7975–32.7981 N、130.7200–130.7202 E。GTFS 清晨東行從味噌天神前、西行從交通局前出車，對得上。
   - 上熊本（B 端點，`beyond: "上熊本"`）：way 413212655–413212667，約 32.8164–32.8176 N、130.6988–130.6993 E。
   有了機廠，`STABLED_AT` 可能就不需要；照 skill 量過再決定。
3. `DataSourceCredits`（福岡）加熊本市交通局 GTFS（CC BY 2.1 JP，https://creativecommons.org/licenses/by/2.1/jp/）。
4. 測試：新 `KumamotoTramTests`（包裡的線與站、B after A 的班次、一起賣 `[A, B]`、標準軌、在 `FukuokaRailwaysTests.fukuoka(start: 2)` 買下、跑一天不死結）；更新列系統數的測試：TrackGaugeTests、DemoRealLinesEverySystemTests、RealRailwaysTests、RealRailwayGameplayTests、TimetableCheckupAllBoughtTests、CheckupBudgets/Fukuoka.swift、FukuokaRailwaysTests、RealLineBundleTests、SharedStationLayoutTests。
5. 決策 `docs/decisions/1041.md`（五個角度）、`WhatsNewNext/` 一行、`tools/fukuoka-map/README.md`。
6. 晚點：GTFS 到分、到站等於離站，遊戲最短停站 36 秒，可能會晚點；用 checkup 量。

## 規則裡還沒做、要另開的

- 車種：工作室模型 `kumamoto-tram-lowfloor` revision-6 還沒審，而且用了新色 `wine` #943040，要先問 Chien（規則 56：說最接近的現有色與為什麼不夠）。之前先用替身車。定員 82 遊戲裡沒有對應（用 C 型）。
- 路上的車避開軌道（只在畫面層）。
- 3 節的 2400 形與單節舊車之後再做。

## UNVERIFIED

全部：還沒 commit、沒跑測試、沒有 CI。
