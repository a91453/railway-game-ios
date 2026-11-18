# MORE-MELODIES（發車旋律加到六首）

## 做了什麼

- 工作串「加更多發車旋律」（雲端），分支 `claude/project-thread-ftimjn`，[決策 868](../decisions/868.md)。存檔版本 109 → 110（`SaveFixtures/v110-more-melodies.json`）；golden schema、replay 不動。
- 三首新的原創發車旋律 D、E、F（同一套取樣樂器、同樣 7.8 秒、同樣大小），和 A、B、C 成三對；路線照舊挑到一對，每站固定響其中一首。每站選單多旋律四、五、六。
- 試聽檔：私有素材庫 `railway-assets-private-2` 的 `game-art-previews/docs/art/departure-melody-2026-11/`（`departure-d|e|f.m4a`、`over-theme-d|e|f.m4a`）。

## 還留下什麼

1. **作者聽**（UNVERIFIED）：雲端不能聽，三首只量過大小與頻段。不喜歡哪一首就改那份樂譜重產（`python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio`，音色庫第一次下載約 400 MB）。
2. **實機**（UNVERIFIED）：車站面板的選單變成七項（依路線＋六首），沒在裝置上看過。
3. 自製車站旋律工作坊（評分檔第 4 項，2.80）還沒派。
