# 台北的機車（決策 446）

`overview.png`：
- 上面：四個近看的騎乘模型（`life-stepScooter` 125 cc 速克達加後箱、`life-stepScooterPair` 載人、`life-electricScooter` 換電式電動機車、`life-deliveryScooter` 外送箱），和右下沒選的做法：只留決策 259 的方塊機車（`life-scooter`，現在成為 350 m 外的遠景版）。用 `tools/train-models`（`run.sh OUT --tag after --ids ...`、`render.mjs`、`overview.py`）畫，同一個紅色塗裝。
- 下面：兩鎮測試地圖同一個鏡頭，上半 `main`（08e63ad）、下半決策 446：騎樓邊緣停一排機車。用 `tools/map3d-preview` 畫（`MAP3D_WORLD=towns MAP3D_CROP=2010:-2454:200 MAP3D_LIFE=2010:-2454:40 MAP3D_VIEWS="c:2009:-2454:18:180"`，Linux 無頭 Chromium，不是 Metal、不是實機；實機的樣子 UNVERIFIED）。

`day/`：四個新模型的七向圖（左、右、前、後、上、下、等角）。夜裡的七向圖沒有放進來（車燈發光的頂點與白天同一組，`check.mjs` 已查），要看用 `tools/train-models/run.sh OUT --tag after --ids life-stepScooter,life-stepScooterPair,life-electricScooter,life-deliveryScooter` 重畫。

停著的機車（`Map3DScooter.addParked`）不在模型包裡，是騎樓近景網格的一部分，所以只有下面那張街景。
