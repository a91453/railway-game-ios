---
name: music-review
description: 遊戲音樂怎麼做、怎麼審：背景音樂、季節曲、主題曲改版、到站鈴與介面音效的響度、頻段、峰值、循環接縫、聽膩的風險，與試聽檔怎麼交給作者。加或改 RailwayGameApp/Resources/Audio 的任何音樂、或審查音樂的 PR 之前先讀。Use before adding or changing any music or jingle in the app (tools/audio, RailwayGameApp/Resources/Audio), and when reviewing a music pull request, especially when nobody can listen to it yet.
---

# 遊戲音樂：公開的程式規則

作曲方向、編制、音色與製作、量測的目標值、聽膩、試聽到定案的流程、來源與授權、歷次的經驗與下次作曲的起點是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/music-review.md`（同節號）與 `docs/studio/music-lessons.md`。**加或改音樂、審音樂 PR 之前先讀那兩份**；這裡只留量測指令、檔案格式與程式上的坑。

## 1. 量測

```sh
python3 -I tools/audio/measure_music.py RailwayGameApp/Resources/Audio/music-loop.caf [...]
python3 -I tools/audio/make_game_audio.py --check RailwayGameApp/Resources/Audio
```

`measure_music.py` 印出長度、響度（LUFS）、響度範圍（LRA）、真峰值（dBTP）、五個頻段的能量占比、每秒音量的範圍與循環接縫的跳動。改版前的檔一起量，數字並排放進 PR；要達到的值在私有那份 §1。量測只擋明顯的錯，不證明好聽。

## 2. 檔案格式

- 循環播放的配樂：ALAC（16-bit 無損）。AAC 有編碼延遲，循環會有空隙；IMA4 在安靜段有嘶聲。
- 只播一遍的檔：AAC 192 kb/s。
- 給作者試聽：`.m4a`（Artifact 試聽頁用 mp3），放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`），不放這個 repo。
- 樂器取樣與 SoundFont 不提交；工具在 `tools/audio/`（`tools/audio/README.md`）。

## 3. 程式上的坑

- 新型別曾取名 `MusicTrack`，和 AudioToolbox 同名，App 匯入 AVFoundation 後 Xcode 建置失敗（Linux 看不到），改名 `MusicTune`。音訊相關的新型別名，先查 Apple 的音訊框架有沒有同名的。
- 速度要讓每個 tick 是整數個取樣（48,000 × 60 是 tempo × 960 的倍數：75、100、120、150 可以），長度是 64 個取樣的整數倍。
- MML 的長度只能是整數 tick 的音符（0.75 拍 `8.`、0.375 拍 `16.`）。

## 4. 回報

- **VERIFIED**：上面的量測、`make_game_audio.py --check`、Linux 測試。
- **UNVERIFIED**：實機聽感（作者用試聽檔與 TestFlight）、iOS 的建置與換曲（`ios-build.yml`）。
