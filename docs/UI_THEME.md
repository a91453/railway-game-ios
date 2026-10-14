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

空狀態與建造卡的插圖（`EmptyLines`、`EmptySaves`、`EmptyTrains`；`Building*`，決策 122 之後的修正）用同一組顏色：外框藏青 `#262C57`、白 `#FFFFFF`、`#ECEEF6`、暖黃 `#FFC86B`、綠松 `#12A08F`，墊 `#BDEFE7` 的圓（建造卡是圓角方塊）。

決策 122 第 6 點。都是插圖裡的色塊，不是文字，不算對比；灰階下黃、藏青、藍灰分得開（art-style 的預覽檢查）。

## 地圖（決策 84）

地圖上每一層畫在哪一層上面：[`MAP_LAYERS.md`](MAP_LAYERS.md)（決策 205）。拉近時的站名和拉遠時一樣墊 `land` 80% 的底牌。

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
| `playerBuilding` | `#FFC86B` | `#FFC86B` | 玩家蓋的建物，八種都是（= `station`，外框用 `ink`，種類看圖示；2026-10-13 作者決定玩家的東西一律暖黃，城鎮的顏色不變） | — |
| `train` | `#262C57` | `#ECEEF6` | 列車 | 11.47／9.64（對地面） |
| `transferLink`／`transferEdge` | `#FFFFFF`／`#262C57` | 同左 | 轉乘群組的連線（MapBuilder 的白線黑框） | — |
| `markerFill` | `#FFFFFF` | `#30376A` | 路線附近的標記的底：候車人數膠囊、等待環的光暈、被擋住那段軌道的白邊（= `Theme.panel`；決策 205） | 上面的 `ink` 13.29／9.64 |
| `trainSelection` | `#FFC86B` | `#FFC86B` | 選取的列車外圈，外面再一圈 `ink`（= `station`；決策 205，以前是 `accentColor`，和軌道同為綠松） | — |

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
| `person`、`crowd`、`full` | 候車人數膠囊（決策 205）：一人是一般；決策 210 起擁擠（過半）換兩人、滿了換三人，同一組擁擠等級 | `ink`，墊 `markerFill` | 13.29／9.64 |
| `train`、`crowd`、`full` | 狀態泡泡：在 `primary`／`warning`／`error` 的圓上；`crowd`（兩個人）與 `full`（三個人）是同一組擁擠等級 | `Theme.panel` | 最低 5.50／5.54 |
| `warning`（墊 `warningSolid`） | 死結 | `metroRed`，墊系統底色 | — |
| `house`、`shop`、`office`、`wharf`、`marina`、`departmentStore`、`hotel`、`amusementPark` | 玩家建物（14 點以上；小一點的建物在 16 m ≥ 6 點時畫成 14 點的徽章，決策 205），建築工具的種類按鈕 | 建物上 `buildingGlyph`（#262C57）；按鈕上跟著按鈕的字色 | 建物上 8.69（對 `playerBuilding`） |
| `train` | 路線示意條的列車（路線色的圓上） | 白 | 跟路線色 |
| `typhoon` | 颱風經過的車站（決策 182）：`land` 圓、`ink` 外框，圖示 `ink` | `ink` | 11.47／9.64 |

### 看得見問題的標記（決策 210）

都照決策 205：不用路線色，用形狀與藏青／白區分；只有「滿」與「死結」用 `metroRed`，而且各有自己的形狀（整圈、實線圈加警告）。

| 標記 | 畫法 | 對比 Light／Dark |
| --- | --- | --- |
| 擁擠站的量表環 | 5 點 `markerFill` 光暈、0.8 點 `ink` 35% 的底圈，從正上方順時針一段 3 點 `ink` 弧，長度＝候車人數／站的容量（過半才畫） | `ink` 對 `markerFill` 13.29／9.64 |
| 滿站的環 | 同上的光暈，整圈 3 點 `metroRed` | 4.48／3.54（圖形 3:1） |
| 等待環的擴散 | 遊戲在跑時每 1.6 秒從環往外 9 點、1.5 點 `ink`，透明度 70% 漸到 0；暫停或「減少動態效果」不畫 | — |
| 為何在等的小牌 | `markerFill` 底、1.2 點 `ink` 外框（死結 `metroRed`）、圓角 3，字 `caption2` 半粗 `ink` | 字 13.29／9.64 |
| 擁擠泡泡的第二行原因 | `caption2`、`Theme.textSecondary`，墊 `Theme.panel` | 5.97／5.79 |

### 機廠（2026-10-13 作者選定，決策 209 的畫面）

機廠在 GameCore 是車站旗標（`Station.isDepot`，決策 209）。圖示三張，都是 24 格的單色模板，選定前給作者看過四個機廠、三種出入庫標記、三種在庫徽章（還有 #553 的另一組與兩份的組合版），作者先選 A、甲、一，再改成「A＋組合版的出入庫＋一」：車庫照 A 的山形屋頂、拱形門，線條加粗；出入庫照組合版的粗箭頭，裡面的小車庫換成同一種山形屋頂，三處是同一棟車庫。決策 214 接上程式（`MapArt.drawPointStation`、`drawDepotPlate`，App 的 `DepotBadge`）；顏色只用下表既有的色票。

| 圖示 | 用在 | 畫法 | 對比 Light／Dark |
| --- | --- | --- | --- |
| `MapGlyphDepot`（山形屋頂、兩個拱形門通到地面；牆 3 格、中柱 4 格） | 地圖上的機廠（圖層 30） | 徽章是**拱門形**（上半圓、下半方、下角圓 0.28 r），`station` 底、1.5 點 `ink` 外框（拉遠 1.2 點），大小和車站一樣；圖示 `stationSymbol`，徽章的 1.1 倍、往下挪 0.06 r。拱門和車站的圓、玩家建物的圓角方塊都不一樣，不加高鐵的第二圈 | 8.69（對 `station`） |
| `MapGlyphDepotOut`（山形小車庫在左、粗箭頭往右）、`MapGlyphDepotIn`（箭頭在左、車庫在右） | 出庫中、入庫中的列車（圖層 51） | 車頭上方一塊圓角 3 的小方牌，**`ink` 底**、1.5 點 `markerFill` 外框，圖示用 `markerFill`；不帶字。地圖上其他標記都是白底藏青框，這個反過來；出庫與入庫靠車庫在左或在右分，13 點、3 倍螢幕、模糊後相差約 45%（擁擠與客滿是 29%）。小車庫只有一個門，尖屋頂加一個門和建物的房子圖示相近，實機要看會不會被讀成「回家」 | 13.29／9.64（`markerFill` 對 `ink`） |
| `MapGlyphDepot` | 車隊清單、路線面板的「在庫」；出庫中、入庫中配 `MapGlyphDepotOut`／`In` | 淡色膠囊：`Theme.chip` 底、圖示與字 `Theme.textSecondary`，字寫「在庫」「出庫中」「入庫中」。隱形車庫（買了沒放上軌道）的車也是在庫 | 字 5.16／5.79 |

停車線照一般軌道畫（`track`、`trackCentre`），不另做圖。參考庫沒有 2D 的機廠圖示；彰化扇形車庫、羅東林場檢車庫的 3D 模型留給 3D（`docs/RAILWAY_REFERENCE_MAPPING.md`）。

## 晝夜與天氣（決策 182）

列車照路線上色（`Palette.trainColor`）：路線的列車是路線色（`Palette.lineColor`），貨運線的是灰色，不在路線上的照舊 `train`；載客量圖層打開時全部用 `train`。車身先畫一圈 `ink`（寬 2 pt），再畫顏色，所以畫在自己路線的同色線上也看得出來。決策 205 起，拉近時一節一節畫（每節 20 m，節與節之間一道藏青接縫，車鼻就是車頭），外框都是 `ink`，選取時外面一圈 `trainSelection` 再一圈 `ink`；拉遠時的車頭圓點外框也改成 `ink`（以前是系統底色，選取時 accent）。

| 名稱 | Light | Dark | 用途 | 對比 Light／Dark |
| --- | --- | --- | --- | --- |
| `freightTrain` | `#666C80` | `#A4AABD` | 貨運線的列車 | 4.51／5.74（對地面） |
| `rain` | `#4A5A80` 45% | `#C9D3EA` 45% | 雨絲（裝飾，不要求對比） | — |
| `weatherShade` | `#10142E` | `#05071A` | 下雨、雷雨、颱風時壓暗地圖（6–30%） | — |
| `lightning` | `#FFFFFF` | `#FFFFFF` | 閃電（35% 以下，一次約 0.3 秒，九秒一次） | — |

時間的色調（`DayNight`，GamePresentation，地圖用 multiply 疊在底圖、城市、軌道與車站上；列車、光暈與天氣在它上面）：

| 時段 | 顏色 | 強度 |
| --- | --- | --- |
| 19:00–05:00 夜間 | `#0E1640` | 25% |
| 05:30 黎明（05:00 起由夜轉暖，06:30 退完） | `#FF9F55` | 15% |
| 06:30–17:30 白天 | — | 0 |
| 18:15 黃昏（17:30 起，19:00 轉成夜間的藍） | `#F07A3C` | 25% |

夜間最多 25%：multiply 讓地面與軌道一起變暗，對比會降低。淺色地圖上軌道對地面 25% 時是 3.01:1（沒有色調時 3.37），40% 時只剩 2.70，不到圖形的 3:1；站名（`ink`）25% 時 7.74:1。深色地圖 25% 時軌道 5.00、站名 7.74。黎明與黃昏的暖色對軌道幾乎沒有影響（3.38）。

夜間的燈（`DayNight.lights`，05:00–06:15 熄、17:30–18:45 亮，smoothstep）：車站底下一圈 `station`（35%）、列車車頭兩圈 `station`（18%、30%）、城市建物三棟裡兩棟有一格窗（`station`）。實景地圖（OSM／Apple）上色調不能和底圖做 multiply（地圖畫在遮罩的群組裡，底圖在群組外），所以是一般的半透明疊色。

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
| `MapView` 的交通圖例（`TrafficLegend`） | `metroGreen`／`metroRed`（「等候」決策 205 起是藏青虛線圈，和地圖上的等待環一樣） | 要和地圖上交通疊圖的顏色一致 |
| `PopulationLegendView` 的色階與色票 | `PopTravel`、`CityMap` 的顏色 | 要和地圖圖層一致；外框、文字、底已改用 Theme |
| `MapArt` 的選取標示（鋪軌預覽線、錨點、選取外圈） | `Color.accentColor`（已跟著全域 tint 變成綠松色） | 擁有者決定維持綠松色（#187）；Phase 8 再檢討 |

### 沿用系統樣式（目前不改）

- Sheet、`List`、`Form` 的背景與分隔線，以及 `role: .destructive` 按鈕：用系統的深淺色，配合全域 tint。
- 教學外框底下的深色光暈（`Color.black.opacity(0.35)`）：讓暖黃外框在任何底色上都看得到。

## 待確認

- 玻璃上的文字（未選中的工具列、狀態列、跟車列）沒辦法算出固定對比，因為 Liquid Glass 會依背後內容自動調整。要用 CI 截圖和 TestFlight 實機確認。
- 教學卡片的「完成這一步」提示是 `warning` 字放在 12% 的 `warning` 底上，對比會比 5.06:1 略低。
