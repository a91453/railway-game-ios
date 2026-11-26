# layout-overview

簡圖：玩家建築排在地塊上的樣子、小站的站房，用遊戲實際的網格畫，**有深度緩衝**（和遊戲的 Metal 畫面一樣逐像素比遠近）。
不是遊戲畫面：沒有遊戲的光影、陰影與貼圖，只是平塗加一個方向的明暗。

```sh
LAYOUT_OVERVIEW_DIR=/tmp/layouts swift test --skip-build --filter LayoutOverviewDumpTests
python3 -I tools/layout-overview/render.py OUT.jpg 3 /tmp/layouts/school-0@200 /tmp/layouts/school-0@20 /tmp/layouts/school-0@110
```

`LayoutOverviewDumpTests` 只在設了 `LAYOUT_OVERVIEW_DIR` 時寫檔（國小、醫院每一款的地塊網格，與香港、台灣一般小站幾種擴建），
平常 CI 跑到它會跳過。`render.py` 的格子寫 `檔名@偏航[,俯角]`（俯角預設 40°）。地塊有墊層時照遊戲畫（墊層 0.1 m，上面的東西站在墊層上）。

**為什麼要深度緩衝（2026-11-25）**：決策 963、967 的總覽圖是把整個三角形照中心的遠近排序後依序塗上（畫家演算法）。
大片的平面三角形（操場、屋頂）會整片蓋到鄰居上或被蓋住，畫出模型裡沒有的斜切三角：國小操場分成深淺兩塊綠、醫院和香港站房屋頂有細長斜條，
被當成模型破圖。遊戲用深度緩衝，沒有這些。新的總覽圖請用這個工具，不要再用排序畫法。
