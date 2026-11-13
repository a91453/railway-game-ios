# HK-GROUND：香港的地形與水域

- 派工：遊戲規劃第 65 任（2026-11-13），雲端 thread session，分支 `claude/project-thread-3r2lp3`。
- 決策 726（`docs/decisions/726.md`）。存檔版本、golden、fixtures、GameCore：不動。
- 做了：`tools/hk-map/build_hk_ground_grids.py`；地圖包加 `heights.dat`、`water.json`、`terrain.pmtiles`；香港開局讀香港自己的高度與水域、開局有地面；2D 地圖的香港山影；`DataSourceCredits` 的「香港的地形」；`HongKongGroundTests`，`HongKongMapTests` 的香港局改成站在地面上。
- 資料在作者 Mac 的 `~/Developer/hk-ground-downloads/`（`hk_dtm.zip`、`hong_kong.pbf`）。雲端連 `static.csdi.gov.hk`、`osmtoday.com` 都 403。

## UNVERIFIED

- 雲端沒有 Swift，本機沒有建置與測試，全交 CI。
- 3D 與 2D 的樣子沒有截圖、沒有實機看過。照任務單屬第三級：`testHongKongMap` 重拍，加一張看得到太平山與維多利亞港的，規劃看過才合。

## 留下的

- 截圖（上一條）。
- 下一張香港資料單：HK-BUILDINGS-GOV（DATA_PRIORITY §6.2），建物站到這次的地面上一起看。
