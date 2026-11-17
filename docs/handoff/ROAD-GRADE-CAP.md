# ROAD-GRADE-CAP 交接（決策 833）

2026-11-17，session_01YGNNum9KxAQFvUm7wHrWuP，分支 `claude/project-thread-h4qjzh`。

做完的：國道（`motorway`）沿路自己的縱斷面，坡度 5%（最陡 8%），填方抬高、挖方路塹。內容與量測在 `docs/decisions/833.md`，量測腳本 `docs/research/road-grade-cap/measure_grade.py`。

留下的（沒有人在做）：

1. **實機看**林口、木柵、深坑的國道（UNVERIFIED）。若路塹坡上站著樹、房子、路燈，把 `roadGrade.cuts` 加進擺放的避開條件（`Map3DTrenches.piece(at:)` 已經能問）。
2. **VIADUCT-PIERS**（3.10，NEXT_PRIORITIES §29.23 第 2 項）：照剖面抬高的國道也要照新的墩規則。
3. **快速公路**（`trunk` 的台 61／62／64）：這次刻意不做（山區省道真的比 5% 陡，市區 trunk 有平面路口）。要做就只挑沒有平面路口的段，另開一項評分。
4. 和 ROAD-RAMP-HEIGHT（另一條串）只在 `roadRise` 尾端相鄰；它改 `pieceRise` 時，國道的剖面仍是在最後取較高者。
