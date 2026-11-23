# GUIDEWAY-BEAM

## 進度

- 做到哪：#2628（決策 947，選項 1：畫面層照車種推得軌道梁）已開，等 CI 與協調者看總覽；這個 session 壓縮過 1 次，不再接新工作。
- 已驗證：本機 `swift build --build-tests -Xswiftc -warnings-as-errors`；Map3DGuidewayTests 7 個與 12 個相關 Map3D 類別共 112 個測試全過。
- 下一步：TRACK-SYSTEM（選項 2）另派一個 session，從下面「接手」開始。

## 派工與現況

- 派工：主規劃 2（session_01JMHz9bnhWwYkKtoh1drToS），之後換協調者第 3 任（session_01JMHz9ZAGUXxY6aSpzWaqHm）。
- session：session_01JMHz9ZMVA57aRmGYnV4Z1D；分支 `claude/guideway-beam`；決策 947；存檔版本、golden、GameCore 不動。
- 評分：`a91453/railway-assets-private-2` `docs/priorities/GUIDEWAY-BEAM.md`（#410）：GUIDEWAY-BEAM 3.30、TRACK-SYSTEM 3.30、TRACK-KINDS 3.15、TRACK-GAUGE 2.30、ZIGZAG-REVERSE 2.15、TRACK-SPLIT 1.75。

## 主規劃 2 後來定的方向（訊息晚了約 1.5 小時才到，那時 #2628 已開）

主規劃 2 選了**選項 2**：軌道梁是玩家另外蓋的一種軌道，不從車種推。內容：

1. 每段軌道多一個屬性 `system`（一般、跨座、磁浮、懸吊），像 `TrackStructure`（地面、高架、隧道）那樣；建造時先選。
2. 車種 × 軌道相容表：三種導軌車只能跑自己的梁，一般車不能上梁；不相容時給玩家一句話。登山軌道（決策 515 的 `TrackEdge.mountain`）是表裡的一列；要不要把 `mountain` 併成 `system` 的一個值由接手的判斷（併就要遷移 `mountain: true`，不併就在 PR 寫一行理由）。
3. 梁和一般軌道不能接在一起。成本照真實比例（梁較貴、預設高架），道岔、車站月台、速度上限照真實系統；數字從參考庫或公開資料找，找不到寫明自訂。
4. 存檔：升版本、加遷移與新版本樣本。舊存檔的一般軌道照舊；只跑導軌車的整條路線轉成對應的梁，混跑的保留一般軌道（這正是 `Map3DGuideway.edges(in:)` 現在的判斷，可以搬進遷移用）。golden 若有值移動逐值說明。
5. 分兩張 PR：GameCore（種類、相容、存檔）先合，再 3D 外觀與建造介面。
6. 留餘地給 `gauge`（1,067、1,435、762，TRACK-GAUGE），這張不做；高鐵仍是一般鋼軌。
7. 之後可接那霸單軌等真實路線（決策 854 因畫不出來沒選），不在這張。

## 接手

- #2628 的畫法（梁的斷面、墩、門形架、月台升降、`lift`、`Map3DSceneKey` 的重建）選項 2 照用；要換的只有「哪段是梁」的來源：`Map3DGuideway.edges(in:)` 改成讀 GameCore 每段軌道的 `system`，`Map3DGuidewaySignature` 跟著改，`edges(in:)` 現在的推法搬去做存檔遷移。
- 存檔版本與決策號在 #2118 取號登記。
- 參考：`railway-reference-private` `Railway/rail-reference/regions/taiwan/source/rail-3d/garage-scenes/metro-kit.js`（斷面、`GAUGE`、其他軌道種類，TRACK-KINDS 也用它）。

## 留下的（決策 947 §4）

機廠股道仍是鋼軌；地下車站月台沒升降；懸吊式車站沒有門形架；接縫兩側的墩可能很近；預覽工具鋪不出彎道。

## UNVERIFIED

其餘 GamePresentation 測試、iOS 建置與 UI 測試（CI）；iPhone 上的畫面（截圖跑了一次）。
