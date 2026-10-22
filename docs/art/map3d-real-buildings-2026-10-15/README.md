# 3D 地圖的真實建物（2026-10-15）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `kaohsiung-mid.jpg` 和文字紀錄；其他 5 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map3d-real-buildings-2026-10-15/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

ARCHITECTURE 決策 239：高雄車站、臺中車站周圍 1.5 × 1.5 km 的真實建物，讀 3D 城市預覽的圖塊（Overture Maps 的足跡、樓層與用途），用本專案的畫風拉高。

圖是 `tools/map3d-preview/` 的軟體算圖（WebGL 照 `Map3DShaders.metal` 的算式），地圖是以車站為錨點的空白實景新局（`MAP3D_WORLD=kaohsiung`、`taichung`，`MAP3D_BASEMAP=1`）。**不是 Metal、不是 iPhone 的畫面**（UNVERIFIED），要等 TestFlight。

| 圖 | 看什麼 |
| --- | --- |
| `kaohsiung-mid.jpg` | 高雄車站，700 m。上：沒有圖塊（#670）；下：真實建物，車站的大屋頂是柱子上的頂蓋 |
| `kaohsiung-close.jpg` | 高雄車站，260 m。上、下同上 |
| `kaohsiung-street.jpg` | 高雄車站東南的街上，180 m |
| `taichung-mid.jpg` | 臺中車站，700 m。上、下同上 |
| `near-far.jpg` | 高雄，1.5 km。上：近版；下：遠版（決策 238，少了屋頂機房） |
| `options.jpg` | 選項。上：A，本專案的畫風（選這個）；下：B，網站 3D 城市預覽那種單一灰色的量體 |

## 三角形（整個場景）

| 地圖 | 沒有圖塊 | 真實建物 |
| --- | --: | --: |
| 高雄，近版 | 37,460 | 77,413 |
| 高雄，遠版 | 33,600 | 65,203 |
| 臺中，近版 | 47,492 | 85,987 |
| 臺中，遠版 | 36,994 | 73,317 |
