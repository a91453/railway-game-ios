# ROVANIEMI-MAP-2

- 派工：遊戲規劃，2026-11-16。Session：session_01JMHz9ZMDXyXPV7QMGtNCaN（雲端）。分支 `claude/rovaniemi-map-2`。決策 [799](../decisions/799.md)。
- 存檔（107）、golden、SaveFixtures、ReplayFixtures、GameCore：不動。
- 做了：羅瓦涅米地圖包的建物（`buildings.pmtiles`，+1.0 MB）、北方地圖的雪地色票（`Map3DSnowGround`）、芬蘭軌距 1,524 mm（`Map3DTrackGauge`）、資料來源頁加建物、預覽工具加 `MAP3D_WORLD=rovaniemi`。

## 還留下什麼

1. **備用車擋夜車一分鐘沒有修**（派工單第一項）。只改資料或收購時的停放股道都不會讓整週變少，數字在決策 799。要修的是 GameCore：有閉塞區間時，已經在路上、等終點月台的車（`deadlock` 回報的 `departs == false`）不會改走站裡的空月台，只等調度下一分鐘移開閒置的車；`takingAnyDeparture`（`RouteReservation.swift`）只在出發時改月台。重現：`RovaniemiRailwaysTests.rovaniemi()` 買 `vr:KJA` 或 `vr:MUL`，逐分鐘 `advance(ticks: 1)` 問 `deadlock(memo:)`，第 529 分（KJA，往凱米耶爾維）與第 330、657、880 分（MUL）各卡 1 分鐘。會動 golden／replay，要另開一張並在 #2118 登記。香港的線（雙線、列車多）一整天是 0。
2. **同一局買不了兩條線**：先買 `vr:KJA` 再買 `vr:MUL`，收購被拒：「這段軌道與另一段軌道並行時距離不到 4 公尺」（兩條線在羅瓦涅米站共用軌道）。用預覽工具 `MAP3D_BUY=vr:KJA,vr:MUL` 就看得到；`RovaniemiRailwaysTests` 每條線各開一局所以沒測到。地圖開放前要解（香港的線怎麼共站可參考）。這張沒查原因。
3. **街道與建物還是台灣的樣子**：`Map3DStreetRegion` 只有台灣與香港，羅瓦涅米落在台灣：綠色人行道、黃色分向線、機車格、紅線、傍晚垃圾車、台式樓房立面與屋頂水塔。要加芬蘭一區（靠右行駛、沒有上述幾樣）；動的檔和 WINTER-LIGHTS 重疊，先在 #2118 寫明。
4. **列車的輪距**：鋼軌已是 1,524 mm，現在收購來的車是台灣車型（輪距 1,067 mm，輪子會落在兩軌之間）。Sr3、Sr2 與雙層客車那一張做車時，`Map3DModels` 的 `gauge` 設 1.524。
5. 雪景的其餘：河湖結冰、樹冠與屋頂積雪、下雪（ROVANIEMI-SNOW）。`Map3DSnowGround.covers(_:)` 可直接拿來判斷哪張地圖有雪。
6. 聖誕老人村（北緯 66.5436、東經 25.8473）現在只有 OpenStreetMap 的一般建物，沒有地標。

## UNVERIFIED

- iOS 建置與實機畫面（macOS CI、TestFlight）。地圖沒開放，沒有截圖驗收。
- 預覽圖是 WebGL 算的，不是 Metal。
