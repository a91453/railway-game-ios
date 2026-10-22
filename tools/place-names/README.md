# 新車站命名用的地名

實景地圖上建新車站時，附近 800 m 內沒有真實車站，就用所在的聚落、村里或鄉鎮市區命名（ARCHITECTURE 決策 159，移植 MapBuilder 的自動命名）。名字來自 OpenStreetMap（ODbL 1.0），由 `build_place_names.py` 離線讀出，打包成 `RailwayGameApp/Resources/RealWorld/taiwan_place_names.json`，由 `GamePresentation` 的 `PlaceNames` 讀取。

## 產生

和其他資料工具同一份台灣整包檔（osmtoday.com 的 `asia/taiwan.pbf`，約 350 MB），需要 pyosmium（`pip install osmium`，BSD 2-Clause；決策 93 同意的依賴），約 1 分鐘：

```sh
pip install osmium
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 tools/place-names/build_place_names.py taiwan.pbf \
    RailwayGameApp/Resources/RealWorld/taiwan_place_names.json
```

## 內容

- `places`：聚落（`place` = hamlet、village、locality、neighbourhood、isolated_dwelling、quarter，有名字的點）；和村里同名的點只是村里的標籤，略過。
- `wards`：村里（`admin_level` 9），外框範圍的中心點，名字去掉「村、里」。
- `townships`：鄉鎮市區（`admin_level` 7、8）的外框，簡化到約 0.0003°（Douglas-Peucker），名字去掉「鄉、鎮、市、區」（只剩一個字時保留，例如北區）。
- 每個鄉鎮的 `county`：它屬於的縣市（決策 332，實景地圖的旅客最多有多少改騎機車或開車）。照行政區代碼（`nat_ref`）判斷，不照外框：鄉鎮的代碼開頭就是縣市的（鳳山區 64000120 → 高雄市 64；直轄市兩碼、其他縣市五碼）。高雄市的外框在抽出檔裡接不起來，縣市交界上的鄉鎮也會同時落在兩個外框上。沒有代碼的鄉鎮看 `is_in:city`、`is_in:county`。
- 座標是 1e-5 度（約 1 公尺）的整數，外框的點記和前一點的差。
- 只收台灣的：整包檔伸到福建，那裡的行政區用簡體字，依字尾排除。

2026-10-22 的資料（osmtoday.com 的檔，OSM 資料到 2026-10-18）：聚落 16,626、村里 7,779、鄉鎮市區 367（旗津區的外框在 OSM 是斷的，讀不出來），每個鄉鎮都有縣市（22 個），1.54 MB。之前一版是 2026-10-11 的（OSM 資料到 2026-10-07，聚落 16,627、村里 7,772）。
