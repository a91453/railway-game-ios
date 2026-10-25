# 真實班次（決策 133）

`extract_pingxi_runs.py` 從參考庫 `Railway/` 網站的 `data/tra_schedule_dense.json`（臺鐵開放資料 ods.railway.gov.tw 的 14 天時刻表，依「政府資料開放授權條款第 1 版」使用）擷取平溪線的列車，寫成 App 的 `RailwayGameApp/Resources/RealRailways/tra_pingxi_runs.json`，給實景示範地圖照真實時刻發車。

```sh
git clone --depth 1 https://github.com/a91453/railway-reference-private /tmp/ref
python3 -I tools/real-timetables/extract_pingxi_runs.py \
  /tmp/ref/Railway/site_archive_clean/data/tra_schedule_dense.json \
  RailwayGameApp/Resources/RealRailways/tra_pingxi_runs.json
```

- 一條路線：八斗子—海科館—瑞芳—猴硐—三貂嶺—大華—十分—望古—嶺腳—平溪—菁桐。停靠平溪線車站的每一班車都取進來，從它在這條線上的第一站到最後一站：八斗子的直通車整班，八堵的車從瑞芳起（八堵—瑞芳是宜蘭線，示範照班距開）。
- 星期幾開：取時刻表第一週（2026-10-02 到 10-08，沒有假日）每天實際開的車；後面的日期可能是假日時刻（10-09 是國慶補假，開週末的車）。
- 真實的車組每天不會回到原處（有些從主線開來、開回主線）。所以每天加一班回送：十分 04:15 開往瑞芳，時刻照 4735 次那一段，讓前一天最後一班（4744 次，到十分）趕上第一班（4704 次，瑞芳 05:07）。
- 程式檢查每天開始與結束時車組都在相同的站（三組：十分、菁桐、瑞芳各一），寫在檔案的 `overnight`。
- 參考庫的檔案更新時重跑，並重跑 `RealWorldDemoGroundTests`。

## 宜蘭線的平日（決策 240）

`extract_yilan_schedule.py` 從同一份 `tra_schedule_dense.json` 擷取 2026-10-05（星期一，沒有假日）頭城到蘇澳新之間停靠兩站以上的列車，寫成 App 的 `RailwayGameApp/Resources/RealRailways/tra-yilan-schedule.json`（格式同 `thsr-schedule.json`，`RealDailySchedule`），給台鐵示範照真實時刻發車。

```sh
python3 -I tools/real-timetables/extract_yilan_schedule.py \
  /tmp/ref/Railway/site_archive_clean/data/tra_schedule_dense.json \
  RailwayGameApp/Resources/RealRailways/tra-yilan-schedule.json
```

- 142 班：區間車、區間快、自強（EMU3000、普悠瑪、太魯閣、推拉式、柴聯）、莒光。新馬那天沒有車停，不取。
- 示範的鐵路止於頭城與蘇澳新；開往更遠處而通過這兩站的列車，在該站照通過時刻算一次停靠，所以自強號跑完全程。
- 通過站的時刻照網站的沿線內插（`passes`），示範用它算路線的停靠時刻。
- 參考庫的檔案更新時重跑，並重跑 `TRADemoTests`、`TRADemoDayTests`。

## 輕軌的班次（決策 400，10j-2）

`extract_metro_runs.py` 讀 App 已打包的 `<系統>.json`（每條線的車站順序）與 `<系統>_times.json`（交通部 TDX 的各站時刻，參考網站 2026-07-16 抓的，政府資料開放授權條款第 1 版），排成玩家可以收購的輕軌的班次，寫成 `RailwayGameApp/Resources/RealRailways/metro_runs.json`；之後照 `extract_branch_runs.py` 的 `line_runs` 檢查、排過夜與回送（同一個工具，多了 `start` 與 `balanced`，台鐵支線的輸出一個位元組都沒變）。

```sh
python3 -I tools/real-timetables/extract_metro_runs.py \
  RailwayGameApp/Resources/RealRailways \
  RailwayGameApp/Resources/RealRailways/metro_runs.json
```

- 淡海藍海線（紅樹林—淡水漁人碼頭）：208 班真實的車、4 班回送、5 組車（過夜：紅樹林 3、漁人碼頭 2）。另有「綠山線已買下時」從濱海沙崙起的一份（4 組車）。
- 淡海綠山線不收：紅樹林要 7 條、崁頂要 6 條軌道過夜，遊戲的終點站只鋪 5 條（自己的線加兩側各兩層待避線；真實的崁頂機廠停 13 組裡的 9 組）。
- 安坑輕軌還沒收：工具排得出來（303 班、7 組車），但遊戲鋪的第二條正線在它的急彎上會與第一條太近；見 `docs/HANDOFF.md` 第 5 節。
- 高雄環狀輕軌不收：單向繞圈回到籬仔內，遊戲的線是兩端折返。
- 時刻表更新時重跑，並重跑 `RealLineAcquisitionTests`。
