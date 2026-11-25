# KUMAMOTO-GROUND 交接

日本往南開到熊本的第 3 張單（評分在私有 repo `docs/priorities/JAPAN-KUMAMOTO.md`）。前一張的交接：`JAPAN-MAP-GROW.md`；
新幹線資料：`KYUSHU-SHINKANSEN-DATA.md`。決策 969「後來：地面到熊本」。

## 進度

- 做到哪：**做完了（2026-11-25）。** `MapPacks/fukuoka/` 的地面（底圖、建物、高度、水域、陡坡、人口、機場、不蓋區）到熊本，
  `pack.json` 有新範圍與 `earlier`。整包 8.6 MB → 45.1 MB。
- **這張合了以後，下一次發版玩家就會看到**：舊福岡存檔開起來地圖長到熊本（原本的四塊照樣是自己的，南邊用買的），日本新局
  四塊起跳。新幹線還沒開賣，「整張全開、不計成就」的選項還沒做（KUMAMOTO-OPEN）。
- 已驗證與沒驗證的：決策 969 最後一段。

## 重做這一包

`tools/fukuoka-map/README.md`「重做」與「到熊本」。國土地理院圖磚 7,286 片（562 MB）約 40 分鐘；其餘各步合計約 6 分鐘。
`grids` 一步分帶算（不分帶記憶體放不下）。

## 留給後面的單

- **SHINKANSEN-SALE**：鐵道檔沒動。`tools/fukuoka-map/kyushu-shinkansen/` 搬進包時，`build_fukuoka_rail.py` 的 `EXTENT` 已經是
  熊本的範圍（`build_kyushu_shinkansen.py` 原本自己設同一個值）。熊本総合車両所（到 32.701N）在範圍裡。
- **KUMAMOTO-OPEN**：
  - 實機量：包的下載時間（45 MB）、開局讀四塊地的時間、舊存檔長大那一次的讀檔時間、3D 地面記憶體。
  - 每買一塊要 93,000 人次（四塊 220 萬居民）；南邊的塊人少（有明海、山），照「買的塊數」算的價錢與里程碑要不要調，
    economy-balance skill 量過再說。
  - 地圖包名字、新遊戲清單、資料來源畫面仍寫「福岡」。範圍已到佐賀東半與熊本，要不要改名（例如「福岡・熊本」）在這張決定。
  - `airfields.json` 多了佐賀、熊本兩座機場，只畫在 3D 地圖上；要不要開航線另評。
  - `JAPAN-MAP-GROW.md`「還留下什麼」「要小心的」各條照舊（全開選項、裝置上的包比存檔舊、颱風重抽）。
- 地標（熊本城、熊本站）與市電：KUMAMOTO-LANDMARKS、KUMAMOTO-TRAM。

## 要小心的

- **repo 變大**：這一包每重做一次，git 歷史多約 45 MB（`basemap.pmtiles`、`buildings.pmtiles` 是壓過的二進位檔，差異存不小）。
  沒有必要不要整包重做；只改鐵道的單不要碰地面檔。
- OSM 的資料日期是 2026-11-21（`kyushu.pbf`），和 11-19 做的鐵道檔不是同一份；`fukuoka_sources.json` 各自記了雜湊。
- 福岡原本那一塊的水域有 6 格、陡坡有 50 格和舊包不同（決策 969「後來」）。舊存檔已讀進去的地不重讀，所以不影響已經蓋好的。
