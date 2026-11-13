# KS-EMPTY-BLOCKS：高雄車站周圍沒有建物

Mac 本機 session，2026-11-13，分支 `claude/kaohsiung-empty-blocks`。決策 431 的「後來」（不拿新號）；存檔版本、golden schema、GameCore 不動。

**做了**：高雄車站地標只清模型本身底下的 64 m 格（66 格 → 36 格），手臂之間的街廓畫回真實建物。原因、量到的數字、推翻的假說在決策 431 的「後來」；前後對照在 `docs/art/kaohsiung-station-blocks-2026-11-13/`。

**還留下**（都不在這個 PR）：

1. **足跡疏的格子沒有補房子。** 高雄車站一帶 Overture 的建物每公頃約 1–10 棟，真實是連棟透天與店屋；決策 389 讓「有任何一棟足跡的 64 m 格」整格不放程序房子，所以街廓裡大半是空地。要補的話是決策 389「沒有選的：一棟一棟讓開」那一條：`layFrontage` 的 `fits` 除了擋格子，改成擋足跡本身的外框（加一點邊），足跡覆蓋率低的格子才補。會動全台的樣子與三角形預算（決策 238、267；`MAP3D_FOOTPRINT_REPORT=1 swift test --filter Map3DSceneMemoryTests`），要領新決策號、量過再做。
2. **`MAP3D_WORLD=kaohsiung`／`taipei`／`taichung`／`douliu` 不是 App 新局的土地**：`GameWorld.newGame(anchor:)` 不給 `land`，用的是空白地圖的種子城鎮。要看 App 的樣子用 `MAP3D_WORLD=island MAP3D_AT=緯度:經度`。`tools/map3d-preview/README.md` 已加一句說明；要不要把那四個改成讀真實土地（會讓舊預覽圖對不上）沒有動。
3. 其他地標的 `clearing` 也是長方形，但它們的模型是實心的一塊，沒有量到同樣的問題；旗津、鼓山渡輪站與大港橋沒有逐一看。
4. 網頁試做看起來滿，推測主要是地面的正射影像，不是建物比較多（同一個來源，App 內高雄那一份 1,212 棟）；只讀了程式，沒有開網頁比。原生要不要鋪影像或給街廓地面上色是 MAP-LIVELY（決策 720）那一邊的事。

**UNVERIFIED**：實機（iPhone）的樣子與幀數。
