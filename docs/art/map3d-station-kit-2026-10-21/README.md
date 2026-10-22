# 3D 的車站用車站套件蓋（決策 321）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `1-taipei-taipei.jpg` 和文字紀錄；其他 7 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map3d-station-kit-2026-10-21/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

無頭 Chromium 的 WebGL 預覽（決策 238，`tools/map3d-preview/`），每張左邊是 main、中間是這個 PR、右邊是 pixelmatch 的差異（`tools/map3d-preview/diff.cjs`，紅色是不同的像素）。

| 圖 | 地圖 | 看什麼 | 不同的像素 |
| --- | --- | --- | ---: |
| `1-taipei-taipei.jpg` | 穿過臺北車站的一條線（`MAP3D_WORLD=taipeiline`，實景底圖） | 臺北代表站的紅色環形屋頂取代城市的大樓，月台上的曲頂雨棚 | 30.12% |
| `2-taipei-taipeimid.jpg` | 同上，450 m | 站前的廣場 | 8.12% |
| `3-keelung-keelung.jpg` | 實景示範（`realdemo`） | 基隆代表站的拱頂站房；會壓到底圖的道路（缺口） | 6.55% |
| `4-ruifang-ruifang.jpg` | 實景示範 | 一般站型：站房在月台那側，兩座月台的雨棚 | 3.86% |
| `5-demo-central.jpg` | 示範地圖 | 中央站有高架線交叉：站房沿月台滑開，不在高架底下 | 11.52% |
| `6-demo-west.jpg` | 示範地圖 | 西站 | 12.65% |
| `7-demo-all.jpg` | 示範地圖全景 | 每個站的站房與雨棚 | 4.06% |
| `8-option-flat-canopy.jpg` | 沒有選的做法 | 上排保留平板雨棚、只加站房；下排是這個 PR | — |

重做：

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_DUMP=/tmp/taipei MAP3D_WORLD=taipeiline MAP3D_HEIGHTS=1 MAP3D_BASEMAP=1 MAP3D_CROP=0:0:700 \
  MAP3D_VIEWS="taipei:0:0:200:30:6;taipeimid:0:0:450:-25:6" swift test --skip-build --filter Map3DPreviewDump
tools/map3d-preview/render.sh /tmp/taipei /tmp/png-taipei taipei,taipeimid
```

瑞芳 `ruifang:2404:-3121:180:30:58`、基隆 `keelung:-4386:-5801:180:30:9`（`MAP3D_WORLD=realdemo`，`MAP3D_CROP` 同中心、700）；示範地圖 `west:-64:0:150:35;central:32:0:150:-30;all:0:30:420:-25`。
