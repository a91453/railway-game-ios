# MODEL-AGE 總覽圖（2026-11-17）

`overview.jpg` 把落後最多的幾項並排。每一格是遊戲鏡頭的角度：傾 40°，從站前斜看。左邊是舊的，右邊是同一類較新的：

| 舊 | 較新 |
| --- | --- |
| 台灣汽車（110 個三角形的盒子，決策 259） | 香港的士（參考 GLB，決策 743） |
| 方塊機車（決策 259，遠一層也是它） | 速克達（決策 446） |
| E200（10-24，#1201） | E500（決策 425，照手冊做） |
| 通用地鐵殼（港鐵四條綫借用） | 港鐵市區綫（工作室，決策 786） |
| 通用通勤殼（EMU100 等） | EMU900（決策 435） |
| 環島之星客車（通用殼） | 莒光客車（決策 430） |

最下面一列是城市高樓：新北新板特區的真實輪廓（`MAP3D_WORLD=island MAP3D_AT=25.0137:121.4635 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1`，450 m），用 `tools/map3d-preview` 拍的。

怎麼拍的：
1. 用 `tools/train-models/run.sh --ids …` 匯出模型。
2. 把三角形旗標遮成第 0 位元：station-kit 渲染器不認玻璃與鋼的旗標。
3. 用 `tools/model-look/shoot.mjs --before … --model …` 拍。
4. 從每張比對圖剪出第二節的第一列。

都在 Linux 的無頭 Chromium 上畫，不是 Metal。

兩份附表：
- `rolling-stock-inventory.md`：每一組列車的檔案、提交、PR、決策、三角形數與遠景。
- `buildings-inventory.md`：建築、kit 與車站。

兩份都是讀程式寫成的英文筆記；結論與分數見 `docs/research/MODEL_AGE_2026-11-17.md`。
