# 鄉間的地表覆蓋（決策 811）

`overview.png`：花蓮縱谷 23.60, 121.40 的實景新局，`tools/map3d-preview` 的 WebGL 預覽（不是 Metal、不是 iPhone 的畫面）。上排沒有地表覆蓋，下排讀 `taiwan_landcover.dat`：OpenStreetMap 沒畫的山坡從灰白的平地變成淡綠的森林地面，上面有樹。左到右：遠景（2600 m）、森林邊（700 m）、山坡（700 m）。

上排是同一個分支不設 `MAP3D_LANDCOVER`，所以 OSM 林地裡低處的闊葉樹（這個分支加的）上下都有。

重做：

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/after MAP3D_WORLD=island MAP3D_AT=23.60:121.40 MAP3D_BASEMAP=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 \
  MAP3D_CROP=0:0:2500 MAP3D_VIEWS="far:0:0:2600:20;edge:1100:0:700:20;edge2:1300:400:700:20" \
  swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/after /tmp/after far,edge,edge2
rm Tests/GamePresentationTests/Map3DPreviewDump.swift
```
