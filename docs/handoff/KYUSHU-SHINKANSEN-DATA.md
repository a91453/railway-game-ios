# KYUSHU-SHINKANSEN-DATA 交接

評分在私有 repo `docs/priorities/JAPAN-KUMAMOTO.md` 第 2 項；前後的單見 `docs/handoff/JAPAN-MAP-GROW.md`。

## 做了什麼

- 九州新幹線博多到熊本 7 站的線形、站名（日、中、英）、高架與隧道、估計班距與一天的班次、熊本総合車両所（富合）的位置，
  放在暫存資料夾 `tools/fukuoka-map/kyushu-shinkansen/`。**遊戲不讀，地圖包沒動，玩家看不到變化。**
  不動 GameCore、GamePresentation、存檔、決策、golden。
- 工具 `tools/fukuoka-map/build_kyushu_shinkansen.py`（用 `build_fukuoka_rail.py` 的讀法），來源、數字與估計的依據在
  `tools/fukuoka-map/README.md`「九州新幹線」一節與 `kyushu_shinkansen_sources.json`。
- 已驗證（雲端 Linux）：工具重跑兩次輸出相同；量到 98.15 km（新幹線自己的長度 98.2 km）；7 站都在新範圍裡；
  `doc_numbers.py --check` 過。

## 還留下什麼（SHINKANSEN-SALE、KUMAMOTO-OPEN 接）

- **搬進地圖包**：把暫存的檔併進 `MapPacks/fukuoka/` 的 `track_lines.geojson`、`track_stations.geojson`、`station_names.json`、
  `rail_structures.json`，加 `kyushushinkansen.json` 與 `_times.json`，再排 `metro_runs.json`
  （`extract_fukuoka_runs.py` 現在只排 `fksubway`；`DEPOT_ENDS` 要加 `kyushushinkansen:KS` → 熊本），改 `pack.json` 的 `SOURCES`。
  要等 KUMAMOTO-GROUND 把包的範圍長到熊本，否則 6 站在圖外。
- **機廠**：`depot.json` 有分岔點、入出庫線與留置線兩端，照 `tools/rail-depots/README.md` 的做法寫成 `RealLineDepotSite`。
  真實的機廠在熊本站過去 8.45 km，待售的線只到熊本站：要嘛收購時把熊本到分岔點那段正線一起鋪（`depot.json` 的 `mainLine`），
  要嘛像橋本那樣把機廠放在線尾附近。先讀 depot-work skill。
- **博多共站**：和空港線、七隈線同名「博多」，照 real-line-laying skill §2 做共站測試（新幹線在高架、地鐵在地下，
  規則是共站同高，怎麼處理在那張單決定）；熊本站之後和市電共站。
- **班次是估計且全部各站停**，86 班一天。排車後要看：熊本端一股停一列夠不夠、博多折返 12 分在遊戲的停站規則下會不會晚
  （七隈線為此留了 `RECOVERY`）。通過中間站的車是 KYUSHU-SHINKANSEN-EXPRESS，還沒評分。
- 軌距、限界、電化的欄位已寫在線與機廠上，等 TRACK-GAUGE、TRACK-ELECTRIFICATION 定欄位名後對一次。
- UNVERIFIED：估計班距的依據只看到 2023 年改點的報導，沒有逐班核對 JR 九州的時刻表；首末班時間是估計。
