# 真實建物稀疏的街廓補沿街的房子：改之前與改之後（2026-11-13）

[決策 723](../../decisions/723.md)。`overview.jpg`：左改之前、右改之後；由上到下是高雄車站正上方（1,100 m）、高雄車站斜看（600 m）、台北車站、斗六車站。

Mac 上的 WebGL 預覽（`tools/map3d-preview/`，不是 Metal）：App 新局讀的真實人口與分區、底圖、城市圖塊、真實足跡、不蓋區。三個地方的 `MAP3D_AT` 是 `22.6394:120.3024`、`25.0478:121.5170`、`23.7117:120.5413`。

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/ks MAP3D_WORLD=island MAP3D_AT=22.6394:120.3024 MAP3D_BASEMAP=1 MAP3D_CITY=1 \
  MAP3D_FOOTPRINTS=1 MAP3D_NOBUILD=1 MAP3D_HEIGHTS=1 MAP3D_CROP=0:0:1500 \
  MAP3D_VIEWS="st:0:0:600:30;top:0:0:1100:0" swift test --skip-build --filter Map3DPreviewDump
rm Tests/GamePresentationTests/Map3DPreviewDump.swift
```

「改之前」是同一個分支把 `Map3DScene.Builder.RealCover.thinShare` 暫時設成 0（並跳過讓開外框的檢查）輸出的；合併 #2138 之前比過，這樣的輸出和 main 逐位元組相同。兩邊都含 #2138（高雄車站地標只清模型底下的格子）。

高雄車站正西、正東緊鄰的幾塊改之後仍是空的：那裡沒有可臨街的路，見決策 723 第 1 節。
