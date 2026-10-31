# 生成的房子沿路排：辦公、公共與休閒的低密度地塊（決策 516）

作者 99.1 的回報：宜蘭平原小鎮外圍，遊戲自己的房子每 64 m 一棟、在格子正中間，不理旁邊的路。

兩張圖都是上半 `main`（94fd338）、下半這個分支，`tools/map3d-preview/` 畫的（WebGL，不是 Metal）：
高鐵示範的世界讀進 24.6478 N、121.7121 E（羅東西邊的平原，GameCore 在這裡有 155 格公共用地）周圍 3 km 的人口與分區，
App 的底圖、足跡與不蓋區都打開，14:00。

- `before-after-wide.png`：鏡頭距離 800 m。上半每格中間一棟診所、學校或消防隊；下半沿路一排。
- `before-after-close.png`：鏡頭距離 300 m。

指令（`tools/map3d-preview/README.md`，加一個讀 `LAT`／`LON` 的 `here` 世界，同 `xiaogang` 的寫法）：

```sh
MAP3D_DUMP=/tmp/s MAP3D_WORLD=here LAT=24.6478 LON=121.7121 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_NOBUILD=1 \
  MAP3D_CROP=0:0:900 MAP3D_VIEWS="wide:0:0:800:25;close:40:-40:300:20" swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/s /tmp/png wide,close
```
