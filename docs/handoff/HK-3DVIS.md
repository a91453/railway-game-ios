# HK-3DVIS：香港地政總署 3D Visualisation Map 本地再試

- 派工單 HK-3DVIS（遊戲規劃第 64 任，2026-11-13），作者 Mac 的本機 session，分支 `claude/hk-3dvis`。只研究、只寫文件；GameCore、存檔版本、決策、golden、fixtures 都不動，沒有拿決策號。
- 做了什麼：在 Mac 上實際下載九個圖幅檔（三種發行形式都有）、讀三份條款、量棟數／三角形／貼圖／座標／全港大小、拿四棟地標試減面並拍圖。結果全在 [`docs/research/HK_3D_VISUALISATION_MAP_2026-11-13.md`](../research/HK_3D_VISUALISATION_MAP_2026-11-13.md)，總覽圖 `docs/art/hk-3dvis-2026-11-13/overview.jpg`，含照片的並排圖在私有素材庫同名資料夾。
- 結論一句：下載得到；建議只拿無貼圖模型的外形做十來棟地標；樓高另看 Buildings。

## 還留下什麼

- **要作者決定**：條款沒有明寫可以改作（報告 §2）；減面工具要不要加 meshoptimizer（MIT）當工具相依，或自己寫（§6）。
- **沒有做的實作**：`tools/hk-landmarks/`、十來棟地標進香港地圖（§6 的四步）。要派實作單才做。
- **另一張研究單**：下載地政總署 Buildings，看高度欄與涵蓋率（§5 第 2 點）。
- 下載的原始檔、試做的 `.m3dmodel` 與腳本只在這個 session 的 scratchpad（`/private/tmp/claude-501/…/scratchpad/`），session 結束就沒有了；重做照報告 §1 的網址與 §4 的流程。

## UNVERIFIED

- Buildings、3D-BIT00 沒有下載。
- 市區圖幅的貼圖模型與整片 mesh 只有 HEAD 的大小，沒有打開。
- 試做的模型沒有在 App（Metal）裡畫過、沒有放上地圖；精確座標換算沒有實做。
- 全港大小是 127 個圖幅的抽樣估計。
