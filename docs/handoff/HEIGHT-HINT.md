# HEIGHT-HINT

派工單 HEIGHT-HINT（session_01YGNNumKAHrYPRtqXnkaYA4，`claude/height-hint`，2026-11-12；派工：#1579 留言 6835797696）。不動 GameCore、存檔版本、golden、ReplayFixtures、SaveFixtures；決策 714 沒有用（釋出）。不進 128。

背景：作者（11-13）說「鐵軌上下滑動好像沒有教學」。鋪軌預覽列的離地高度格（決策 646）只在「這版新增」提過。

## 改了什麼

- **一次性的小提示**：預覽列有可以滑的高度格時，預覽列正下方多一條膠囊「按住上面的高度上下滑，可以把這一端架高或挖到地下。」，右邊一顆 ✕。玩家調過一次高度（滑、− ＋、VoiceOver 調整都算）或按 ✕ 之後不再出現；記在裝置（`@AppStorage`，鍵 `hints.trackHeightSlide.seen`），不進存檔。教學進行中不出現。
  - 判斷在 `Sources/GamePresentation/HeightSlideHint.swift`，測試 `Tests/GamePresentationTests/HeightSlideHintTests.swift`。
  - 畫面在 `RailwayGameApp/Views/MapConstructionHUD.swift`（`heightHint`）；`MapView.swift` 只多傳一個 `tutorialRuns`。
  - 只有 ✕ 接觸控（44 點），其餘讓觸控穿到地圖，和預覽列一樣。它在最上面那一欄裡，欄變深，地圖上的 ✓ 泡泡本來就會避開那一欄（`topColumnDepth`）。
  - 動態：出現與消失用 `pop`，下面的版面讓位用 `change`；減少動態時只淡入淡出、版面直接到位。沒有新的秒數。
- **說明頁**：「建設」那一節第二條「怎麼把軌道架高或放到地下？」（`HelpGuide.swift` 的 `trackHeight`），兩種語言。
- **UI 測試啟動時**（`-ui-testing`）這個提示預設當作看過，和進路、待避線的一次性卡片一樣；要看它的測試加 `-show-height-hint`。
- **截圖**：`WebsiteScreenshotTests.testTrackHeightHint`（提示在、按 ✕ 後不在；中英各一）。

## 加的範圍（規劃 11-12，#1579 留言 6835894923）

- **站長建議泡泡**：點了會帶玩家去某處的建議（分區工具、路線、地圖上的位置或車站），泡泡尾端多一個「›」；只會收起泡泡的建議沒有。VoiceOver：泡泡本來就藏著（站長按鈕會唸它的字），所以在站長按鈕上加一個動作（「到這裡劃分區」「打開這條路線」「在地圖上看」）。去哪裡的判斷從畫面搬到 `StationMasterAdvice.destination`（`StationMasterAdvice.swift`），測試在 `StationMasterAdviceTests`。點泡泡的行為不變。教學沒有教這件事（查過 `Tutorial.swift`、`Lessons.swift`）。
- **列車運行圖**：預設只看兩小時（`TrainDiagramViewport.openingSpan`），所以圖例下面加一行「兩指縮放；拖曳看其他時段。」（`TrainDiagramViewport.gestureHint`）。一直顯示，沒有條件。
- **說明頁再加四條**：`dragTrack`（鋪軌用拖的、拖到邊緣地圖自己捲）、`miniMap`（小地圖點或拖）、`follow3DZoom`（3D 跟車時兩指拉近拉遠）、`collectionCamera`（「圖鑑」裡一指轉、兩指捏合縮放、兩指拖平移；設定裡現在叫「圖鑑」，不是「車庫」）。
- 截圖測試：`testTrainDiagramGestureHint`、`testStationMasterBubbleMark`（後者用 `freight` 場景，站長說哪一句看場景，不一定是有「›」的那種）。

## 沒做的與理由

- **教學（`Tutorial.swift` 的 `track.draw`）沒有加一句。** 那一步的卡片只有一句「讓軌道穿過城鎮，至少幾公尺」，第一段在平地上、用不到高度；多一句會讓新手在第一步就多一件要懂的事。提示在教學中也不出現，教學後第一次自己鋪軌時才出現。
- 沒有做成新的一課（派工說不做）。

## UNVERIFIED

- 畫面、動態、減少動態、VoiceOver：Linux 看不到。畫面看 PR 裡 `website-screenshots.yml` 的截圖（iPhone Pro、橫拿、深色）；小 iPhone、iPad、淺色、最大字級、實機沒看。
- 「玩家滑過一次後不再出現」的那一下（手勢）沒有 UI 測試，只有 Linux 上的判斷測試；截圖測試只按 ✕。
