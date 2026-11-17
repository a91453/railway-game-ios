# TPE-MRT-ELEVATED：淡水信義線高架車站外觀（決策 826）

- 2026-11-17，雲端 project thread「做淡水信義線高架車站外觀」，分支 `claude/project-thread-vqunh2`（遊戲 repo 與素材庫同名）。
  NEXT_PRIORITIES §29.22 第 1 名（3.45），REAL-STATIONS-3D 的第一批。存檔版本、golden schema、GameCore 都不動。
- 作者 11-17 傍晚說還有一點額度，當晚接回遊戲（決策 826 寫好規則與已知缺點）。

## 做到哪裡

- 素材庫 `a91453/railway-assets-private` PR #133，`game-art-previews/docs/art/tpe-mrt-elevated-2026-11/`：
  - `README.md`：工作室派工單。四型 standard（圓山、士林、芝山、明德、石牌、唭哩岸、奇岩）、jiantan、beitou、xinbeitou；
    軌道淨空、預算、色票格位、自查表。§3、§6 已照 Commons 照片改寫：standard 與新北投是**宮殿式**（金黃兩坡長屋頂、兩層簷、
    山牆白搏風板與圓窗、月台層兩側開、簷下紅梁），不是底稿的紅磚盒。
  - `base/`：灰色底稿 GLB（大形起點，改寫自 Slop New York，Copyright (c) 2026 Mr.doob，MIT，https://github.com/mrdoob/slop-newyork ；
    作者 11-17 定：版權只寫 Slop New York）與十站的 OSM 外框（ODbL）。
  - `ref/`：15 張照片（CC BY／BY-SA／CC0，`ref/SOURCE.md`）。作者舊版 `~/SwiftRailMac/assets/分類/` 看過 48 個，沒有可沿用的。
  - `revision-1/`：工作室第 1 輪（8 個 GLB、7 向圖、遊戲大小、總覽）＋審查：**needs-fix**（站體長度以外的淨空）。
- 工作室（作者 Mac）：任務 `tpe-mrt-elevated`，做的人 Codex A（額度快用完，用完換 Codex B `--profile pro` 接手，作者 11-17 指示），
  審查 Claude Pro。**三輪做完，第 3 輪 pass**（素材庫 `1e711b08`，`revision-3/`：8 個 GLB、7 向圖、`game-size.jpg`、
  `overview.jpg`（含照片，只留素材庫）、`review/r3-verify.md`、重建腳本）。三角形 近／遠：standard 3,824／1,432、劍潭 4,036／1,628、
  北投 4,442／2,106、新北投 3,364／1,524。工作室任務已 release、session 全關。
- 審查列的已知缺點（接回時決定修或列進決策 826）：照現行決策 625 切法劍潭剩 45.5%、新北投剩 3.9% 會整站不畫（所以一定要改成只切淨空盒）；
  模型的 `deck`、`pier` 和遊戲自己的高架面、墩柱重疊，二選一（建議拿掉模型的）；北投屋頂與石塊同色太近、桁架玻璃是黑格（照片是亮銀網）；
  新北投牌樓偏小、屋頂沿長向幾乎不出簷；金頂 #EBD099 比照片淡（沒加新色，用簷口深線分開）；士林八角窗沒做；北投、新北投沒有空拍照片。

## 已接回遊戲（11-17）

- `Sources/GamePresentation/Map3DTaipeiMRTStations.swift`：十站、四型、對齊規則（決策 826 的 1–6 條）；
  `Map3DStations.swift` 的 `addStations` 先找出有外殼的站，那些站不畫 kit 雨棚與站房。
- `Map3DTaipeiMRTStationMeshes.swift`：由 `tools/tpe-mrt-stations/glb_to_swift.py` 從素材庫 `revision-3/*.glb` 產生，不要手改。
- `Tests/GamePresentationTests/Map3DTaipeiMRTStationsTests.swift`：預算、淨空、「切到就紅」、彎站、新北投山牆、軌面與地面。
- 資料來源頁加 `slopNewYork`（只寫 Slop New York、Mr.doob、MIT）。

## 接下來

1. 新外觀：總覽圖給規劃看過才合（決策 482）。
2. 淡水線真實場景的測試：照 `Map3DStationExteriorsTests` 的 `DemoRealLinesTrackReportTests.game(at:in:half:)` 量十站，
   確認每站都有外殼（不是因彎站或高度退回 kit）、淨空零切到；遊戲線形若只有一股，中線要改取上下行兩股。
3. 已知缺點（決策 826）：北投顏色與桁架玻璃、新北投牌樓、金頂偏淡、士林八角窗、模型高架面與遊戲高架橋重疊、窗夜裡不亮、跨區塊。
   要改模型就回工作室開第 4 輪（素材庫同一資料夾），再重跑 `glb_to_swift.py`。

## UNVERIFIED

- 只在 Linux 跑過建置與 `Map3DTaipeiMRTStationsTests`；沒有在 App、Simulator 或實機看過。
