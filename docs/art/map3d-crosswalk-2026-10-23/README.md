# 斑馬線與車道箭頭的修正（決策 370，2026-10-23）

`crosswalk.jpg`：台北的新局，台北車站南邊的路口，鏡頭 85 m。左為改前（main），右為改後；上排 14:00，下排 21:00。改前晚上的斑馬線和箭頭是比路面暗的方塊，白天是灰條；改後白漆白天晚上都清楚，晚上和路面一樣受路燈照。

做法：`tools/map3d-preview/` 的同一套（`MAP3D_WORLD=taipei`、`MAP3D_BASEMAP=1`、`MAP3D_CITY=1`、`MAP3D_HEIGHTS=1`、`MAP3D_MINUTE=840` 與 `1260`），同一份場景分別用 main 與這次的預覽頁畫。原因與改法在 `docs/decisions/370.md`「斑馬線與車道箭頭」。
