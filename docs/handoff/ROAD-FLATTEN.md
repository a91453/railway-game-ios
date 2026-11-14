# ROAD-FLATTEN 交接（2026-11-14）

- 決策 [737](../decisions/737.md)：實景地圖的 3D 地面先整平（`Sources/GamePresentation/Map3DLevelledGround.swift`、`Map3DScene.Builder.levelGround(under:)`）。
- 分支 `claude/project-thread-f35ks6`。GameCore、存檔、golden、replay 不動。
- 量測腳本：`docs/research/road-flatten/`（`measure.py` 現況、`opt2.py` 有門檻的模糊、`opt3.py` 採用的做法）。從 repo 根目錄 `python3 docs/research/road-flatten/opt3.py`（要 `pip install mapbox-vector-tile numpy`）。
- 第三級：改前改後截圖（含斜視角）作者看過才合。
- 留下的：決策 737「下一步」（ROAD-DTM、ROAD-LAYER、軌道格旁的台階）。
- 作者 11-14 看過總覽圖說「ok」。**還要查**：左營站棚頂下的太陽陰影改後變淡（截圖 e 列，assets #110）。推測是鏡頭對準點的地面高度變了、太陽陰影圖（決策 357）跟著鏡頭；要在 Mac 用同一個相機絕對位置（不是對準地面）拍一次確認，若不是這個原因再查。
