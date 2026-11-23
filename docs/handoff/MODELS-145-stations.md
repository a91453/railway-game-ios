# MODELS-145-stations：工作室車站、月台、街具接回（決策 929）

2026-11-22，工作串「145 模型接回 B 車站月台街具」。分支 `claude/models-145-stations`。

## 做完的

芬蘭小站、平溪、日南、高鐵苗栗／彰化／雲林／嘉義、平交道柵欄機：`docs/decisions/929.md`。

## 還沒做的

1. **跨站天橋與地下道入口**（`railway-assets-private-2` `game-art-previews/docs/art/station-footbridge-2026-11/revision-4`，#301；經驗 `docs/studio/lessons/station-footbridge.md`）。遊戲地圖上目前沒有畫天橋，要新寫放法：哪些站畫（兩個以上月台、地面站）、跨哪幾股、樓梯落在哪個月台、和雨棚與站房的避讓，並照 `Map3DTrainRoom` 的淨空。台／港／日三款各有 end、pier、span（5 m 一節）、stair（16 m）與遠景；轉乘時間不看畫出來的橋（GameCore 不動）。
2. **月台轉乘指示牌**（`platform-transfer-sign-2026-11/revision-2`，#269；經驗 `platform-transfer-sign.md`）。掛在 `Map3DPlatformProps.swift`：`StationTransfers` 的 `quickest.kind == .acrossPlatform` 才掛；吊牌只在雨棚兩端（面朝外、離端 ≤ 0.3 m），沒有雨棚用立柱牌、離雨棚 ≥ 1 m；字用 `Map3DBoardGlyphs`、位置在 `slots.json`；`badge` 換成對面路線的顏色，−X 半邊是 −X 側那股的線。
3. **高鐵四站的後續**：月台屋頂沒有照遊戲月台長裁；站房比真實位置靠軌道 8 到 18 m（決策 929 §2.3），下一輪模型請工作室照 OSM 軌道重放站房與高架的相對位置（苗栗 −7.9、彰化 +17.4、雲林 +5.4、嘉義 +18.2 m，嘉義高架在另一側）。
4. **平交道**：火車來時桿放下、`-night` 亮燈；`stopWhite`、`crossingDeck`、`barrierRed` 收進色票。
5. 平溪主體偏 1 m（外廓不對稱，`addHouse` 照外廓置中）。

以上都還沒評分進優先清單，請遊戲規劃排。
- 高鐵苗栗的淺色大屋頂和站前地面對比不足（`Map3DRoofContrastTests.known` 加了 `station-study/studio-miaoli`），請工作室下一輪處理。
