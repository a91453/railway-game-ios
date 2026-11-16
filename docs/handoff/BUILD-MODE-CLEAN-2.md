# BUILD-MODE-CLEAN-2

## 進度（中斷後只讀這一節與 `git status`、`git log -3`）

- 做到哪：程式、測試、決策 803 第 8 節、這份交接都推了；PR #2309（draft）已開並訂閱，已在 #2118 留言（壓縮第 1 次）。還沒拍截圖。
- 已驗證：Linux 本機建置（warnings-as-errors）與 151 個相關測試過。App 畫面檔還沒編過（等 PR 的 `ios-build.yml`）。
- 下一步的第一個指令：查 PR #2309 的 iOS 建置；編得過就開一次 `website-screenshots.yml`（ref `claude/build-mode-clean-2`，`kind=website`、`device=iphone`、`tests=testTrackHeightFixes`，先確認沒有別的截圖在跑，失敗不重跑），截圖轉 JPEG 85 放 `docs/art/build-mode-clean-2-2026-11-16/`，貼進 PR，補本檔「截圖結果」。

派工單 BUILD-MODE-CLEAN-2（session_01JMHz9c3vpC3pdNMzXWMZ1i，`claude/build-mode-clean-2`，2026-11-16；遊戲規劃派，登記在 #2118 留言 6924206474）。決策 803 的補充（`docs/decisions/803.md` 第 8 節），沒有取新號。不動 GameCore、存檔版本（107）、golden、ReplayFixtures、SaveFixtures、`project.yml`、String Catalog。接在 `docs/handoff/BUILD-MODE-CLEAN.md` 之後。

背景：作者看了 #2302 的截圖說「字不會太多嗎」。

## 改了什麼（對照表與細節在決策 803 第 8 節）

- **原因一行短句**：鋪軌被拒絕時卡片上只寫一行，不寫數字與條件。`NetworkPreview.problemBrief`，各原因的短句在 `Sources/GamePresentation/TrackRefusalBrief.swift`；整句 `problem` 沒有改，仍在詳細卡、狀態訊息，VoiceOver 在卡片上念的也是整句。
- **建議按鈕只寫做法與價格**：`NetworkHeightFix.buttonTitle`（用橋、走高架、架高、走隧道、降低）；VoiceOver 念 `title`（哪一端、幾公尺）加價格。`shortTitle` 拿掉了。
- **被拒絕時不再帶備註**（第一段是直線、複線渡線的說明）：只在詳細卡。
- **版面**：原因那一條與卡片同寬；兩顆建議同寬；手機橫拿、被拒絕又有建議時是「原因一行＋一列（兩顆建議、✕ ✓）」，按鈕 44 點高，卡片約 82 點高。算式 `BuildConfirmLayout.columnWidth`、`equalCells`、`arrangement(…hasFixes:)`、`buttonHeight`；App 裡是 `MapBuildConfirm.swift` 的 `PillColumn`、`EqualCells`。
- **道路與建物**：手指拖的時候不出 ✕ ✓ 卡片，放開才出（`GameSession.buildFingerDraws`）。這是上一張交接表的第二列。
- identifier：沒有改名或拿掉，也沒有新增。

## 還留下什麼

分數照 `docs/research/NEXT_PRIORITIES_2026-10-12.md` §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。前四列是上一張交接留下、這次沒動的。

| 問題 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 道路、公車路線、渡輪、升級軌道、月台位置的卡片，被拒絕的原因仍是整句（這次只做鋪軌）。做法照 `TrackRefusalBrief.swift`：各自的預覽多一個短句欄位 | 3 | 3 | 2 | 1 | 1 | 2.25 |
| 在地圖上選新路線的卡片（旁邊掛著兩站比較的抽屜，決策 384）在手機橫拿時仍是字在上、按鈕在下 | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 輔助使用的最大字級加手機橫拿：卡片可能比上下控制項之間還高（決策 800 留下的） | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 副站長正在說第一條路線的步驟時建造中仍留在原位，還是會擋到 | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 建造時右下的 3D 鈕、左下的圖層鈕都留著；作者若還嫌多，在 `BuildModeChrome` 加一個欄位就能收 | 2 | 4 | 2 | 1 | 1 | 2.20 |
| 橫拿時卡片 82 點高、放得進軌道上下的 97 點，只有算式（上下控制項之間 195 點是決策 803 寫下的數字），實機與小 iPhone 沒量；若還蓋住，再把原因那一條的底色拿掉可再少 6 點 | 3 | 3 | 2 | 1 | 1 | 2.25 |

## 截圖

見本檔最後「截圖結果」。

## VERIFIED（Linux，本機）

- `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨。
- `swift test --skip-build --filter` 跑過：`TrackRefusalBriefTests`（新）、`BuildConfirmLayoutTests`、`NetworkHeightFixTests`、`CityBusToolTests`、`BuildingFlowTests`、`BuildingSessionTests`、`HeightSlideHintTests`、`BuildModeChromeTests`、`TrackGeometryProblemTests`、`TraceOverlapTests`、`TracedSaleTests`、`NetworkSessionTests`、`RoadDrawRealMapTests`、`LocalizationTests`、`DisplayTextTests`，共 151 個過。

## UNVERIFIED

- App 的畫面檔（`RailwayGameApp/Views/MapBuildConfirm.swift`）在 Linux 編不了：建置、UI 測試（教學、第一課）交 CI（`ios-build.yml`）。
- `PillColumn`、`EqualCells` 兩個 SwiftUI 排版本身沒有測試，只有背後的算式有。
- 畫面、VoiceOver、放大字級：只有 `website-screenshots.yml` 的 `testTrackHeightFixes`（iPhone 橫拿、深色）拍一次；直拿、iPad、小 iPhone、淺色、最大字級、實機都沒看。
- 道路與建物拖的時候沒有卡片、放開才出：UI 測試用點的，只有實機看得到。
- 套件其餘的測試交 CI（這張動 GamePresentation，跑它的 tier）。
