# 決策 391（續）：圖磚的 `layer`

上半 `main`（b69d02c，圖磚沒有 `layer`，每座橋都是 1 層 6 m），下半這個 PR（重切的 `taiwan.pmtiles`，2 層以上的橋帶 `layer`）。台北車站實景新局（`MAP3D_WORLD=taipei MAP3D_BASEMAP=1 MAP3D_HEIGHTS=1`），14:00，WebGL 預覽（`tools/map3d-preview`，不是 Metal）。

- `overview.jpg`（鏡頭 `low:-1060:-150:160:200`）：忠孝橋引道與市民大道高架（OSM `layer=2`）在中華路、環河南路口上方，從 6 m 抬到 12 m，墩變高。
- `stack.jpg`（鏡頭 `stack:-1080:-250:420:35`）：環河快速道路（`layer=4`）、市民大道（2–3）、忠孝橋匝道（2–4）疊在一起的地方，俯看。
