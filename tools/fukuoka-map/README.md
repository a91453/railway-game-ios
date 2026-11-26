# 福岡的地圖資料（決策 854）

日本的第一張地圖。開圖時只開福岡市一小區（北緯 33.52–33.72、東經 130.29–130.48，約 17.6 × 22.2 公里）；**2026-11-25 起地面往南、往東做到熊本**（北 33.72、西 130.29 不變，南 32.69、東 130.90，約 56.5 × 114.1 公里，KUMAMOTO-GROUND，決策 969「後來：地面到熊本」；見下面「到熊本」）。不匯入全日本；全國的 N02 只拿來挑這一區（評分在私有 `railway-assets-private-2` 的 `docs/priorities/JAPAN-MAP.md`）。做成自成一包的地圖包 `RailwayGameApp/Resources/MapPacks/fukuoka/`，檔名與格式和香港（`tools/hk-map/`）、羅瓦涅米（`tools/rovaniemi-map/`）一樣。

有鐵道（福岡市地鐵空港線 K、箱崎線 H、七隈線 N）、人口、底圖、建物、高度、水域、地形、機場與不蓋區（FUKUOKA-GROUND，決策 854「後來」）。FUKUOKA-OPEN（2026-11-19）打開了：`OverseasMaps.open` 有福岡，`RailwayGameApp/AssetPacks/fukuoka.json` 是它的地圖包清單（發版時上傳，App 只帶 `pack.json`，決策 858），福岡機場與桃園、高雄的航線開圖（決策 712）。

地面這幾步和羅瓦涅米共用 `tools/overseas-map/overseas_ground.py`（人口裁切、陡坡、寫 `water.json`／`heights.dat`／`terrain.pmtiles`、海岸線在切出範圍邊上補齊）與 `overseas_buildings.py`（羅瓦涅米的建物規則，決策 799），這裡只留福岡自己的：高度從哪來、檢查哪座山。

## 來源

| 檔案 | 從哪裡來 | 授權 |
|---|---|---|
| `N02-25_Station.geojson` | 国土数値情報 鉄道データ N02 2025 年版，`https://nlftp.mlit.go.jp/ksj/gml/data/N02/N02-25/N02-25_GML.zip`（14.2 MB，取 `UTF-8/N02-25_Station.geojson`） | CC BY 4.0；署名「『国土数値情報（鉄道データ）』（国土交通省）を加工して作成」 |
| `jpn_pop_2025_CN_1km_R2025A_UA_v1.tif` | WorldPop 日本 2025，constrained，1 km | CC BY 4.0，WorldPop |
| 國土地理院標高圖磚 | `https://cyberjapandata.gsi.go.jp/xyz/dem5a_png/15/…`（沒有就 dem5b、dem5c），另抓 `dem_png/14/…`（DEM10B） 補 5 m 沒有值的點；`fetch_gsi_dem.py` 一次六片地抓（三縣是 5 m 31,672 片、10 m 8,100 片，約 2 小時；中斷了再跑會接著抓） | 国土地理院コンテンツ利用規約（與 CC BY 4.0 相容），署名「国土地理院の標高タイルを加工して作成」 |
| `kyushu.pbf`、`chugoku.pbf` | OpenStreetMap 九州與中國地方，`https://osmtoday.com/asia/japan/kyushu.pbf`（約 354 MB，會轉到 geo2day.com）與 `chugoku.pbf`（約 265 MB）。九州的用 `osmium extract` 切成 `fukuoka.pbf`（約 30 MB，鐵道用）；兩包 `osmium merge` 後切成 `three.pbf`（約 228 MB，地面與縣界用，決策 991：北邊到關門海峽對岸的下關） | ODbL 1.0，© OpenStreetMap 貢獻者 |

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
curl -L -o /tmp/fk/osm/chugoku.pbf https://osmtoday.com/asia/japan/chugoku.pbf
apt-get update && apt-get install -y osmium-tool    # 只用來切範圍（GPL-3.0，只執行、不抄程式）
osmium extract -b 130.25,33.49,130.52,33.75 -s smart -o /tmp/fk/osm/fukuoka.pbf /tmp/fk/osm/kyushu.pbf    # 鐵道（1、2）
osmium merge /tmp/fk/osm/kyushu.pbf /tmp/fk/osm/chugoku.pbf -o /tmp/fk/osm/merged.pbf
osmium extract -b 129.69,32.05,131.37,34.07 -s smart -o /tmp/fk/osm/three.pbf /tmp/fk/osm/merged.pbf    # 地面（3、4），福岡、佐賀、熊本三縣
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
python3 -I tools/fukuoka-map/build_fukuoka_ground.py basemap /tmp/fk/osm/three.pbf RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/build_fukuoka_ground.py buildings /tmp/fk/osm/three.pbf RailwayGameApp/Resources/MapPacks/fukuoka   # 約 2 分鐘，要先有人口
python3 -I tools/airfields/build_airfields.py /tmp/fk/osm/three.pbf RailwayGameApp/Resources/MapPacks/fukuoka/airfields.json
python3 -I tools/no-build-land/build_no_build.py /tmp/fk/osm/three.pbf RailwayGameApp/Resources/MapPacks/fukuoka/no_build.json
python3 -I tools/fukuoka-map/fetch_gsi_dem.py /tmp/fk/gsi
python3 -I tools/fukuoka-map/build_fukuoka_ground.py grids /tmp/fk/gsi /tmp/fk/osm/three.pbf RailwayGameApp/Resources/MapPacks/fukuoka

# 4. 依縣界拆成三包（決策 991）：底圖與建築切給福岡、佐賀、熊本三個資料夾，pack.json 寫上各份、範圍、
#    開局點與舊存檔的範圍。上面幾步會把 pack.json 的九州新幹線條目弄掉，先從 git 拿回來。
git checkout -- RailwayGameApp/Resources/MapPacks/fukuoka/pack.json
pip install shapely   # BSD 3-Clause，只有拆分用
osmium tags-filter -o /tmp/fk/osm/admin4.pbf /tmp/fk/osm/kyushu.pbf r/admin_level=4   # 縣界（整個關係，不切）
python3 -I tools/fukuoka-map/split_prefectures.py /tmp/fk/osm/admin4.pbf RailwayGameApp/Resources/MapPacks

swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter FukuokaRailwaysTests
```

## 地面

- **高度用國土地理院的，不用 Copernicus**：Copernicus 是地表模型（樹頂、屋頂），羅瓦涅米的樹林與矮房可以用；福岡市中心高樓多，用它會把線鋪在樓頂上。國土地理院 5 m 是雷射測量的地面（沒有 5 m 的點用 10 m）。每格取格內像素的平均，海與離岸遠的水是 0，岸邊的水保留水面（和香港同一條規則）。
- **海岸**：九州的海岸線在切出的範圍四邊都被切開，`overseas_ground.coast_in_box` 把每段切到範圍裡、沿範圍的邊逆時針補到下一段（陸地在左，OSM 的畫法），能之島、志賀島是自己封閉的環。
- **檢查**：愛宕山（68 m）與熊本西邊的金峰山（665 m）附近最高格差 25 m 以內（格是約 50 m 見方的平均，小山頂會被拉低；5 m 像素量到 64 m）；高程模型 1 m 以上的格子，OSM 也要算陸地的至少 97 %。

## 到熊本（KUMAMOTO-GROUND，2026-11-25）

範圍寫在 `build_fukuoka_rail.py` 的 `EXTENT`（現在）與 `EARLIER`（以前的範圍，由舊到新），`pack.json` 的 `extent`、`earlier` 由它寫出（決策 969：有 `earlier` 的包，舊存檔開起來世界會長大、擁有原本那四塊，新局四塊起跳）。**西北角不動**，所以格網從同一個角數起，福岡原本那一塊的每一格都在原位。

| | 福岡（以前） | 到熊本 |
|---|--:|--:|
| 範圍 | 17.6 × 22.2 km | 56.5 × 114.1 km（地圖塊 4 × 7） |
| 人口（WorldPop） | 約 170 萬 | 484 萬 |
| 高度格（1.875″） | 400 × 384 | 2000 × 1200 |
| 建物 | 28.5 萬棟 | 107.9 萬棟 |
| `basemap.pmtiles` | 3.1 MB | 23.7 MB |
| `buildings.pmtiles` | 4.5 MB | 16.5 MB |
| `heights.dat`＋`terrain.pmtiles`＋`water.json` | 0.2 MB | 3.9 MB |
| 整包（`pack.json` 的 `bytes`） | 8.6 MB | **45.1 MB** |

- **舊邊界沒有階差**：福岡原本那一塊 153,600 格裡，高度只有 1 格差 1 m（四捨五入的邊界），水域差 6 格（OSM 比 11-19 新），陡坡差 50 格（都在舊的南緣、東緣那一排：以前邊界外沒有鄰格可比）。跨舊南緣（33.52N）相鄰兩格的高差平均 6.4 m、最大 34 m，跨舊東緣（130.48E）平均 2.1 m、最大 27 m，和往裡 200 格、往外 200 格的同樣量法是同一個量級（油山、三郡山的山坡），不是牆。`FukuokaGroundTests.testTheOldEdgesHaveNoStep` 釘住。
- **新範圍裡有什麼**：筑紫平野（鳥栖、久留米、佐賀東半、大牟田）、有明海、熊本平野與熊本市、阿蘇熊本機場（台地上約 190 m）、佐賀機場；西南角是島原半島東半，最高格 1,457 m 是雲仙的平成新山（1,483 m）。高度 −2 到 1,457 m；陸地 5,607.5 km²（沒有高度的 0.1 km²）、水 1,097.7 km²、陡坡 761.6 km²。有人住的格裡陡坡 0.74 %。
- **機場**：`airfields.json` 現在有三座（福岡 FUK、佐賀 HSG、熊本 KMJ），只是 3D 地圖上畫出來；航線還是只有福岡。
- **記憶體**：整張 5 m 像素約 4.5 億點，一次放不進雲端容器的記憶體，`mean_heights` 改成每 8 排圖磚算一次、把每格的總和與點數累加。
- **鐵道檔**：`track_lines.geojson` 等檔有福岡地鐵三條線與九州新幹線（SHINKANSEN-SALE，決策 975，見下面「九州新幹線」）。
- **還沒做的**：地圖包的名字與資料來源畫面仍寫「福岡」，KUMAMOTO-OPEN 再決定要不要改。

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

## 九州新幹線（博多—熊本，KYUSHU-SHINKANSEN-DATA）

九州新幹線博多到熊本的資料（KYUSHU-SHINKANSEN-DATA，#2667）做好後放在 `tools/fukuoka-map/kyushu-shinkansen/`，**SHINKANSEN-SALE（決策 975）已併進地圖包 `MapPacks/fukuoka/`，遊戲會讀**：日本地圖的第二個系統 `kyushushinkansen`（`OverseasMap.systems`），在收購清單單獨賣。格式與福岡地鐵的檔一樣，工具用 `build_fukuoka_rail.py` 的同一套讀法。

三個步驟，都在 repo 根目錄跑，輸出逐位元可重現（`build_kyushu_shinkansen.py` 一開頭就 import osmium，先 `pip install osmium`）：

```sh
# 1. 只重排一天的班次（改了班距、折返時間時；不讀 N02 與 OSM）。
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py times tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
# 2. 併進地圖包：線、站、站名、橋隧併進地鐵的四個檔，複製 kyushushinkansen.json 與 _times.json，改 pack.json。
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
# 3. 排進 metro_runs.json（地鐵三條線與新幹線一起）。
python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka
```

`build_fukuoka_rail.py` 重寫地鐵的鐵道檔之後，要再跑第 2、3 步。**不要為了新幹線重生地面檔**（高度、水、陡坡、建物；每重做一次 git 多 45 MB）。

從 N02 與 OSM 重做暫存資料夾（線形或車站變了才需要）：

```sh
# N02 與 kyushu.pbf 同上；這裡讀整包九州，不用先切（約 15 秒）。
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py /tmp/fk/n02/N02-25_GML/UTF-8/N02-25_Station.geojson \
  /tmp/fk/osm/kyushu.pbf tools/fukuoka-map/kyushu-shinkansen
```

| 檔案 | 內容 |
|---|---|
| `kyushushinkansen.json` | 一條線 `KS`：7 站（博多、新鳥栖、久留米、筑後船小屋、新大牟田、新玉名、熊本）、線形、站間估計時間、估計班距 |
| `kyushushinkansen_times.json` | 照估計班距排的一天班次（`estimated: true`） |
| `track_lines.geojson`、`track_stations.geojson`、`station_names.json` | 線、站（代碼 `KS01`–`KS07` 是本專案的，JR 九州的新幹線沒有站號）、日文與英文站名 |
| `rail_structures.json` | 高架橋與隧道，一個 OSM way 一筆（66 筆） |
| `depot.json` | 熊本総合車両所（富合）：入出庫線離開正線的點、入出庫線、留置線 |

每次讀了什麼、量到多少寫在 `kyushu_shinkansen_sources.json`。

- **線形**：OSM 的 `railway=rail`、`highspeed=yes`、名字有「九州新幹線」的正線（博多站與最前面約 8 km 和博多南線共用，OSM 的名字兩個都寫）。量到 **98.15 km**，新幹線自己的長度是 98.2 km（工具差超過 2 % 就停）。隧道 37.0 km（筑紫隧道等）、高架與橋 56.4 km、地面 4.7 km。
- **車站與日文站名**：N02（九州旅客鉄道的九州新幹線，取博多到熊本 7 站）。中文站名七個都和日文同字；英文是 JR 九州的羅馬字去掉長音（OSM 把新大牟田、新玉名寫成 `New Omuta`、`New Tamana`，沒用）。
- **班距是估計**：JR 九州沒有公開可再利用的時刻表（沒有 GTFS，官網時刻表不可轉載）。離峰 30 分一班，依據是 2023 年 3 月改點後平日下午博多每小時 01 分、36 分各一班往熊本的「櫻」或「燕」（<https://www.tetsudo.com/news/629/> 的報導）；尖峰 15 分一班、熊本首班 6:00、博多末班 23:10 是本專案的估計。**每一班都各站停**（「燕」的停法），一天 86 班（單向 43）；通過中間站的「瑞穗」「櫻」與直通鹿兒島中央、新大阪的車沒有做（KYUSHU-SHINKANSEN-EXPRESS，之後）。
- **站間時間是估計**：照距離、最高速 260 km/h、加減速 0.45 m/s² 算，再加一成餘裕；博多到熊本含停站 48 分 20 秒（真實的「燕」約 50 分）。每站停 60 秒，博多折返 8 分（`FAR_TURN = 480`）。
- **博多 2 股、折返 8 分**（決策 975）：第一版博多 1 股、折返 12 分，一天晚點 22–24 班：尖峰 15 分一班，下一班在新鳥栖（約 10.5 分前）就要訂博多的進路，前一班還在，遊戲把等著的車趕回熊本的機廠。`extract_fukuoka_runs.py` 用 `TRACKS_AT_LEAST = {"kyushushinkansen:KS": {"博多": 2}}`（`extract_metro_runs.py` 的新參數：某站至少幾股）給博多兩股（真實是 4 面 8 線）。改後 0 班晚點（`CheckupBudgets/Fukuoka.swift`）。
- **機廠在熊本那一端**：`depotEnd` 是熊本，整天從熊本排車（決策 898 的排法），博多不留夜車。**遊戲裡的機廠鋪在熊本站南邊**（`RealLineDepotSite.kumamoto`，「熊本車輛基地」8 股）：待售的線只到熊本站，真實的分岔點在更南 8.45 km；下面的真實位置只是紀錄，線往南開時再用。熊本総合車両所在熊本站南邊：入出庫線在熊本站過去 8.45 km 的 (32.716903, 130.673816) 離開正線，再 1.47 km 到留置線；OSM 畫了 13 股各 288 m。機廠最南到約 32.701N，在新範圍（南緣 32.69N）裡。熊本站到分岔點那 8.45 km 的正線也寫在 `depot.json`（`mainLine`），待售的線只到熊本站。
- **軌距與限界**：線與機廠都寫了 `gaugeMm: 1435`、`loadingGauge: "shinkansen"`、`electrification`、`maxSpeedKmh: 260`，給之後的 TRACK-ELECTRIFICATION 讀；軌距遊戲照系統名鋪（`TrackGauge.ofRealLine`，決策 970、975：1,435 mm 新幹線級），不讀這幾個欄位。
- **節數**：8 節（N700 系「瑞穗」「櫻」的編組，`DemoRealLines.cars(ofSystem:)`），月台 200 m。
- **顏色** `#C8102E` 是本專案選的（JR 九州的紅，比旁邊空港線的橘紅深）；OSM 的路線關係沒有顏色。
