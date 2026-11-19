# PLAYER-MELODY（2026-11-19，雲端工作串「做自製發車旋律工作坊」）

決策 883：旋律工作坊。玩家在車站面板「車站鈴聲」一段按「自己寫一段旋律…」，用鋼琴捲軸（四小節 3/4、八分音符一格、C 大調 C5–C7）寫一首、存進世界（最多 16 首、一首 128 個音），指定給車站；App 用六個取樣鋼琴音在裝置上合成（`PlayerMelodySynth`）。存檔版本 111。

## 還沒做的

1. **旋律二開頭的 C7 沒聲音**（決策 883 §5）：室內樂音色庫的鋼琴只到 93 鍵。改 `tools/audio/sampled/chamber.json` 的鋼琴鍵範圍（或旋律二降八度）要重產音色庫、改 SHA、重跑 `make_game_audio.py`；旋律以外用鋼琴的音檔都要看有沒有變。
2. **玩家旋律的伴奏**：目前只有鋼琴一軌。
3. **匯入**：貼上 MML、MIDI 檔（研究文件 §2.10）。
4. **實機**：合成的速度、點格子的手感、VoiceOver 念格子都沒在裝置上看過；截圖只拍一次（`WebsiteScreenshotTests.testMelodyWorkshop`）。

## 怎麼重產與試聽

```sh
python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio   # 六個鋼琴音與 manifest
MELODY_PREVIEW_DIR=/tmp/prev swift test --skip-build --filter MelodyWorkshopTests   # 官方六首的主旋律用工作坊播的 WAV
```
