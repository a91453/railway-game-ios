# FUKUOKA-OPEN：打開福岡地圖與飛福岡的航線

- 派工：協調者（工作串「做福岡地圖」），2026-11-19，雲端 thread session，分支 `claude/project-thread-08of3m`。
- 決策 854 的後來一節（`docs/decisions/854.md`）。存檔版本、golden、replay、GameCore：不動。
- 合併時機：協調者 2026-11-19 說 141 發版後才合，排進 142。

## 做了

- `OverseasMaps.open` 加福岡；`RailwayGameApp/AssetPacks/fukuoka.json`（`mappack-fukuoka`）。
- `AirportCatalog`：福岡機場（`fuk`）與桃園、高雄往返的航線（數字與來源在決策裡）；資料來源頁加「福岡機場」。
- 測試：`FukuokaRailwaysTests.testFukuokaIsOpen`、`AirRoutesTests.testTheAirportsThatFlyToFukuoka`、`MapPackDownloadsTests`、`TimetableCheckupAllBoughtTests.testFukuokaLines`（三線共站，一起買；`ci.yml` 夜間體檢的 branch-lines-and-rovaniemi 組加進去）；`RovaniemiReportTests` 加 `ROVANIEMI_CITY=fk`。

## 還留下的

1. **FUKUOKA-LATE**（bug，`docs/priorities/FUKUOKA-LATE.md`）：七隈線折返晚 126–127 班、空港線機場尖峰空 10 分；`TimetableCheckupAllBoughtTests.budgets` 的福岡兩列修好後調低。
2. **FUKUOKA-FARE**（評分在私有 `railway-assets-private-2` `docs/priorities/FUKUOKA-FARE.md`）：三線一天賠約 NT$410 萬（決策裡的表）。先查成本是哪一項大（車、站、隧道的維護），再看票價與需求；改共用規則時台灣、香港、羅瓦涅米與機捷都要重量。
3. **網站 `credits.html`**（`railway-reference-private`）加福岡一節（鐵道、地形、人口、建物、地標、機場），142 發版後才合。
4. **App Store Connect**：142 的 build 送審時，`mappack-fukuoka` 這個 asset pack 要跟著核准（和香港、羅瓦涅米第一次一樣，是作者的步驟）。
5. **沒有在手機上看過**：飛福岡開圖、下載地圖包（設定裡的地圖包列表多一列）、買三線一組、機場的航班。下一版 TestFlight 要看。
6. `JAPAN-FUKUOKA-1.md` 的 4–7 項（車、西鐵貝塚線、直通、機廠）照原順序。
