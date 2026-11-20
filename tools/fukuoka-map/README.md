# 福岡的地圖資料（決策 854）

日本的第一張地圖。只開福岡市一小區（北緯 33.52–33.72、東經 130.29–130.48，約 17.6 × 22.2 公里），不匯入全日本；全國的 N02 只拿來挑這一區（評分在私有 `railway-assets-private-2` 的 `docs/priorities/JAPAN-MAP.md`）。做成自成一包的地圖包 `RailwayGameApp/Resources/MapPacks/fukuoka/`，檔名與格式和香港（`tools/hk-map/`）、羅瓦涅米（`tools/rovaniemi-map/`）一樣。

有鐵道（福岡市地鐵空港線 K、箱崎線 H、七隈線 N）、人口、底圖、建物、高度、水域、地形、機場與不蓋區（FUKUOKA-GROUND，決策 854「後來」）。FUKUOKA-OPEN（2026-11-19）打開了：`OverseasMaps.open` 有福岡，`RailwayGameApp/AssetPacks/fukuoka.json` 是它的地圖包清單（發版時上傳，App 只帶 `pack.json`，決策 858），福岡機場與桃園、高雄的航線開圖（決策 712）。

地面這幾步和羅瓦涅米共用 `tools/overseas-map/overseas_ground.py`（人口裁切、陡坡、寫 `water.json`／`heights.dat`／`terrain.pmtiles`、海岸線在切出範圍邊上補齊）與 `overseas_buildings.py`（羅瓦涅米的建物規則，決策 799），這裡只留福岡自己的：高度從哪來、檢查哪座山。

## 來源

| 檔案 | 從哪裡來 | 授權 |
|---|---|---|
| `N02-25_Station.geojson` | 国土数値情報 鉄道データ N02 2025 年版，`https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip`（14.2 MB，取 `UTF-8/N02-25_Station.geojson`） | CC BY 4.0；署名「『国土数値情報（鉄道データ）』（国土交通省）を加工して作成」 |
| `jpn_pop_2025_CN_1km_R2025A_UA_v1.tif` | WorldPop 日本 2025，constrained，1 km | CC BY 4.0，WorldPop |
| 國土地理院標高圖磚 | `https://cyberjapandata.gsi.go.jp/xyz/dem5a_png/15/…`（沒有就 dem5b、dem5c），另抓 `dem_png/14/…`（DEM10B） 補 5 m 沒有值的點；`fetch_gsi_dem.py` 一次一片地抓（約 630 片，十幾分鐘） | 国土地理院コンテンツ利用規約（與 CC BY 4.0 相容），署名「国土地理院の標高タイルを加工して作成」 |
| `kyushu.pbf` | OpenStreetMap 九州，`https://osmtoday.com/asia/japan/kyushu.pbf`（約 354 MB，會轉到 geo2day.com），用 `osmium extract` 切成 `fukuoka.pbf`（約 30 MB） | ODbL 1.0，© OpenStreetMap 貢獻者 |

這兩個在雲端容器都連得到（2026-11-18）。每次讀了什麼寫在 `fukuoka_sources.json`。

- **車站與日文站名**：N02（月台那一段折線的中點）。站序是業者的站號（K01 姪浜…），工具核對 N02 的站和站號表一筆不差。
- **軌道、隧道、高架、路線色**：OSM（`railway=subway` 的正線，不含機廠、側線、渡線；`tunnel`、`bridge` 標籤）。
- **中文站名**：本專案的（N02 的站名換成正體字：姪浜 → 姪濱、恵 → 惠、県庁 → 縣廳、薬 → 藥、辺 → 邊、桜 → 櫻、呉 → 吳；福岡空港 → 福岡機場）。
- **英文站名**：本專案的（業者的羅馬字去掉長音符號），工具和 OSM 的 `name:en` 對照，不同的印出來（`福岡空港` OSM 寫 `Fukuokakūkō (Airport)`、`櫛田神社前` OSM 寫 `Kushida Shrine`）。國土地理院的多言語表記是實驗性資料，沒用（`docs/research/JAPAN_RAIL_DATA_2026-10-21.md` §4.F）。
- **班距**：福岡市地鐵**沒有公開的時刻表**（2026-11-18 查過，福岡市的開放資料只有渡船的 GTFS）。尖峰班距照福岡市的改點新聞稿（空港線中洲川端—福岡空港 3 分 20 秒，2026 年 3 月；七隈線平均 3 分 15 秒，2023 年 8 月），箱崎線與離峰班距、首末班、站間時間都是本專案的估計，`fksubway_times.json` 寫明是估計。

## 重做

```sh
mkdir -p /tmp/fk/n02 /tmp/fk/osm
curl -L -o /tmp/fk/n02/N02-25_GML.zip https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip
(cd /tmp/fk/n02 && unzip -o -q N02-25_GML.zip)
curl -L -o /tmp/fk/osm/kyushu.pbf https://osmtoday.com/asia/japan/kyushu.pbf
apt-get update && apt-get install -y osmium-tool    # 只用來切範圍（GPL-3.0，只執行、不抄程式）
osmium extract -b 130.25,33.49,130.52,33.75 -s smart -o /tmp/fk/osm/fukuoka.pbf /tmp/fk/osm/kyushu.pbf
pip install osmium

# 1. 鐵道與估計班距（約 50 秒）。
python3 -I tools/fukuoka-map/build_fukuoka_rail.py /tmp/fk/n02/N02-25_GML/UTF-8/N02-25_Station.geojson \
  /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka
# 2. 排班（`tools/real-timetables/extract_metro_runs.py`，和香港同一套）。
python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka

# 3. 人口、底圖、機場、不蓋區、高度與水域（FUKUOKA-GROUND）。
mkdir -p /tmp/fk/pop /tmp/fk/gsi
curl -L -o /tmp/fk/pop/jpn.tif https://data.worldpop.org/GIS/Population/Global_2015_2030/R2025A/2025/JPN/v1/1km_ua/constrained/jpn_pop_2025_CN_1km_R2025A_UA_v1.tif
pip install tifffile imagecodecs numpy
python3 -I tools/fukuoka-map/build_fukuoka_ground.py population /tmp/fk/pop/jpn.tif RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/build_fukuoka_ground.py basemap /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/build_fukuoka_ground.py buildings /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka   # 約 30 秒，要先有人口
python3 -I tools/airfields/build_airfields.py /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka/airfields.json
python3 -I tools/no-build-land/build_no_build.py /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka/no_build.json
python3 -I tools/fukuoka-map/fetch_gsi_dem.py /tmp/fk/gsi
python3 -I tools/fukuoka-map/build_fukuoka_ground.py grids /tmp/fk/gsi /tmp/fk/osm/fukuoka.pbf RailwayGameApp/Resources/MapPacks/fukuoka

swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter FukuokaRailwaysTests
```

## 地面

- **高度用國土地理院的，不用 Copernicus**：Copernicus 是地表模型（樹頂、屋頂），羅瓦涅米的樹林與矮房可以用；福岡市中心高樓多，用它會把線鋪在樓頂上。國土地理院 5 m 是雷射測量的地面（沒有 5 m 的點用 10 m）。每格取格內像素的平均，海與離岸遠的水是 0，岸邊的水保留水面（和香港同一條規則）。
- **海岸**：九州的海岸線在切出的範圍四邊都被切開，`overseas_ground.coast_in_box` 把每段切到範圍裡、沿範圍的邊逆時針補到下一段（陸地在左，OSM 的畫法），能之島、志賀島是自己封閉的環。
- **檢查**：愛宕山（68 m）附近最高格差 25 m 以內（格是約 50 m 見方的平均，小山頂會被拉低；5 m 像素量到 64 m）；高程模型 1 m 以上的格子，OSM 也要算陸地的至少 97 %。

## 三條線

| 線 | 站數 | 長度（量的） | 官方 | 一天的班次（估計） |
|---|--:|--:|--:|--:|
| `K` 空港線 姪濱—福岡機場 | 13 | 12.94 km | 13.1 km | 512 |
| `H` 箱崎線 中洲川端—貝塚 | 7 | 4.73 km | 4.7 km | 326 |
| `N` 七隈線 橋本—博多 | 18 | 13.54 km | 13.6 km | 514 |

- 三條線各跑自己的區間：箱崎線直通空港線到姪濱、空港線直通 JR 筑肥線的車沒有做（FUKUOKA-THROUGH）。
- 博多（空港線、七隈線）與中洲川端（空港線、箱崎線）兩站共站。照「共站的線綁在一起賣」，開圖時三條線會是一組。
- 隧道約 30 km、高架約 0.6 km（姪濱一帶），其餘是地面。
- 七隈線尖峰用平均 3 分 15 秒，不用最短的 3 分：3 分時，尖峰轉離峰多出來的車，兩端各要 6 股，沒有機廠的線遊戲只鋪 5 股。真實的機廠在橋本，決策 898 起收購時一起蓋（`RealLineDepotSite.hashimoto`，位置與為什麼不在真實的位置見 `tools/rail-depots/README.md`）。
- **七隈線整天從橋本端排車**（決策 898，`SERVICE["N"]["depotEnd"]`、`FAR_TURN`）：博多的每一班都是橋本開來的車到站 6 分鐘後折返，夜裡 23 組車都在橋本（4 組在站、19 組在機廠），博多不留夜車。博多離機廠 13.5 km，留在那裡的車夜裡會被收回機廠、清晨再空車開回去，擋住博多的頭幾班。只重排時刻不重讀 OSM：`python3 -I tools/fukuoka-map/build_fukuoka_rail.py times RailwayGameApp/Resources/MapPacks/fukuoka`，再跑 `extract_fukuoka_runs.py`。車組數照遊戲的最短停站 36 秒算（時刻表每站 25 秒），橋本再留 3 分鐘讓晚到的車追回來（`extract_branch_runs.RECOVERY`），所以是 23 組不是 20 組。
- **建物**：OSM 的外形與用途，樓層或高度有標的照標（福岡約九成有標，是圖友匯入的福岡市 3D 模型），沒標的照羅瓦涅米的規則估（同類、同人口密度、同面積的四分位數）。約 28.5 萬棟、4.5 MB，最高 48 層；統計在 `fukuoka_buildings.json`。PLATEAU 不另外接：OSM 已經帶了它的高度。
