# 3D 的架空線（決策 326）

無頭 Chromium 的 WebGL 預覽（決策 238，`tools/map3d-preview/`），有貼圖的那一版。

| 圖 | 看什麼 |
| --- | --- |
| `overview.jpg` | 四張縮圖：車站、高架、環狀彎道、猴硐 |
| `station.jpg` | 示範地圖的車站：月台那一側沒有桿，另一邊才有；高架上的桿立在橋面邊 |
| `viaduct.jpg` | 高架的端點：桿、腕木、接觸線與吊線近看 |
| `ring.jpg` | 半徑 300 m 的彎道：桿立在外側，間距縮到約 25–30 m，線是一段段的弦 |
| `houtong.jpg` | 猴硐（實景示範，宜蘭線）：有電的臺鐵，桿立在沒有鄰軌的那一側 |
| `option-900-kit.jpg`、`option-900-row.jpg` | 沒有選的做法：#900 的透天厝（獨棟、四面開窗、底座寬）與排成一排的樣子；現在的地塊見 `docs/art/map3d-arcade-life-2026-10-17/close.jpg` |

十分、大華（平溪線，柴油支線）的預覽裡沒有任何一根桿；那一帶的軌道在高度檔的地面下（原有問題），圖沒有放。

重做：

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
env MAP3D_DUMP=/tmp/demo MAP3D_WORLD=demo 'MAP3D_VIEWS=viaduct:0:-144:60:40;ring:-200:50:60:300;station:0:30:90:120' \
  swift test --skip-build --filter Map3DPreviewDump
NODE_PATH="$(npm root -g)" tools/map3d-preview/render.sh /tmp/demo /tmp/png-demo viaduct,ring,station
```

猴硐 `houtong:4484:-678:90:30:111`（`MAP3D_WORLD=realdemo MAP3D_HEIGHTS=1 MAP3D_BASEMAP=1`，`MAP3D_CROP` 同中心、700）；十分 `shifen:-757:4440:90:30:182`。
