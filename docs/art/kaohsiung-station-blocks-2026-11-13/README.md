# 高雄車站周圍的街廓：改之前與改之後（2026-11-13）

決策 431 的「後來」。`overview.jpg`：左改之前、右改之後；上排正上方看（1,100 m），下排斜看（600 m）。

Mac 上的 WebGL 預覽（`tools/map3d-preview/`，不是 Metal）：App 新局讀的真實人口與分區、底圖、城市圖塊、真實足跡、不蓋區。

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/ks MAP3D_WORLD=island MAP3D_AT=22.6394:120.3024 MAP3D_BASEMAP=1 MAP3D_CITY=1 \
  MAP3D_FOOTPRINTS=1 MAP3D_NOBUILD=1 MAP3D_HEIGHTS=1 MAP3D_CROP=0:0:1500 \
  MAP3D_VIEWS="st:0:0:600:30;top:0:0:1100:0" swift test --skip-build --filter Map3DPreviewDump
rm Tests/GamePresentationTests/Map3DPreviewDump.swift
```

「改之前」是同一個分支把 `Map3DTaipeiLandmark.clearsOnlyUnderItself` 暫時改成 `false` 輸出的。
