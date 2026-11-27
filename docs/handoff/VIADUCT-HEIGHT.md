# VIADUCT-HEIGHT：收購鋪的高架車站降到真實高度

## 做了什麼

- 派工：規劃4 工作串「降低高架鐵道到真實高度」，分支 `claude/project-thread-4t4o7t`，決策 [1023](../decisions/1023.md)。存檔版本、golden schema、GameCore 不動。
- 站在自己真實高架上的車站最低離地 10 m（`RealLineAcquisition.viaductStation`，和站間高架同高），原本 16 m；抬高讓開公司軌道的共站（決策 809）仍 16 m。
- 量到：台灣 15 條在售線高架月台離地中位數 16.0 → 10.3 m；博多新幹線 16 → 10 m；改前改後的報告在決策 1023。
- VERIFIED（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors`；real-line-laying §2 的測試組、`KyushuShinkansenTests`、`FukuokaRailwaysTests` 等 75 個 0 失敗。UNVERIFIED：Metal 畫面與實機。

## 還留下的

1. **鐵路高架跨高架道路時局部抬高。** 3D 的高架道路第一層 9 m，跨鐵路高架時留得出淨空就從下面壓低過、留不出就從上面跨。站間鐵路高架一直是 10 m，現在車站也是，所以高架道路在那裡壓低從下面過。真實的是鐵路在那裡抬高（忠孝復興站的文湖線跨市民高架）。要讓收購鋪法讀得到道路的層數（地圖格子的 `layer`），在交叉點加一個「離地至少 道路層高＋淨空」的高度下限，像決策 552 的 `crossingLevels`。
2. **熊本仍在 16.8 m。** 遊戲地形在熊本站 600 m 的平直段裡從 9 m 起伏到 15.9 m，真實高架的下限（每一點離地 10 m）壓在最高那點。改法要看那段地形是不是讀錯（真實站場是平的），或在車站平直段裡改成只看站中心。
3. **淡海輕軌淡金鄧公 6.9 m、算路堤。** 坡度到不了的站用了車站寬限，下限低了它也跟著低；真實是 8 m 的橋。
