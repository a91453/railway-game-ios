# ROAD-SMOOTH（決策 821）

## 做了什麼

- 派工單：ROAD-JOIN-DRAW＋ROAD-SMOOTH（NEXT_PRIORITIES §29.19 第 1 項）。session_01JMHz9biVWhZiRyEa1eaFLN，分支 `claude/road-smooth`。ROAD-JOIN-DRAW 已在 #2338 合併。
- 存檔、golden、GameCore、SaveFixtures、ReplayFixtures 不動。
- 自己鋪的路照舊存格子，畫的時候在格子裡拉直、轉彎畫成弧；2D、3D、公車走的路與拖曳預覽同一條線。拖曳改成取手指直線經過的格子。細節見 [決策 821](../decisions/821.md)，前後對照圖 `docs/art/road-smooth-2026-11-17/compare.png`。

## 還留下什麼

- ROAD-FORK-CELL、ROAD-PRICE-SLANT：打分在 NEXT_PRIORITIES §29.26。
- UNVERIFIED：iOS 實機與 Simulator 上的樣子（網站截圖沒有玩家鋪路的場景，這次沒跑截圖）；作者發版後看斜路、彎路、T 字路口。
