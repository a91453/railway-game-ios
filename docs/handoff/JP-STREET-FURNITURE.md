# JP-STREET-FURNITURE：福岡的電線桿（舊版電柱）、行人燈、公車站牌（決策 923）

## 進度
- 做到哪：做完，PR 開了（決策 923）。接 `docs/handoff/JP-STREET-SIGNALS.md`（決策 921）留下的電線桿、行人號誌、公車站牌三項。
- 已驗證：雲端 Linux Swift 6.4 `swift build --build-tests -Xswiftc -warnings-as-errors` 無警告；`Map3DJapanStreetTests`、`Map3DJapanSignalTests`、`Map3DModelPackLockTests`、`Map3DModelPackSizeTests`、`Map3DModelTests`、`Map3DTaiwanCarsTests`、`Map3DWinterLightsTests`、`Map3DPedestrianSignalTests` 等 70 個測試全過。
- UNVERIFIED：沒在模擬器、實機看過，等 TestFlight。
- 2026-11-22 接著做：行人燈換成工作室 r2（燈箱改深色），工作串「jp-street-signals-r2 接回」、分支 `claude/jp-walk-dark-r2`，寫在決策 923 §6「後來」；素材 assets-2 #339。存檔、golden 不動。

- 派工：專案協調者，工作串「搬舊版電線桿路燈進福岡」（作者：「所以記得先找舊版 沒有才自己做 很重要」）。
- session：雲端 thread session，分支 `claude/project-thread-6b2atn`。存檔、golden、fixtures、GameCore 不動。
- 素材：assets-2 #329（舊版電柱原檔與經驗），工作室的行人燈 #327、站牌 #331。

## 還留下
- ~~行人燈燈箱工作室做成淺灰，照片是深褐近黑：工作室 r2 小修~~（2026-11-22 已換 r2，決策 923 §6；重轉的指令在那裡，`hashes.lock.json` 照測試失敗輸出更新）。
- 大路的路燈仍是台灣款（一般弧臂路燈，決策 923 §3.4）；舊版的木製電柱顏色沒用（日本鄉下地圖要用再加）。
- 舊版「電柱」15 個裡的灰模（4×4 貼圖）沒搬，外形和有貼圖的一樣。
