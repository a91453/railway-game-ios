# SPARSE-FRONTAGE：真實建物稀疏的街廓補沿街的房子

Mac 本機 session，2026-11-13，分支 `claude/sparse-frontage`（疊在 #2138 上）。[決策 723](../decisions/723.md)；存檔版本、golden schema、GameCore 不動。

**做了**：真實建物（城市圖塊加足跡）蓋不到四分之一的 64 m 格不再整格擋掉，沿街的程序房子一棟一棟讓開真實建物的外框（1 m）。數字、門檻怎麼定、前後圖都在決策 723。

**還留下**（都不在這個 PR）：

1. **實機沒看。** 近版三角形多 19%（台北）到 77%（斗六），遠版也多；iPhone 上的樣子與幀數要量（[決策 709](../decisions/709.md) 的做法）。
2. **`Map3DSceneMemoryTests.testRealFootprintsRoundBanqiaoCostNoMoreThanTheGamesHouses` 的 far 斷言在 main 上本來就是紅的**（真實足跡 far 1,305,393 > 遊戲房子 958,577；這支要 `MAP3D_FOOTPRINT_REPORT=1`，CI 不跑）。決策 455、709 把遊戲房子的遠版降下來之後沒有人重跑。這個決策之後是 1,556,703。要嘛降真實足跡的遠版，要嘛改斷言的基準，是另一件事。
3. **斗六補得比高雄多**（72% 的格在門檻下）。要不要照地塊密度給鄉鎮低一點的門檻，等作者看 `docs/art/sparse-frontage-2026-11-13/overview.jpg` 的斗六那一列。改 `RealCover.thinShare` 一個數字就能試。
4. **高雄車站正西、正東緊鄰的舊站場還是空的**：那裡沒有可臨街的路（只有 `service` 便道），不是被真實建物擋住。要補得改決策 385 的 `isFronted`，會動全台的停車場與廠區便道。
5. 門檻 15% 的圖、每格覆蓋率的 CSV、輸出與拼圖的腳本在這組 session 的共用筆記資料夾 `sparse-frontage/`（不在 repo）。

**UNVERIFIED**：iPhone 實機的樣子與幀數。
