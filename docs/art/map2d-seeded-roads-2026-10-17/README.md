# 空白地圖的 2D 種子道路（決策 270）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `zoom-10.jpg` 和文字紀錄；其他 1 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map2d-seeded-roads-2026-10-17/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

**這不是 App 的畫面**：Linux 上沒有 SwiftUI，這兩張是用 Python 依 `Map3DScene.seededStreets` 算出的同一份道路、`CitySkyline` 的地塊與軌道畫的近似圖。配色與寬度照 `MapArt.drawStreets`，建物只畫平面的地塊。App 的畫面要在 Simulator 或實機看。

兩鎮地圖第一個城鎮的中心。每張都是上半 `main`（2D 沒有道路，這就是沒有選的「不畫」），下半新版。

- `zoom-10.jpg`：64 m 格子 40 點（每 16 m 10 點）。主要道路、街、巷照真實寬度，白色路面加淺色邊線，和實景 2D 地圖的道路一樣。有些地塊之間沒有路，合成一個街廓；巷子在鐵路前停住，主要道路與一半的街越過鐵路（平交道）。
- `zoom-25.jpg`：64 m 格子 100 點（每 16 m 25 點），接近雙指交給 3D 的比例（決策 269）。這時交給 3D，3D 裡是同一份道路。

16 點以下不畫，16–24 點之間淡入，拉遠時地圖不會變成密密的格子。
