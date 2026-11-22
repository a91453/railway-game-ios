# JP-STREET-SIGNALS：福岡（日本）的車用號誌改用作者舊版的三灯式信号

## 進度
- 做到哪：車用號誌做完、已合併（#2580，決策 921）；電線桿與路燈還沒開始，本 session 壓縮過一次，照規矩交給新串。
- 已驗證：雲端 Linux Swift 6.4 建置無警告；`Map3DJapanSignalTests` 等 11 個類別全過；PR 的 CI 全綠。
- 下一步的第一個指令：在舊版名單裡找下面的「電柱」幾款 GLB，照 `tools/fukuoka-map/japan_signal.py` 的方法轉。

- 派工：專案協調者，工作串「福岡改用日本紅綠燈」（作者：「然後福岡為何是用台灣的紅綠燈」「重點是我舊版就有了」「記得要把色票換成遊戲正在使用的紅綠燈」）。
- session：雲端 thread session，分支 `claude/project-thread-lemc87`。
- 決策 921（`docs/decisions/921.md`）。存檔、golden、fixtures、GameCore 不動。
- 做完：`tools/fukuoka-map/japan_signal.py` 把舊版 `item_ebd5cc627de55b8fb6e7ded9`（三灯式信号）轉成 `jp-signal-red/amber/green`，`Map3DStreetRegion.hasJapaneseSignals`、`Map3DScene.Builder.japanSignals`、`Map3DSignalTiming.Models.japan`。素材與經驗在 assets-2 `game-art-previews/docs/art/jp-street-signals-2026-11/`、`docs/studio/lessons/jp-street-signals.md`。
- 還留下：
  - **電線桿與路燈（新串做，不派工作室）**：作者舊版有，照同樣方法轉成 Swift 編碼的網格、用遊戲色票。舊版名單：電柱(鉄筋) `2594988f`、`2ee41674`；電柱(鉄筋 変圧器付) `9563cbe0`、`422748cd`；電柱(木製)／(木製 変圧器付) `2a2d1b6a`、`070f5afb`；電柱(木製 街灯付) `48ae680d`（可當路燈）。遊戲裡電線桿由 `Map3DRealGround` 的 PropRule 放（`hasUtilityPoles`），路燈換款的例子是芬蘭（`Map3DRealGround.swift` 約 1124 行）。要在 #2118 登記新的決策號。
  - **行人號誌**：舊版沒有，工作室單 assets-2 `jp-street-signals-2026-11/README.md` §1（jp-walk-stop/dark/walk）。
  - **公車站牌**：舊版沒有，工作室單 assets-2 `game-art-previews/docs/art/jp-bus-stop-2026-11/`。
- UNVERIFIED：號誌沒在模擬器、實機看過，等 TestFlight。
