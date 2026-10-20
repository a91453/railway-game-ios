# 真實車站的運量

決策 298：實景地圖的轉乘站照真實車站的運量給轉乘點數。這個資料夾的工具把官方開放資料整理成 App 內附的小檔，只用 Python 標準函式庫。

## 台鐵：`build_tra_ridership.py`

**來源**：政府資料開放平臺的[臺鐵每日各站點進出站人數](https://data.gov.tw/dataset/8792)（國營臺灣鐵路股份有限公司），依政府資料開放授權條款第 1 版使用，要標示出處（遊戲的資料來源畫面「臺鐵開放資料」那一項）。

**輸出**：`RailwayGameApp/Resources/RealRailways/tra_ridership.json`。一個完整年度裡，每站平均一天的人次：（進站＋出站）÷ 2，除以那一站有資料的天數，四捨五入。用台鐵的站碼當 key，就是 App 的 `tra_station_info.json` 的 `id`。檔案裡記著資料集、檔名、壓縮檔的 SHA-256、下載日期、授權與期間。

### 怎麼更新

1. 先看最新的檔到哪一天。資料集頁面寫「每月更新」，實際上 2026-10-20 查的時候最後修改是 2026-03-17、最新的年檔到 2025-12-31：

   ```sh
   curl -s https://data.gov.tw/api/v2/rest/dataset/8792 | python3 -I -c 'import sys,json; d=json.load(sys.stdin)["result"]; print(d["modifiedDate"]); [print(r["resourceDescription"], r["resourceDownloadUrl"]) for r in d["distribution"]]'
   ```

2. 下載「自 2019-04-23 起」那份壓縮檔（每年一個 CSV），放在 scratchpad，不進 repository：

   ```sh
   curl -o tra-ridership.zip https://ods.railway.gov.tw/tra-ods-web/ods/download/dataResource/8ae4cac3799a9b6b01799d00fd37014b
   ```

3. 用**最近一個完整年度**（不用今年只有一部分的、也不用 2020–2022 疫情那幾年）：

   ```sh
   python3 -I tools/real-ridership/build_tra_ridership.py tra-ridership.zip \
       --year 2025 --downloaded 2026-10-20 \
       --stations RailwayGameApp/Resources/RealRailways/tra_station_info.json \
       --output RailwayGameApp/Resources/RealRailways/tra_ridership.json
   ```

   年度不滿 365 天就拒絕。它會印出 App 不認得的站碼、App 有但資料沒有的站、資料天數不足一年的站：新站、改名、停駛的站都看得到，不會被默默丟掉。

**什麼時候重跑**：每年等前一年整年的檔出來（目前是隔年第一季），或有新站、新線通車時。

### 2026-10-20 的結果（2025 年）

- 241 站，2025-01-01 到 2025-12-31，App 不認得的站碼：沒有。
- App 有、資料沒有的：台北-環島（環島列車的另一個名字）、平鎮（資料裡沒有）、枋野（號誌站）、樹林調車場、潮州基地。轉乘點數退回站等的規則。
- 最多的：台北 63,307、桃園 28,045、台中 25,981、台南 25,957、板橋 25,692；最少的一天不到 10 人。
- 天數不滿一年的 30 站（停駛、颱風、施工）只用有資料的天數平均；最少的是南方小站 5 天、新馬 2 天。

## 高鐵、捷運

還沒做：要找官方的各站人次與它的授權，或在 TDX 找（`.github/workflows/tdx-check.yml` 可以用作者的金鑰抓任一 TDX API）。做好之後寫在這裡。
