# 台鐵真實誤點的統計

`docs/research/TRA_DELAY_ANALYSIS_2026-10-27.md`（派工單 AA）的數字從這裡來。只用 Python 標準函式庫。

## 輸入（都在私庫 `a91453/railway-reference-private`，不放進這個公開的 repository）

- `Railway/tdx-snapshot-2026-10/data/TRA_LiveTrainDelay_*.jsonl.gz`：TDX 的台鐵歷史誤點，2025-11-20 到 2026-10-26，87 個檔、24,390,062 筆。授權：政府資料開放授權條款第 1 版，「交通部運輸資料流通服務平臺（TDX）」。
- `Railway/taiwan-rail-reference-clean/source/data/tra_schedule.json` 與 `tra_station_info.json`：台鐵 2026-10-16 起 14 天的時刻表（臺鐵開放資料），用來把車次對到車種與停靠順序。

只要 sparse checkout 這兩處：

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/a91453/railway-reference-private ref
git -C ref sparse-checkout set --no-cone /Railway/tdx-snapshot-2026-10/ \
  /Railway/taiwan-rail-reference-clean/source/data/tra_schedule.json \
  /Railway/taiwan-rail-reference-clean/source/data/tra_station_info.json
```

## 重跑

```sh
python3 -I tools/tra-delay-analysis/analyze.py \
  --data ref/Railway/tdx-snapshot-2026-10/data \
  --timetable ref/Railway/taiwan-rail-reference-clean/source/data \
  --out tools/tra-delay-analysis/results
```

一次約 3.5 分鐘（Linux 雲端 session，2026-10-27）。輸出是 `results/` 的小 CSV，每次重跑內容相同。

## 定義

- **一趟**：同一個車次號的回報，依 `SrcUpdateTime` 排序，相隔超過 8 小時就切成下一趟。台鐵同一車次一天只開一次，最長的環島車加上大誤點也不到 8 小時沒有回報。一趟的日期與時段照它第一筆回報的台灣時間。
- **那一趟的誤點**：最後一個有回報的時刻表停靠站，該站最後一筆 `DelayTime`。TDX 只在列車離開或通過車站時回報，終點站沒有回報，所以多半是終點的前一個回報站（233,212／234,693 趟落在最後兩個回報站）。對不上時刻表的趟，用最後一個回報站。
- **準點**：那一趟的誤點 ≤ 5 分（台鐵以抵達終點站延遲 5 分鐘以內為準點）。
- **對上時刻表**：那個車次在 2026-10 時刻表裡，而且它停靠站中「會回報的車站」（約 150 個，最新一個檔出現過的）有 80 % 以上這一趟回報了。對上的才分車種與沿路位置；其餘歸「未對上時刻表」。
- **尖峰**：平日 06:30–09:00、16:30–19:30 出發（第一筆回報）。
- **連假**：`analyze.py` 的 `HOLIDAYS`（人事行政總處 114、115 年辦公日曆表）。

## 輸出

| 檔案 | 內容 |
| --- | --- |
| `overview.csv` | 筆數、車次數、車站數、時間範圍、趟數、對上時刻表的趟數 |
| `final_by_*.csv` | 每趟誤點依全部、車種、車型（carName）、尖離峰、星期、月份、連假、出發小時分組：趟數、準點率、平均、中位數、90／99 百分位、最大 |
| `max_by_type.csv` | 同上，但用一趟中最大的誤點 |
| `final_histogram.csv` | 每趟誤點的分布 |
| `along_route.csv` | 依停靠順序切成十段，每段停靠站的誤點（沿路累積） |
| `event_by_hour.csv` | 每筆回報依台灣時間小時分組 |
| `by_day.csv` | 每天的筆數、趟數、準點率、平均、最大 |
| `worst_trips.csv` | 一趟中最大誤點最多的 40 趟 |
| `station_departure_on_time.csv` | 各回報站（趟數 ≥ 1,000）離站的準點率，由低到高 |
| `month_timetable_match.csv` | 各月對上 2026-10 時刻表的比例 |
