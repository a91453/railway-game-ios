# EMU900 接進營運（決策 435）

`overview.png`：`tools/map3d-preview`（WebGL，不是 Metal、不是 iPhone 的畫面）。左：三列各十輛的前兩輛，上 EMU900 近景（`emu900`）、中 EMU900 遠景（`emu900Far`，`light` 單元）、下 EMU800 近景（`emu800`）。右：從前方看三列的車頭，左起 EMU800、EMU900 遠景、EMU900 近景。14:00 的光線，燈在白天看不太出來。

做法：`Map3DPreviewDump.swift.txt` 複製進測試後，把 `MAP3D_TRAINS` 的列車改成只排 `MAP3D_TRAIN_KEYS` 的 set、每列 `MAP3D_TRAIN_CARS` 輛、每輛用 `layout` 的長度（這個改動只在暫時的複本裡，沒有提交），`MAP3D_WORLD=towns MAP3D_CROP=30000:30000:300 MAP3D_TRAINS=30000:30000 MAP3D_TRAIN_KEYS=emu900,emu900Far,emu800 MAP3D_TRAIN_CARS=10`，鏡頭 `a0:30025:30000:40:0` 與 `a270:30025:30000:40:270`。
