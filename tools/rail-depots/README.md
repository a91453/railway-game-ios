# 真實機廠的位置

決策 479：收購真實路線時，一起蓋出它真實的機廠。`depot_site.py` 從一整包台灣的 OpenStreetMap 檔讀出機廠的位置：入出庫線從正線分出的地方，以及停車線的近端與遠端。這些數字存在 `Sources/GamePresentation/RealLineDepot.swift` 的 `RealLineDepotSite`。

```sh
pip install osmium        # BSD 2-Clause，決策 93
curl -LO https://osmtoday.com/asia/taiwan.pbf
python3 -I tools/rail-depots/depot_site.py taiwan.pbf
```

約 1 分鐘。資料是 OpenStreetMap 貢獻者的，授權 ODbL 1.0；遊戲的資料來源畫面已經標示 OpenStreetMap。

2026-10-29 用的是 osmtoday.com 的整包檔：

- 三峽機廠（way 619043484）：入出庫線在橫溪與龍埔之間的渡線（way 1156270818）離開正線，停車線（way 1136774767、1136774768）在正線西南方約 200 到 500 m。
- 三鶯線的 19 個月台面，每個長 40.1 到 41.7 m。

新北市捷運局的資料寫三峽主機廠可停 33 列，線上只在兩端站（LB01、LB14）停車過夜。遊戲的機廠每股停一列，所以只鋪了 4 股，剛好放下真實時刻表留在中間站過夜的 4 列。
