# DATA-OFFICIAL

派工單 DATA-OFFICIAL（session_01YGNNukgknJjSKgDYLdjLS5，`claude/data-official`，2026-11-13；遊戲規劃第 64 任派，#2118）。只研究、只寫文件。不動 GameCore、存檔版本、決策號碼、golden、三套 fixture、`Sources/`、`RailwayGameApp/`、`tools/`。

## 做完的

- `docs/research/OFFICIAL_STATS_2026-11-13.md`：作者 11-13 貼的資料來源清單逐項查證（機場營運量、國際商港旅客、觀光署主要觀光遊憩據點遊客人次、高鐵各站、臺鐵各站、國土測繪中心正射影像、OpenStreetMap），每一項的官方網址、機關、授權、更新、格式、這個環境抓不抓得到，和遊戲現有資料的比較，建議與先後。
- `docs/research/official-stats-2026-11-13/attraction_matches_2024.csv`：遊戲 215 個景點用名字自動對到觀光署 2024 年據點的結果（95 個對上，**沒有人工確認，有錯的**）。資料取自交通部觀光署「歷年國內主要觀光遊憩據點遊客人數月別統計」（data.gov.tw 8116），依政府資料開放授權條款第 1 版使用。

## 結論（細節在文件第 0 節）

- 機場、高鐵各站、臺鐵各站，遊戲已經在用官方資料（`DataSourceCredits` 的 `airports`、`ridership`），不用換。
- 缺的是觀光據點人次，官方有開放資料（8116，CSV，2012–2024，每月）；沒有座標，要人工對照表。
- 建議先後：觀光人次（先顯示、再校正星等）→ 機場按月 → 其餘不接。

## 還留下的（都沒有派工，等規劃決定）

1. **觀光人次第 1 步**：`tools/tourism-spots/build_official_visitors.py`、人工對照表 `official_names.json`、景點卡多一行、`DataSourceCredits` 新一筆（文字草稿在文件 5.1）。不動 GameCore。
2. **觀光人次第 2 步**：同類型內照人次校正星等，先照 economy-balance 量。月別曲線要動 GameCore 的 `seasonFactor`，另開決策。
3. **機場按月**：`tools/airports/build_airport_months.py`（讀 data.gov.tw 31915 的 ODS）。月別係數要不要進 GameCore 沒有查。
4. **請作者在台灣做的**：
   - 開交通部統計查詢網的高鐵「旅客人數─按進出站分」（22090），看 2025 年各站和高鐵公司網站的表是否相同（這個環境連不上 `stat.motc.gov.tw`）。
   - 正射影像若還想用，向國土測繪中心問商業 App 線上介接的條件，或給出那份使用條款的網址。

## UNVERIFIED

見文件第 10 節：交通部統計查詢網沒連上；國土測繪中心有沒有另一份條款全文沒找到；觀光查詢網站 2025、2026 年的數字沒抓；自動比對沒有人工確認；建議的做法都沒有實作。
