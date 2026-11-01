# 竹中六家線彎道月台的列車（決策 538）

`overview.jpg`：左邊是改之前的放法，右邊是這次的放法；上排從上方看，下排從斜後方看。實景新局在竹中，收購內灣線與六家線，06:01 兩列 EMU900 停在架高的彎道月台（決策 462）。改之前，最後一節（畫面右下）直直伸出彎道、懸在高架外；改之後每節兩端都在軌道上。

- 做法：`tools/map3d-preview` 的 `Map3DPreviewDump`，加一個 `zhuzhong` 世界與畫出世界裡的列車（只在本機用，沒有提交），`MAP3D_HEIGHTS=1`、`MAP3D_CROP=20:5:450`，鏡頭 `close:22:4:95:150:93;top:22:4:110:90:93`。
- 「之前」是同一個分支上暫時把 `TrainCars` 的 `track` 關掉、高度只用車身（就是 main 的放法），只改這一件事，沒有另開 main 的 worktree。
- WebGL 預覽，不是 Metal、不是 iPhone 的畫面；實機 UNVERIFIED。
