# Real land prices 實價登錄推算地價 (decision 1025)

`build_land_price_grid.py` makes `RailwayGameApp/Resources/RealWorld/taiwan_land_price.dat`:
how dear each 7.5″ cell (some 230 m) of Taiwan's land is against the
country's median of the same zone, in thousandths (100 to 10,000), from the
real-price registry's sales of 110S1 to 115S3. GamePresentation reads it as
`LandPriceGrid`; when a map's land is read, each 256 m square takes its
cell's factor (`GameWorld.setLandLocations`), and a cell's land value is its
use's base times that factor (`LandValueRules.located`).

每格土地單價（土地殘餘法：總價扣車位、扣建物折舊後成本，再除土地面積）÷ 全台同年同分區的中位數，
取幾何平均。格內買賣不到 6 筆就往外擴 3、7、15、31 格，再不夠用鄉鎮平均。

## Commands 指令

The script's docstring has the three commands and how long each takes
(the door-number points via `tools/overture-footprint-tiles/usage_permits.py`,
the registry's season zips, then the grid). Everything is downloaded from
plvr.land.moi.gov.tw and Overture Maps; nothing needs a key.

```sh
python3 -I tools/real-land-price/build_land_price_grid.py at \
    RailwayGameApp/Resources/RealWorld/taiwan_land_price.dat 121.5654 25.0330
```

prints the factor at a point (here Taipei 101).

## Sources and licence 來源與授權

- 內政部地政司「不動產買賣實價登錄批次資料」, data.gov.tw 18703.
- 各縣市門牌坐標, through OpenAddresses and Overture Maps.
- 內政部鄉鎮市區界線, as `a91453/railway-reference-private`
  `Railway/geo-scene-reference-clean/source/public/statistics/township-reference.geojson`.

All three under the Open Government Data License, version 1.0 (政府資料開放授權條款第 1 版):
commercial use allowed with attribution, given in the game's data sources
page (`DataSourceCredits`, `landPrice`).
