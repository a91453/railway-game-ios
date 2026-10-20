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

## 高鐵：`build_thsr_ridership.py`

**來源**：台灣高鐵公司網站的[客運運輸情形](https://www.thsrc.com.tw/corp/9571df11-8524-4935-8a46-0d5a72e6bc7c)「各站進出旅客人數」表（2017 年起，每年一張進站、一張出站，每月一列、每站一欄、最後一欄是總計）。這是公司公布的營運統計，**沒有開放資料授權**；只取各站的年度合計（事實數字），標示出處「台灣高鐵公司」。政府開放資料平臺上找不到各站別的資料集（2026-10-20 查）。

**輸出**：`RailwayGameApp/Resources/RealRailways/thsr_ridership.json`，以站名（南港到左營）為 key，一天平均（進站＋出站）÷ 2，記著網址、頁面的 SHA-256、讀取日期與期間。每個月的 12 站要加起來等於頁面的總計，12 個月都要有，頁面改版就會失敗而不是給錯的數字。

```sh
python3 -I tools/real-ridership/build_thsr_ridership.py --year 2025 --downloaded 2026-10-20 \
    --output RailwayGameApp/Resources/RealRailways/thsr_ridership.json
```

**2026-10-20 的結果（2025 年）**：一天平均台北 47,192、台中 37,887、左營 29,402、桃園 26,857、新竹 21,577、板橋 16,051、台南 14,425、南港 11,090、嘉義 9,195、雲林 4,938、苗栗 3,617、彰化 2,621。年度進站數和 PTT 鐵道板轉貼的同一份表（[2025 全年](https://www.ptt.cc/bbs/Railway/M.1767965275.A.1BE.html)）逐站相同。頁面已有 2026 年到 9 月，明年一月起可以改用 2026 全年。

## 台北捷運：`build_trtc_ridership.py`

**來源**：政府資料開放平臺的[臺北捷運各站分時進出量統計](https://data.gov.tw/dataset/128506)（臺北大眾捷運股份有限公司，資料放在 data.taipei），依政府資料開放授權條款第 1 版使用。它是一份索引，每月一個 CSV：每天每小時、每一站到每一站的人次，一個月約 300 MB。2026-10-20 查的時候已有 2026 年 9 月。

**輸出**：`RailwayGameApp/Resources/RealRailways/trtc_ridership.json`，以資料裡的站名為 key，一天平均（進站＋出站）÷ 2。工具一個月一個月串流讀（不存檔），每月記 SHA-256；12 個月、整年的天數都要有。印出 App 的 `trtc.json` 沒有的站名，和 App 有但資料沒有的站。

```sh
python3 -I tools/real-ridership/build_trtc_ridership.py --year 2025 --downloaded 2026-10-20 \
    --stations RailwayGameApp/Resources/RealRailways/trtc.json \
    --output RailwayGameApp/Resources/RealRailways/trtc_ridership.json
```

一年要讀約 3.7 GB，在雲端容器約半小時。

## 共同的注意

- 兩個下載的工具用 `curl` 讀，不用 Python 的 `urllib`：雲端容器經過的代理憑證，Python 3.13 的嚴格檢查不接受，curl 照系統設定接受。不關掉任何檢查。
- **還沒有的**：高雄捷運（政府資料開放平臺 [159640](https://data.gov.tw/dataset/159640)、[159641](https://data.gov.tw/dataset/159641) 的各站出站、入站，在 data.kcg.gov.tw；雲端容器連不上那個主機，2026-10-20）、台中捷運、桃園機捷、輕軌、三鶯線、林鐵。這些站的轉乘點數照系統的規則（決策 298）。高雄捷運可以之後用 GitHub Actions 讀（runner 連得上的話）。
