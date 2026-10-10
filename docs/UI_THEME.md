# 介面配色（Theme）

2026-10-07 定。App 的介面改成和 App 圖示同一套風格：扁平、圓角，四個主色取自圖示。地圖以外的畫面都用 `RailwayGameApp/Views/Theme.swift`；地圖和路線的顏色留在 `Palette.swift`，理由和預定時機見下方「刻意保留」。

PR：#187（配色與 HUD）、#190／#192（地圖為主的玻璃版面）、#194–#196 與 #197（逐一替換）、地圖畫風（決策 84）。

## 取色

從圖示 PNG 統計像素，和圖示的 SVG 原稿一致：

| 圖示元素 | Light 圖示 | Dark 圖示 |
| --- | --- | --- |
| 底色 | `#ECEEF6` | `#262C57` |
| 綠松色軌道 | `#12A08F` | `#45D3C0` |
| 軌道中心描邊 | `#BDEFE7` | `#D4FAF4` |
| 建物 | `#262C57` | `#ECEEF6` |
| 燈光／車站 | `#FFC86B` | `#FFC86B` |

## Theme 色票

對比度用 WCAG 2 公式計算。文字色同時對 `background` 和 `panel` 檢查，表中列較差的值。

| 名稱 | Light | Dark | 用途 | 對比 Light／Dark |
| --- | --- | --- | --- | --- |
| `primary`（= `AccentColor`，全域 tint） | `#0D766A` | `#45D3C0` | 控制項、圖示、選取 | 4.75／6.03 |
| `onPrimary` | `#FFFFFF` | `#262C57` | `primary` 上的字 | 5.50／7.17 |
| `accent` | `#FFC86B` | `#FFC86B` | 暖黃：圖示底、徽章、教學外框；不當文字 | — |
| `onAccent` | `#262C57` | `#262C57` | `accent` 上的字 | 8.69 |
| `background` | `#ECEEF6` | `#262C57` | 畫面底色 | — |
| `panel` | `#FFFFFF` | `#30376A` | 卡片、面板 | — |
| `panelBorder` | `#262C57` 14% | `#ECEEF6` 16% | 面板邊線、未選按鈕外框 | — |
| `chip` | `#262C57` 6% | `#ECEEF6` 8% | 小膠囊、圖示底的淡填色 | — |
| `textPrimary` | `#262C57` | `#ECEEF6` | 內文 | 11.47／9.64 |
| `textSecondary` | `#5B6189` | `#B4B9D9` | 次要文字 | 5.16／5.79 |
| `success` | `#1E7334` | `#5FD68A` | 正餘額、完成、準點 | 5.10／6.10 |
| `warning` | `#8A5B0F` | `#FFB454` | 暫停、問題、誤點 | 5.06／6.33 |
| `error` | `#C62828` | `#FF9B9B` | 負餘額、移除、超載 | 4.85／5.54 |
| `onError` | `#FFFFFF` | `#262C57` | `error` 上的字 | 5.62／6.59 |

圖示淺色版的軌道綠松 `#12A08F` 放在淺底上只有 2.81:1，所以 `primary` 沿同一色相壓暗。

## 樣式

| 名稱 | 用途 |
| --- | --- |
| `ThemeSelectableButtonStyle(isActive:)` | 開／關按鈕：開時填 `primary`，關時只有 `panelBorder` 外框。狀態不只靠顏色區分 |
| `ThemeProminentButtonStyle(isDestructive:)` | 主要動作：`primary`，移除類用 `error`；不能按時用 `panelBorder` 底配 `textSecondary` |
| `.themeCard(padding:cornerRadius:)` | 實色 `panel` 卡片，即使放在玻璃上，文字對比也固定 |
| `.glassBackground(in:interactive:)` | 浮在地圖上的元件：iOS 26 用 Liquid Glass，iOS 17–25 用 `.regularMaterial` |

`.borderedProminent` 固定用白字，在 Dark 的 `primary`（1.85:1）和 `error` 上都不到 AA，所以主要動作改用 `ThemeProminentButtonStyle`。`.bordered` 按鈕沿用全域 tint。

## 地區外觀（決策 106）

2026-10-09 作者決定：介面用上面的 `Theme`（各國共用），加上參考庫網站的造型元素（膠囊、實體陰影、站名牌樣式）；一個國家「長得像那裡的鐵道」的顏色另放在 `RegionStyle`（`RailwayGameApp/Views/RegionStyle.swift`），換國家只換它。作者要求不用網站的配色，改用查得到的那個國家的鐵道色。

目前只有台灣：

| 名稱 | Light | Dark | 用途 | 對比 Light／Dark |
| --- | --- | --- | --- | --- |
| `nameboard` | `#1D4F91` | `#8DB6EE` | 站名牌底色：藍皮普快的藍（藍皮解憂號復駛時考證恢復） | — |
| `onNameboard` | `#FFFFFF` | `#162544` | 站名牌上的字 | 8.14／7.28 |

台鐵、高鐵都沒有公開色碼，`nameboard` 是近似值，要在實機上確認；看起來太像網站的藏青（`#2A4A73`）時改用初代莒光號的白底淺藍。查到、但還沒有東西用的台灣鐵道色（用到時再加）：台鐵公司新指標的北上藍、南下綠；鳴日號的黑橘；高鐵的白、橘、黑。

顏色的出處與這一輪改版的研究紀錄見 [`research/UX_REDESIGN_STUDY.md`](research/UX_REDESIGN_STUDY.md)。

### 站長（決策 122）

台灣的站長是提著號誌燈的黃山雀（`RegionStyle.stationMasterArt` = `StationMasterTaiwan`），正面、圓胖，圖在 `Assets.xcassets`，三種表情各一張多色 SVG，淺色、深色共用：

| 顏色 | 用在 |
| --- | --- |
| `#FFC86B` | 臉、身體、燈、領巾上的站徽（App 圖示的黃點） |
| `#262C57` | 外框、頭冠、兩邊翅膀、鳥喙、腳、燈框 |
| `#3D4470` | 鳥喙上的反光 |
| `#FFFFFF` | 眼睛的反光、翅膀的白點 |
| `#6482A3` | 翅膀上波浪形的羽緣（藍灰） |
| `#1D4F91`、`#163D73` | 領巾與垂下的一角（和 `nameboard` 同一個藍皮普快的藍） |
| `#F0A93C` | 燈上的兩條直線 |
| `#FFE9BC` | 燈的光暈；擔心時燈變暗（`#E8D9B0`）、沒有光暈 |
| `#8DB6EE` | 擔心時的汗滴 |
| `#BDEFE7`、`#12A08F`／`#D4FAF4` | 底色與一段軌道（圖示的軌道） |

決策 122 第 6 點。都是插圖裡的色塊，不是文字，不算對比；灰階下黃、藏青、藍灰分得開（art-style 的預覽檢查）。

## 地圖（決策 84）

2026-10-08 作者決定，地圖不等 Phase 8，先改成圖示的畫風（`Palette`），並畫出路線、共線區段與轉乘群組（見 ARCHITECTURE 決策 84）。

| 名稱 | Light | Dark | 用途 | 對比 Light／Dark |
| --- | --- | --- | --- | --- |
| `land` | `#ECEEF6` | `#262C57` | 地面 | — |
| `mapEdge` | `#262C57` 30% | `#ECEEF6` 30% | 世界的邊界 | — |
| `track` | `#10917F` | `#45D3C0` | 軌道道床（圖形，對地面） | 3.37／7.17 |
| `trackCentre` | `#BDEFE7` | `#D4FAF4` | 軌道中間的淺色線 | — |
| `ink` | `#262C57` | `#ECEEF6` | 站名、節點、隧道、車站外框、高架外框 | 11.47／9.64 |
| `station` | `#FFC86B` | `#FFC86B` | 車站、月台（外框用 `ink`） | — |
| `stationSymbol` | `#262C57` | `#262C57` | 車站裡的符號 | 8.69 |
| `train` | `#262C57` | `#ECEEF6` | 列車 | 11.47／9.64（對地面） |
| `transferLink`／`transferEdge` | `#FFFFFF`／`#262C57` | 同左 | 轉乘群組的連線（MapBuilder 的白線黑框） | — |

圖示的淺色軌道 `#12A08F` 對地面只有 2.81:1，不到圖形的 3:1，所以淺色模式壓暗到 `#10917F`。路線用 `Palette.lineColor`（路線面板的顏色）。

## OSM 底圖（決策 151）

實景地圖的 OpenStreetMap 底圖用遊戲自己的樣式（`Sources/GamePresentation/BaseMapStyle.swift` 的 `Colors`）：地面和一般地圖相同，其他是同一個色相、很淡的色塊，讓軌道、車站與城市浮在上面（和 Positron 一樣，底圖的道路、水不要求 3:1，它們是背景）。文字照 4.5:1。

| 名稱 | Light | Dark | 用途 | 對比 Light／Dark |
| --- | --- | --- | --- | --- |
| `land` | `#ECEEF6` | `#262C57` | 地面（= `Palette.land`） | — |
| `water` | `#C3CEEA` | `#1A1F45` | 海、湖、河 | 對地面 1.36／1.19 |
| `wood`／`grass`／`park` | `#D9E7D3`／`#E2EDDB`／`#D2E8C4` | `#2B4458`／`#2D3F60`／`#2F4D52` | 森林、草地、公園 | — |
| `sand`／`wetland` | `#F1EBD8`／`#D6E0EA` | `#3A3B5C`／`#293360` | 沙灘、濕地 | — |
| `road`／`roadMajor`、`casing` | `#FFFFFF`、`#CDD1E4` | `#363D72`／`#424A84`，`#1E2348` | 道路與外框 | — |
| `motorway`、`motorwayCasing` | `#FFE4B0`、`#E2B866` | `#6E6475`、`#1E2348` | 國道與快速道路 | — |
| `boundary` | `#262C57` 35%／18% | `#ECEEF6` 35%／18% | 縣市界、鄉鎮市區界（虛線） | — |
| `text` | `#262C57` | `#ECEEF6` | 城市、鄉鎮、區名 | 11.47／11.47 |
| `textMinor` | `#5B6189` | `#B4B9D9` | 村里、聚落、路名 | 5.16／6.89（對地面） |
| `waterLabel` | `#344C8A` | `#93A7DB` | 河名、島名 | 5.24／6.63（對水） |
| `halo` | `#ECEEF6` | `#262C57` | 文字的外框（= 地面） | — |
| `shadow`／`highlight`／`accent` | `#4A5482`／`#FFFFFF`／`#8D95BA` | `#0D1029`／`#5A63A3`／`#171B3D` | 山的陰影、受光面、谷（`hillshade`，強度 0.42） | — |

## 地圖圖示（決策 121）

2026-10-09 作者決定：地圖上的東西改用自己畫、和 App 圖示同一個畫風的圖示（`Assets.xcassets` 的 `MapGlyph*`，程式用 `MapGlyph`），取代 SF Symbols。介面的按鈕照舊用 SF Symbols。

畫法：24 × 24 的 SVG，只有實心形狀，挖空用 even-odd；筆畫粗、轉角圓，縮到 10 點左右還看得出來。每個都是單色模板，顏色在畫的地方給，所以沒有深淺兩套。

| 圖示 | 用在 | 顏色 | 對比 Light／Dark |
| --- | --- | --- | --- |
| `train` | 車站徽章（`station` 底） | `stationSymbol` | 8.69 |
| `train`、`crowd`、`full` | 狀態泡泡：在 `primary`／`warning`／`error` 的圓上；`crowd`（兩個人）與 `full`（三個人）是同一組擁擠等級 | `Theme.panel` | 最低 5.50／5.54 |
| `warning`（墊 `warningSolid`） | 死結 | `metroRed`，墊系統底色 | — |
| `house`、`shop`、`office`、`wharf`、`marina` | 玩家建物（14 點以上），建築工具的種類按鈕 | 建物上 `buildingGlyph`（#262C57）；按鈕上跟著按鈕的字色 | 建物上最低 3.11／4.72 |
| `train` | 路線示意條的列車（路線色的圓上） | 白 | 跟路線色 |

## 城市的建物（決策 126）

一般地圖上城市自己的建物（`Palette.cityRoof`／`cityWall`，淺色、深色共用）：屋頂淺、外牆深，色相照用途圖層。外框 `cityOutline`（`#262C57`，兩種模式都是）。屋頂對淺色地面只有 1.25–1.46:1，靠外框區分（`#262C57` 對 `#ECEEF6` 11.47:1）；深色地面上屋頂本身就亮（對 `#262C57` 7.86–9.15:1）。

| 用途 | 屋頂 | 外牆 |
| --- | --- | --- |
| 住宅 | `#A8DCA8` | `#63B06F` |
| 商業 | `#A9CBEB` | `#5F95CB` |
| 辦公 | `#F5CD95` | `#D99649` |
| 工業 | `#CFC9E6` | `#9088C2` |
| 學校與公共設施 | `#F6BCAE` | `#DB7C6E` |
| 觀光休閒 | `#AEE0D8` | `#4CA597` |

空地：`parkGround` 公園 `#CDE8B5`／`#3E6B3A`，`farmGround` 農地 `#F1E6C8`／`#5A5236`（淺色／深色）。

## 刻意保留（程式碼裡標「Theme: kept」）

### 永久保留

| 位置 | 保留的 | 理由 |
| --- | --- | --- |
| `Palette.lineColor`、`Palette.color(LineColor)`：LinesPanel 的徽章與色票、FollowBar 的圓點 | 路線色、玩家選的顏色，以及徽章上的白字 | 路線的識別色 |
| RealWorldPicker、AppleMapBackground：RealRailways 的線色與車站色 | 官方線色 | 實景資料 |

### Phase 8（換地圖 renderer）時一起改

地圖本身的畫法已在決策 84 改用圖示畫風（見上）；下列項目仍留到 Phase 8。

| 位置 | 保留的 | 理由 |
| --- | --- | --- |
| `MapView` 的交通圖例（`TrafficLegend`） | `metroGreen`／`metroAmber`／`metroRed` | 要和地圖上交通疊圖的顏色一致 |
| `PopulationLegendView` 的色階與色票 | `PopTravel`、`CityMap` 的顏色 | 要和地圖圖層一致；外框、文字、底已改用 Theme |
| `MapArt` 的選取標示（鋪軌預覽線、錨點、選取外圈） | `Color.accentColor`（已跟著全域 tint 變成綠松色） | 擁有者決定維持綠松色（#187）；Phase 8 再檢討 |

### 沿用系統樣式（目前不改）

- Sheet、`List`、`Form` 的背景與分隔線，以及 `role: .destructive` 按鈕：用系統的深淺色，配合全域 tint。
- 教學外框底下的深色光暈（`Color.black.opacity(0.35)`）：讓暖黃外框在任何底色上都看得到。

## 待確認

- 玻璃上的文字（未選中的工具列、狀態列、跟車列）沒辦法算出固定對比，因為 Liquid Glass 會依背後內容自動調整。要用 CI 截圖和 TestFlight 實機確認。
- 教學卡片的「完成這一步」提示是 `warning` 字放在 12% 的 `warning` 底上，對比會比 5.06:1 略低。
