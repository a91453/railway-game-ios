# LAZY-MODELS：模型只在第一次畫到時上 GPU（決策 750）

2026-11-14，雲端串，分支 `claude/project-thread-wkovhc`。接 `PERF-DEVICE-2026-11-14.md`「3D 記憶體」剩下的第 1 項。

- 做了什麼、為什麼、沒選的：[決策 750](../decisions/750.md)。
- 怎麼看效果：Debug 版 3D 畫面點開細節數字，`models 已上傳/全部 · MB` 一行。
- 量法同 `PERF-DEVICE-2026-11-14.md`：同一局、台北車站 1,500 m、拉遠等 2 分鐘，讀 frame-times.json 的 `memoryPeak`、`memoryWarnings`。

留下的：
- 2D 時就寫檔放掉頂點（2D 也少約 287 MB）。
- 場景 CPU 網格約 276 MB（決策 749 第 6 節）。
