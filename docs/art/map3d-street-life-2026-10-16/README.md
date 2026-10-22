# 3D 地圖的行人與車輛（決策 259）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `station.jpg` 和文字紀錄；其他 6 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map3d-street-life-2026-10-16/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

用 `tools/map3d-preview` 畫：WebGL 照 `Map3DShaders.metal` 的算式重畫，不是 iPhone 的畫面。每張都是上下兩半，下午 2 點的光線。

**上半 `main`、下半新版**：
- `station.jpg`：兩鎮地圖的車站，鏡頭距離 180 m，`MAP3D_BUSY=1`（每站當作候車 400 人、一天 8,000 人次）。
- `towns-street.jpg`：同一個車站附近的高樓街區，320 m。
- `taipei-road.jpg`：台北車站的空白實景新局，130 m。底圖的道路上，汽車在車道上，機車靠路邊，人走在人行道上。

**上半是同一個分支不畫人車，下半畫人車**（地塊之間的街道與月台雨棚也是這個分支新加的）：
- `row-houses.jpg`：透天厝街區，170 m，最接近作者目標畫面的角度。遊戲的鏡頭在 170 m 時俯角是 55°；目標畫面的 35°，在這台鏡頭上要拉到約 700 m 才會出現，那時人已經不畫了。
- `street-close.jpg`：同一區的街道近照，110 m。車沿著藏青的路面、靠右走；人走在兩邊的人行道上。
- `platform-close.jpg`：月台近照，70 m。上半是 `main` 的雨棚（整條月台都蓋住），下半雨棚只蓋中間五分之三，兩端看得到站在月台面上候車的人；月台外的空地是站前的人潮。
- `options-full-vs-reduced.jpg`：其他做法。上半是選定的份量（`full`），下半是舊機型與掉幀時的份量（`reduced`）。
