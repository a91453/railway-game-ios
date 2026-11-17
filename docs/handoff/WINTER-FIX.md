# WINTER-FIX：冬季活動 12/1 前的修正與任務內容

- 派工單：WINTER-FIX（遊戲規劃派，2026-11-17）；session_01JMHz9b5eDTLf6YgDPzKWVr；分支 `claude/winter-fix`。
- 決策 814。存檔、golden、GameCore、SaveFixtures、ReplayFixtures：都不動。
- 做了什麼（細節在 [`decisions/814.md`](../decisions/814.md)）：
  - 第 5 週算進 00:00 開始營運的路線（L23 P3-1）。
  - 沒手動存過的新局，第一次選聖誕塗裝就取存檔列，重開 App 塗裝還在（L25 P3-1）。
  - 第 2 週改成連到板橋／尖沙咀（其他地圖是市中心）、17–22 時開出 6 班。
  - 三個數字用 `WinterMissionReportTests` 量過，保留 3、6、1,000。
  - 五枚徽章圖（方案 B 冬夜）取代 SF Symbols。

## 還留下的

1. **羅瓦涅米地圖包開關關著也隨 App 帶（L24 P3-3，約 13 MB）：沒改**，因為羅瓦涅米目標 11/30 開放，現在移出、開放時又得改回來。若開放延到 12 月以後再做：
   - `RailwayGameApp/project.yml` 的 `Resources/MapPacks` 是整個資料夾參照（`type: folder`）。改成兩個資料夾參照 `Resources/MapPacks/hongkong`（目的地仍是 `MapPacks/hongkong`，`MapPack.bundled` 照路徑找），羅瓦涅米不列。
   - 依 CLAUDE.md 用 XcodeGen 2.46.0 重產專案並一起提交。
   - 開放那張單把它加回來，或照決策 776 加 `RailwayGameApp/AssetPacks/rovaniemi.json` 改成下載。
   - Linux 的 `RovaniemiRailwaysTests` 直接讀 repo 裡的檔，不受影響。
   - L24 說的另一半（3D 地圖把沒開的城市的圖磚也對映進來）已經不在了：`BaseMapFiles.cityTiles` 現在只列 `OverseasMaps.open` 的城市。
2. **徽章總覽圖要遊戲規劃看過才合**：`docs/art/winter-badges-2026-11-17/overview.jpg`（A、B、C 三種，選 B）。
3. 開新局時，上一局沒手動存過的自動存檔被收成新名字的存檔（決策 502），它的塗裝記在原來的列，不跟著改名。修之前同樣不見，影響小，沒有評分。
4. 羅瓦涅米版的第 3 週「連到聖誕老人村」（企劃 §2.4）沒做；第 3 週的 1,000 人在羅瓦涅米沒量（NOT ASSESSED）。
5. 第 3 週 1,000 人太容易（第一條線第 1 天就 4 倍，CONCERNS）。要調高就照決策 814 §3 的表再量一次。

## UNVERIFIED

- 活動卡上的徽章（28／32 pt、灰階、深淺色）沒在模擬器或實機看過：活動卡只在 12/1–1/6 出現，要把裝置日期調到 12 月；網站截圖跑不到這張卡。
- Asset Catalog 吃不吃得下這五張 SVG：交 CI 的 iOS 建置與 Release Archive。用到的元素、屬性都是 Catalog 裡已有的圖用過的（`circle`、`ellipse`、`rect`、`path`、`fill="none"`、`stroke-linecap`）。
