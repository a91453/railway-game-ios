# MUSIC-WINTER ＋ MUSIC-REFRESH 交接

## 進度

<<<<<<< HEAD
- 做到哪：#2333、#2335 的 Xcode 建置第一次紅在 `MusicTrack` 與 AudioToolbox 同名，改名 `MusicTune` 後重推，等 CI。PR 2（`claude/music-refresh`）接在 PR 1 之上，選候選 1；試聽檔在 railway-assets-private#132 的 `game-art-previews/docs/art/music-refresh-2026-11-17/`。
- 已驗證：PR 1 見下；PR 2 `make_game_audio.py --check` 逐位元組相同、`MusicTuneTests` 5 個通過；新主題曲 76.8 秒、−15.95 LUFS、120 Hz 以下能量 72% → 4%。
- 下一步的第一個指令：兩個 PR 的 CI 綠了各自在 #2118 留「可合併、head …」並轉 ready；PR 2 要在 #2333 合併之後合（它包含 #2333 的 commit）。
=======
- 做到哪：PR 1（冬季曲，`claude/music-winter`，決策 815）程式、音檔、測試、文件都好了，開 draft PR 等 CI。PR 2（主題曲改版，`claude/music-refresh`）還沒開始。
- 已驗證：Linux `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`MusicTuneTests` 5 個、`WinterEventTests`、`RunningSoundTests`、`SoundCueTests` 共 53 個通過；`make_game_audio.py --check` 逐位元組相同、三份冬季 MML 與樂譜相符；冬季曲 −15.94 LUFS 對主題曲 −15.95，峰值 −1.27 dBFS，112 秒，接縫 0.023。
- 下一步的第一個指令：PR 1 的 CI 綠了就在 #2118 留「可合併、head …」並轉 ready；接著 `git checkout -b claude/music-refresh origin/main`，在 `tools/audio/` 做三個主題曲候選。
>>>>>>> claude/music-winter

## 派工

- 派工單：MUSIC-WINTER ＋ MUSIC-REFRESH，遊戲規劃 session_01JMHz9Yps9xJyFfDFR4mUed 派。
- session：session_01JMHz9cGsvfsJaQrxo2Y89Z（雲端 Linux，Opus 高）。
- 決策 815；存檔版本、golden schema、fixture 都不動。

## PR 1 冬季曲（決策 815）

- 12/1–1/6（裝置日期）背景音樂換成 `music-winter.caf`：〈Jingle Bells〉（公有領域）自己編，三份 MML 分軌 → 樂譜 → 同一套合成器，加 `glock`、`sleigh` 兩種音色。
- `MusicTune`（GamePresentation）決定哪天播哪首；`GameAudio.updateMusic()` 換檔。
- **UNVERIFIED**：實機聽感（TestFlight）；iOS 建置與播放（`ios-build.yml`）。

## PR 2 主題曲改版（決策 815 的補充）

選候選 1（決策 79 的和弦加旋律、低音提高），另兩個候選與改版前、冬季曲的試聽檔在 railway-assets-private。**UNVERIFIED**：實機聽感，作者在 iPhone 上聽三個候選。

以下是派工時寫下的要求：

派工單的要求：比現在明亮、有記憶點的旋律、不吵、同一套合成器；三個候選（保留和弦加旋律並提亮低頻／較快較亮的新曲／只調混音），五方各一行選一個，另兩個留試聽檔（大於約 2 MB 放 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/`），寫成決策 815 的補充。冬季曲量到的數字可以直接當起點：主題曲 72% 的能量在 120 Hz 以下（和弦墊的低音在 F1–C2），這是「壓抑」最直接的原因。
