# MAP3D-FAR

- 派工單：MAP3D-FAR（遊戲規劃第 64 任，2026-11-13）。三件：一、最遠視野的空地；二、實機最遠視野 GPU 一格 53–58 ms 是哪一樣；三、#2098（PERF-FAR，決策 709）要不要合。
- session：Mac 本機（模擬器與實機 iPhone 17 Pro）。分支 `claude/map3d-far`（第一件）；第三件在 `claude/perf-far`。
- 決策 [714](../decisions/714.md)。存檔版本、golden、fixture、GameCore：都不動。

## 第一件：最遠視野的空地（做完，這個 PR）

- **原因**（都不是 #2105 造成的，`cfc051d` 的串流規則一樣）：
  - 不拖也只有中間一條：串流只建目標四周 3 km，場景本體 12 km 見方，最遠視野橫向看得到約 23 km。
  - 快拖後整片空：3D 鏡頭沒有限制在地圖內；存檔 B 的地圖只有 16.4 km 見方，最遠視野拖三次（每次約 11 km）就出了地圖，地圖外沒有東西可建。
- **修法**：鏡頭看得到的區塊也建（由近到遠，還看得到就不卸）；鏡頭的目標夾在地圖內。每格三角形預算不動；區塊緩衝超過決策 711 的上限時不再往外建；卸載半徑與建的範圍用同一個數字。細節、圖、沒選的在決策 714。
- 新測試 `Map3DFarSightTests`（9 個；其中 `testTheFarthestViewBuildsWhatItSees`、`testAViewDraggedOffTheSceneBuildsWhatItSees`、`testTheTargetStaysOverTheMap` 在舊規則下會失敗）。另有只在給 `MAP3D_SAVE` 時才跑的 `Map3DFarDragReportTests`（用存檔重演拖曳，印出每一批區塊要多久、看得到的有幾塊建了；加 `MAP3D_OLD=1` 是舊規則）。
- 給 129 的「這版新增」建議一行（沒有改 `WhatsNew.swift` 與 `.github/testflight-whats-new.md`，免得和別的 PR 撞；請規劃整理時補）：「3D 地圖拉到最遠時，整個畫面都有地面、道路與鐵路，不再只有中間一塊；拖到地圖邊會停住，不會拖到一片空白。」

## 第二件、第三件

還沒做（這個檔之後接著寫）。

## 這台 Mac 上留下的東西（不在 repo）

- 沿用 DEVICE-C 留下的模擬器「DEVICE-C iPhone 17 Pro」（515E3DDD…），裡面現在裝的是這個分支的 Debug 版；`autosave.json` 被換成存檔 A（原本的六筆存檔沒動）。
- 存檔來源：`~/RailwayGameDeviceBackups/2026-11-13-before-device-c/`（B 是 `save-2026-11-12 120131.json`，A 是 `save-2026-11-12 203909.json`）。

## UNVERIFIED

- **實機**：第一件只在模擬器（Debug）看過。實機要看的列在決策 714 第 7 節；做第二件時會把這個分支裝上手機一起看，結果補在這裡。
- 本機只跑了快的檢查（`swift build --build-tests -Xswiftc -warnings-as-errors`；`Map3DFarSightTests`、`Map3DStreamingTests`、`Map3DSceneBudgetTests`、`Map3DSceneRebuildTests`、`Map3DCoarseChunkTests`、`Map3DCameraTests`、`CabinFollowTests`、`FollowBusTests` 共 71 個全過；模擬器 Debug 建置）；其餘交 CI。
