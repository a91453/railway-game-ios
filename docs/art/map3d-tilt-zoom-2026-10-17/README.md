# 拉近就傾斜（決策 269）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `tilt-170m.jpg` 和文字紀錄；其他 2 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map3d-tilt-zoom-2026-10-17/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

用 `tools/map3d-preview` 畫：WebGL 照 `Map3DShaders.metal` 的算式重畫，不是 iPhone 的畫面。兩鎮地圖、下午 2 點，同一個中心、方向 20°。每張都是上半 `main` 的傾斜曲線（300 m 以內 55°），下半新的曲線（800 m 以外平視，150–200 m 約 34–40°，最多 42°）。

- `tilt-170m.jpg`：170 m。上半 55°，斜得多，遠處一路排到畫面頂；下半約 38°，街廓與立面都看得清楚，是作者目標畫面的角度。上半就是沒有選的「舊曲線」。
- `tilt-450m.jpg`：450 m。上半約 50°，接近最大；下半約 9°，剛開始傾斜。
- `tilt-800m.jpg`：800 m，2D 地圖交給 3D 的距離。上半約 30°，交接時畫面會跳；下半正上方往下看，和 2D 地圖同一個方向與比例。

交接本身（2D 雙指拉近時變成 3D）要在 Simulator 或實機上看：新的 UI 測試 `MapInteractionTests/testPinchingCloseOpensTheThreeDMapAndPinchingOutComesBack` 在 full lane 檢查它。
