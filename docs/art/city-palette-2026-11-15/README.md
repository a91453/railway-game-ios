# 城市建築色票擴充：改前改後（決策 764）

`overview.jpg`：左改前、右改後。上：台北小巨蛋一帶遠景；中：高雄巨蛋一帶遠景；下：台北小巨蛋近景。

用 `tools/map3d-preview` 畫（WebGL，照 `Map3DShaders.metal` 的算式，不是 Metal、不是 iPhone）：

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/tpe MAP3D_WORLD=island MAP3D_AT=25.0516:121.5497 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 \
  MAP3D_CROP=0:0:900 MAP3D_VIEWS="wide:0:0:700:30;near:0:0:320:30" \
  swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/tpe /tmp/tpe wide,near
```

高雄巨蛋是 `MAP3D_AT=22.6693:120.3029`。改前是 `origin/main` `2c038b9` 的三個來源檔。

旁邊的台北田徑場（橢圓形）是地標模型，不走城市色票，這次沒有變。
