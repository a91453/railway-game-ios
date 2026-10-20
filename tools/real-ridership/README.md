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
- App 有、資料沒有的：台北-環島（環島列車的另一個名字）、平鎮、枋野（號誌站）、樹林調車場、潮州基地。轉乘點數退回站等的規則。
  - 和 TDX 2026-10-20 的台鐵站表（`tdx-check.yml` 抓的，245 站）對過：TDX 有、App 沒有的站沒有，沒有改名；平鎮（1105）在 TDX 的站表裡卻沒有 2025 年的進出站，可能是 2025 年之後才營運的站，明年用 2026 全年重跑時再看。
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

**2026-10-20 的結果（2025 年）**：118 站，全部對上 App 的 `trtc.json`；App 有、資料沒有的只有廣慈/奉天宮（2025 年還沒營運）。兩條線分開計閘門的站，資料用路線代碼開頭（`BL板橋`、`Y板橋`、`G大坪林`、`O景安`、`O頭前庄`），工具加到同名的站；`大橋頭站` 去掉「站」。最多的：台北車站 149,891、西門 68,403、市政府 61,891、中山 51,610、忠孝復興 44,570。

一年要讀約 3.7 GB，在雲端容器約半小時；`--cache 資料夾` 留下每個月的加總，重跑只讀新的月份。12 月的檔包含跨年夜通宵運行的 1 月 1 日 06:00 前，那些人次算在 12/31 的營運日，不多算一天。

## 高雄捷運：`build_krtc_ridership.py`

**來源**：政府資料開放平臺的[高雄都會區大眾捷運系統各站旅運量入站](https://data.gov.tw/dataset/159641)與[出站](https://data.gov.tw/dataset/159640)（高雄市政府；資料集頁面沒有寫是哪個局處），依政府資料開放授權條款第 1 版使用。一年一列、一站一欄（紅線與橘線，不含輕軌）。

**雲端容器連不上 data.kcg.gov.tw**（連線一開始就被切斷，另一條網路路徑回 503；看起來擋國外連線），所以由**作者在台灣下載兩個 CSV、附在對話裡**；工具記下兩個檔的 SHA-256 與下載日期。原始 CSV 不進 repository。

**輸出**：`RailwayGameApp/Resources/RealRailways/krtc_ridership.json`，以 App 的 `krtc.json` 的站名為 key，一天平均（進站＋出站）÷ 2。資料用的是舊站名，五站之後改了名，工具裡的 `RENAMED` 對照：楠梓加工區→楠梓科技園區、南岡山→岡山高醫、西子灣→哈瑪星、市議會→前金、技擊館→苓雅運動園區。

```sh
python3 -I tools/real-ridership/build_krtc_ridership.py 入站.csv 出站.csv --year 2025 --downloaded 2026-10-20 \
    --stations RailwayGameApp/Resources/RealRailways/krtc.json \
    --output RailwayGameApp/Resources/RealRailways/krtc_ridership.json
```

**2026-10-20 的結果（2025 年）**：38 站，全部對上 App 的紅線與橘線。最多的是左營 20,244、高雄車站 15,230、巨蛋 14,099、三多商圈 11,171、美麗島 9,549。

## 台中捷運：`build_tmrt_ridership.py`

**來源**：政府資料開放平臺的[臺中捷運股份有限公司捷運各站旅運量](https://data.gov.tw/dataset/175718)（臺中捷運股份有限公司，檔在 `newdatacenter.taichung.gov.tw`），依政府資料開放授權條款第 1 版使用。每月一個 JSON，一站一列（`欄位名稱` 是站名，`數值` 是當月人次）。

**平臺缺月**：2025 年只有 2、4、5、7、8、11、12 月 **7 個月**，而且 2026-02 以前的檔**只有出站**（2026-02 起多了入站、團體票、其他；4 月又只有出站）。所以 2025 年用的是「**7 個月的出站，除以這 7 個月的天數（212 天）**」，當作一天的人數（研究 `RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md` §1 的 (a)）：全系統進站與出站相等，單站兩者也差得不多。這是唯一不是完整年度的檔，`tmrt_ridership.json` 的 `months` 與 `measure` 寫著。團體票、其他是全線的列，沒有站，不算。

**輸出**：`RailwayGameApp/Resources/RealRailways/tmrt_ridership.json`，以 App 的 `tmrt.json` 的站名為 key（資料都帶「站」，App 只有 `北屯總站`、`高鐵臺中站` 帶），記每個月檔的 SHA-256、下載日期、授權、期間與月份。工具從平臺的 API 列出那一年有的月份、用 curl 下載；少於 12 個月要加 `--partial` 才接受。每個月都有入站時改用（進站＋出站）÷ 2。

```sh
python3 -I tools/real-ridership/build_tmrt_ridership.py --year 2025 --partial --downloaded 2026-10-20 \
    --stations RailwayGameApp/Resources/RealRailways/tmrt.json \
    --output RailwayGameApp/Resources/RealRailways/tmrt_ridership.json
```

**2026-10-20 的結果（2025 年 7 個月）**：18 站，全部對上 App 的綠線；App 不認得的站名、App 有資料沒有的站：都沒有。最多的：高鐵臺中站 8,436、市政府 5,791、文心崇德 3,428、大慶 3,280、文心中清 3,201；最少的九張犁 31。

**什麼時候重跑**：2027 年初看 2026 年是否 12 個月都有（2026-10-20 已有 2–8 月，缺 1 月）。12 個月齊了就照 #851 的「最近一個完整年度」，拿掉 `--partial` 重跑 2026，換掉這份 7 個月的檔；不齊就仍用最近一年有的月份，在這裡寫明。

## 桃園機捷：`build_tymc_ridership.py`（等作者的 12 個 CSV）

**來源**：政府資料開放平臺的[桃園大眾捷運各場站運量每月統計表](https://data.gov.tw/dataset/164957)（桃園大眾捷運股份有限公司，檔在 `opendata.tycg.gov.tw`），依政府資料開放授權條款第 1 版使用。每月一個 CSV（平臺寫 Big5），欄位：年度、月份、捷運站別、平均日運量。

**雲端容器連不上 `opendata.tycg.gov.tw`**（回「Request Rejected」，看起來擋國外連線），所以和高雄捷運一樣，**由作者在台灣下載 2025 年 12 個 CSV、附在對話裡**：

1. 開 [data.gov.tw/dataset/164957](https://data.gov.tw/dataset/164957)，下載 `捷運各站運量統計表_202501` 到 `_202512` 共 12 個檔（網址列在研究 `RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md` §1「桃園機捷：作者在台灣下載的步驟」）。
2. 順便下載[164956「桃園大眾捷運每月平均日運量統計」](https://data.gov.tw/dataset/164956)（全線每月的平均日運量），用來對下面第 3 步。
3. **平均日運量是什麼**：資料集沒寫。工具每個月印出「各站加總」與 A1 的數字：
   - 各站加總約等於全線的平均日運量（新聞：2025 年到 10 月底約 12.65 萬），A1 約 2.5 萬：是（進站＋出站）÷ 2 或進站數，用 `--measure mean`；
   - 各站加總約是全線的兩倍，A1 約 5 萬：是進站＋出站，用 `--measure sum`（工具除以 2）。
   - 對照：桃捷公司 2025-04 的新聞稿說 2023-07 到 2025-02 A1「平均每日進出站人數」51,287 人次（[中央社](https://www.cna.com.tw/news/ahel/202504130017.aspx)）；這個數字本身也沒說是進＋出還是 ÷ 2，所以以全線的對照為準，結果寫在這裡。
4. 跑工具；原始 CSV 不進 repository。每個月以天數加權平均成一年。

```sh
python3 -I tools/real-ridership/build_tymc_ridership.py 捷運各站運量統計表_2025*.csv \
    --year 2025 --measure mean --downloaded 下載日期 \
    --stations RailwayGameApp/Resources/RealRailways/tymc.json \
    --output RailwayGameApp/Resources/RealRailways/tymc_ridership.json
```

產出後：在 `RealRidership` 加 `tymc` 一張表（照 `tmrt`），`RealRailways.load` 讀 `tymc_ridership`，資料來源畫面加桃捷的出處（164957），`RealTransfersTests` 加 A1、A8、A12、A13 的點數，用 XcodeGen 重產專案。

**還沒跑**（2026-10-20）：工具用假的小 CSV 測過（`test_tools.py`），還沒有真的檔。

## 新北捷運：`build_ntmc_ridership.py`

**來源**：新北大眾捷運股份有限公司網站的[統計資料](https://www.ntmetro.com.tw/basic/?node=10145)，每月一份「全系統運量統計」試算表，附件 1 是**每日全線各站運量統計表**的進站與出站：淡海輕軌（V）、安坑輕軌（K）、環狀線（Y），2026-07 起加上三鶯線（LB）。2025-09 起是 `.ods`，之前是 PDF 或 `.xlsx`。網站的「政府網站資料開放宣告」**沒有開放授權**，所以照高鐵的做法，只取各站的平均（事實數字），標示出處「新北大眾捷運股份有限公司」。

**為什麼不用台北捷運的檔算環狀線**：128506（`trtc_ridership.json`）裡雖然有環狀線各站，但只是台北捷運閘門記到的那一部分，只有新北捷運自己數的幾分之一（中原 701 對 2,831、新埔民生 301 對 4,445）。所以環狀線改用這份；台北捷運與新北捷運都有的站（大坪林、景安、板橋、頭前庄），App 取兩份中大的那個，不相加，免得同一趟算兩次。

**期間**：最近的 **12 個連續月份 2025-10 到 2026-09**（365 天），不是曆年：2025 年 1–8 月只有 PDF 或 `.xlsx`，標準函式庫讀不了。（進站＋出站）÷ 2 除以天數；每一列的每日數字要加起來等於「總計」欄，每個月要有每一天，否則失敗。`人工統計資料`（單程票、優待票等，約佔各線 2%）沒有分站，不算。

**輸出**：`ntdlrt_ridership.json`、`ntalrt_ridership.json`、`ntmc_circular_ridership.json`，以 App 的 `ntdlrt.json`、`ntalrt.json`、`trtc.json` 環狀線的站名為 key，記每個月檔的 SHA-256、下載日期、期間與使用條件。

```sh
python3 -I tools/real-ridership/build_ntmc_ridership.py --first 2025-10 --downloaded 2026-10-20 \
    --app RailwayGameApp/Resources/RealRailways --output RailwayGameApp/Resources/RealRailways
```

**2026-10-20 的結果（2025-10 到 2026-09）**：全部站名對上 App。
- 淡海輕軌 14 站，全線一天 17,469（一年約 638 萬；審計處 2025 年 603 萬）：紅樹林 7,781、濱海義山 1,522、淡水行政中心 1,284。
- 安坑輕軌 9 站，一天 6,201（約 226 萬；2025 年 203 萬）：十四張 2,662、新和國小 779。
- 環狀線 14 站，一天 67,274（約 2,456 萬；2025 年約 2,200 萬）：板橋 11,640、景安 7,278、大坪林 6,950、新北產業園區 6,292。
- 三鶯線：2026-06-30 才通車，只有 2026-07 起的月份，**不到 12 個月，工具跳過**，照決策 298 的後備 1 點。2027-07 有 2026-07 到 2027-06 之後，用 `--first 2026-07` 重跑就會產出 `sanying_ridership.json`（之後要在 `RealRidership` 加 `sanying`）。

**什麼時候重跑**：每年一次，和其他檔一起；`--first` 取最近 12 個 `.ods` 月份的第一個。

**查過的地方**（2026-10-20）：新北市資料開放平臺 data.ntpc.gov.tw 的搜尋 API 要登入；政府資料開放平臺的完整清單（52,525 個資料集，`https://data.gov.tw/datasets/export/csv`，SHA-256 `5c269d21…0c07`）裡，新北市政府捷運工程局、交通局只有路線長度、車站數、建設進度、自行車架、接駁公車，**沒有各站運量**；新北捷運公司網站（2026-10-20 研究時連不上）這次連得上，找到上面的統計資料。作者若想要 2025 曆年或 PDF 的月份，可以在台灣用瀏覽器查 data.ntpc.gov.tw，或照政府資訊公開法向新北捷運公司申請各站年運量。

## 測試

`python3 -I tools/real-ridership/test_tools.py`：台中、桃園、新北三個工具用假的小檔測（不連網）：天數加權、只有出站、進＋出除以 2、缺月拒絕、民國年與 UTF-8、ODS 的重複格。CI 沒有跑它，改工具時在本機跑。

## 共同的注意

- 下載的工具用 `curl` 讀，不用 Python 的 `urllib`：雲端容器經過的代理憑證，Python 3.13 的嚴格檢查不接受，curl 照系統設定接受。不關掉任何檢查。
- **還沒有的**：桃園機捷（工具寫好，等作者的檔）、三鶯線（還不到 12 個月）、高雄環狀輕軌（只有全系統）、林鐵。這些站的轉乘點數照系統的規則（決策 298），不推估、不拿年運量平分。TDX 沒有各站運量的 API（2026-10-20 查過它軌道類的全部 API 說明）。
