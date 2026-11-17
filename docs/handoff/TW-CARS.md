# TW-CARS：台灣街上的汽車換掉盒子（決策 838）

## 進度

- 做完：轎車、休旅、廂型、黃色計程車四台，換掉決策 259 的盒子（`docs/decisions/838.md`）。
- 驗證：Linux 的建置與相關測試，`shoot.mjs` 對照片看圖五輪；實機與 Xcode 交給 CI 與作者。
- 下一步：沒有人在做。留下的見下面。

## 派工

- 工作串「換掉台灣汽車的方盒子」（新專案協調者，2026-11-17），分支 `claude/project-thread-3lp98k`。
- 決策 838；存檔版本、golden schema、GameCore 不動。
- 預覽與照片：`a91453/railway-assets-private` 的 `game-art-previews/docs/art/tw-cars-2026-11-17/`。

## 還留下

- **實機沒看過**（UNVERIFIED）：Metal 上的樣子、夜裡的車燈與計程車頂燈、一條街上很多車時的幀率。每台約 1,000 個三角形，比香港的士（2,076）少一半，但比盒子（110）多九倍；決策 259 的車只在近處畫，數量上限沒改。實機若掉幀，先看 `Map3DStreetDetail` 的車數上限，或比照機車（決策 446）加遠景用盒子（`far`）。
- **SCOOTER-OLD**（2.65，`docs/research/MODEL_AGE_2026-11-17.md` 第 7 列）：遠處的方塊機車沒動。
- 休旅車是 Kenney 的吉普改的：水箱罩比 Corolla Cross 方正，座艙後半是原件的軟頂形狀；在遊戲大小看得出是休旅，近看不像特定車款。
- 計程車只有轎車一種；台灣的計程車也很多是 Wish、Sienta 這類 MPV。
- 舊版 `~/SwiftRailMac/assets/分類/` 的車這次沒看（雲端沒連 Mac）。
