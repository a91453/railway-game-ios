# PRIVATE-DOCS-2：獨門文件搬到私有庫，第二批（2026-11-18）

#2437 搬了工作室流程，這次（#2442、railway-assets-private-2 #17）搬了交接總表、優先清單、評分檔與 art-style 的畫風規矩。公開端原路徑留指路短檔，章節號不變。

## 還沒搬、下一批做

分法：工作室、派工單、審查、建模教訓、色票與美術風格、規劃與優先順序放私有 `a91453/railway-assets-private-2`（`docs/studio/`、`docs/planning/`）；公開 repo 只留建置、測試、程式風格與純程式規則。拿不準就放私有。

1. `.claude/skills/music-review/`：音樂方向與審查規矩搬到私有 `docs/studio/`，公開端留量測指令（`tools/audio/measure_music.py`）與檔案格式。
2. 各 kit 的 skill（civic、coach-bus、coastal、commercial、detail、estate、low-floor-bus、midi-bus、park、recreation、residential、shuttle-bus、station、works）：配方與造型做法搬走，公開端留重建指令與檢查。skill 要留在 `.claude/skills/` 才會自動觸發，所以留一個短的 SKILL.md 指路，不要整個刪掉。
3. `model-look` §6 的色票規則，以及 `rolling-stock` 裡的塗裝與造型做法。
4. `docs/handoff/`：工作室、建模相關的交接檔逐一看，獨門的搬到私有 `docs/studio/`，留一行指路。
5. `docs/research/` 裡的模型盤點與色票檢視。

## 注意

- 搬之前先 grep 引用處：測試、`tools/`、`.github/` 讀的檔留在原處或改成一般寫法。這次查過，HANDOFF、NEXT_PRIORITIES、評分檔都沒有被讀（只有註解提到）。
- 評分檔的格式檢查改成 `doc_numbers.py --priorities --root ../railway-assets-private-2`，CI 的 `doc-numbers` 工作不再檢查它們。
- 已經推上公開 repo 的舊內容還在 git 歷史裡，搬走只擋得住以後新寫的。
