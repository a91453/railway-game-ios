# 高鐵兩款與 E200 接進營運（決策 408）

同一個相機的前後，工具 `tools/hsr-trains-408/`。每列都照 `Map3DTrains.frame` 的排法（`TrainCars.cars`，每節拉到它那段軌跡的弦長），高鐵十二節、莒光號四節。

- `overview.png`：N700S-G（作者的 mesh 減面＋遊戲色票，一列 74,202 個三角形，單號的列車）、700T（#1201 照原樣，一列 74,528，雙號的列車）、兩款與之前（#900）並排與 120 m 半徑的彎道、兩款頭車近看、N700S-G 的中間車 C 與集電弓車 D。
- `e200.png`：莒光號之前（舊 E200）與之後（#1201 的 E200），及三款在彎道上。
- `assignment.png`：兩款怎麼分給營運的列車，選用的（單號／雙號）與沒有選的做法。

圖是 Chromium WebGL（swiftshader）畫的原生頂點，不代表 iPhone 的 Metal。

大圖在私庫 `Railway/game-art-previews/docs/art/hsr-trains-408/`：作者原檔與減面版同角度對照（`before-after.png`）、每節與整列的各角度、減面的試驗（每節 4,000／5,000／6,000、誤差加不加權、稜線與小零件不動）、沒有選的前兩版（`cabs-v2.png`：700T 改鼻形；平塗重建現在當 500 m 外的遠景）。作者的原始模型（GLB、原生 M3DM、整列預覽）只在私庫 `Railway/n700s-n700st-2026-10-24/n700s-g/`。
