# 把遊戲的錢改成新台幣：盤點、比例比較與實作計畫

日期：2026-10-27。派工單 AJ（研究，只寫文件），由遊戲規劃開。基準：`main` `0f2a1cb`。
不改 Sources、Tests、fixtures；存檔、決策、golden 都不動。

## 0. 結論

**建議：B，NT$3＝$1。** 把遊戲裡所有的錢整體乘 3（`Money` 的單位不變，仍是 1/100 元，只是這個「元」改叫新台幣），舊存檔載入時自動乘 3，再修三處對不上真實的：高鐵票價、區間票價的整數元、預設分段票價。五方打分 B 3.15，第二名 D2（只改顯示）2.65，其餘 2.4 以下（第 3 節）。

三行理由（給規劃用）：

1. 玩家看得到、有真實出處的數字，乘 3 之後剛好對上：路網均一 $5 → NT$15（公車一段票、臺鐵短程）、車站人事 $620 → NT$1,860（約 1.2 個基本工資人天）、公車每車公里 $20 → NT$60（真實 NT$52–66）。乘 10 的話，一趟捷運要 NT$50。
2. 唯一用 NT$10＝$1 的高鐵，改成直接用官方票價表（NT$1,490 就是 NT$1,490）；乘 3 之後它比現在的遊戲內水準貴約 3.3 倍，要重量高鐵的平衡，這是整張單裡唯一不是機械乘 3 的地方。
3. 一次改完比分批改便宜：存檔載入只多一道乘 3，golden／replay／測試的金額欄位都是「新 ＝ 3 × 舊」，可以用腳本逐值驗證，不必逐個重新判斷。

**要先知道的三件事**（和派工單的說法有出入，第 1 節有證據）：

- **玩家數不影響遷移成本。** 存檔載入時自動乘 3，50 個人與 5,000 個人一樣便宜。真正隨玩家變多而變貴的是外面已經看到的東西：截圖、攻略、評論裡的「$」數字。所以重點是「App Store 上架前做完」，不是「越快越好」。
- **資本財（軌道、車站、車輛、土地）不可能照真實新台幣訂。** 遊戲的資本財比真實小數百到數千倍（軌道每公里 $100,000，真實高架每公里是億元級；公告現值最貴的台北 101 是 NT$2,001,000／m²，遊戲地價上限 $500／m²），因為運量也縮小了，第一條線要 10 天回本。只有「每個人付的票價」與「每天的人事、能源」有真實的錨。所以 A（全部照真實重訂）不可行。
- **公開 TestFlight 是 10/31，離現在只有四天。** 這一輪是完整層級的 GameCore PR（要 `full-ci`、完整 shard、重錄 9 個 replay），照 CLAUDE.md 發版要 `main` 的完整 `ci.yml` 與 full lane 都綠。建議第 5 節的 PR-1 在 10/29 合併、10/30 看夜間完整 run；來不及就讓 10/31 先帶 `$` 出去，App Store（約 11/14）之前補上，不要為了趕 10/31 省量測。

balance 判定：**NOT ASSESSED — NO DATA**。這張只讀程式與文件，沒有跑任何報告測試；第 5.6 節列出下一張要跑的報告與指令。

## 1. 核對現況

### 1.1 `Money` 的單位

- `Money` 是 `Int64`，單位是 1/100 元（`Sources/GameCore/Economy/Money.swift`；`EconomyText.swift:9–15` 的 `moneyText` 把 `amount` 除以 100 四捨五入顯示）。`Money(500)` 顯示成 `$ 5`。派工單說「美分」是對的。
- **「整數元」到處當不變量。** 時薪票收、日結的收入與成本、一日券價格都要求 `amount % 100 == 0`（`LineAccounts.swift:96`、`Operations.swift:557,560`、`DayPass.swift:84`、`Requests.swift:496,511`、`TrainTrips.swift:98`、`Freight.swift:392`），不少計算以 `/ 100 * 100` 湊整（約 43 處）。這個 100 在新台幣之後變成「整數新台幣」，剛好是我們要的最小單位，所以 `Money` 的 1/100 不用動。
- **`Money` 也被拿來格式化人數。** `Money(riders).displayText` 在 `Sources/` 出現 77 次（運量、人口、候車人數），只是借它的千分位。改幣別時這些不能被帶著加上 `NT$`；`moneyText`／`centsText`／`shortMoney` 才是錢。建議順手把這個千分位函式獨立出來（`Int64.groupedText`），讓「這是錢」一眼看得出來；非必要，列在第 5 節的 PR-0。
- **`pricingBalance = Money(1 << 60)`**（`Operations.swift:51`）是「算價錢用的無限餘額」哨兵，不是價格，不能乘 3（`maximumBalance` 是 `1 << 62`，乘 3 會超過）。遷移與常數表都要跳過它。
- 其他上限（`maximumFare` 1e9 ＝ $1,000 萬、`maximumAccrued` 2^50、`maximumHourly` 2^40）乘 3 都放得下，不必改；`maximumFare` 若想保留「$1,000 萬」的語意可以改 3e9，沒有要求。

### 1.2 現在有四種「比例」

| 位置 | 比例 | 出處 |
| --- | --- | --- |
| 遊戲全體（路網均一 $5、成本、地價……） | 沒有比例，是參考庫的美元（決策 36） | `FareRules.standardFare` ＝ 500 |
| 高鐵示範的真實票價表 | NT$10＝$1 | 決策 325，`HighSpeedFares.centsPerNewTaiwanDollar` ＝ 10；台北—左營 NT$1,490 ＝ `Money(14_900)` ＝ $149 |
| 公車（#1365，決策 438） | NT$3＝$1 | 一段票 $5 ≈ NT$15；`BusRoute.costPerKilometre` ＝ `Money(2_000)` ＝ $20（註解：NT$52–66 一車公里，NT$3＝$1）。本研究讀的是 main（`BusRoute.swift:117–124`），#1365 的後續改動未讀 |
| 一日券 | 約 NT$2.9＝$1 | 決策 319 附近（`ARCHITECTURE.md` 15166 行）：最短一趟的 3 倍，$5 → $15，對平溪線 NT$80（三貂嶺—菁桐 12.9 km × 2.18 ≈ NT$28） |

結論：除了高鐵，這幾個都已經落在 NT$3 上下；高鐵的 NT$10 是為了讓長程票價貼著決策 168 的每公里 $0.45，不是真實比例（決策 325 自己寫「新台幣那輪拿掉」）。

### 1.3 存檔與其他會留下錢的地方

- `SavedGame.currentVersion` ＝ 74（main）；#1365 預約 75。載入沒有集中的遷移函式，靠各型別的 `init(from:)` 補欄位（`SavedGame.swift` 開頭的說明）。要乘 3 的地方就是**所有解碼 `Money` 的欄位**（帳本、日結、年結、資產、貸款、列車行程、觀光、委託、子公司、公司建物、貨運、公車……），第 5.2 節給單點做法。
- 存檔裡的錢不全是 `Money` 型別：核對過的 `Int64` 金額常數（`Tourism.souvenirCost`、`Subsidiary.templeSpend` 等）都是程式常數，不進存檔；進存檔的 `Int64` 金額要在實作時再逐個核（第 5.2 節的稽核）。
- **存檔庫的索引另存一份餘額**：`SaveLibrary.swift:605–629` 的 `balance: Int64`（「The balance, in cents」）供存檔清單顯示，不在 `SavedGame` 裡。若只遷移存檔，清單會在打開存檔前顯示舊數字（少 3 倍）。要一起遷移或改成讀檔後重算。
- Game Center 排行榜的分數是「天數」，不是錢（`GameCenterMapping.swift`）。成就解鎖紀錄（`achievements.data`）只存 ID 與時間。這兩個不受影響。`CompanyRank` 的 `netWorth` 是從世界現算的，不存。

## 2. 每一個錢的數字

來源：`grep` 全部 `Money(…)`（`GameCore` 90 行、`GamePresentation` 159 行，排除 `Money(0)` 與 `Money($0 …)`）、26 個具型別的 `Money` 常數，加上以整數字面值寫的價格表。「×3」「×10」欄是照該比例整體乘的值（元）；「真實」欄只填有出處的，沒查證的寫「未查」。**這些是靜態盤點，沒有跑任何量測。**

真實數字的出處（本次查的，2026-10-27）：

- 基本工資：2026-01-01 起月薪 NT$29,500、時薪 NT$196（勞動部；[公視](https://news.pts.org.tw/article/772368)、[workstem](https://www.workstem.com/tw/?p=17104)）。
- 臺鐵：2025-06-23 起票價平均調漲 26.8%，區間車平均每公里 NT$1.82（舊 1.46）；自強號台北—高雄 NT$994、台北—花蓮 583、台北—台東 936；莒光號台北—高雄 767；台北—板橋區間車由 NT$15 調至 22（[公視](https://news.pts.org.tw/article/714124)）。決策 319 用的區間車新費率是 2.18 元／km（50 km 以下）。
- 高鐵：台北—左營標準車廂 NT$1,490（`thsr_fare.json`，決策 325，TDX）。
- 公告土地現值：113 年台北 101 NT$2,001,000／m²，連續 11 年地王（[Yam 新聞](https://n.yam.com/Article/20231220221384)）；全市平均與其他縣市沒查到單一數字，下一張要從內政部地政司資料補。
- 公車一段票 NT$15、平溪線一日券 NT$80：決策 438、319（repo 內）。

### 2.1 票價與需求

| 檔案:行 | 意義 | 現值 | ×3 | ×10 | 真實 NT$ |
| --- | --- | --: | --: | --: | --- |
| `Economy/Fares.swift:50` | 路網均一票價 `standardFare` | $5 | NT$15 | NT$50 | 公車一段 15；臺鐵台北—板橋區間 22；台北捷運 20–65 |
| `Fares.swift:136` | 票價 0 時改收的最低價 `standardMinimum` | $5 | 15 | 50 | 同上 |
| `Fares.swift:55–59` | 編輯器預設分段票價（0.55／0.70／0.85／1.00／1.20，依 `fareBaseline` 縮放後湊整到 0.05） | $0.55–1.20 | 1.65–3.60 | 5.5–12 | 不是整數元，**乘 3 之後湊整單位要改成 NT$1**（`Fares.swift:78` 的 `/ 750 * 5`） |
| `Fares.swift:146` | 需求的票價基準 `demandBaseline`（只做比值） | $0.75 | 2.25 | 7.5 | 比值，不是價格；新遊戲另設 `fareBaseline`（`NewGame.swift:69` ＝ `standardFare`） |
| `Fares.swift:86` | 票價上限 `maximumFare` | $1,000 萬 | 3,000 萬 | 1 億 | 輸入檢查，可不動 |
| `Economy/DayPass.swift:47,84` | 一日券建議價 ＝ 3 × 最短票價；價格要整數元、至少 $1 | $15 | NT$45 | NT$150 | 平溪線 NT$80（約 2.9 倍短程票） |
| `Passenger/DistanceDemand.swift:114` | 站外旅客票價倍數 × 基準 | 倍數 | 跟著基準 | | 比值 |
| `Passenger/HighSpeed.swift:62,73` | 高鐵每公里票價 `centsPerKilometre`（0.45）：$0.45 ×（兩站直線公里） | $0.45／km | NT$1.35 | NT$4.5 | 台北—左營 NT$1,490／340 km ≈ **NT$4.4／km** |
| `Presentation/HighSpeedFares.swift:36–39` | 高鐵示範票價表換算 | NT$×10 美分 | **直接用 NT$（×100）** | 現狀 | NT$40–1,530（`thsr_fare.json`） |
| `Passenger/BusRoute.swift:120` | 公車票價 | $5 | NT$15 | NT$50 | 一段票 NT$15 |

### 2.2 每天的營運成本

| 檔案:行 | 意義 | 現值 | ×3 | ×10 | 真實 NT$ |
| --- | --- | --: | --: | --: | --- |
| `Economy/Operations.swift:407,412` | 車站人事，每站每天（參考：`620·stations`） | $620 | NT$1,860 | NT$6,200 | 基本工資 196×8 ＝ 1,568／人日，約 1.2 人日 |
| `Operations.swift:376–385`（`LineAccounts.swift:488`） | 列車人事每列每天 480；能源每列 360、每路線公里 220 | $480／$360／$220 | 1,440／1,080／660 | 4,800／3,600／2,200 | 人事約 0.9 人日；電費未查（一列 4 節電聯車每天幾百度電以上，下一張補） |
| `RollingStock.swift:88` | 一列標準車固定日成本：人事 480 ＋ 能源 360 ＋ 保養 8×24 | $1,032 | 3,096 | 10,320 | 未查 |
| `Railway/Depot.swift:471` | 機廠側線每天費用 | $400 | 1,200 | 4,000 | 未查 |
| `BusRoute.swift:124,172` | 公車每車公里成本 | $20 | NT$60 | NT$200 | NT$52–66（決策 438） |

### 2.3 車輛

| 檔案:行 | 意義 | 現值 | ×3 | ×10 | 真實 NT$ |
| --- | --- | --: | --: | --: | --- |
| `Economy/GameEconomy.swift:31` | GameCore 自己的預設價（測試用） | 軌道 $10／16 m，車站 $500，車 $2,000 | ×3 | ×10 | 不是遊戲價 |
| `Presentation/NewGame.swift:231` | 新遊戲建設價：軌道每 16 m、車站、第一節、每加一節 | $1,600、$200,000、$150,000、$40,000 | NT$4,800、60 萬、45 萬、12 萬 | | 見下：遠小於真實 |
| `Railway/TrainTypeCatalog.swift:197…` | 各車種第一節／每加一節 | $80,000–900,000／$20,000–150,000 | ×3 | ×10 | 一節電聯車真實約數千萬（未查） |
| `RollingStock.swift:29–30,57,73` | 車價、賣出 70% 帳面值 | | ×3 | | 70% 是比例，不變 |
| `Presentation/RollingStockCatalog.swift:89` | 車種每日成本顯示 | | ×3 | | |

### 2.4 建設、土地、建物

| 檔案:行 | 意義 | 現值 | ×3 | ×10 | 真實 NT$ |
| --- | --- | --: | --: | --: | --- |
| `Railway/TrackSections.swift:125,354–383,649` | 軌道 ＝ `costs.track` ×（結構係數 地面 1、高架 3、橋 4、隧道 5）＋ 土方 | 軌道 $100,000／km（地面） | NT$30 萬／km | NT$100 萬／km | 真實高架每公里億元級，**遊戲小 300–10,000 倍** |
| `City/RoadGrid.swift:38,294` | 站前路每公尺 | $50 | NT$150 | NT$500 | 未查 |
| `City/LandValue.swift:91–140` | 地價（每 m²）：空地底價 1,000、最低 500、最高 50,000（單位 1/100 元）、各種加成 | $5–$500／m² | NT$15–1,500 | NT$50–5,000 | 偏遠到台北 101（NT$2,001,000）**遊戲小約 1,300 倍**；全市平均未查 |
| `City/CompanyBuildings.swift:34,41,68,115,300,343,360` | 蓋樓每 m² 樓地板 40；拆除 10%；收購 120% | $40／m² | NT$120 | NT$400 | RC 造價約 NT$1.8–2.4 萬／m²（未查證），遊戲小 150 倍 |
| `City/BuildingSale.swift:54,119,122` | 出售土地價、事業按獲利倍數 | 比例 | | | |
| `World/MapExpansion.swift:62,135` | 買下一塊地圖（每 10 萬人次 ）| $5,000,000 | NT$1,500 萬 | 5,000 萬 | 遊戲設計價 |
| `Railway/LineAcquisition.swift:51,52,63` | 收購真實支線：每日運量一人 | 支線 $10,000／輕軌 $70／捷運 $100 | NT$30,000／210／300 | | 遊戲設計價（決策 315、400） |

### 2.5 事業、觀光、貨運、委託

| 檔案:行 | 意義 | 現值 | ×3 | ×10 |
| --- | --- | --: | --: | --: |
| `City/StationCommerce.swift:28–30,57–59,68` | 便利商店／遊樂場／商場的開店價；每位顧客消費（單位待下一張核對） | $350,000／3,150,000／12,500,000 | ×3 | ×10 |
| `Passenger/Tourism.swift:135,137,139,207,780` | 名產店升級 $300,000；每級每遊客消費 4；每日維護率 | | ×3 | ×10 |
| `Economy/Requests.swift:142,178` | 城市委託獎金上限 $1,000 萬、下限 | | ×3 | |
| `Freight/Freight.swift:46,58` | 貨運設施 $50,000；每噸公里 $5（`centsPerTonKilometre` ＝ 500） | | NT$150,000；NT$15 | |
| `City/Subsidiary.swift:62–77,291` | 廟宇、夜市每人消費 30／30、獲利倍數 6 | 倍數不變 | | |

### 2.6 金融

| 檔案:行 | 意義 | 現值 | ×3 | ×10 | 真實 |
| --- | --- | --: | --: | --: | --- |
| `Economy/Accounts.swift:400,402` | 貸款單位、上限 | $100,000／$5,000,000 | NT$30 萬／1,500 萬 | | |
| `Accounts.swift:405` | 年利率 5%（比例） | | 不變 | | 比例，另題 |
| `Accounts.swift:408,409` | 稅：每天免稅獲利 $100,000，超過部分 50% | | 免稅額 NT$30 萬；稅率不變 | | **稅率 50% 對真實營利事業所得稅 20%** 是比例不是幣別，不在這張 |
| `Presentation/LoanPreview.swift` | 試算 | | 跟著 | | |

### 2.7 開局、挑戰、成就、劇本、教學

| 檔案:行 | 意義 | 現值 | ×3 | ×10 |
| --- | --- | --: | --: | --: |
| `Presentation/NewGame.swift:219` | 新遊戲開局現金 | $3,000,000 | NT$900 萬 | 3,000 萬 |
| `RealWorldDemo.swift:87,255`、`HighSpeedDemo.swift:794,811`、`RealWorldDemoGround.swift:477` | 示範／實景開局＝標準現金＋興建這條線的費用 | 算出來的 | 自動 ×3 | |
| `PingxiChallenge.swift:58` | 平溪線 一年淨利目標 | $2,000,000 | NT$600 萬 | |
| `BranchLineChallenge.swift:261,264` | 集集線 淨利目標、開局現金 | $3,000,000／$7,000,000 | NT$900 萬／2,100 萬 | |
| `LiuMingchuanChallenge.swift:135` | 劉銘傳 開局現金 | $8,000,000 | NT$2,400 萬 | |
| `Scenarios.swift:141` | 大亨：一年淨利、公司權益 | $3 億／$8 億 | NT$9 億／24 億 | |
| `Achievements.swift:372,382` | 「生意興隆」事業累計獲利、「車隊投資」 | $1,000,000／$5,000,000 | NT$300 萬／1,500 萬 | |
| `CompanyRank.swift:50` | 公司等級 `netWorth` 滿分目標 | $5 億 | NT$15 億 | |
| `GamePresentation` 教學課程 | 各課開局現金與目標 | **未逐行盤點**，下一張用 `LessonTargetReportTests` 與 `grep balance:` 補 | | |

**玩家看得到的字裡直接寫死的金額**（要跟著改，最好改成由常數產生）：`Achievements.swift` 的「$1,000,000」「$5,000,000」、`Scenarios.swift` 的「3 億」「8 億」、集集線與平溪線挑戰的任務文字（`BranchLineChallenge.swift:232–233`）、`HelpGuide.swift`（含金額約 5 行）。粗略 grep：`Sources/GamePresentation` 裡含 `$` ＋數字或 `$\(` 的行約 170 行，App `Views/` 有 9 個檔案含 `$` 字樣（多半是 Swift 的 `$binding`，要逐一看）。

### 2.8 顯示格式

| 檔案:行 | 內容 | 要做的事 |
| --- | --- | --- |
| `EconomyText.swift:14–26,164–166` | `moneyText` ＝ `"$ " + 千分位`；`centsText` ＝ `"$ 5.00"`；帳本正負號 `+$ `／`-$ ` | 前綴 `NT$`；`centsText` 在整數元之後幾乎不再需要（只剩「不夠錢」的訊息），改成顯示整數元或保留 2 位小數 |
| `TrainRoster.swift:259–265`（`shortMoney`） | `$12`、`$3.4k`、`$1.2M` | 英文保留 k／M；繁中建議改 萬／億（見 5.5） |
| `GameFeedback.swift:43` | 建造回饋 `−$12k` | 同上 |
| `StatusBarWidths.swift:53–56` | HUD 現金最寬：至少 7 位數 `"$ -8,888,888"`，隨位數增加 | 前綴多 2 個字元；開局現金 9,000,000 剛好 7 位 |
| `Policy.swift:719` | 圖表的現金軸 `"$\($0 / 100)"` | 前綴 |
| `SaveLibrary.swift:605–629` | 存檔清單的餘額 | 一起遷移（1.3） |
| `CityMap.swift:384–464` | 地價 `centsText` | 前綴；地價這種小數目 NT$15–1,500 整數即可 |
| `TourismText.swift`、`BusRouteEditor.swift:532`、`StationCommerceText.swift`、`FinancialStatements.swift`、`FinanceHistory.swift`、`DayPassCard.swift`、`FareDemandHint.swift`、`LoanPreview.swift`、`TodayAccount.swift` | 都經過 `moneyText`／`centsText` | 前綴一次改好 |
| `PopTravel.swift:89`（派工單 AI 在改） | 地價說明寫「每平方公尺美元」 | 不用管 |

### 2.9 固定資料與測試

| 項目 | 規模 | 乘 3 的影響 |
| --- | --- | --- |
| `SaveFixtures/` | 78 個檔，v1–v74 | 不能改檔；載入後金額乘 3。`SavedGameTests.swift` 有三處對載入結果的金額斷言（338、364、408 行附近：`-60_600`、`131_595_600`、`69_962_900`），這是對「舊存檔載入」的斷言，要依遷移後的值改，PR 逐項說明。還要新增 v76 的 fixture |
| `GoldenScenarios/` | 77 個檔；含金額欄位的主要有 `city-requests`（277 行命中）、`land-value`、`zoning`、`water-terrain`、`materials-growth`、`city-buildings-growth/raise`、`line-accounts`（各 140 多行），其餘 6–17 行 | 輸入（票價、成本、貸款額）與預期值都要換。規則：「新 ＝ 3 × 舊」逐欄用腳本證明；湊整造成的差另列 |
| `ReplayFixtures/` | 9 個檔（`economy`、`kernel`、`line-dispatch`、`line-patterns`、`line-route-preferences`、`long-leg-traffic`、`network-economy`、`problem-report-blank-map`、`repeating-services`） | 檢查碼涵蓋「錢與帳」，**全部會動**，無法避免。README 允許「刻意的行為改變」重錄，PR 要逐檔說明（原因一致：單位乘 3） |
| 測試的金額斷言 | `Tests/GameCoreTests` 約 2,187 行、`GamePresentationTests` 約 3,161 行提到 `Money` 或 `$`；字串斷言 `"$ 12"` 一類約 620 處（191 個檔） | 大多可用機械改寫；字串斷言建議改成呼叫同一個格式函式，不要再寫死 `$`（PR-0 做） |

## 3. 比例比較

候選：

- **A** NT$1＝$1，所有數字照真實新台幣重訂。
- **B** NT$3＝$1，整體乘 3，舊存檔載入時乘 3，再修高鐵、區間票價整數元、預設分段票價。
- **C** NT$10＝$1，整體乘 10（高鐵不用修）。
- **D1** 只把 `$` 改成 `NT$`，數字不動（1:1 換標籤）。
- **D2** 儲存值不動，只在顯示時乘 3（OpenTTD 的幣別是這樣：內部固定、顯示用匯率；GPL，只借想法，下面 6 節）。

| | A 照真實 | B ×3 | C ×10 | D1 換標籤 | D2 顯示乘 3 |
| --- | --- | --- | --- | --- | --- |
| 和真實差多少 | 全部對，但運量沒縮放，第一條線永遠不回本 | 票價、人事、公車對；資本財小 300 倍起；高鐵貴 3.3 倍（要重量） | 高鐵對；一般票價 NT$50 貴 3.3 倍，人事 NT$6,200 是 4 個人日 | 票價 NT$5 低於任何真實票（最低 NT$15）；高鐵 NT$149 差 10 倍 | 同 B，但票價只能是 3 的倍數：NT$22、28 都設不出來 |
| 要升存檔嗎 | 要，倍率不一 | 要（+1，載入時 ×3） | 要（+1，×10） | 不用 | 不用 |
| golden | 全部重寫、行為也變 | 金額欄位全 ×3，行為不變（可用腳本逐欄證明） | 同 B，×10 | 不動 | 不動 |
| replay | 全重錄 | 全重錄（9 個） | 全重錄 | 不動 | 不動 |
| 挑戰與教學目標重量 | 全部 | 不用，機械 ×3；跑報告確認 | 同 B | 不用 | 不用 |
| UI 數字長度 | 最長：資本財億級 | 開局 NT$9,000,000；大亨目標 NT$2,400,000,000（13 位數）；比現在多 2 字元（前綴）加半位 | 多一位數 | 只多前綴 | 同 B |
| 外部已看到的數字 | 全變 | 全變，且之後不再變 | 全變 | 之後還要再變一次（把假的比例換成真的） | 之後還要再變 |

五方打分（權重：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15；每方 1–5）：

| | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --- | --: | --: | --: | --: | --: | --: |
| A | 1 | 1 | 2 | 5 | 1 | 1.75 |
| **B ×3** | **4** | **3** | **3** | **4** | **1** | **3.15** |
| C ×10 | 2 | 3 | 2 | 3 | 1 | 2.25 |
| D1 | 2 | 3 | 5 | 1 | 1 | 2.40 |
| D2 | 2 | 4 | 3 | 3 | 1 | 2.65 |

各方一行：

- 玩家：B 的票價、人事、公車在台灣人眼裡是對的數字（NT$15 一趟、NT$80 一日券的倍數關係還在）；C 的 NT$50 一趟不像台灣；D1 的 NT$5 一趟更不像；D2 能顯示 NT$15 卻設不出 NT$22。
- 開發：B 一次到位，但是 GameCore 的完整層級 PR；D1 最省卻是把「假比例」留給將來更大的遷移；D2 最省且不動存檔，代價是永遠帶著一個隱藏的 3，每個新常數都要記得是「元的三分之一」。
- 美術：D1 數字最短最好排；B 多一個 `NT$` 前綴與半位數，HUD 有寬度計算（`StatusBarWidths`）可以吃下，繁中用 萬／億 可再縮短。
- 鐵道迷：B 讓票價、人事、公車、高鐵都對得上有出處的數字；A 資本財也對但遊戲玩不了；D1 最差。
- 音樂：無（各選項同分 1）。

**建議 B。** 它是唯一同時滿足「票價與人事貼真實」「一次遷移」「規則行為不變可驗證」的選項；C 只有高鐵比較準，其他都差；D2 有「票價只能是 3 的倍數」的硬傷（臺鐵、捷運的真實票價 22、28、32 都設不出來）。

**B 的代價（要誠實說）：**

1. 資本財仍然是遊戲尺度，不是真實新台幣；玩家若拿 NT$30 萬一公里的軌道去比真實，會覺得假。這是運量縮放帶來的，不是這張單能解的（第 6 節未決）。
2. 高鐵票價 NT$1,490 相對現在的遊戲內水準貴 3.3 倍（現在 $149，乘 3 才是 NT$447）。高鐵示範的收入會增加；需要用 `HighSpeedReportTests` 量過，必要時調高鐵的車價、日成本或需求。
3. 預設分段票價（`standardBands`）原本是參考庫的美元分數（0.55–1.20），乘 3 變 NT$1.65–3.60，不是整數元。需要換一組 NT$ 整數元的預設（例如 15／20／25／30／35），隨 `fareBaseline` 縮放後湊整到 NT$1。

## 4. 為什麼不是「只做顯示」

D2 的好處是不動存檔、不動 golden、不動 replay，看起來最便宜。三個理由還是不選：

1. 票價的最小單位會是 NT$3，與「臺鐵台北—板橋 NT$22」「平溪線 NT$28」這種真實票價相衝，而且票價編輯器的步進也會是 3。
2. 之後每個新常數都要記得除以 3 才是 NT$，開發者與文件裡的「元」和玩家看的「元」不同。
3. 作者說的是「未來更多玩家轉換更困難」。D2 讓這個負擔永遠留著，B 在存檔裡一次做完。

## 5. 實作計畫（給下一張，Opus）

### 5.1 預留號碼與順序

- 存檔版本：**1 個**。main 是 74，#1365 預約 75 → 這張取 76（以登記當下的「最大 ＋ 1」為準）。
- 決策：**1 個**（`docs/decisions/<N>.md`；目前登記到 441，#1366 用 441，取 442 或之後）。要不要把「高鐵票價改用真實表並重量」另開一個決策，由實作 session 自己定；建議同一個。
- golden schema：**1 個**（`GoldenScenario.schemaVersion` 現在是 74 → 75，以登記當下的最大加 1 為準），標明「金額單位為新台幣（1/100 元）」，所有含金額欄位的 golden 一併升。
- 新 fixture：`SaveFixtures/v76-nt-dollar.json`（載入後金額在新單位）。
- 先決：**#1365（公車，存檔 75）先合併**。它新增的常數（`BusRoute`）要在這一輪的清單裡；不先合併就是兩個 PR 都改同一批常數與存檔版本。實作 session 開工前重新 `grep -rn "Money("`，並在 #1041 登記期間請規劃**暫停合併任何新增金額常數的 PR**（#1361 的站前路、#1366 之類，合併後要補乘 3）。

### 5.2 PR 切法

不能拆成「先改常數、再遷移」：兩者必須同一個提交，否則中間狀態的世界不一致。切成：

- **PR-0（前置，GamePresentation、App，不動 GameCore，不升存檔，可立刻開，可平行）**：
  - 所有玩家字串裡的金額都經過 `Money.moneyText`／`wholeText`／`shortMoney`，不再手寫 `$`；成就、劇本、挑戰文字裡寫死的「$5,000,000」「3 億」改由常數產生。
  - 測試的字串斷言改用同一個格式函式，不再寫死 `"$ 12"`。
  - 把借來格式化人數的千分位（`Money(x).displayText`，77 處）換成獨立函式。
  - 完成標準：全部既有測試不改值就綠；之後 PR-1 的測試 diff 只剩金額數字。
- **PR-1（GameCore ＋ GamePresentation，一個原子 PR，完整層級）**：
  1. **存檔**：`SavedGame.currentVersion` ＋ 1；版本 < 新版本時所有 `Money` 解碼乘 3。單點做法首選：在 `SavedGame.init(from:)` 讀到版本後，用 `@TaskLocal`（標準函式庫，Linux 可用，GameCore 不需要 Foundation）把倍率傳給 `Money.init(from:)`，只包住 `world` 的解碼；其他地方（成就、設定）解碼 `Money` 時倍率預設是 1。解碼乘法要檢查溢位，並維持 `maximumBalance` 等上限的現有驗證（超過就拒讀）。備案：每個型別自己補一個遷移欄位（欄位太多，不建議）。
  2. **稽核**：寫一個測試把「所有含 `Money` 的 Codable 型別」的欄位逐一設成互不相同的質數，走一遍遷移，證明每個都乘 3；再做**雙版本差分**：同一個舊 fixture，base（舊程式）與 head（新程式）各跑 30 天，每天的帳本金額必須是 3 倍（±湊整），人數、位置等非金額欄位必須相同。非 `Money` 型別的 `Int64` 金額欄位（1.3）用 grep 逐個列進 PR。
  3. **常數**：第 2 節所有「×3」欄；`pricingBalance` 哨兵不動。`/100*100` 湊整單位不動（現在代表整數新台幣）；`Fares.swift:78` 的 `/ 750 * 5`（湊到 0.05）改成湊到 NT$1。
  4. **高鐵**：`HighSpeedFares.centsPerNewTaiwanDollar` 換成 100（直接用表上的新台幣，檔名與註解跟著改）；`HighSpeed.centsPerKilometre` 由 45 改成使台北—左營沿軌道約 NT$1,490（約 4.4 元／km，實作時以表的端點校準）；重量高鐵（見 5.6）。
  5. **預設分段票價**：換一組整數元預設（決策裡寫理由與出處：臺鐵區間 2.18 元／km、捷運分段）。
  6. **golden**：新增 `tools/golden-checks/nt_scale.py`，有明確的「金額鍵」清單，兩個模式：`--rewrite`（輸入與預期值 ×3）與 `--verify`（比對 base 與 head 的同一檔：金額欄位 ＝ 3 × 舊，差額列表；非金額欄位完全相同）。**預期值不手改**：腳本改寫後再跑測試，若有欄位不等於 3 × 舊（湊整造成），PR 逐項列出。
  7. **replay**：9 個檔重錄，PR 一個表，寫「每個檔：原因＝單位乘 3；以 `--verify` 證明命令序列相同、非金額狀態相同」。
  8. **SavedGameTests 的三個載入值**依遷移結果改，PR 逐項說明；補 v76 fixture 與載入測試。
  9. **存檔清單的餘額**（`SaveLibrary`）一併遷移或讀檔後重算。
- **PR-2（量測與調整，可併入 PR-1 的後續提交）**：跑第 5.6 節的報告，依結果調高鐵、可能的 `NewGameBalanceTests` 區間；若有 CONCERNS 在這裡處理。
- **PR-3（顯示與對外文字，GamePresentation、App、文件）**：前綴 `NT$`（建議不加空格：`NT$12,345`，台灣慣例；現在是 `$ 12,345`）；繁中壓縮顯示用 萬／億（`NT$900 萬`，HUD、建造回饋、列車行程等窄位置；帳本與面板維持千分位精確值）；英文保留 k／M；`StatusBarWidths` 的最寬值；`HelpGuide`；`WhatsNew`（見 5.5）。

若時間緊，PR-3 的 萬／億 可以延到上架之後；**前綴 `NT$` 要跟 PR-1 同一個版本出去**，否則數字乘 3 了還寫 `$`。

### 5.3 玩家文字與翻譯

- 前綴與金額字串都在 GamePresentation 的 `language.text(英文, 中文)`，不在 `Localizable.xcstrings`（`xcstrings` 裡的 `$` 是 `%1$@` 格式符號，不是錢）；要補的是上面 PR-0 列的寫死金額。
- 規則（CLAUDE.md）：玩家看的字只寫功能，不寫比例、換算、「新台幣」的由來；`NT$` 就是幣別本身，不需要說明。
- 繁中翻譯檢查（`ios-build.yml` 的 Traditional Chinese translation check）：新增的字串要有中文；`NT$` 在英文與中文都是 `NT$`。
- 「美元」一詞：派工單 AI 正在改地價說明，之後不再有；實作時 `grep -rn "美元\|dollar"` 再核一次（目前 `Sources` 裡 `DisplayText.swift`、`EconomyText.swift`、`TourismText.swift` 等註解或文字有出現，下一張逐一看是否玩家看得到）。

### 5.4 PR 要附的

- 對照表：參考庫檔案 → 目標檔（這張研究沒讀私庫；下一張要讀 `Railway/taiwan-rail-reference-clean/source/data/thsr_fare.json`、`tra_station_of_line.json`、票價與 `data_provenance.json`，並把表放進 PR）。
- 五方理由（本文第 3 節可直接用）。
- 搜尋紀錄：已在第 6 節。
- 平衡：依 economy-balance skill 的格式（情境、判定、前後表）。
- 決策檔：`docs/decisions/<N>.md`，含「量到的」段落。

### 5.5 官網、What's New、截圖、商店

- **What's New**：要寫。`Sources/GamePresentation/WhatsNew.swift` 與 `WhatsNewTests.swift`、`WhatsNewView.swift`：一行，例如「金額改用新台幣，舊存檔自動換算」，英文與繁中各一。
- **官網截圖**：`website-screenshots.yml` 是手動，PR-3 合併後在 `main`（或該分支）跑一次；之前截圖含 `$`。
- **App Store 文字與截圖**：Apple 後台是作者的步驟；請規劃提醒作者截圖要在 PR-3 之後重拍。
- **docs**：`docs/UI_THEME.md`（玩家看的文字）、`docs/UI_INTERFACES.md`、`docs/OVERVIEW.md`、`docs/ROADMAP.md` 裡寫 `$` 的地方只在改到的敘述順手改，不全面改寫歷史。

### 5.6 要跑的報告與 shard

照 `.claude/skills/economy-balance/SKILL.md`，release build，前後各量一次，兩張表逐欄比；通過標準：**每個金額欄位 ＝ 3 ×（±0.5%），每個非金額欄位（運量、人口、天數）相同**。

| 報告 | 指令（環境變數） | 看什麼 |
| --- | --- | --- |
| `BalanceReportTests` | `BALANCE_REPORT=30`，14 個情境；示範地圖 `BALANCE_REPORT=60` | 回本天數仍是 4–10（示範 7–10）；日損益 ×3 |
| `NewGameBalanceTests`（斷言） | `.github/scripts/swift-shards.sh run campaigns-8` | 第一條線造價與回本 |
| `ChallengeReportTests` | `CHALLENGE_REPORT=<種子數>`（一個種子超過一小時，分 `CHALLENGE_SEEDS`） | 沙盒三種玩法達標日 |
| `LiuMingchuanReportTests`、`JijiReportTests`、`PingxiChallengeTests`、`BranchLineChallengeTests` | `LIU_REPORT=1` 等 | 劉銘傳、集集、平溪目標日 |
| `HighSpeedReportTests`、`HighSpeedFirstMapReportTests` | `BALANCE_REPORT=1` | 高鐵需求對真實十二站；**票價貴 3.3 倍之後的收入與成本** |
| `LessonTargetReportTests` | | 教學課目標 |
| `AcquisitionReportTests`、`BusFeederReportTests`、`RealWorldExpansionReportTests`、`ActionCostReportTests`、`CoreLoopBaselineReportTests`、`LongGameCostReportTests` | 各自的環境變數 | 收購、公車、購地門檻、動作成本 |
| 屬性 campaign | `swift-shards.sh run campaigns-6`、`campaigns-9`（`EconomyPropertyTests`） | 帳要對得上（決策 179） |
| 其他 | `GoldenScenarioTests`、`ReplayFixtureTests`、`SavedGameTests`、`WhatsNewTests`、所有字串斷言 | |

要重量的平衡目標清單（其餘機械 ×3，量過即可）：

1. 高鐵：每公里票價、示範開局現金（`HighSpeedDemo`）、車價與日成本、`HighSpeedReportTests` 的收入／成本比；
2. 預設分段票價（新預設）與 `fareBaseline` 對需求的作用；
3. 一日券建議價（3 × 最短票價 ＝ NT$45，對平溪線 NT$80 的比例仍成立，不必動）；
4. 公車（#1365 已是 NT$3＝$1，乘 3 之後與其他一致，不必重量，只需確認不會重複乘）。

### 5.7 風險

- **進行中的 PR 新增金額常數**（公車、道路、機廠等）合併後少乘 3。對策：暫停合併或要求 PR-1 前最後一刻重新 grep；PR-1 加一個「掃描 `Money(` 字面值」的稽核清單放進 PR（不是 CI 測試，因為無法自動判斷哪些是價錢）。
- **iCloud 同步與舊版**：新版存檔（v76）舊版讀不了（現有規則：「save is newer」），同一個玩家兩台裝置版本不同時會出現；TestFlight 內部約 50 位，風險小，但 What's New 與測試者說明要提到「請兩台都更新」。
- **溢位**：乘 3 後的最大餘額、年度累計仍遠小於 `maximumBalance`（2^62 ≈ 4.6e18），但 `pricingBalance`（2^60）不能乘；遷移要用帶溢位檢查的乘法。
- **遷移的漏網欄位**：非 `Money` 型別的 `Int64` 金額欄位（5.2 的稽核處理）。
- **CI 容量**：完整層級的 GameCore PR 最多同時 2 個（CLAUDE.md）；另一個 GameCore PR 在跑時要排隊。
- **平衡**：本研究沒有量測，判定 NOT ASSESSED。

## 6. 搜尋與出處

- 參考庫（`a91453/railway-reference-private`）：本研究**沒有附加或讀取**，因為只寫文件；下一張實作要照 CLAUDE.md 做參考核對（見 5.4）。repo 內已有的：`thsr_fare.json` 的 MD5 與出處在 `HighSpeedFares.swift` 註解、決策 325；區間車 2.18 元／km 在決策 319 附近。
- 外部（開放網頁）：基本工資、臺鐵 2025 票價、台北 101 公告現值，連結在第 2 節開頭；公告現值的全市平均沒有找到單一數字，標「未查」。
- 其他專案做法：OpenTTD 的幣別是內部單位固定、顯示套匯率（D2 的原型）；授權 GPL，只借想法，沒有複製任何程式；這個記述是依記憶，這次沒有再開專案核對。結論：我們的玩法需要把票價設在真實整數元，所以不採 D2。沒有找到適合直接複製的現成程式，遷移鉤子（`@TaskLocal` ＋ `Money.init(from:)`）是本專案自己寫的。

## 7. 沒做的事與下一步

- 沒有跑任何報告或測試（只寫文件）：所有「現值」是讀原始碼；「真實」欄中標「未查」者沒有出處，不要當事實引用。
- 沒有逐行盤點教學課程的開局現金與目標（2.7 末列）、`RailwayGameApp/Views` 裡含 `$` 的 9 個檔、`HelpGuide.swift`；這些是 PR-0 的第一步。
- 稅率（50% 對真實 20%）、利率（5%）、資本財尺度屬於「比例」不是「幣別」，不在這一輪；若要做，是 NEXT_PRIORITIES 第 36 項「經濟加深」的其他部分，和這張分開。
- 規劃要決定的兩件事：(1) PR-1 的目標日期（10/29 合併，還是讓 10/31 先帶 `$` 出去）；(2) 要不要在 PR-3 把繁中大數字換成 萬／億（建議要，但可在上架後）。
