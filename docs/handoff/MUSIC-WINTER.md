# MUSIC-WINTER ＋ MUSIC-REFRESH 交接

## 進度

- 做到哪：遊戲規劃聽過後要的兩點已改（#2333）：活動期間冬季曲與主題曲輪流各播一遍（`MusicTune.play`、`MusicPlay`、`GameAudio` 的 `MusicEnd`）；鐘琴高八度、雪橇鈴 2.5–7 kHz。#2335 已 merge 進來，等兩個 PR 的 CI；新的冬季曲試聽檔要更新到 railway-assets-private#132。
- 已驗證：Linux 建置（warnings-as-errors）乾淨、`MusicTuneTests` 7 個通過、`make_game_audio.py --check` 逐位元組相同；冬季曲 1–4 kHz 能量 4.1% → 33%、−15.95 LUFS（ffmpeg −16.0）、true peak −2.1 dBTP、接縫 0.024；主題曲位元組不變。
- 下一步的第一個指令：CI 綠了在 #2118 留「可合併、head …」並轉 ready（#2335 在 #2333 之後合）；#132 等遊戲規劃說可以。

## 派工

- 派工單：MUSIC-WINTER ＋ MUSIC-REFRESH，遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed 派。
- session：session_01JMHz9cGsvfsJaQrxo2Y89Z（雲端 Linux，Opus 高）。
- 決策 815；存檔版本、golden schema、fixture 都不動。

## PR 1 冬季曲（決策 815）

- 12/1–1/6（裝置日期）背景音樂是 `music-winter.caf` 與主題曲輪流各一遍：〈Jingle Bells〉（公有領域）自己編，三份 MML 分軌 → 樂譜 → 同一套合成器，加 `glock`、`sleigh` 兩種音色；鐘琴高八度、雪橇鈴 2.5–7 kHz（遊戲規劃要的亮度）。
- `MusicTune`（GamePresentation）決定哪天播哪首、輪到哪首（`play(at:continuing:)`、`play(after:at:)`）；`GameAudio.updateMusic()` 換檔，播完由 `MusicEnd`（`AVAudioPlayerDelegate`）接下一首。
- **UNVERIFIED**：實機聽感（TestFlight）；iOS 建置與播放（`ios-build.yml`）。

## PR 2 主題曲改版（決策 815 的補充）

選候選 1（決策 79 的和弦加旋律、低音提高），另兩個候選與改版前、冬季曲的試聽檔在 railway-assets-private。**UNVERIFIED**：實機聽感，作者在 iPhone 上聽三個候選。

以下是派工時寫下的要求：

派工單的要求：比現在明亮、有記憶點的旋律、不吵、同一套合成器；三個候選（保留和弦加旋律並提亮低頻／較快較亮的新曲／只調混音），五方各一行選一個，另兩個留試聽檔（大於約 2 MB 放 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/`），寫成決策 815 的補充。冬季曲量到的數字可以直接當起點：主題曲 72% 的能量在 120 Hz 以下（和弦墊的低音在 F1–C2），這是「壓抑」最直接的原因。
