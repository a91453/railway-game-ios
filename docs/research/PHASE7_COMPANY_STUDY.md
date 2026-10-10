# Phase 7 公司經營與房地產：參考盤點與設計提案

狀態：**供作者決定，未實作**。盤點基準為 `railway-game-ios` 的 `origin/main` `8ff0929`，以及 2026-10-07 複製的 `a91453/railway-reference-private` `main` `f27339b`。本文所有「來源」數值均指實際讀到的檔案；本文新訂的價格、倍率、稅率、年限和行為一律標為**原生（gap）**。金額一律是遊戲美元的美分 `Money(Int64)`，不能把參考網站的美元、Simulator 的新台幣或真實房價混在一起。

依序讀過 `AGENTS.md`、`CLAUDE.md`、`docs/ARCHITECTURE.md` 決策 36、46、67、70、72–76，`docs/ROADMAP.md` Phase 6–8 與跨階段議題、`docs/RAILWAY_REFERENCE_MAPPING.md` G1c／G1d、決策 67、Phase 6a／6b，以及 `docs/research/PHASE6C_BUILDINGS_STUDY.md` §5–§7。後者的 §5.3 曾建議「居民、就業兩項都要放下才選密度」，**已由決策 74 改為只按主要用途選級**；以已合併的程式為準。Phase 6c 的一般住宅、商業、辦公建物是城市資產，城市自動生成及升級；公司自建或買入才是 Phase 7。

## 1. 現況與 Phase 7 接點

| 檔案 | 已有型別、函式與實際責任 | Phase 7 接點 |
| --- | --- | --- |
| `Sources/GameCore/Economy/Money.swift` | `Money.amount:Int64`、`+`、`-`、比較與單值 `Codable`，整數美分。 | 交易、每日收支和帳面價值都用它；乘法須先做上限檢查。 |
| `Sources/GameCore/Economy/GameEconomy.swift` | `ConstructionCosts {track,station,train,car}`；`trackPricingLength=1024` 世界單位＝16 m，`standard` 為 1000／50000／200000／0 美分。`GameEconomy {balance,costs}` 的 `canAfford`、`spend`、`earn`、`settle`：建造不得透支，結算可為負。 | 房地產報價、原子扣款與資本支出記錄；不把土地價塞入既有 `track`。 |
| `Sources/GamePresentation/NewGame.swift` | `GameWorld.startingBalance=300000000` 美分（$3,000,000）；`ConstructionCosts.newGame` 為軌道每 16 m 160000、車站 20000000、列車 15000000、加一節車廂 4000000 美分。 | 平衡例只用這組 App 開局價；GameCore 的 `standard` 另存並可由存檔自訂。 |
| `Sources/GameCore/Economy/Fares.swift` | `EconomyMode`、`FareBand`、`FareRules`；`standardFare=500` 美分，距離分段 0／6／12／22／32 km 對 55／70／85／100／120 美分；`fare(squaredDistance:)`、`charged`（0 以下收 $5）、`demandFactor(fare:baseline:)`（千分比表），驗證上限與 `Codable`。 | 房產可讀既有票價或車站服務，但不另造票價或以 UI 浮點數決定租金。 |
| `Sources/GameCore/Economy/Accounts.swift` | `HourlyAccrual` 記票價、付款人、離站次數、列車距離、乘客與座位；`LedgerItem` 現有票價、營運、維修、路線／列車能源、車站／列車人事、貸款利息；`LedgerLine`、`LedgerEntry.Kind`（`hourlyNet`、`dailyEnergy`、`dailyStaff`、`dailyInterest`）、`CrowdingMetrics`。`DayAccount.add(_:)` 聚合日帳；`FinancePeriod.days`＝1／7／30／360，`CompanyAccounts.record` 留最近 50 列、720 天，`report` 給本期及上期；`FinanceSummary` 算營業利益、扣息淨利。 | 增收租金、物業費、出售損益與折舊；要分清現金流、損益及資產變動。每一列分項精確加總成該列額。 |
| `Sources/GameCore/Economy/Operations.swift` | `setEconomyMode`、`setFareRules`、`setFareBaseline`、`borrow`、`repayLoan`；`tripFare`、`financeReport`；`chargeFares`、`countDeparture`；`fixedAssets(memo:)` 僅算各線停靠站數、路線長、配置列車數，**不是**帳面固定資產。`settleAccounts` 在整點先 `settleHour`，午夜再 `settleDay`；`write` 同步動現金與日帳。`accountsProblem`／`isWellFormed` 查分項符號、順序、總和及存檔界線。 | 可沿用結算時鐘與驗證框架；必須新增真正的成本基礎／折舊帳，而不能把 `FixedAssets` 當資產負債表。 |
| `Sources/GamePresentation/EconomyText.swift` | 金額格式、帳目中英標籤、`recentLedgerTotals(minutes:)`、`recentLedgerEntries(_:)`、`loanText`。 | 新類別的台灣用語／英文、資產及現金流文字。 |
| `Sources/GamePresentation/GameSession.swift`、`RailwayGameApp/Views/EconomyPanel.swift` | Session 呼叫核心的票價、模式、借還款指令；面板有餘額、貸款、票價、近一小時、日／週／月／年本期與上期報表、最近帳目。 | 買賣命令經 Session 傳到 `GameWorld`；畫面只顯示核心的報價與報表。 |

結算細節：`Operations.chargeFares` 於上車計入當小時，離站計班次；整點 `openedAt < now` 才結算剛結束的小時，以 `now−1 分鐘` 歸日。營運美元額＝`round(75×班次 + 42×列車公里 + 18×各線車站數)`，維修＝`round(12×路線公里 + 9×列車公里 + 8×列車數)`；距離用 64000 世界單位／公里，最後換成美分。午夜的能源＝`round(220×路線公里 + 360×列車數)`，人事＝`620×各線車站數 + 480×列車數`；先小時再能源、利息、人事。`borrow`／`repayLoan` 每次是 10000000 美分（$100,000）的整倍數，最多 500000000 美分（$5,000,000）；借還是現金與本金互換，不是收入或費用。`dailyLoanInterest(on:)` 在午夜按本金 × 500 基點 ÷ 10000 ÷ 360 四捨五入至整美元，利息不列入 `totalCost`、但扣自 `netProfit`。自由模式不結算。`GameWorld.advance(ticks:)` 的**目前程式順序**是在整分鐘先 `growTowns`、事件與需求計畫，**再** `settleAccounts`、釋出與派車；閒置跳步仍逐分鐘走帳。對照表 6c-2 所述「午夜先經濟後城鎮」是參考包的建議順序，與此處已合併的實際呼叫順序不同，Phase 7 應以程式為準並明訂新項目時點。

| 城市檔案 | 已有內容與限制 | 接點 |
| --- | --- | --- |
| `Sources/GameCore/City/Land.swift` | `LandUse` 住宅／商業／辦公；`LandCell {row,column,use,residents,jobs}`、`Land.cellLength=4096` 世界單位＝64 m、每項最多 100000、`catchmentRadius=51200`＝800 m；`Land.cell`、`totals(within:of:)`、`towns(seed:in:)`。格最後一列／行可能不滿 64 m。 | 所有權以同一格鍵、面積按世界邊界裁切；腹地人口與就業是收益輸入。 |
| `Sources/GameCore/City/LandDemand.swift` | `LandDemand.shares(of:among:)` 以距離權重及最大餘數分配，`Share.demand` 每 100 人／工作 40 旅次；`growLand(reached:)` 於午夜依站順序升級、成長、擴張，`upgradesPerStation=2`，`spread(towards:)` 新增 4 人住宅格。 | 公司建物必須與此處單格容量、擴張及一日一次順序接合，不能讓城市免費升級公司資產。 |
| `Sources/GameCore/City/Building.swift` | `BuildingID`、`CellPosition`、`BuildingKind.city/existingStock`、`BuildingDensity.d1…d4`（2／6／18／40 層）、`Building.tableCapacity(of:_:)`、`fitting`、`capacity(on:)`、`CityBuildings`、`setCityBuildings`、`buildingCapacity`、`catchmentBuildings`、`replaceLand`／`addLand`／`buildingProblem`。開啟時每個有人格恰有一棟城市建物；一般建物一棟一格。 | 需明確擴充所有權與同格唯一性。購買現有建物不得再加一份人口／容量。 |
| `Sources/GameCore/City/LandValue.swift` | `LandValueRules` 的空地／住／商／辦基準 1000／2000／3000／3500 美分／m²、D1–D4 係數 1000／1250／1600／2000；最好車站的服務分 S 與可達 A，`value=clamp(base+15S+1000A,500,50000)`；`landValue(row:column:)`、`landValues()` **只即時推導**。 | 交易時擷取報價並存成交成本；不把即時地價偽裝成帳面成本或保存地價時間序列。 |

## 2. 私有參考庫逐處盤點

### Ci/reference_snapshot

`lib/app__q_c234188b7c397f91.js` 是約 399 萬字元的壓縮 JS。下表是該檔實際函式／鍵，而非缺席的 `window.MetroEconomy` 引擎內部：

| 路徑／符號 | 實際看到的格式及數值 | 分類與用途 |
| --- | --- | --- |
| 同檔 `metroEconomyNewHourlyPending`、`metroEconomyAccrueHourlyFare`、`metroEconomyAccrueDeparture` | pending 物件有 `fareRevenue,operatingSubsidy,fareTrips,transferBoarded,departures,trainKm,passengers,seats`；舊路徑以 `Math.round(count*fare)` 累積票價，出發累計 trainKm；新引擎分支還有 `carKm,serviceCost,penaltyCost`。 | **需轉譯成 Swift**：已有 G1c 對應；車公里不能當房產折舊額。 |
| 同檔 `metroEconomyFixedAssets`、`metroEconomySettleHourlyIfNeeded` | 依 `branchRootId` 分組、車站用集合計數；舊路徑營運 `round(75·departures+42·trainKm+18·stationCount)`、維修 `round(12·routeKm+9·trainKm+8·trainCount)`；`lastHour` 鍵是 `day|hour` 防重結。 | **需轉譯成 Swift**，既有結算已吸收；「fixedAssets」只是營運量，不是資產價值。 |
| 同檔 `metroEconomySettleDailyForEndedDay` | `G._metroEconomySettledDays[day]` 防重；能源 `round(220·routeKm+360·trainCount)`，分項 `metro_route_energy`、`metro_train_energy`；人事 `round(620·stationCount+480·trainCount)`，`simMin:1439`，`allowNegativeBalance:true`。 | **需轉譯成 Swift**，既有日結已吸收；日結識別可參考。 |
| 同檔 `FLOW_DASHBOARD_FINANCE_BUCKETS`、`summarizeFinanceForTransport` | 日／週／月／年 `days:1/7/30/360`，`max:30/52/12/50`；摘要有 `revenue,totalCost,operatingProfit,investingCashFlow,netCashFlow`，將 `quota_purchase` 負額列為 `quotaPurchaseCashOutflow`，`quota_return` 列為流入。 | **需轉譯成 Swift**：投資現金流與損益分列值得採用；既有期間已移植。 |
| 同檔 `metroQuotaRingItems`、`metroQuotaPurchaseCatalogItems` | 配額鍵 `km/stations/cars/expressLines`；僅引擎沒給 catalog 時的備用項：`metro.routeKm.10` 購 10 km、`basePrice:100`，`metro.stations.5` 5 站／75，`metro.cars.6` 6 節／60，`metro.expressLines.1` 1／350；正常分支從 `MetroEconomy.getPurchaseCatalog().items` 取值。 | **需轉譯成 Swift** 才能實作配額，但只有備用價目，不能推定正式建設費；本提案建議不採用。 |
| 同檔 `metroEconomyHourlyPending`、`metroEconomyCommitImmediateExpense` | 使用 `window.MetroEconomy.metroRules().operatingSubsidy`、`recordServiceExpense`，然而引擎檔不在快照；fallback `recordServiceExpense` 有 `breakdown`、`allowNegativeBalance`、`simDay/simMin`。 | **gap**：沒有可核對的補貼、貸款、房地產、折舊、稅率實作。 |
| `lib/aviation_economy_curves__q_d3a7027251db4359.js` 的 `reference`／`forSeats`；`lib/aviation_economy_completed__q_7b75c8d57f0ba33b.js` 的 `perSeat`／`quote`／`weights`／`allocate` | `reference` 回傳每機型／航程的 `revenue,profit,cost=revenue-profit`；`forSeats` 依座位數比率縮放。`quote` 回傳 `actualRevenue=perSeatRevenue×passengers`；`weights` 依載具級別給成本拆分，`allocate` 按餘數與索引分配整數；曲線用 `Math.pow` 等浮點運算。 | **需轉譯成 Swift** 但屬航空日後範圍；「每類精確分攤」方法可參考，數值與房租無關，不能直接放 GameCore。 |
| `lib/ui-locales/zh-CN__q_8e57e7fa49d074d2.js` 的 `economy.ledger.*`／`economy.group.*` | 經營畫面的分類標籤是簡體中文鍵。 | **只是畫面**；台灣用語須另寫。 |

搜尋 `Ci/reference_snapshot/lib/` 的 `depreciation, realEstate, real_estate, rentalIncome, rentRevenue, propertyTax, taxRate, subsidiary, assetValue, loanInterest, quotaPurchase, quotaReturn, subsidy`；核心 `app` JS 對前九個房產／折舊／稅詞沒有命中，`subsidy` 與配額命中的是上述帳目及引擎呼叫。再找 `economy.js`、`metro_economy_rules.js`，快照沒有這兩檔。故**房產購入、租金、出售、折舊、稅與子公司規則均是 gap**；`aviation` 是不同運具的收入模型。

### Railway/site_archive_clean

`data/tra_station_info.json` 每站是 `{name,id,address,lat,lon,feature}`，例如基隆 `id:"0900",lat:25.13191,lon:121.73837`；沒有售價或租金鍵。`rail-3d/blender-buildings.js` 的 `buildingCatalog()` 讀 `blender-buildings-v1`／`historic-buildings-v2` 的 `catalog.json` 和 `placement.json`；`rail-3d/assets/blender-buildings-v1/hsinchu-tra/model.json` 有 `category:"station",displayHeightM:20,footprintWidthM:65,footprintDepthM:22,rotationDeg:0,placementStatus:"pending-georeference"`。這些**只是畫面／位置資料**，房產權利、營收及成本是 **gap**。搜尋 `rent,revenue,economy,loan,depreciation,tax,property,price,fare`，排除 i18n 法律頁、車站網頁的票價文案及 vendor 後，未見可執行的公司經營規則。

### Railway/railway_game_reference_clean

先讀 `00_READ_ME_FIRST.md`、`01_MIGRATION_MAP.md`。後者 §8–§9 **只列** `src/economy.cpp`、`src/company_cmd.cpp`、`src/vehicle_cmd.cpp`、`src/town_cmd.cpp`、`src/industry_cmd.cpp`、`src/subsidy.cpp`，主張經濟、公司、城鎮分層；固定 tick 範例列 `EconomySystem.tick()` 再 `TownSystem.tick()`。`binary_reference/relevant_source_paths.txt` 也列前述路徑；實際 `src/*.cpp` 未收錄，只有 `binary_reference/railway_core_15_3.wasm` 與符號／路徑清單，沒有可核對的貸款、補貼、折舊、房租數值或 Swift 可直接呼叫的經營函式。分類：**需轉譯成 Swift的架構提示**；數值和演算法為 **gap**。搜尋 `economy,company,subsidy,loan,depreciation,EXPENSES_,max_loan` 及上述路徑；不得把檔名當成已讀到原始碼。

### Railway/city_world_reference

先讀 `00_READ_ME_FIRST.md`，再查 `source/assets/`。`world-DCb11kLR.js` 的 `pickType`／`floorsFor` 用區域 style、機率與樓層範圍決定建物**外觀**；site metadata 的 `lot`、`claims`、`placement`、`proxy` 是尺寸、保留範圍與渲染資料。例如 `site-donqi-ximen-C4Uhuz6T.js` 內的商品看板有 `{text:"泡麵",price:29}`、`{text:"面膜",price:99,unit:"/10入"}`，`world-DCb11kLR.js` 的 site 選項會讀 `option.price` 並以 `state.addMoney(-price,"site")` 扣互動費。這是**場景商品／互動價格**，不是地標的營業額、房租或收購價，分類為**只是畫面／不同玩法**。site `lot` 如 donqi 24×22 m、`proxy` 高度 18.2 m 可用於 Phase 8 外觀，不能轉成一格容量或價值。搜尋 `price,rent,revenue,income,cost,lot,claims,site,landmark,floorsFor,pickType`；未見每格資產或每日房產收益，為 **gap**。

### Simulator

先讀 `REFERENCE_REFRESH_2026-10-07.md`、`SANITIZATION_REPORT.md`：保留的是模型火車模擬器的軌道、模板、場景與 2D／3D 程式。`reference_snapshot/_next/static/chunks/4193-d08071182eb33d9c.js` 的 Tomix 零件有 `{id:"S18.5",kind:"straight",length:18.5,priceNTD:32}`、`S140` 長 140、`priceNTD:51`、`S280` 長 280、`priceNTD:64`。`app/page-45ab3e3298c392f9.js` 以 `priceNTD` 或按 `kind/radius/length` 的備用價算 `unitPrice`、`subtotal=unitPrice×count`；`app/simulator/page-38607521e5e99afd.js` 用 `priceNTD×missingCount` 算缺件估價。這是**模型零件的新台幣購買清單**，尺度、幣別與實體軌道不同，**不能直接重用為 ConstructionCosts**；清單乘數格式可借鑑，但 Phase 7 房價仍是 gap。搜尋 `priceNTD,costNTD,landValue,zoning,residential,population,catchment,rent,depreciation,tax`。

### Railway/SWIFT_GIS_GAME_REFERENCE_STUDY.md

本文只列 GISTools、MVTTools、SwiftGodot 等 GIS／匯入／呈現的研究順序，沒有房地產、貸款、折舊或公司收入公式。Phase 7 只需記得匯入資料經確定的整數世界模型，renderer 不能寫帳；分類為**只是架構研究**。搜尋 `economy,company,asset,rent,tax,price,valuation` 無 Phase 7 數值規則。

## 3. 設計提案（以下新規則皆原生／gap）

### 3.1 所有權、種類與格佔用

**原生（gap）建議**：先做五種公司的房地產用途：出租住宅、商辦、商場、旅館、遊樂設施。前 3 種分別映射 6c 的住宅／辦公／商業容量表；旅館、遊樂設施第一版先映射商業用途與就業容量，但營收類別不同，具體旅客夜數／門票需求待作者定案。每棟先佔一個 64 m 格，一格最多一棟有容量的建物，**公司建物與城市建物不能同格並存**。買既有建物是將同一棟的所有權由城市轉成公司、保留格、用途、密度、居民及就業，不增加容量；城市停止替公司免費升級。公司在空格建造後才供應容量；當日不憑空生人口或運量，日後只由既有 `LandDemand` 成長與擴張入住。公司格的容量計入 `buildingCapacity`，增加的居民／就業由既有土地需求推導旅次；旅館與遊樂設施**不另加即時旅次**，否則會重複計數。公司買下空地時只是所有權，不是房屋，人口／容量皆為零；城市 `spread` 不應偷偷在公司空地免費蓋樓，待公司自建後才可入住。這要求擴充 6c「有人格恰一棟」的不變量與 `spread` 的候選處理，不能在 UI 另存第二份所有權。

### 3.2 取得與整數報價

**原生（gap）公式**，既有 6c 地價只是報價輸入，不是參考庫的交易規則。先算格在世界內的實際面積：`widthUnits=min(4096,bounds.width−column×4096)`、`heightUnits` 同理，`areaM2=floor(widthUnits×heightUnits/4096)`；為避免不足 1 m² 的邊格免費取得，合法格且面積正數時至少 1 m²。完整格 4096 m²，與 6c 邊格「按整格給容量」不同；作者須決定是否接受此差異。`L=landValue.value × areaM2` 美分，當下即時計算。建物成本 `B=1536 × floors(density) × 4000` 美分（即每 m² 樓板 $40，**原生／gap**，不是 Simulator 模型零件價）；旅館／遊樂設施若先共用商業 D1–D4，`B` 也先相同。買空地付 `L`；在已擁有空地上建付 `B`；一步在未持有的空地蓋則原子付 `L+B`；向城市買現有建物付 `L+B`（以成本而非市場價估建物，**原生／gap**）。所有報價均在指令驗證時重新計，餘額不足不改任何欄位；成交當下把 `landBasis=L`、`buildingBasis=B`、`acquisitionDay` 存檔。只有買空地不設 `buildingBasis`。禁止以畫面快取價成交。既有存檔與自由模式如何開放交易見 §6。

### 3.3 日收入、費用與帳本

**原生（gap）公式**，先針對可租用的住宅／商辦／商場；旅館、遊樂設施第一版若沒有入住／運量契約，建議只允許建模及持有，營業收入暫為零，待作者決定需求來源。設該格當前居民 `R`、就業 `J`（不超過 `Land.maximumPerCell`）；`S` 為當前 `LandValue` 選中站的服務分（0…1000），`V` 為當前美分／m² 地價（500…50000）。已入住才收費：

```
baseCents = R × 1000 + J × 1500
grossCents = floor(baseCents × (1000 + floor(S/2)) × V / 10000000)
maintenanceCents = ceil(buildingBasis × 2 / 10000)
propertyTaxCents = floor((landBasis + 5000) / 10000)
netCashCents = grossCents − maintenanceCents − propertyTaxCents
```

每居民 $10、每就業 $15 的日基價、服務係數、地價係數、建物每日 2 基點維護與土地每日 1 基點稅，**全部原生（gap）**；這是遊戲美元的日租／營收代理值，不宣稱是真實台灣稅法。`S`、`V` 只由核心即時推導；若作者不希望稅，移除稅率與類別即可。用**一天一列** `dailyProperty`，分項 `propertyRevenue` 正、`propertyMaintenance`／`propertyTax` 負，列額就是三項整數和；日帳分開歸收入、營業費與稅，既有 `operatingProfit`／`netProfit` 的定義要一併擴充。不要再把淨額以另一列當收入。沒有應收帳款或空置率的額外隨機性。

**時點**：建議在午夜 00:00 的 `growTowns` **之前**，先為剛結束的一日，以未成長的 `R/J` 及當時可見的上一筆 `S/V` 結算物業；其餘既有 `settleAccounts` 順序維持原樣。這是新一步，不移動 G1c 的小時、能源、人事、貸款結算。`lastPropertySettledDay`（存檔）保證一日最多一次，買入當日的收益從次一個完整日算起，賣出當日不再收該日租金；若要按持有小時比例，另訂規則而非暗中補帳。此定義刻意有最多一天的車站服務量測延遲，且日內地價不回頭改已結算的帳；一日相同狀態只有一個價。若批量推進經閒置跳步跨午夜，必須在其醒來處執行同一步。

### 3.4 出售、損益及資產負債表

**原生（gap）出售價**：`saleCash = floor(currentLandValue×areaM2×950/1000) + max(0,buildingBasis−accumulatedDepreciation)`；5% 土地交易折讓是遊戲平衡值，不是來源稅。出售後清除所有權及成本基礎，格回城市控制，原居民／就業不搬走，城市建物按當時人數初始化為最低容納主用途的密度。`bookValue=landBasis+buildingBasis−accumulatedDepreciation`，`realizedGain=saleCash−bookValue`；虧損可為負。資本利得／損失**只計入損益一次**，出售收到的全部現金只計入投資現金流一次。

目前 `LedgerEntry.amount` 同時是現金變化，`breakdown` 加總也必須等於它；不能將 `saleCash` 及負的 `bookValue` 放進同一列而同時聲稱列額是現金。建議 7a 增 `CapitalEvent {kind,day,cashDelta,assetDelta,liabilityDelta,profitDelta,referenceID}` 及分項，讓**各現金列分項加總＝cashDelta、各損益列分項加總＝profitDelta**；`DayAccount` 分別累計。出售現金列只有 `propertySaleProceeds=+saleCash`；同筆事件的損益欄是 `realizedGain`，附清除的 `bookValue` 作可驗證依據。購置現金列 `propertyPurchase=−price`、資產增 `+price`，本期損益為零；貸款本金亦只動現金與負債。資產負債表列：現金、鐵路設施（軌道／車站）、車輛、土地、公司建物成本、各類累計折舊、貸款本金與權益；`資產＝負債＋權益`，期初權益與其後淨利／資本事件都須可重算。`FinanceSummary` 新增物業營收、維護、稅、折舊、已實現損益及投資現金流，保留既有利息獨立於營業成本。

**原生（gap）折舊**：土地不折舊；建物直線 30×360＝10800 日、車站／軌道 20×360＝7200 日、列車及加購車廂 10×360＝3600 日，殘值零。每天以 `cumulative(day)=min(costBasis,floor(costBasis×min(daysHeld,lifeDays)/lifeDays))`，本日費用＝今天累計−上次累計，避免每日四捨五入吞掉尾數；不動現金。帳面價值不得跟著 6c 即時地價跳動；可另顯示「目前估值」但不入帳。新建軌道、車站、購車與加車廂開始記逐資產成本；移除軌道等無退款指令要沖銷尚未折完的帳面額；若軌道邊切分或合併，基礎按整數里程與最大餘數法分派，合計不變。**舊存檔的既有鐵路資產原始購入價已無從證實**：遷移時採成本基礎零、把「目前重建價」僅作非帳面參考，並在報表註明「舊資產成本未記錄」。不要用目前 `ConstructionCosts` 反推歷史成本。每筆需保存穩定資產 ID、`costBasis`、`acquiredDay`、`accumulatedDepreciation`／`lastDepreciatedDay`；房產另外保存 `landBasis`、`buildingBasis`、`ownedCells`、用途／密度、所有權與最近物業結算日。成本基礎是**成交價歷史**，正是 6c 不保存地價歷史以外的新業務資料；僅憑即時地價不能還原已付價、出售損益或折舊。`DayAccount` 只留 720 天，因此還需保存累計留存盈餘／期初權益，不能拿最近兩年的報表倒算全生命週期權益。欄位精確形狀由存檔負責者定案。

### 3.5 配額、城市回饋、決定性與上限

**建議維持現金經濟（原生決策）**。參考的配額能控制里程／站／車廂的總量，`Ci` 有備用購買價及投資現金流類別，但正式 `getPurchaseCatalog`、補貼和額度消耗引擎缺席。若加入配額，鐵路與房產交易要同時檢查現金、配額兩種資源、退額與舊存檔遷移，且「10 km/$100」的備用價不能作當前 $100,000/km 的建設平衡。現金經濟已有 `ConstructionCosts`、貸款與約 8 日首線回本校準；Phase 7 先補資產及房產，日後若有完整配額引擎再另提規則。這一項需作者明確決定，見 §6。

**城市回饋（原生／gap）**：公司建物只透過既有 `Building.capacity` 供給容量，`LandDemand` 在以後的午夜才把新增人口／就業推成運量；擁有權本身不加服務分、不加地價，旅館與遊樂設施暫不憑空加需求。地價仍只看用途、密度與站的已存服務量測；買入當日不觸發建物自動升級。玩家命令只能在整個一步完成後改狀態，同日不反覆跑「地價 → 建設 → 成長 → 地價」。若未來讓公司設施刺激成長，必須使用**前一個已完成日**的固定量測，午夜只更新一次，再供次日建設報價。

**決定性（原生／gap）**：所有交易先按 `(row,column)`、資產 ID 驗證與報價，成功才一次扣款／改所有權；每日同格、同資產 ID 順序結算，禁用 `Dictionary` 的迭代次序。沒有新亂數需求；未來旅館事件若抽籤只能用世界存檔的 `SeedDraw(seed,purpose,ordinal)`。每次 `advance` 跨午夜的結果要與逐分鐘／逐秒及午夜前後存檔續玩相同；`lastPropertySettledDay` 和折舊累計讓日結冪等。報表需逐日檢查 `每列分項合計＝列額`、`現金變動＝全部現金事件`、`資產＝負債＋權益`。

**乘法界線**：完整格的最大土地報價 `50000×4096=204800000` 美分；本提案 D4 建物 `1536×40×4000=245760000` 美分；合計每格至多 `450560000`，65536 格全買至多 `29527900160000` 美分，低於 `Int64.max`。出租式的最壞合法人數各 100000、`S=1000`、`V=50000` 時，中間乘積 `(100000×1000+100000×1500)×1500×50000=18750000000000000`，也低於 `Int64.max`；單棟 D4 建物的折舊乘積上界 `245760000×10800=2654208000000`。鐵路成本可由存檔自訂，故沒有這個單棟上界，仍須對外來存檔、折舊及累計餘額作 checked multiply/add，必要時用現有的寬整數運算，限制資產數不超合法格／設施數，對超界指令原子拒絕；不要依賴 Swift trap。新遊戲所有價仍在 `Money`；公司餘額沿用既有 `±2^62` 存檔界線。

### 3.6 可手算的平衡場景

此例是**原生（gap）假設場景，不是執行過的遊戲測試**。依現有 App 價：開局 $3,000,000；地面 28 段 16 m 軌道 $44,800、3 站 $600,000、一列 4 節車 $150,000+$120,000，首線共 **$914,800**，蓋完剩 **$2,085,200**。假設此線每日票價扣營運／能源／人事後淨現金 **$114,350**、無貸款，八日共 $914,800 回收首線成本；這個每日淨額只是將約 8 日回本寫成可手算條件，不能宣稱 6c 新局實際輸出固定如此。

第八日之後買一格既有住宅 D2，假定即時 `V=14500` 美分／m²、`S=600`、格內有 168 居民及 36 就業（D2 容量表的例值）。完整格 `L=14500×4096=59392000` 美分＝**$593,920**；`B=1536×6×4000=36864000` 美分＝**$368,640**；成交共 **$962,560**，當日若八日淨現金都已入帳，餘額 `$3,000,000−$962,560=$2,037,440`。次一完整日：`base=168×1000+36×1500=222000` 美分；`gross=floor(222000×1300×14500/10000000)=418470` 美分＝$4,184.70；維護 `ceil(36864000×2/10000)=7373` 美分＝$73.73；稅 `floor((59392000+5000)/10000)=5939` 美分＝$59.39；物業淨額 **405158 美分＝$4,051.58／日**。連同假設的鐵路現金流是 $118,401.58／日。只算物業自己的現金回本，`ceil(96256000/405158)=238` 個完整日；若土地／服務／入住改變，此天數會變。折舊另減會計淨利，不減現金回本。`V=14500`／`S=600` 可由決策 76 的住宅 D2、站距 400 m、`lastService=800`、`lastReached=3` 手算；交易、租金與稅公式本身都是本提案原生值。

## 4. 存檔、golden、replay 與差分模型影響預估

新增有所有權和成本基礎的欄位，舊版讀取器可能丟掉它們，**建議由作者提高 `SavedGame.currentVersion`（目前 14）至 15**，新增一份 v15 `SaveFixtures`，維持所有舊 fixture 可載入；本研究不改版本或 fixture。沒有公司資產的舊局應解為空持有、房產日結游標設為目前日，避免載入後補收過去租金；舊鐵路資產基礎零並明示。解碼驗證同格唯一、所有權與城市建物互斥、成本／累計折舊與 ID 合法、日結游標不超現在、現金／損益／資產恆等，失敗不改世界。新 `GoldenScenarios` schema（目前 39）應由作者升版，增加買空地／城市建物、自建、出售、折舊、日結及資產負債表觀察；既有預期值不得為過關而改。replay 新指令需新增錄製與 checksum 說明；舊 replay 不含房產，應保持相同 digest。`Tests/GameCoreTests/ReferenceWorld.swift` 的差分經濟模型目前只重算既有 G1c，需擴充獨立的房產與資產帳實作，另以手算 Python／golden 驗算分項、賣出損益、邊格、溢位、批量／逐秒／存讀。新報表畫面再由 GamePresentation 與 iOS UI 驗收；本研究沒有執行任何測試。

## 5. 建議 PR 拆分與驗收

| PR | 範圍 | 驗收條件 |
| --- | --- | --- |
| **7a 資產、折舊與帳的契約** | 成本基礎／`CapitalEvent`／資產負債表、每日折舊、建軌／建站／購車及貸款的現金與資產分類，存檔遷移；不提供玩家房產。 | 手算每期損益與現金流、每列分項精確相加、資產恆等；跨 360／720 日及舊檔；不改既有 golden 預期。 |
| **7b 公司建物與每日收支** | 單格所有權、空地／城市建物買入與自建、容量接 6b、租金／維護／可選稅；與午夜順序、存檔驗證。 | 同格唯一、買入不增人口、空地不免費生城市樓、當日不收租、跨日只結一次；批量／逐秒／存讀相同，手算 $4,051.58 例。 |
| **7c 出售、財務畫面與平衡** | 出售與已實現損益、報表／資產負債／投資現金流、Session 與 App 指令及中英文字；平衡場景。 | 出售現金與損益不重複、原子失敗、既有居民保留、238 日例可重算；golden/replay/差分模型與 UI 統一。 |

## 6. 參考對照表草案與作者待決問題

| 參考檔案／函式或資料鍵 | 建議目標檔案／函式 | 定點比例／狀態 |
| --- | --- | --- |
| `Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`／`metroEconomySettleHourlyIfNeeded`、`metroEconomySettleDailyForEndedDay` | 現有 `Sources/GameCore/Economy/Operations.swift`／`settleAccounts`、`settleHour`、`settleDay`，加 `settlePropertyDay` | 美元→美分 ×100；公里→世界單位 ×64000；前者已移植，物業日結原生。 |
| 同檔／`FLOW_DASHBOARD_FINANCE_BUCKETS`、`summarizeFinanceForTransport` 的 `investingCashFlow`／`quota_purchase` | `Sources/GameCore/Economy/Accounts.swift`／`FinancePeriod`、`FinanceSummary`、新 `CapitalEvent`；`RailwayGameApp/Views/EconomyPanel.swift` | 1／7／30／360 日已移植；投資現金流概念需轉譯；房產數值原生。 |
| 同檔／`metroQuotaPurchaseCatalogItems`、`metroQuotaRingItems` | 暫不加入 `ConstructionCosts` 或配額狀態 | 10 km／5 站／6 節的備用價目非現有美分價；不採用配額是待決建議。 |
| `Ci/.../aviation_economy_completed__q_7b75c8d57f0ba33b.js`／`allocate` | 可參考 `CompanyAccounts.record` 的整數餘數分配 | 航空曲線浮點、不能直入 GameCore；房產若不拆分不需此函式。 |
| `Railway/railway_game_reference_clean/01_MIGRATION_MAP.md` §8–§9 | `GameWorld` 的經濟／城市分層、`Sources/GameCore/City/LandDemand.swift` | 只有路徑與架構；所有交易數值 gap。 |
| `Railway/city_world_reference/source/assets/world-DCb11kLR.js`／`floorsFor`、site `lot`／`proxy`，`Railway/site_archive_clean/rail-3d/blender-buildings.js`／`buildingCatalog` | Phase 8 的公司建物外觀資產；核心仍用 `Building.cells` | 公尺→世界單位 ×64；外觀資訊不能當價值／容量。 |
| `Simulator/reference_snapshot/_next/static/chunks/4193-d08071182eb33d9c.js`／`priceNTD` | 不接 `ConstructionCosts` | 新台幣模型零件，不換成遊戲美元／真實鐵路價格。 |
| 本 repo `Sources/GameCore/City/LandValue.swift`／`landValue`、`LandValueRules` | 建議 `Sources/GameCore/Economy/Property.swift` 的 `quotePurchase`／`quoteSale` | 美分／m² × 整數 m²→美分；地價原生既有規則，買賣折讓與建物價仍為 gap。 |
| 本 repo `Sources/GameCore/City/Building.swift`／`capacity(on:)`、`Sources/GameCore/City/LandDemand.swift`／`growLand` | 建議 `Sources/GameCore/City/CompanyBuilding.swift` 與原有 `buildingCapacity`／`spread` | 一格 4096 單位、容量整數人；所有權、日租、稅與折舊原生。 |

待作者在實作前決定（每題附建議）：

1. **要採配額嗎？** 建議**維持現金經濟**：引擎與正式配額價缺席，現有建造費／貸款已可平衡；配額可另開設計。
2. **公司是否可買城市現有建物、是否可與城市樓同格？** 建議可買，但只有一棟建物、所有權原子轉移；避免重複容量與運量。
3. **旅館／遊樂設施何時開放收入？** 建議先保留類型與外觀，收入待有獨立住客／訪客需求時才開；不能無條件生運量。
4. **邊格價格按實際面積，容量仍按整格嗎？** 建議價格裁切、容量暫守 6c 契約，並在購買面板說明；若不接受，需一併改 6c 容量和舊存檔。
5. **物業稅採每日 1 基點嗎？** 建議採為**原生遊戲平衡費**，不稱真實稅率；若希望簡化，可在 7b 前刪除此項。
6. **出售應保留居民與建物嗎？** 建議保留居民／就業、由城市接回同格建物，避免賣出瞬間毀掉人口與既有旅次。
7. **舊存檔的鐵路帳面價值如何建立？** 建議零歷史成本、另列即時重建價，避免以新價假冒舊成交價；新局逐資產記實價。
8. **先做哪個報表？** 建議 7a 同時有損益、投資現金流與資產負債表的資料契約；7c 再上畫面，因出售時三者必須一致。

未檢查到的部分：缺席的 `MetroEconomy` 引擎原始碼、OpenTTD `src/*.cpp`、43 個未收錄的台北 site 模組、真實台灣房價／法定稅資料及 iOS 執行結果。本文只作靜態檔案盤點與算式提案，沒有程式變更，沒有宣稱測試通過。
