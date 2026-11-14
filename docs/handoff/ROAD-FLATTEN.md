# ROAD-FLATTEN 交接（2026-11-14）

- 決策 [737](../decisions/737.md)：實景地圖的 3D 地面先整平（`Sources/GamePresentation/Map3DLevelledGround.swift`、`Map3DScene.Builder.levelGround(under:)`）。
- 分支 `claude/project-thread-f35ks6`。GameCore、存檔、golden、replay 不動。
- 量測腳本：`docs/research/road-flatten/`（`measure.py` 現況、`opt2.py` 有門檻的模糊、`opt3.py` 採用的做法）。從 repo 根目錄 `python3 docs/research/road-flatten/opt3.py`（要 `pip install mapbox-vector-tile numpy`）。
- 第三級：改前改後截圖（含斜視角）作者看過才合。
- 留下的：決策 737「下一步」（ROAD-DTM、ROAD-LAYER、軌道格旁的台階）。
