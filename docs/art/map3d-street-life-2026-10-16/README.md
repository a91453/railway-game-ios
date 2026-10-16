# 3D 地圖的行人與車輛（決策 259）

用 `tools/map3d-preview`（WebGL 照 `Map3DShaders.metal` 的算式畫，不是 iPhone 的畫面）。每張圖都是上半 `main`、下半新版，下午 2 點的光線。

- `station.jpg`：兩鎮地圖的車站，鏡頭距離 180 m，`MAP3D_BUSY=1`（每站當作候車 400 人、一天 8,000 人次）。
- `towns-street.jpg`：同一個車站附近的街道，320 m。
- `taipei-road.jpg`：台北車站的空白實景新局，底圖的道路，130 m。
- `options-full-vs-reduced.jpg`：上半是選定的份量（`full`），下半是舊機型與掉幀時的份量（`reduced`）。
