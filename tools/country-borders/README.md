# 國界（決策 154）

`build_country_borders.py` 從 Natural Earth 1:50m 的國家（admin-0，v5.1.2，公有領域）取出遊戲有國定假日的 24 國，把每一圈國界簡化到約 1 公里（Douglas-Peucker，0.01°），四捨五入到千分之一度，寫成 `Sources/GamePresentation/CountryBorders.swift`（每國一個 base64 字串）。GamePresentation 的 `CountryLookup` 用它判斷實景地圖在哪一國。

只用 Python 標準函式庫。資料檔放在 scratchpad，不進 repository：

```sh
curl -sSfL -o /tmp/ne_50m.geojson https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_50m_admin_0_countries.geojson
python3 -I tools/country-borders/build_country_borders.py /tmp/ne_50m.geojson Sources/GamePresentation/CountryBorders.swift
```

輸出：24 國、26,825 點、約 111,000 字元。國家取 `ISO_A2_EH`（`ISO_A2` 是 `-99` 時，例如法國）。新增有假日的國家時，同時加進 GameCore 的 `HolidayCalendar.countries` 與這支工具的 `COUNTRIES`（`CountryLookupTests` 檢查兩邊一致）。

授權：Natural Earth 是公有領域（「Made with Natural Earth」），不需要標示。
