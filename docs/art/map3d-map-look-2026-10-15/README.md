# 3D 地圖的地圖感（2026-10-15）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `kaohsiung-mid.jpg` 和文字紀錄；其他 5 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map3d-map-look-2026-10-15/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

ARCHITECTURE 決策 241。作者說比較喜歡網站 3D 城市與參考庫 `city_map_reference_clean` 的風格，並交代「記得調整到遊戲風格而不是照搬」。

這一步只改地面與道路：
- 地面不再是草地貼圖，改成遊戲 2D 地圖那種平塗的淺色；
- 道路依等級用藏青的深淺（2D 地圖文字與陰影的顏色），不是 city map 的黑；
- 主要道路兩側有人行道，雙向道路有台灣的黃色中心線；
- 水是比 2D 地圖清楚的藍，免得河看起來像路。

圖是 `tools/map3d-preview/` 的軟體算圖（WebGL 照 `Map3DShaders.metal` 的算式）。**不是 Metal、不是 iPhone 的畫面**（UNVERIFIED），要等 TestFlight。上半是這一步之前（#672），下半是這一步。

| 圖 | 看什麼 |
| --- | --- |
| `kaohsiung-mid.jpg` | 高雄車站，700 m |
| `kaohsiung-street.jpg` | 高雄車站東南的街上，180 m：人行道與黃線 |
| `taichung-mid.jpg` | 臺中車站，700 m |
| `towns-near.jpg` | 空白地圖的兩鎮：草地換成淺色地面 |
| `realdemo-mid.jpg` | 瑞芳實景示範的山區：林地照舊，路與河分得開 |
| `options.jpg` | 選項，同一個高雄場景。左上：原本（F）；右上：paper；左中：atlas；右中：watercolor；左下：ink（city map 的四種配色直接套上）；右下：網站 3D 城市的截圖 |

## 三角形（整個場景，近版／遠版）

| 地圖 | 之前 | 這一步 |
| --- | --: | --: |
| 台北車站的空白實景新局 | 61,093／48,343 | 77,763／67,153 |
| 高雄車站（含真實建物） | 77,413／65,203 | 89,699／77,489 |
