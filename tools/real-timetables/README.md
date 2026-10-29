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
- 輸入維持舊的 `Railway/site_archive_clean/data/tra_schedule_dense.json`：新版 `taiwan-rail-reference-clean/source/data/` 的同名檔是 2026-10-16 的新時刻表，與打包資料不同（2026-10-05 不在其中，平溪線也少一班），所以不能換。
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

## 輕軌與捷運的班次（決策 400，10j-2、10j-3）

`extract_metro_runs.py` 讀 App 已打包的 `<系統>.json`（每條線的車站順序）與 `<系統>_times.json`（交通部 TDX 的各站時刻，參考網站 2026-07-16 抓的，政府資料開放授權條款第 1 版），排成玩家可以收購的輕軌與捷運的班次，寫成 `RailwayGameApp/Resources/RealRailways/metro_runs.json`；之後照 `extract_branch_runs.py` 的 `line_runs` 檢查、排過夜與回送（同一個工具，多了 `start` 與 `balanced`，台鐵支線的輸出一個位元組都沒變）。

```sh
python3 -I tools/real-timetables/extract_metro_runs.py \
  RailwayGameApp/Resources/RealRailways \
  RailwayGameApp/Resources/RealRailways/metro_runs.json
```

- 淡海藍海線（紅樹林—淡水漁人碼頭）：208 班真實的車、4 班回送、5 組車（過夜：紅樹林 3、漁人碼頭 2）。另有「綠山線已買下時」從濱海沙崙起的一份（4 組車），收購時鋪在綠山線旁 30 m（決策 489）。
- 淡海綠山線（紅樹林—崁頂，決策 489）：249 班真實的車、5 班回送、13 組車（過夜：崁頂 9、紅樹林 4）。和崁頂後面真實的淡海機廠一起收購（`DEPOT_ENDS`）：崁頂的 9 組晚上停在機廠，白天用不到的車也回機廠，所以軌道只算兩小時內要發車的車（`depot_tracks`）：紅樹林 6、崁頂 6，端點最多 7 條（兩側各三層待避線）。把紅樹林的 4 組在半夜送回去的回送照真實時刻表留著。
- 淡海綠山線在藍海線之後不收：從濱海沙崙起，班次在那裡切斷，濱海沙崙同時要停 11 組，端點最多 7 條（`docs/HANDOFF.md` 第 5 節）。
- 安坑輕軌還沒收：工具排得出來（303 班、7 組車），但遊戲鋪的第二條正線在它的急彎上會與第一條太近；見 `docs/HANDOFF.md` 第 5 節。
- 高雄環狀輕軌不收：單向繞圈回到籬仔內，遊戲的線是兩端折返。
- 捷運（10j-3，`METROS`）：一天後面已經沒有班要用的車，一進站折返好就回過夜的站（`balanced` 的 `prompt="spare"`），不等最後一班發出；捷運的晚上進站的車比發出的快。台鐵支線不走這條，輸出沒變。
  - 新北投支線（北投—新北投）：298 班、1 班回送、3 組車（過夜：北投 2、新北投 1）。
  - 小碧潭支線（七張—小碧潭）：243 班、沒有回送、3 組車（過夜：七張 1、小碧潭 2）。
  - 不收（終點站同時要停的車比遊戲鋪的 5 條軌道多）：淡水信義線（25 條）、松山新店線（14）、中和新蘆線新莊端（迴龍 8）與蘆洲端（南勢角 6、古亭 4、蘆洲 8；共用的主線因此也不做）、板南線（13）、環狀線（12）、桃園機場線（8）、高雄紅線（小港、岡山車站各 8）、橘線（大寮 7）、台中綠線（北屯總站、高鐵臺中站各 6）。文湖線不試（35 m 的彎）。
  - 三鶯線（頂埔—鶯桃福德，`sanying:LB`）：398 班、8 班回送、12 組車（過夜：頂埔 4、鶯桃福德 4，媽祖田、長壽山、國華、永吉公園各 1）。端點只有 5 條軌道，所以 4 組停在中間站的正線上；晚上把它們送過去的回送（`extract_branch_runs.facing`）從另一端開來，停在往較近端點的那一條、面向它（遊戲半夜擺車的樣子），並且在當天最後一班經過那站之後才到；較靠端點的那一站先送，另一班才不會開過停著的車。以前照「一進站就送」從近的端點開過去，停在反方向的正線上，擋住當晚最後幾班，整條線從第二天起停住（決策 400 的「量到的」10j-3）。
- 時刻表更新時重跑，並重跑 `RealLineAcquisitionTests`。
