# 3D 的站前商店街（決策 322）

無頭 Chromium 的 WebGL 預覽（決策 238，`tools/map3d-preview/`），有影子的那一版。「前」是 main 加 #922（決策 321 的車站），「後」是這個 PR。

| 圖 | 看什麼 |
| --- | --- |
| `1-overview.jpg` | 前後對照：示範地圖西站、瑞芳、猴硐（實景示範）；最下排是站前對面那一排的近看與夜景（招牌亮、窗不亮） |
| `2-close.jpg` | 瑞芳、猴硐近看：站房兩側與站前對面的店，最高的一間在離車站最近處 |
| `3-option-flat-awning.jpg` | 沒有選的做法：左邊是這個 PR 的條紋斜雨遮，右邊是 #900 的平頂單色雨遮 |
| `4-diff.jpg` | pixelmatch 差異（`tools/map3d-preview/diff.cjs`，紅色是不同的像素）：示範地圖西站、瑞芳；只有店的地方變了 |

不同的像素：示範地圖西站 13.05%、東站 6.72%、全景 0.89%、瑞芳 3.87%、猴硐 3.56%。

重做：

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
env MAP3D_DUMP=/tmp/demo MAP3D_WORLD=demo 'MAP3D_VIEWS=west:-100:-40:50:20;east:35:231:50:20;all:0:30:420:-25' \
  swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/demo /tmp/png-demo west,east,all
```

瑞芳 `ruifang:2404:-3121:90:30:58`、猴硐 `houtong:4484:-678:90:30:111`（`MAP3D_WORLD=realdemo MAP3D_HEIGHTS=1 MAP3D_BASEMAP=1`，`MAP3D_CROP` 同中心、700）。夜景加 `MAP3D_MINUTE=1320`（22:00）。
