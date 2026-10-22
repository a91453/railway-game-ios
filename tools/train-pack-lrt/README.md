# 列車包的五節、七節輕軌：每節怎麼切（決策 338 續）

畫出輕型捷運（`C`）兩節、三節時，3D 地圖實際會怎麼擺這兩台輕軌：每節照 `Map3DTrains.instance` 拉到 19 m − 0.6 m，節間留 0.6 m；另畫一份每節多轉 0.12 弧度的急彎。幾種切法都畫，`docs/art/train-pack-lrt-2026-10-22/` 是結果。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
bin="$(swift build --show-bin-path)"
swiftc -swift-version 6 -I "$bin" tools/train-pack-lrt/export.swift "$bin/libGamePresentation.a" "$bin/libGameCore.a" -o OUT/export
OUT/export OUT                      # 印出每節長度、拉伸、三角形數
node tools/train-pack-lrt/render.mjs OUT
python3 tools/train-pack-lrt/sheet.py OUT five.png "標題=five-A-mid-side,five-A-mid-joint,five-A-mid-curve-jointOut" ...
```

`export.swift` 用 `@testable import`，所以要 debug 版（`swift build` 預設）。Chromium 用 `/opt/pw-browsers`（或 `CHROMIUM_PATH`），playwright 從全域 node_modules 讀（或 `NODE_GLOBAL`）。WebGL 的圖不代表 iPhone 的 Metal。
