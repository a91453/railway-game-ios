# WINTER-LIVERY：聖誕塗裝套到各款車、路線頁的開關

- 派工單：WINTER-LIVERY（遊戲規劃 session_01JMHz9aiAQ16u6jrjjW2amC 派，2026-11-16）；實作 session_01JMHz9abdUuJXGnh5YBZc9X；分支 `claude/winter-livery`。
- 決策 795。存檔、golden、GameCore、replay、模型包的模型與雜湊：都不動。
- 做了什麼：每節跑的車照部位（側面的車身、線色帶、細線）套 `Map3DWinterDecor.christmasLivery`；路線頁「聖誕塗裝」開關（活動期間或拿過第 4 週徽章才出現）；照存檔列記在裝置偏好；套用的路線傳進 `WinterMissionFacts(world:liveried:)`，第 4 週拿得到。細節在 [`decisions/795.md`](../decisions/795.md)。

## 還留下的

1. **照 model-look 看圖**：部位是自動分的，沒有拍過圖、沒和照片並排。白帶比紅車身大的幾款（700T、推拉式客車、淡海與安坑輕軌、文湖線、阿里山客車）與沒有白帶的幾款（普悠瑪、太魯閣、EMU800／900、EMU3000 頭車）要看過再決定加不加例外（決策 795 §4）。
2. 2D 地圖的列車沒換色。
3. 還沒存過的新局，關掉 App 前沒存，選的塗裝就不見（記錄跟著存檔列）。

## UNVERIFIED

- Metal 畫面、iOS Simulator、實機上的樣子與效能；路線頁的開關（11 月看不到，要把裝置日期調到 12 月）。
- iOS 建置、字串目錄檢查交 CI。
