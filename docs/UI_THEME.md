# 介面配色（Theme）

2026-10-07 定。App 的介面改成和 App 圖示同一套風格：扁平、圓角，四個主色取自圖示。地圖以外的畫面都用 `RailwayGameApp/Views/Theme.swift`；地圖和路線的顏色留在 `Palette.swift`，理由和預定時機見下方「刻意保留」。

PR：#187（配色與 HUD）、#190／#192（地圖為主的玻璃版面）、#194–#196 與本次（逐一替換）。

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

## 刻意保留（程式碼裡標「Theme: kept」）

### 永久保留

| 位置 | 保留的 | 理由 |
| --- | --- | --- |
| `Palette.lineColor`、`Palette.color(LineColor)`：LinesPanel 的徽章與色票、FollowBar 的圓點 | 路線色、玩家選的顏色，以及徽章上的白字 | 路線的識別色 |
| RealWorldPicker、AppleMapBackground：RealRailways 的線色與車站色 | 官方線色 | 實景資料 |

### Phase 8（換地圖 renderer）時一起改

| 位置 | 保留的 | 理由 |
| --- | --- | --- |
| `MapArt.swift`、`MapView.swift` 的地圖畫法 | 軌道、建物、圖層、列車、車站、土地等 `Palette` 色 | 地圖畫法由 Phase 8 重做 |
| `MapView` 的交通圖例（`TrafficLegend`） | `metroGreen`／`metroAmber`／`metroRed` | 要和地圖上交通疊圖的顏色一致 |
| `PopulationLegendView` 的色階與色票 | `PopTravel`、`CityMap` 的顏色 | 要和地圖圖層一致；外框、文字、底已改用 Theme |
| `RealWorldPicker` 的 16 公里方框與中心十字 | `Palette.station` | 預覽要和遊戲地圖的車站色一致 |
| `MapArt` 的選取標示（鋪軌預覽線、錨點、選取外圈） | `Color.accentColor`（已跟著全域 tint 變成綠松色） | 擁有者決定維持綠松色（#187）；Phase 8 再檢討 |

### 沿用系統樣式（目前不改）

- Sheet、`List`、`Form` 的背景與分隔線，以及 `role: .destructive` 按鈕：用系統的深淺色，配合全域 tint。
- 教學外框底下的深色光暈（`Color.black.opacity(0.35)`）：讓暖黃外框在任何底色上都看得到。

## 待確認

- 玻璃上的文字（未選中的工具列、狀態列、跟車列）沒辦法算出固定對比，因為 Liquid Glass 會依背後內容自動調整。要用 CI 截圖和 TestFlight 實機確認。
- 教學卡片的「完成這一步」提示是 `warning` 字放在 12% 的 `warning` 底上，對比會比 5.06:1 略低。
