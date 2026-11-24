# TRAIN-TYPE-PICK

## 進度

- 做到哪：第一張 PR（決策 959，(D) 型錄改到打開它的那列車）開了；第二張（決策 960，(B) 線上有車後換車型、(E) 車隊總覽的型錄直接買）在分支 `claude/train-type-pick-2` 進行中。
- 已驗證：`TrainTypePickTests` 1 個測試過（Linux，Swift 6.4）。
- 下一步：`git checkout claude/train-type-pick-2`，接畫面（`LinesPanel.swift` 有車的線的換車型區、`TrainControls.swift` 在軌道上的車也有車種按鈕、`RollingStockCatalogView.swift` 的 `.browse` 加「買一列」）。

## 範圍

- 派工：協調者第 3 任；第 4 任收範圍：(A) 併入 TRAIN-MODEL-UNIFY、(C) 不是 bug，都不做。
- 存檔版本、golden schema、重播：不動。
