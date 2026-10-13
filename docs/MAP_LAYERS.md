# 地圖圖層順序

2026-10-13 寫（美術線，決策 205）。地圖上每一層畫在哪一層上面。**新加一種疊層時，先決定它在這張表的哪一列，再寫程式**，並把這張表一起改掉。

表由下往上：號碼越大畫得越上面。「在哪裡畫」是 `RailwayGameApp/Views/` 裡的檔案與函式。

## 1. 底圖（`MapView` 的 `.background`）

只有實景地圖才有。

| # | 層 | 在哪裡畫 |
| --- | --- | --- |
| 1 | Apple 地圖或 OSM 底圖（決策 97、151） | `AppleMapBackground`、`OSMMapBackground` |
| 2 | 用途圖層打開時，把 Apple 地圖洗淡（60% 系統底色） | `MapView` 的 `.background` 裡的 `.overlay` |

## 2. 地圖本身（`MapView` 的 `ZStack`，由下往上四個 Canvas）

| # | 層 | 在哪裡畫 | 備註 |
| --- | --- | --- | --- |
| 10 | 地面（`Palette.land`；實景地圖不畫） | `MapArt.drawBase` | `MapBaseCanvas`：鏡頭或圖層變了才重畫 |
| 11 | 城市的建物、夜裡的窗（決策 126、182） | `drawSkyline` | |
| 12 | 人口、旅次、城市、地形圖層之一 | `drawPopulation`／`drawTravel`／`drawCity`／`drawTerrain` | 同時只有一種 |
| 20 | 世界邊界外的陰影、邊界線、還沒買的地（決策 123、160） | `MapArt.drawMap` 開頭、`drawMapExpansion` | `MapCanvas` 從這裡開始 |
| 21 | 車站的服務範圍圈 | `drawCatchmentRings` | 圖層開關 |
| 22 | 路堤、路塹的坡面 | `drawSlopes` | |
| 23 | 軌道（道床、中心線、高架、隧道） | `drawNetwork` → `drawEdge` | |
| 24 | 路線的色帶（或區間流量，兩者擇一） | `drawLines`／`drawSectionFlow` | |
| 25 | 轉乘群組的連線 | `drawTransfers` | |
| 26 | 進路預覽（決策 201） | `drawRoutePreview` | |
| 27 | 列車的行車許可（交通管制） | `drawAuthorities` | |
| 28 | 建造工具：城市建物的位置、玩家的建物、建物的預覽 | `drawCityBuildingSites`、`drawPlacedBuildings`、`drawBuildingOverlay` | |
| 29 | 夜裡車站的燈 | `drawStationLights` | |
| 30 | 車站（徽章、高鐵的第二圈、選取圈、站名、候車人數） | `drawPointStation` | 一站一站畫完，所以後面的站會蓋住前面站的站名 |
| 31 | 拉遠時的站名（帶底牌） | `drawOverviewNames` | |
| 32 | 鋪軌的預覽線、錨點 | `drawNetworkOverlay` | |
| 33 | 軌段編號（決策 201） | `drawTrackNumbers` | |
| 34 | 等待列車與擋住它的那段軌道、虛線 | `drawWaits` | |
| 40 | 時間的色調（multiply，決策 182） | `MapView` 的 `Palette.tint` | 只蓋到上面這些，蓋不到列車 |
| 50 | 列車（車身、車頭、夜燈） | `MapArt.drawTrains` → `drawTrain` | `MapTrainCanvas`：每一幀重畫 |
| 51 | 等待環、死結的警告 | `drawWaitMarks` | |
| 60 | 天氣：壓暗、雨、閃電、颱風標記 | `MapWeatherLayer` → `drawWeather` | |
| 61 | 鋪軌的放大鏡：同一個 `MapCanvas` 換成 3 倍近的相機，拖曳鋪軌時在一角（#522，一鍵雙線工具） | `MapView` 的 ZStack | 照這張表的 20–34 畫，配色跟著 `MapArt` |

## 3. SwiftUI 的疊層（`MapView` 的 `.overlay`，由下往上）

這些是 View，不是 Canvas 裡畫的，所以一定在第 2 節所有東西上面。

| # | 層 | 在哪裡畫 |
| --- | --- | --- |
| 70 | 手勢（不畫東西） | `MapGestures` |
| 71 | 建造時淡淡的景點 | `MapAttractionMarks(isPassive: true)` |
| 72 | 建造的旗子、取消與確定 | `MapBuildConfirm` |
| 73 | 狀態泡泡（擁擠、客滿、死結，決策 109） | `MapAlertBubbles` |
| 74 | 景點的星星（決策 174） | `MapAttractionMarks` |
| 75 | 選取的車站的名牌（決策 119） | `MapStationTagView` |
| 76 | 剛蓋好的閃一下（決策 117） | `BuildPulseMark` |
| 77 | 圖層的提示框（人口、城市、區間流量、地形） | `MapView` 的 tooltip |
| 80 | 圖例、縮放、圖層按鈕、HUD、面板 | `MapView` 其他 overlay、`ContentView` |

## 規則

- **標記不只靠顏色**（決策 205）：路線色是玩家選的，任何顏色都可能和某條路線一樣。畫在路線附近的標記（候車人數、等待、選取）要用路線不會有的形狀或外框分出來：藏青外框、白底、圖示。
- **字在底牌上**：地圖上的字（站名、候車人數）都放在底牌上，底牌是地面色或面板色加藏青外框，字對底牌至少 4.5:1（`docs/UI_THEME.md`）。
- **玩家的東西在城市的東西上面**：玩家的建物（28）、車站（30）、列車（50）都在城市的建物（11）上面。
- **會動的在不動的上面**：列車與等待環在自己的 Canvas（50–51），色調（40）蓋不到它們，所以夜裡也看得清楚。
- **一次一個東西被選取**：選取圈畫在那個東西自己的那一層，不另開一層。
- 新的疊層若會一直變（每一幀），放進 `MapTrainCanvas`；只隨鏡頭變的放 `MapBaseCanvas`；其他放 `MapCanvas`。
