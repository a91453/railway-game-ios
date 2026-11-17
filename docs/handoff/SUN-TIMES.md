# SUN-TIMES：3D 地圖的日出日落照緯度與日期

- 派工：遊戲規劃，2026-11-17（`MAP_DATA_SOURCES_2026-11-16.md` 第 1 名，3.40；併冬季活動的 I 極夜光線）。Session：session_01JMHz9Y8TZ98BX9hknterNZ（雲端）。分支 `claude/sun-times`。決策 [813](../decisions/813.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。
- 做了：`Map3DSunPath`（NOAA 太陽位置，照參考庫 sun.mjs 翻譯；日出日落）、`Map3DSunPlace`（錨點 → 緯度經度與時區、芬蘭夏令時間）、`Map3DLighting(at:place:)`（光線、天空的日月照真的太陽；極地正午的藍色暮光）、`Map3DPreviewScreen` 改用它、`Map3DSunPathTests`、`tools/map3d-preview` 的 `MAP3D_DAY`。

## 還留下什麼（下一步，照容易接的順序）

1. **2D 地圖的晝夜**（`DayNight.swift`，決策 182）還是照時鐘的分鐘固定 06–18 時；照 `Map3DSunPath` 的高度角算 night 只要改 `DayNight.tint(at:)` 一處（參考 train-lighting.js 本來就是用高度角 −6°～8° 的 smoothstep）。
2. **雪景（ROVANIEMI-SNOW）**：`Map3DLighting.polarNoon` 是藍色暮光的關鍵格；下雪天的灰藍光（WINTER_EVENT §4.1 第 2 點）可以疊在它上面，`Map3DWeather` 的 `skyMix` 照舊。
3. **極光**：要「晚上偶爾」時，用 `Map3DSky` 的 `stars`（晴天的夜）乘上一個依日期的種子決定哪幾晚有；只在 `Map3DSunPlace.latitude` 高於約 60° 畫，照 `motion` skill 減少動態時不動。
4. **月相與月出月落**：月亮現在畫成太陽正對面的滿月。參考庫 `city_map_reference_clean/source/environment/celestial-math.js` 有月亮位置、月相、月出月落（`getMoonPosition`、`getMoonIllumination`、`getMoonTimes`），可以照它翻，給夜景的月亮用。
5. **環境音的晝夜切換**（MAP_DATA_SOURCES §4.3 的音樂角度）可以改問真的日落。

## UNVERIFIED

- iOS 建置、Metal 畫面、實機（macOS CI、TestFlight）。預覽圖是 WebGL 算的。
- 截圖驗收（`website-screenshots.yml`）：網站截圖的場景都是台灣、時刻固定，看不出季節；這次只附 WebGL 預覽，沒跑 macOS 截圖。
- 完整測試留給 CI；本機只跑了建置（warnings as errors）與相關的測試類別。
