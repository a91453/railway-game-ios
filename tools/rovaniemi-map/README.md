# 羅瓦涅米的地圖資料（決策 789）

把芬蘭拉普蘭羅瓦涅米一帶（北緯 66.30–66.80、東經 25.20–27.60，從穆羅拉到凱米耶爾維）做成一個自成一包的地圖包 `RailwayGameApp/Resources/MapPacks/rovaniemi/`，檔名與格式和香港的一樣（`tools/hk-map/`）。企劃在 `docs/research/WINTER_EVENT_2026-11-15.md` §3。

遊戲還不讀這一包：`OverseasMaps.open` 沒有羅瓦涅米。

## 來源

| 檔案 | 從哪裡來 | 授權 |
|---|---|---|
| `finland.pbf` | OpenStreetMap 芬蘭整包，`https://osmtoday.com/europe/finland.pbf`（約 853 MB，會轉到 geo2day.com），用 `osmium extract` 切成 `rovaniemi.pbf`（約 7 MB） | ODbL 1.0，© OpenStreetMap 貢獻者 |
| `digitraffic_trains.json`（這個資料夾裡） | Fintraffic Digitraffic，`https://rata.digitraffic.fi/api/v1/trains/<日期>` 與 `metadata/stations` | CC BY 4.0：「Source: Fintraffic / digitraffic.fi, licence CC 4.0 BY」 |
| 地形資料庫（Maastotietokanta）的 `<圖幅>L_mtk.zip`、`<圖幅>R_mtk.zip`（72 個）與 3D 建物（Rakennukset 3D）2022 羅瓦涅米 LoD2 的 `<圖幅><A–H>.zip`（64 個） | 芬蘭國土測量局（MML），從 Kapsi 的鏡像 `https://kartat.kapsi.fi/files/maastotietokanta/kaikki/etrs89/gml/` 與 `https://kartat.kapsi.fi/files/3D-rakennukset/kaikki/2022/etrs89/citygml/Rovaniemi/LOD2/` 抓（約 300 MB 與 18 MB；`mml_buildings.py fetch`，決策 1009） | MML 開放資料授權＝CC BY 4.0（可商用）；署名「Contains data from the National Land Survey of Finland Topographic Database and Buildings 3D (2022)」 |
| `fin_pop_2025_CN_1km_R2025A_UA_v1.tif` | WorldPop 芬蘭 2025，constrained，1 km | CC BY 4.0，WorldPop |
| `T4312.tif` … `T5223.tif`（36 張） | 芬蘭國土測量局（Maanmittauslaitos）10 m 高程模型（Korkeusmalli 10 m，雷射測量的地面，ETRS-TM35FIN、N2000），2023 年 8 月版，從 Kapsi 的鏡像 `https://kartat.kapsi.fi/files/korkeusmalli/hila_10m/etrs-tm35fin-n2000/` 抓（各約 9 MB，共 322 MB；`fetch_nls_dem.py`）。CSC Paituli 的鏡像 `https://www.nic.funet.fi/index/geodata/mml/dem10m/2019/` 有 2019 年版，檔名相同 | 芬蘭國土測量局開放資料授權＝CC BY 4.0（可商用）；署名「National Land Survey of Finland, Elevation model 10 m, 08/2023」 |

這些在雲端容器都連得到（2026-11-15）。芬蘭國土測量局（MML）自己的下載服務要 API 金鑰（401），所以高程從上面兩個公開鏡像抓（2026-11-25）。決策 971 之前用的是 Copernicus DEM GLO-30：它是地表模型，量到的是樹頂，拉普蘭整片是林，鐵路、道路、空地在裡面都成了 10–20 m 深的溝。每次讀了什麼寫在 `rovaniemi_sources.json`。

## 重做

```sh
mkdir -p /tmp/rv/osm /tmp/rv/pop /tmp/rv/nls
curl -L -o /tmp/rv/osm/finland.pbf https://osmtoday.com/europe/finland.pbf
apt-get install -y osmium-tool    # 只用來切範圍
osmium extract -b 25.15,66.27,27.65,66.83 -s smart -o /tmp/rv/osm/rovaniemi.pbf /tmp/rv/osm/finland.pbf
pip install osmium tifffile imagecodecs numpy

# 1. Digitraffic 的列車（前後各多抓一天，夜車才完整）；結果進 repo。
python3 -I tools/rovaniemi-map/fetch_digitraffic.py 2026-12-13 2026-12-21

# 2. 鐵道與時刻（12/14 那一週），再排班次。
python3 -I tools/rovaniemi-map/build_rovaniemi_rail.py /tmp/rv/osm/rovaniemi.pbf \
  tools/rovaniemi-map/digitraffic_trains.json RailwayGameApp/Resources/MapPacks/rovaniemi 2026-12-14
python3 -I tools/rovaniemi-map/extract_rovaniemi_runs.py RailwayGameApp/Resources/MapPacks/rovaniemi

# 3. 人口。
curl -L -o /tmp/rv/pop/fin.tif https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/FIN/v1/1km_ua/constrained/fin_pop_2025_CN_1km_R2025A_UA_v1.tif
python3 -I tools/rovaniemi-map/build_rovaniemi_ground.py /tmp/rv/pop/fin.tif RailwayGameApp/Resources/MapPacks/rovaniemi

# 4. 底圖（約 10 秒）。
python3 -I tools/rovaniemi-map/build_rovaniemi_basemap.py /tmp/rv/osm/rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi/basemap.pmtiles

# 5. 地形與水域。
pip install tifffile imagecodecs numpy
python3 -I tools/rovaniemi-map/fetch_nls_dem.py /tmp/rv/nls    # 36 張，約 2 分鐘
python3 -I tools/rovaniemi-map/build_rovaniemi_ground_grids.py /tmp/rv/nls /tmp/rv/osm/rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi

# 5b. 建物（決策 799、1009；約 1 分鐘，先要有第 3 步的人口）。MML 的輪廓與實測高度，OSM 補用途與新建物。
#     osmtoday.com 連不上時，OSM 改抓 https://download.openstreetmap.fr/extracts/europe/finland/lapland-latest.osm.pbf 再切。
pip install shapely
python3 -I tools/rovaniemi-map/mml_buildings.py fetch /tmp/rv/mml    # 約 320 MB
python3 -I tools/rovaniemi-map/build_rovaniemi_buildings.py /tmp/rv/mml /tmp/rv/osm/rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi

# 6. 機場與不蓋區（台灣那兩支工具），最後重寫 pack.json。
python3 -I tools/airfields/build_airfields.py /tmp/rv/osm/rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi/airfields.json
python3 -I tools/no-build-land/build_no_build.py /tmp/rv/osm/rovaniemi.pbf RailwayGameApp/Resources/MapPacks/rovaniemi/no_build.json
python3 -I -c "import sys; sys.path.insert(0, 'tools/rovaniemi-map'); import build_rovaniemi_rail as b; b.write_manifest('RailwayGameApp/Resources/MapPacks/rovaniemi')"

swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter RovaniemiRailwaysTests
```

## 兩條線

- `KJA` 凱米耶爾維線：羅瓦涅米、米西、凱米耶爾維。
- `MUL` 羅瓦涅米—穆羅拉：往奧盧的主線在地圖上的一段；列車在穆羅拉進出地圖，不停穆羅拉的車也算在穆羅拉發到。

車站的中文名（羅瓦涅米、穆羅拉、米西、凱米耶爾維）與線名、線色是本專案的；英文站名與代號是 Digitraffic 的。
