# 遊戲的音樂與音效

`make_game_audio.py` 合成 App 的音樂與音效（`RailwayGameApp/Resources/Audio/`）。它和第一支介紹影片的配樂是同一套合成，所以遊戲聽起來和影片一樣（ARCHITECTURE 決策 79）。

```sh
python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio
```

需要 numpy，以及 `PATH` 上的 ffmpeg（把音樂轉成 IMA4 的 CAF）。每次輸出相同。

## 檔案

| 檔案 | 內容 | 遊戲裡 |
| --- | --- | --- |
| `music-loop.caf` | 38.4 秒、可無縫循環的音樂：和弦墊、琶音與鐵軌接縫聲，C 大調 I – vi – IV – V，100 bpm；IMA4，48 kHz 立體聲 | App 在前景時循環播放 |
| `station-chime.wav` | 兩個音的到站鈴 | 營運中的列車到站 |
| `rail-joint.wav` | 「喀噠、喀噠」的鐵軌接縫聲 | 建好一段軌道 |
| `whoosh.wav` | 一秒的「咻」聲 | 換工具、開始或離開遊戲 |
| `build-done.wav` | 輕輕的「咚」加上往上的兩個撥弦音（G、高八度的 C） | 放好建物、加好月台或車站（決策 117） |
| `coins.wav` | 兩個相隔五度的高音鈴 | 每小時結算收到車資、每日收到租金（決策 117） |

## 來源與授權

全部由這支腳本用正弦波與固定種子的雜訊產生，沒有取樣、現成音樂或第三方音源，是本專案自己的素材。

音樂兩輪和弦正好 1,843,200 個取樣，是 IMA4 封包（64 個取樣）的整數倍，所以 CAF 結尾沒有補零；腳本會檢查這一點。改節奏或長度時，要保持這個條件，否則循環會有短暫的空隙。
