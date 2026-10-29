# 資料視覺化盤點（2026-10-29，派工單 VIZ，決策 478）

作者 2026-10-29：「然後還有哪裡需要做資料視覺化的，順便一起派」。這份表列出 App 裡用數字或文字列表呈現、但畫成圖會更好讀的地方。資料分兩類：

- **第一類**：資料已經在 GameCore 或 GamePresentation 裡，畫圖只動畫法。
- **第二類**：GameCore 要開始記歷史才畫得出來。這一類會動存檔，只寫進決策 478 的「下一步」。

盤點的基準是 main `58c6c2b`。行號是那個版本的。之後合併的 #1467（CJ，決策 472，main `d2a2b0a`）已經畫了幾張圖，列在下面「已經有的圖」，表裡不重算。

## 已經有的圖（不重做）

| 圖 | 檔案 | 備註 |
| --- | --- | --- |
| 財務趨勢：收入與成本、淨利、旅客 | `FinanceTrendCharts.swift`（`FinanceTrendCharts`） | 決策 176；UI 健檢 3-7 的兩件都已修：利潤另成一張圖，成本虛線已列在圖例 |
| 路線每日運量、每日損益 | `FinanceTrendCharts.swift`（`LineOperatingCharts`） | 決策 179 |
| 車站各時段進出 | `StationPanel.swift`、`StatisticsCharts.swift`（`StationFlow.chart`） | #1467（決策 472）改成 Swift Charts，標出尖峰時段 |
| 路線清單：運量迷你走勢線、最滿列車條 | `LinesPanel.swift`、`StatisticsCharts.swift`（`LineReport.sparkline`、`loadGauge`） | #1467（決策 472）；只有昨天一班最滿的，沒有逐日 |
| 路網流量：最擠區間排行 | `NetworkFlowSheet.swift`（`SectionRankingChart`）、`NetworkFlowReport.rankedSections` | #1467（決策 472）；每段只看最擠的那個小時 |
| 縱斷面、運行圖 | `NetworkControls.swift`（`LongSectionView`）、`TrainDiagramView.swift` | — |
| 已經是手畫長條的 | 路線虧損卡、滿意度卡（`LinesPanel.swift:2017`、`:2166`），路網流量的路線頁（`NetworkFlowSheet.swift:74`），列車運用表（`TrainRosterView.swift:244`），目標（`GoalsPanel.swift:112`），公司等級（`PromotionLineView.swift:67`），站長稱號、成就 | 已經算是圖。要換成 Swift Charts 只是一致性問題，排在最後 |

## 第一類：資料已經有

分數是五方各 1–5 分的合計（玩家、鐵道迷、開發、美術、音樂）。音樂一律 1 分：能加的只有 VoiceOver 的 Audio Graph，每張新圖都會有。

| # | 畫面 | 檔案:行號 | 現在怎麼顯示 | 資料從哪來 | 畫成什麼圖 | 玩家能多看懂什麼 | 玩／鐵／開／美／音 | 合計 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **路線：各站間載客** | 沒有。路線面板只有站序與 `RouteStrip`（`LinesPanel.swift:1006`） | 沒有顯示 | 乘客計畫 `plannedPassengerLegFlows()`，以 `SectionFlow.segments`、`capacities` 分到每一段（`SectionFlow.swift:224`） | 每段一列，左右對開的橫條：一個方向向右，另一個方向向左 | 哪一段最擠、哪個方向；要加車或加區間車該加在哪 | 5／5／4／4／1 | **19，做了** |
| 2 | **路網流量：區間各時段** | `NetworkFlowSheet.swift:142–181` | 每個區間只寫最擠那個小時：「08:00 · 載客／運能（%）」（#1467 把它畫成排行，仍是一段一個小時） | `SectionFlow.Section.loads[24]`、`capacities[24]`；報表原本只留最擠的一小時 | 24 小時長條，座位畫成虛線階梯 | 尖峰有多長；離峰是不是空跑；超過座位的有幾個小時 | 4／5／5／4／1 | **19，做了** |
| 3 | **路線營運：每日最擠的一班** | `LinesPanel.swift:681`（列表那行字的「尖峰 87%」，#1467 加了昨天的最滿列車條）；`LineOperatingCharts` 沒有這張 | 只有昨天一個數字 | `LineOperatingDay.peakLoadPercent`（`LineReportText.swift:37`），最多 30 天 | 折線，100% 畫一條「座位」線 | 是不是天天都擠、哪幾天超過座位 | 4／4／5／4／1 | **18，做了** |
| 4 | 經濟：票價距離級距 | `EconomyPanel.swift:385–393` | 一段說明文字 | `FareRules.distanceBands`（`Fares.swift:31`） | 階梯線：距離對票價 | 多搭一站會貴多少 | 3／4／5／3／1 | 16 |
| 5 | 車隊總覽：各列車滿載率 | `FleetOverviewSheet.swift:339` | 每列一條小載客條 | `trainLoadInfo(of:)`（`EconomyText.swift:293`） | 依滿載率排的橫條，100% 一條線；或分布直方圖 | 哪幾列太擠、哪幾列空跑 | 4／3／4／3／1 | 15（SHOT 在改這個檔，之後再做） |
| 6 | 公車路線 30 天 | `ControlPanel.swift:591`、`StationPanel.swift:855` | 只寫一行今天的數字 | `BusRoute.days`（`BusRoute.swift:143`），30 天的乘客、票收、成本 | 照 `LineOperatingCharts` 的每日乘客與損益 | 公車線有沒有在長、是不是在賠 | 4／2／4／3／1 | 14（ROAD #1469 在改公車；StationPanel 是 CJ 的） |
| 7 | 經濟：成本細項 | `EconomyPanel.swift:515–528` | 損益表的格子 | `DayAccount` 的營運、保養、電費、人事、利息、稅（`Accounts.swift:191`，720 天）；`FinanceTrendPoint` 現在把它們加成一個 `cost` | 堆疊長條，或收入圖的成本拆開 | 錢花在哪一項 | 4／3／3／3／1 | 14 |
| 8 | 月報：成長與衰退最多的車站 | `MonthlyReport.swift:63–64`、`:120–127` | 「▲ +n」「▼ n」各三列 | `MonthlyReport.grown`／`fallen`（`MonthlyReportText.swift:106`） | 左右對開的橫條（增減） | 哪裡在長，一眼比大小 | 3／3／4／3／1 | 14 |
| 9 | 路網流量：沒被滿足的需求 | `NetworkFlowSheet.swift:186–221` | 每對車站一行「n 人」 | `NetworkFlowReport.unmet` | 依人數排的橫條 | 下一條線該往哪蓋 | 3／3／4／3／1 | 14 |
| 10 | 路線：一天的服務時段 | `LinesPanel.swift:452–508`、`:1231–1276` | 選單與每級的文字 | `serviceDay.bands`（`ServiceLine.swift:163`）、`LevelServiceSummary` | 24 小時的時段帶，疊上各時段的計畫乘客 | 尖峰時段的班次與人潮對不對得上 | 3／4／3／3／1 | 14 |
| 11 | 月報：本月數字 | `MonthlyReport.swift:50–57` | 五行數字，各附上月的 ▲▼% | `accounts.days`（24 個月） | 每個數字旁一條 12 個月的小走勢線 | 這個月是趨勢還是偶然 | 3／2／4／3／1 | 13 |
| 12 | 經濟：貸款 | `EconomyPanel.swift:292`、`:327–345` | 一句話 | `CompanyAccounts.loan`、`maximumLoan` | 量表：已借對上限 | 還能借多少 | 3／1／5／3／1 | 13 |
| 13 | 觀光：各景點 | `TourismPanel.swift:64–69` | 「今日・昨日・今年・去年」一行字 | `AttractionRow`（`TourismText.swift:80`） | 今年對去年的成對長條，依人數排 | 哪個景點在長 | 3／2／4／3／1 | 13 |
| 14 | 目標：今天的班次 | `TodaySettlementsSection.swift:61–119` | 三格數字與八列 | `tripLog` 今天每班的到站時間與票收 | 每小時的票收與準點長條 | 一天裡哪個時段賺 | 3／3／3／3／1 | 13 |
| 15 | 年報、資產負債表 | `YearEndReport.swift:81–97`、`EconomyPanel.swift:538–586` | 數字格子：今年對去年 | `accounts.years`（最多 50 年，含期末資產負債表） | 各年資產分類堆疊對貸款；各年淨利長條 | 公司是在長還是在借錢撐 | 3／2／3／3／1 | 12 |
| 16 | 地圖圖例：服務涵蓋 | `PopulationLegendView.swift:233–240` | 一行字 | `CoverageSummary`（`CoverageSummary.swift:15`） | 進度條：涵蓋人口對總人口 | 還有多少人沒被服務 | 2／1／5／3／1 | 12 |
| 17 | 經濟：上一小時 | `EconomyPanel.swift:468–486` | 每項一行 | `recentLedgerTotals()`（`EconomyText.swift:208`） | 每項一條橫條 | 哪一項花最多 | 2／1／5／2／1 | 11 |
| 18 | 車站：去哪裡、乘客去向、昨日進出、土地 | `StationPanel.swift:1070–1379` | 文字與數字行 | `StationRidership.pairs`、`passengerLedgerRows` 等 | 進出成對橫條、乘客去向堆疊 | — | — | 車站面板是 #1467（決策 472）的範圍，那邊的下一步再看 |
| 19 | 車站營運：月台忙碌、天氣預報 | `StationOperationsView.swift:101–219` | 小條與 % | `StationOperations` | 小長條 | 不多 | 2／2／4／2／1 | 11 |

這次做 1、2、3：分數最高的三張，都在講「擠不擠」，鐵道迷看斷面運量與時段的習慣，三張一起看得出要加車加在哪段、哪個時段、是不是天天如此。第 4 名的票價級距（16 分）與它們不相干，留給下一張。第 5、6 名的檔案別的 session 正在改（SHOT、ROAD、CJ），等它們合併後再做。

## 第二類：要 GameCore 新記錄歷史

這些都要在 GameCore 加欄位、存進存檔（`SavedGame` 要升版、加遷移與新的 fixture）。存檔 76、77 已保留給別的工作，所以這次只寫下來，見決策 478 的「下一步」。

| # | 想畫的圖 | 現在有什麼 | 缺什麼 |
| --- | --- | --- | --- |
| A | 城市人口、居民與工作的成長線 | 只有現在的土地與建物；`MonthlyBaseline`（`NewsLog.swift:83`）只留上個月的車站旅次與高樓數 | 每月一筆人口、居民、工作、建物數 |
| B | 車站每日旅次的走勢 | `TownGrowth.Place` 只有 `base`、`counted`、`lastGrowth`；`LineAccounts.flows` 只有今天與昨天 | 每站每天（或每週）一筆上下車人數，最多約 30 天 |
| C | 實際的各站間載客 | 第一類的圖用的是乘客計畫，不是實際載到的人 | 每段每方向每天一筆實際載客（由 `LineTally` 的出站載客累加） |
| D | 路線每小時的實際乘客 | 只有計畫的 `SectionFlow` | 每線每小時上車數，今天與昨天 |
| E | 每天的現金餘額、貸款餘額 | 年底的 `years[].closing`；每天的收支 `days`、`capitalDays`（可以倒推，但倒推遇到買賣與遷移就不準） | 每天記一筆期末現金與貸款 |
| F | 公司等級、目標進度的走勢 | 每次重算，不存 | 每月一筆等級分數 |
| G | 景點的月走勢 | 只有今天、昨天、今年、去年 | 每景點每月一筆 |
| H | 每列車滿載率的走勢 | 只有現在 | 每列每天一筆最擠 |

## 參考庫看了什麼

| 參考 | 內容 | 怎麼用 |
| --- | --- | --- |
| `Railway/geo-scene-reference-clean/source/docs/features/viz-library/README.md` | 儀表板的共用視覺規格：一份規格、色盲驗證測試、數字格式 | 本作的對應物是 `ChartSpec`（圖的資料與摘要一份，畫面與 VoiceOver 共用）與 `Theme` 的 `chart*` 色票（已照 dataviz 驗過）；不搬程式 |
| 同上 `features/chart-hover-tooltip/README.md` | 35 個圖表統一一套 hover 提示 | 本作用 Swift Charts 的 `chartXSelection`／`chartYSelection`：點一下，圖上方那一行字換成那一點的數字（同財務圖） |
| 同上 `design-system/spec.md` §P2b、§P5 | 走勢線的最新值圓點；資料色對底至少 3:1；缺值和 0 要分得開 | 3:1 已是 `Theme.chart*` 的規則；「沒有列車」與 0 人分開寫（`hourText`、`sectionText`） |
| `Railway/city_world_reference/` | 城市遊戲，沒有圖表 | 沒有可用的 |
| 本作 `SectionFlow`（決策 178，取自 `Ci/` 的 `metroAllocateSectionFlowOnLineLeg`） | 每段的計畫載客與運能 | 第 1、2 張圖的資料直接讀它 |
