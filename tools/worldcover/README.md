# 台灣的地表覆蓋（ESA WorldCover）

決策 811。3D 地圖的鄉間原本是一片空白的平地：OpenStreetMap 畫了的林地、農地才有顏色與樹，沒畫的山坡全是灰綠。這個工具把 ESA WorldCover 10 m 2021 v200（CC BY 4.0）摺成遊戲用的八類，存在水域檔的格子上，App 讀它給鄉間的地面上色，在森林裡種樹。

- 輸出：`RailwayGameApp/Resources/RealWorld/taiwan_landcover.dat`（約 1.8 MB；高度檔的格式，magic `TWLC`，`LandCoverGrid` 讀）。
- 格子：`taiwan_water.json` 的格子（1.875″，約 58 × 53 m，9296 列 × 8064 欄）。水域檔已經是水的格子存 0（App 照水域檔畫水）。
- 每格取它裡面最多的那一類，再取周圍 3 × 3 格最多的那一類（同票取小的；0 的格子維持 0）。只存類別，不存樹的比例（森林格有 96 % 至少一半是樹，存比例要多一倍的大小）。
- 資料日期：2021 年的衛星影像（v200，2022-10 發布）。
- 國土利用調查要付費，不用。

| 值 | 遊戲的類別 | WorldCover 的類別 |
| --: | --- | --- |
| 0 | 不知道（或水域檔的水） | — |
| 1 | 森林 | 10 Tree cover |
| 2 | 灌叢 | 20 Shrubland |
| 3 | 草地 | 30 Grassland、100 Moss and lichen |
| 4 | 農地 | 40 Cropland |
| 5 | 建成區 | 50 Built-up |
| 6 | 裸地 | 60 Bare / sparse vegetation、70 Snow and ice |
| 7 | 水 | 80 Permanent water bodies |
| 8 | 濕地 | 90 Herbaceous wetland、95 Mangroves |

## 用法

需要 `tifffile` 與 `numpy`（坡度工具已經在用，`tools/real-world-population/build_slope_grid.py`），讀進來的檔放在自己的空資料夾，用 `python3 -I` 跑。

```sh
pip install tifffile numpy
mkdir -p /tmp/worldcover
for t in N21E117 N21E120 N24E117 N24E120 N24E123; do
  curl -fsSL -o /tmp/worldcover/ESA_WorldCover_10m_2021_v200_${t}_Map.tif \
    "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_${t}_Map.tif"
done
python3 -I tools/worldcover/build_landcover_grid.py \
  RailwayGameApp/Resources/RealWorld/taiwan_water.json /tmp/worldcover \
  RailwayGameApp/Resources/RealWorld/taiwan_landcover.dat
```

檔名照 WorldCover 原本的名字（工具認這個名字）。五個圖塊共約 120 MB，跑約 2 分鐘；N24E123 在格子東邊之外，工具會略過，實際用到 4 個。2026-11-17 跑出的比例：陸地有類別的格 11,590,345 個，森林 78.2 %、草地 2.6 %、農地 10.2 %、建成區 7.6 %、裸地 0.5 %、水 0.9 %（灌叢、濕地不到 0.1 %）。

## 和網站版的關係

作者的網站版（railway-reference-private `Railway/rail-reference/regions/taiwan/source/scripts/build_worldcover.py`，說明 `docs/worldcover-0908.md`）讀的是同樣 4 個圖塊：工具開頭的 `SHA256` 照它的 `manifest.json` 抄，檔案不同（例如 WorldCover 出了新版）就停下，不讓兩邊的地圖悄悄不一致。類別表、出處文字也和它一樣。

不同的地方：網站版輸出 z6–11 的 Mapbox 向量圖磚（918 個、約 23 MB，要 rasterio、shapely、mapbox-vector-tile、mercantile 四個套件），App 只要每 64 m 一格的類別，所以這裡存成高度檔格式的格子（1.8 MB，只用 tifffile 和 numpy）；海岸用水域檔的格子，不另讀內政部縣市界線。

## 出處

© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium。CC BY 4.0，<https://doi.org/10.5281/zenodo.7254221>。App 的資料來源頁（`DataSourceCredits` 的 `esaWorldCover`）與 3D 地圖角落的出處都列了它。
