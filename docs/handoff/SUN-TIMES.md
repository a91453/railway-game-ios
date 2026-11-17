# SUN-TIMES：3D 地圖的日出日落照緯度與日期

- 派工：遊戲規劃，2026-11-17（`MAP_DATA_SOURCES_2026-11-16.md` 第 1 名，3.40；併冬季活動的 I 極夜光線）。Session：session_01JMHz9Y8TZ98BX9hknterNZ（雲端）。分支 `claude/sun-times`。決策 [813](../decisions/813.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。
- 做了：`Map3DSunPath`（NOAA 太陽位置，照參考庫 sun.mjs 翻譯；日出日落）、`Map3DSunPlace`（錨點 → 緯度經度與時區、芬蘭夏令時間）、`Map3DLighting(at:place:)`（光線、天空的日月照真的太陽；極地正午的藍色暮光）、`Map3DPreviewScreen` 改用它、`Map3DSunPathTests`、`tools/map3d-preview` 的 `MAP3D_DAY`。

## 還留下什麼（下一步，照容易接的順序）

1. **2D 地圖的晝夜**（`DayNight.swift`，決策 182）還是照時鐘的分鐘固定 06–18 時；照 `Map3DSunPath` 的高度角算 night 只要改 `DayNight.tint(at:)` 一處（參考 train-lighting.js 本來就是用高度角 −6°～8° 的 smoothstep）。
2. **雪景（ROVANIEMI-SNOW）**：`Map3DLighting.polarNoon` 是藍色暮光的關鍵格；下雪天的灰藍光（WINTER_EVENT §4.1 第 2 點）可以疊在它上面，`Map3DWeather` 的 `skyMix` 照舊。
3. ~~**極光**~~：已做（AURORA，決策 813 的「後來：極光」）。
4. **月相與月出月落**：月亮現在畫成太陽正對面的滿月。參考庫 `city_map_reference_clean/source/environment/celestial-math.js` 有月亮位置、月相、月出月落（`getMoonPosition`、`getMoonIllumination`、`getMoonTimes`），可以照它翻，給夜景的月亮用。
5. **環境音的晝夜切換**（MAP_DATA_SOURCES §4.3 的音樂角度）可以改問真的日落。

## 交給遊戲規劃排序的新項目（作者 2026-11-17 問「還有其他測試能用類似方法加速嗎」）

**TEST-JUMP：讓測試直接從要測的時刻或狀態開始，不從頭跑**（還沒量，先評分）

- 背景：光線只看時刻，測試可以直接給「第 350 天」。GameCore 的模擬不行：狀態是一分鐘一分鐘接著算的，跳過去就不是玩家會遇到的狀態，存檔與重播的確定性也守不住。慢的也不是天數：`AnnualPropertyTaxesTests` 空世界跑滿一年，7 項共 0.1 秒；花時間的是車多、站多的那幾天。
- 要做的：(1) 先量：各 shard 與 iOS UI 測試的時間花在哪幾支、哪些是「開新局一路點到某個狀態」；(2) UI 測試若有這種，改成啟動時讀準備好的存檔或時刻；(3) 長的 campaign 從存好的中途狀態開始，只在規則改了會自動失效時才做（`ReplayFixtures` 的風險）。
- 五方（權重照 NEXT_PRIORITIES §19）：玩家 2（CI 快一點，修正早一點進 TestFlight，間接）、開發 4（PR 的 gate 與 shard 變短）、美術 1、鐵道迷 1、音樂 1 → **2.05**。和 CI 優化那條線（HANDOFF §1「多久做一次 CI 優化」：看數字過線才開）是同一件事，可以併進下一次 CI 優化。

## UNVERIFIED

- iOS 建置、Metal 畫面、實機（macOS CI、TestFlight）。預覽圖是 WebGL 算的。
- 截圖驗收（`website-screenshots.yml`）：網站截圖的場景都是台灣、時刻固定，看不出季節；這次只附 WebGL 預覽，沒跑 macOS 截圖。
- 完整測試留給 CI；本機只跑了建置（warnings as errors）與相關的測試類別。
