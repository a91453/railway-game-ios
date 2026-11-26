# E200／700T 原生素材的工具（已刪，只留 `glb-audit.py`）

2026-11-27：作者定的規則「遊戲裡有新版模型，被取代的舊模型就刪掉」。這裡是決策 408 的 E200 與配方 700T 的製作、拍圖與檢查工具。配方 700T 在決策 988 由舊版 700 系改成的 700T（`Map3DTHSR700T`）取代，模型與測試已刪，所以這些工具也一起刪了。E200 還在遊戲裡（`Map3DTrainShapeRefresh.model("refresh-e200")`），它的樣子由 `tools/e500-refresh/` 與 `tools/e200-mingri-style/` 拍。

只留 `glb-audit.py`：其他工具（`tools/tourism-emu500/`、`tools/new-taipei-lrt/`）用它在 Blender 裡檢查 GLB。

要看或重跑原本的工具，用 git 歷史：commit `109dade0` 的 `tools/train-shape-refresh/`。`docs/art/native-vehicle-modeling/` 的製作手冊連到這裡的檔案，那些檔也在同一個 commit。
