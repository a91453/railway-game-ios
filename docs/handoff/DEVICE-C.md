# DEVICE-C

- 派工單：DEVICE-C（含 PERF-FAR-VERIFY；遊戲規劃第 64 任，#1579 留言 6841570600）。
- session：Mac 本機（模擬器與實機 iPhone 17 Pro），2026-11-13。分支 `claude/device-c`。第一個對話開了兩分鐘就封存，這個對話接手。
- 決策、存檔版本、golden、fixture、GameCore：都不動。**沒有改程式**，只加文件與對照圖。

## 做了什麼

- **第一段 PERF-FAR-VERIFY，做完**：把 main 併進 `claude/perf-far`（#2098，只解衝突，`a9c822c`），main 與它各建 Debug 版，在模擬器用同一個存檔、同一個座標對照。#2105 之後 main 的市區最遠視野仍是 236–249 萬三角形（頂著預算），#2098 降到 48–78 萬（少 67–81 %）；建議不要關 #2098，圖請規劃看。數字、圖、量法、坑：[DEVICE_C_2026-11-13](../research/DEVICE_C_2026-11-13.md) 第 1 節。

## 還留下什麼

- **#2098 的預算成本沒跟上**（報告 1.3）：併 main 之後，711 的 `Chunk.cost` 仍用整份遠景的三角形數算預算，不知道 709 這一格只畫一段，邊緣區塊可能被多砍。沒有改，請規劃派。
- 第二段實機七項：見報告第 2 節（還沒寫的就是還沒量）。

## 這台 Mac 上留下的東西（不在 repo）

- 模擬器「DEVICE-C iPhone 17 Pro」（上一個對話建的），裡面裝著 main 的 Debug 版與實機備份來的六筆存檔。可以刪。
- worktree `.claude/worktrees/device-c-perf-far`（`claude/perf-far`，上一個對話開的）。

## UNVERIFIED

- 實機上 #2098 的每格時間與樣子（模擬器的 GPU 是 Mac 的，分不出快慢）。
- 傾斜的最遠視野、拉遠途中每一級換的樣子（只拍了正上方、停住的）。
