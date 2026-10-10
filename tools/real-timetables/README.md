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
