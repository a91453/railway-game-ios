# JAPAN-FUKUOKA-1：日本第一張地圖（福岡）的鐵道資料

- 派工：協調者（工作串「開始做日本地圖」），2026-11-18，雲端 thread session，分支 `claude/project-thread-ankqzn`。
- 決策 854（`docs/decisions/854.md`）。存檔版本、golden、replay、GameCore：不動。
- 做了：`tools/fukuoka-map/`；地圖包 `MapPacks/fukuoka/`（只有鐵道，0.8 MB）；`OverseasMap.fukuoka`（**沒有**加進 `OverseasMaps.open`，沒有 AssetPacks 清單）；資料來源頁的福岡一節（打開後才列）；`FukuokaRailwaysTests`。
- 評分：私有 `railway-assets-private-2` 的 `docs/priorities/JAPAN-MAP.md`（選區四候選、後續六項、羅瓦涅米雪橇彩蛋）。

## 還留下的（照順序，一項一串）

1. **FUKUOKA-GROUND**（2.85）：底圖、地形、水域、人口、機場、不蓋區、建物，照 `tools/rovaniemi-map/README.md` 的 3–6 步。
   - 九州的 OSM 全包：`https://osmtoday.com/asia/japan/kyushu.pbf`（354 MB，雲端下載約 2 分）；`apt-get update && apt-get install -y osmium-tool` 才裝得到。**不要用 pyosmium 直接掃全包**（單執行緒跑超過 10 分還沒完），先 `osmium extract` 切範圍（13 秒）。
   - 人口：WorldPop 日本，或国土数値情報 mesh1000（CC BY 4.0）；N05 是非商用，**不能用**。
   - 地形：Copernicus GLO-30（羅瓦涅米用的）或國土地理院 DEM（授權要查）。
   - 範圍 `EXTENT` 已含北邊的西鐵貝塚線（到北緯 33.72）。
   - 現在沒有高度檔，`FukuokaRailwaysTests` 給遊戲一片 5 m 高的平地（`flat()`）才鋪得了線；有了 `heights.dat` 之後改讀地圖包的高度、拿掉 `flat()`。
2. **FUKUOKA-OPEN**（3.15）：開關。
   - `OverseasMaps.open` 加福岡；`AirportCatalog` 加福岡機場（`fuk`）與台灣各機場往返的航線（民航局表 50-x 的 2025 年數字），航班開圖（決策 712、763）。
   - 分包下載：照 PACK-OUT 定案的做法（香港、羅瓦涅米實機兩列都「已下載」後），能只下載就不內建；`MapPackDownloadsTests` 會要求開了的城市有清單。
   - 共站綁賣：三條線在博多、中洲川端共站，等「收購改共線綁賣」那串（淡海兩線、六家＋內灣、香港機場三綫）合併後，福岡三線是一組。
   - `economy-balance` 量價格與回本：**新局與擬實兩種規則都量，並且一定要跑機捷**（看共用的規則沒有被改壞）。
   - 時刻表體檢（決策 844、`TimetableCheckupAllBoughtTests`）加福岡三線；共站的三條要一起買來測。
   - 網站 `credits.html` 加福岡（reference-private），發版後才合。
3. **FUKUOKA-TRAINS**（3.00）：地鐵三線的車交工作室。簡化造型、不用官方車名（日本鐵道公司常收商品化授權），先找 Chien 舊版與私有庫有沒有類似的。開圖前先用現成的通用捷運車。
4. **NISHITETSU-KAIZUKA**（2.40）：西鐵貝塚線（OSM 關係 9436788，N02 `西日本鉄道` `貝塚線`，11.3 km、10 站），在貝塚和箱崎線共站。
5. **FUKUOKA-THROUGH**（2.15）：箱崎線直通空港線到姪濱、空港線直通 JR 筑肥線（地圖邊界進出，照羅瓦涅米往穆羅拉的車）。
6. **FUKUOKA-DEPOT**（沒評分）：七隈線真實的機廠在橋本、空港線在姪濱。有了機廠，七隈線尖峰可以改回最短的 3 分（現在 3 分 15 秒，README 有原因）。

## 這次參考了哪些香港、芬蘭的教訓

| 教訓（出處） | 這次怎麼做 |
| --- | --- |
| 第一次做大地圖要分開（作者 11-18） | 只開福岡市一區，約 17.6 × 22.2 km，比香港的 63 × 45 小；全國的 N02 只拿來挑區 |
| 機場開圖（決策 712、763；作者 11-18） | 選區時把「機場在鐵路上」列進評分；`opensByFlights` 為 `true`，到達點是福岡機場站；航線留給開關那一張 |
| 開關先關、資料先合（羅瓦涅米 MAP-1，決策 789） | 不加進 `OverseasMaps.open`、不加 AssetPacks 清單，玩家與手機都看不到 |
| 地圖資料要能下載、不要內建（PACK-OUT，記憶 rovaniemi-map） | 地圖包照現在的格式放在 `Resources/MapPacks/`（下載與內建同一個資料夾）；改成只下載等 PACK-OUT 定案，寫在上面第 2 項 |
| 共站的線綁在一起賣（作者 11-18 14:39） | 博多、中洲川端共站，三條線開圖時是一組；等綁賣那串 |
| 雙語站名（決策 845，STATION-BILINGUAL） | `station_names.json` 每站有英文（`en`）與日文原名（`ja`）；中文是正體字；測試釘住每站都有英文名 |
| 時刻表體檢要涵蓋新線（決策 844、TIMETABLE-CHECKUP-ALL） | 寫進開關那一張；這一步各線先買來跑一整天、0 分鐘死結（`FukuokaRailwaysTests`） |
| 新局與擬實都要量、一定要跑機捷（HEALTH、TYMCLIST 系列） | 寫進開關那一張；這一步不動 GameCore，所以沒有量 |
| 香港沒有公開時刻表時用估計班距（決策 697） | 同樣：尖峰照福岡市新聞稿，其餘估計，檔案寫 `estimated` |
| 只補在售路線真的有跑的車（FINLAND-TRAINS） | 車輛只列地鐵三線，交工作室；日本車避官方車名 |
| 下載坑（香港 CSDI 403、芬蘭 MML 要金鑰） | N02、osmtoday 雲端都下得到；九州全包不要用 pyosmium 直接掃 |
| 工作室模型經驗（assets-2 `docs/studio/lessons/` 港鐵各綫、馴鹿） | 這一步沒做模型；FUKUOKA-TRAINS 開工前先讀（車頭三向輪廓、主要零件顏色對照片、玻璃逐面標） |

## UNVERIFIED

- 雲端 Linux 跑過：`swift build --build-tests -Xswiftc -warnings-as-errors`、`FukuokaRailwaysTests`（結果見 PR）。
- 沒在 iOS Simulator、iPhone 上看過：開關關著，玩家看不到；3D 裡的隧道與地下車站沒看過。
- 價格與平衡沒量；只有鐵道、沒有人口，運量沒意義。
