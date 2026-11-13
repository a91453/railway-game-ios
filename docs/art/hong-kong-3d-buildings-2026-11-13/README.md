# 香港 3D 地圖的建物（決策 712「續四」）

`overview.png`：上半是中環（買下機場快綫，香港站在中間），下半是九龍（油麻地、旺角到西九龍）。建物來自地圖包的 `buildings.pmtiles`（OpenStreetMap，`tools/hk-map/build_hk_buildings.py`）。

WebGL 預覽（`tools/map3d-preview/`，下午兩點的光線），不是 Metal、不是 iPhone 的畫面；模擬器的截圖在 PR 的 `testHongKongMap`。

重做：

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/hk/central MAP3D_WORLD=hongkong MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_BUY=hkmtr:AEL \
  MAP3D_AT=22.2850:114.1582 MAP3D_VIEWS="mid:0:0:1200:20" MAP3D_CROP=0:0:3500 swift test --skip-build --filter Map3DPreviewDump
MAP3D_DUMP=/tmp/hk/kowloon MAP3D_WORLD=hongkong MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_BUY=hkmtr:AEL \
  MAP3D_AT=22.3120:114.1680 MAP3D_VIEWS="far:0:0:3000:200" MAP3D_CROP=0:0:3500 swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/hk/central /tmp/hk/central mid
tools/map3d-preview/render.sh /tmp/hk/kowloon /tmp/hk/kowloon far
rm Tests/GamePresentationTests/Map3DPreviewDump.swift
```
