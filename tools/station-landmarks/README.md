# 新車站命名用的地標、道路與路口

實景地圖上建新車站時，800 m 內沒有真實車站，就先看 300 m 內有沒有夠大的地標（大學、高中、醫院、大公園、夜市商圈、百貨），再用聚落、村里、鄉鎮命名；取名欄下另有一排候選（地名、最近的地標、最近的公園、路名、路口名），點一下就換（決策 569，接決策 159）。資料來自 OpenStreetMap（ODbL 1.0），由 `build_station_landmarks.py` 離線讀出，打包成 `RailwayGameApp/Resources/RealWorld/taiwan_station_landmarks.json`，由 `GamePresentation` 的 `StationLandmarks` 讀取（掛在 `PlaceNames.landmarks`）。

## 產生

和其他資料工具同一份台灣整包檔（osmtoday.com 的 `asia/taiwan.pbf`，約 350 MB），需要 pyosmium（`pip install osmium`，BSD 2-Clause；決策 93 同意的依賴），約 2 分鐘。地名檔（`tools/place-names`）的鄉鎮外框用來排除整包檔伸到的福建：

```sh
pip install osmium
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 -I tools/station-landmarks/build_station_landmarks.py taiwan.pbf \
    RailwayGameApp/Resources/RealWorld/taiwan_place_names.json \
    RailwayGameApp/Resources/RealWorld/taiwan_station_landmarks.json
```

## 內容

- `landmarks`：`[緯度, 經度, 種類, 面積（百 m²）, 中文名, 英文名?]`。種類照 `kinds` 的順序：
  - `university`：`amenity=university/college`，名字有「大學、學院、科大、專科」、不是系館或中心，校地至少 2 公頃；
  - `school`：`amenity=school`，名字看得出是高中職（高中、高級、中學、高工、高商…；不收國中、國小），至少 0.5 公頃；
  - `hospital`：`amenity=hospital`，名字有「醫院」，至少 0.4 公頃；
  - `park`：`leisure=park`，名字以「公園」結尾，至少 3 公頃；
  - `market`：名字有「夜市」的 `amenity=marketplace`，以及名字以「商圈」或有「夜市」、不是公車站或車站的地方（點也收）；
  - `mall`：`shop=mall/department_store`，至少 0.3 公頃，不收全聯、小北等連鎖小店。
  - 只畫成點的學校、醫院、商場不收：取名用的是大家知道的地方。
  - 名字是車站會用的短名：去掉「國立、私立、某某市立」，高級中學 → 高中、女子高級中學 → 女中、高級工業職業學校 → 高工等（國立臺灣大學 → 臺灣大學、臺北市立建國高級中學 → 建國高中）。同名的兩處在 600 m 內只留大的。
- `roads`：有名字的 trunk、primary、secondary、tertiary 道路（路、街、大道；不收高速、快速、公路、道路），名字去掉段（南京東路三段 → 南京東路），英文去掉 Section，最長的路在前。
- `ways`：每條路的線（同名相接的 way 接成一條），簡化到約 0.0004°（約 40 m）：`[路的索引, 第一點, 之後每點和前一點的差…]`。
- `crossings`：兩條路共用的節點：`[緯度, 經度, 路 A, 路 B]`，較長的路在前；同兩條路 600 m 內只留一個。路口名（南京東路 × 復興北路 → 南京復興）在 Swift 算（`StationLandmarks.crossingName`），有測試。
- 座標是 1e-5 度（約 1 公尺）的整數。

2026-11-03 的資料（osmtoday.com 的檔，2026-11-03 下載）：地標 1,717（大學 193、高中 414、醫院 199、公園 563、夜市商圈 221、百貨 127），道路 4,175 條名字、12,342 條線，路口 10,591，1.07 MB。

## 為什麼不用公車站牌

作者提過用公車站牌命名。路口名從道路直接算得到；站牌名多半是村里名（已經有）或「捷運某某站」「某某國小」，和現有的重複，或繞回車站自己。見決策 569。
