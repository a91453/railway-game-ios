# TRACK-SYSTEM

## 進度

- 做到哪：第一張 PR（只 GameCore，決策 951、存檔 112）在分支 `claude/track-system`。
- 已驗證：見 PR 說明（本機 `swift build --build-tests -Xswiftc -warnings-as-errors` 與碰到的測試類別）。
- 下一步：第二張 PR（建造介面與 3D 換來源），從下面「第二張 PR」開始；另派 session。

## 派工與現況

- 派工：協調者第 3 任（session_01JMHz9ZAGUXxY6aSpzWaqHm）。評分：`a91453/railway-assets-private-2` `docs/priorities/GUIDEWAY-BEAM.md` 第 4 列（3.30）。
- session：session_01JMHz9a2vUkgtY2iK74bNGB；分支 `claude/track-system`；決策 951；存檔版本 112；golden schema、重播不動。
- 前情：`docs/handoff/GUIDEWAY-BEAM.md`（#2628，決策 947，梁的畫法）。

## 第一張 PR 做了什麼（細節在決策 951）

- `TrackEdge.system`（`TrackSystem`：一般、跨座、磁浮、懸吊），建造指令與 `TrackEdgePlan` 可以指定；不指定就跟著接上的軌道。
- 梁只接同一種梁；登山軌道不能是梁。
- `TrackCompatibility`（列是 `TrackKind`，含登山軌道）：派車、改車種、手動放車與指定路徑時檢查。
- 梁的速度上限 80／100／75 km/h，造價 1.2／1.6／1.3 倍（跨座／磁浮／懸吊）。
- 存檔 112：111 以前的存檔，只跑同一種導軌車的整塊軌道轉成梁；混跑的保留一般軌道，車留在路線上。

## 第二張合併前不要發版

第一張合併後、第二張合併前，**新蓋的線派不上導軌車**：一般軌道拒絕 `MONORAIL`、`MAGLEV`、`SKYRAIL`（玩家看到一句「這種車不能跑這種軌道」），而介面還沒有蓋梁的選項。舊存檔的導軌線不受影響（讀檔時轉成梁，混跑的車留著跑）。這段期間的 TestFlight 版會讓玩家買了導軌車卻用不上，所以第二張（TRACK-SYSTEM-UI）合併前不要發版；要先發版就先做第二張的第 2、3 項。

## 第二張 PR（還沒做）

GameCore 給第二張用的入口：

- `world.network.edge(id)?.system`、`.kind`：哪段是梁。
- `world.trackKinds(ofLine:)`、`TrackCompatibility.runs(type, on: kind)`：車種選單要不要列某種車。
- `world.buildTrackEdge(…, system:)`、`TrackEdgePlan(…, system:)`、`world.trackEdgePrice(…, system:)`：蓋梁與報價；`TrackCostParts.guideway` 是梁多出來的錢。
- `GameError.trackSystemMismatch`、`.trainTrackMismatch`：給玩家的一句話已在 `DisplayText.swift`（兩種語言）。

要做的：

1. **3D 換來源**（現在仍照決策 947 從路線上的車推，所以沒有車的梁畫成鋼軌）：`Sources/GamePresentation/Map3DGuideway.swift` 的 `edges(in:)` 改成讀每段的 `system`（`Kind` 對 `TrackSystem` 一對一），`Map3DGuidewaySignature` 改成看梁的那些段；App 的 `Map3DSceneKey` 照舊。混跑而留在一般軌道上的導軌車照決策 947 站在鋼軌上。
2. **建造介面**：鋪軌時先選系統（一般、跨座、磁浮、懸吊），選梁時結構預設高架；`PlayerCommand` 的鋪軌指令帶 `system`（紀錄檔的欄位可省略，省略等於跟著接上的軌道，舊的重播檔不用重錄）；預覽報梁的價錢；`NetworkSession`、`TrackPreviewMarks`、`DoubleTrack`、`PlatformTrack`、`LevelPlatformTrack`、`NetworkCrossover`、`NetworkDiamond`、`DepotYard` 接在梁上時現在已經會蓋出梁（跟著接上的軌道），但要逐一看預覽與價錢。平面交叉（`NetworkDiamond`）：梁和一般軌道在同一高度交叉會共用節點而被拒絕，介面要先說。
3. **車種選單**：路線跑在梁上時只列對得上的車種；一般軌道的路線不列三種導軌車。新遊戲買導軌車後，玩家要先蓋梁才派得出去，教學或說明要有一句。
4. **收購真實路線**（`RealLineAcquisition` 等）：現在全部鋪一般軌道。之後接真實的單軌、磁浮路線（那霸單軌，決策 854）時鋪成梁。
5. 截圖驗收：新的建造選項是既有畫面的小改，3D 是既有模型換來源（ui-review 的第二級）。

## 評分

第二張 PR 與決策 951 §2 沒做的三項已評分，在 `a91453/railway-assets-private-2` `docs/priorities/TRACK-SYSTEM.md`：TRACK-SYSTEM-UI 3.15、GUIDEWAY-GRADE 2.25（梁的坡度上限照真實放寬）、GUIDED-PERFORMANCE 2.25（導軌車自己的性能）、GUIDEWAY-SWITCH 2.15（梁的道岔與月台規則）。

## UNVERIFIED

其餘測試分片、iOS 建置與 UI 測試（CI）；介面與 3D 沒有動，所以沒有實機或截圖要看。
