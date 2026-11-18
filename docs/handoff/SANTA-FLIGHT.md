# SANTA-FLIGHT：平安夜聖誕老人的雪橇飛過 3D 地圖

## 進度

- 做到哪：做完，#2382 CI 全綠後合併（作者常設授權：綠了就合、截圖自己判斷；規劃換到新專案，總覽圖沒有另外審）。
- 已驗證：Linux 建置（warnings-as-errors）乾淨；`SantaFlightTests` 8 個與模型包、冬季、飛機相關的測試通過；`make_game_audio.py --check` 通過；雪橇鈴 −15.1 LUFS、真峰值 −1.5 dBTP。
- 下一步的第一個指令：REINDEER 的模型已換上（決策 [840](../decisions/840.md)）；羅瓦涅米聖誕老人村旁的鹿群也擺好了；剩實機看。

## 派工

- 派工單：SANTA-FLIGHT（`/mnt/project-files/dispatch/SANTA-FLIGHT.md`），Ultra 遊戲規劃 session_01YGNNupAVETTN22PN18vAjU 派。
- session：雲端 thread「做聖誕夜聖誕老人飛過天空」，分支 `claude/project-thread-bu0kxf`（派工單寫的 `claude/santa-flight` 這個 session 不能推）。
- 決策 [831](../decisions/831.md)。存檔、golden schema、GameCore、fixture 都不動。

## 做了什麼

- `SantaFlight`（GamePresentation）：12/24 18:00–12/25 06:00（裝置時鐘）每 6 分鐘一趟；每趟從羅瓦涅米的方向飛過鏡頭當時看的地方，羅瓦涅米地圖上從機場跑道 21 起飛；可點、可跟（`Map3DAircraft.FlightID.santa`），跟飛列只有後方與旁邊；減少動態效果或關掉節慶裝飾時不飛。
- App：`Map3DPreviewScreen` 的 feed 畫雪橇、點選、跟飛；`GameAudio.setSleighBells(_:)` 播 `sleigh-bells.caf`。
- 暫用的方塊造型 `SantaFlight.Model`（1,512 三角形），模型包冬季裝飾之後。

## 還留下的

1. ~~**REINDEER 的模型到了換上**~~（決策 840 做完）：工作室 GLB → `tools/train-models/glb_to_swift.py` → `SantaFlight.Model.model` 回傳它（名字不變），量 `length`、`seat`、`nose`、`lantern`，更新 `hashes.lock.json` 與 `Map3DModelPackSizeTests`、`Map3DModelPackLockTests` 的數字（決策 831「換模型的接點」）。
2. 這張不拍 CI 截圖（截圖要裝置日期在 12/24 晚上）；作者在 TestFlight 把日期調到 12/24 20:00 看。

## UNVERIFIED

- iOS 建置與 UI（`ios-build.yml`）、實機的樣子、跟飛與鈴聲；總覽圖是 WebGL 正投影，不是 Metal。
