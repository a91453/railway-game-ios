# BUILD-CARD-PHONE

派工單 BUILD-CARD-PHONE（session_01JMHz9YujMeYht6HenKN43i，`claude/build-card-phone`，2026-11-16；派工：#2118 留言 6906740172）。決策 800。不動 GameCore、存檔版本（107）、golden、ReplayFixtures、SaveFixtures、`project.yml`、String Catalog。

背景：作者在 0.6.0 (134) iPhone 橫拿鋪軌的截圖。一段 130 公尺、太陡不能鋪的軌道：上方的警告被地圖上有兩顆建議按鈕與 ✕ ✓ 的卡片蓋住；卡片也蓋住正在拉的軌道；兩顆建議都寫 NT$ 0。

## 改了什麼（細節在 `docs/decisions/800.md`）

- **不能鋪的原因搬到 ✕ ✓ 那張卡片**（✓ 旁邊），上方那一列只留長度與高度。手指還在拖時原因照舊在上方。新的 identifier：`map.build.problem`；原有的 `map.build.*`、`map.constructionHUD*` 沒有改名。
- **手機橫拿**（畫面矮）：鋪軌卡片有字時，字與建議在左、✕ ✓ 在右。
- **卡片避開正在拉的那一段**、終點與兩端的旗子。
- **NT$ 0**：那一局是資金無限，GameCore 的報價本來就是 0，沒有算錯。0 元不寫價格（建議按鈕、✓、VoiceOver 的名字）。
- 程式：`Sources/GamePresentation/BuildConfirmLayout.swift`（`arrangement`、`wordsWidth`、`hudSaysProblem`、`priceText`、`flagFrame`、`stretchObstacles`），測試 `Tests/GamePresentationTests/BuildConfirmLayoutTests.swift`；畫面 `RailwayGameApp/Views/MapBuildConfirm.swift`、`MapConstructionHUD.swift`（多一個 `saysProblem`），`MapView.swift` 只在 `MapTopColumnOverlay` 多傳這個參數。

## 還留下什麼（同一畫面看到的其他手機橫拿問題，這張沒做）

分數照 `docs/research/NEXT_PRIORITIES_2026-10-12.md` §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。

| 問題 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 鋪軌時副站長還站在地圖中間偏下，擋到地圖與正在拉的軌道；建造工具開著時可以收到角落或收起來 | 3 | 3 | 3 | 1 | 1 | 2.40 |
| 輔助使用的最大字級加手機橫拿：卡片可能比上方那一列與底部工具列之間還高，仍會照決策 190 的退路往上疊到長度那一列。可以讓卡片的字在放不下時可捲動，或暫時收起底部工具列 | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 手指拖的時候，✕ ✓ 的卡片就在手指下面跟著跑，手擋住它，也擋住終點；拖的時候可以先不出卡片，放開才出 | 3 | 3 | 2 | 1 | 1 | 2.25 |
| 側邊的軌道卡開著時（地圖剩約 430 點寬），建議按鈕只放得下短的字（「24 公尺，走高架」），看不出動的是起點還是終點；VoiceOver 念的是完整的 | 2 | 4 | 2 | 1 | 1 | 2.20 |
| 選月台位置、蓋建物、公車與渡輪的卡片在手機橫拿時仍是上下排；字多的時候（月台位置的人口與整地說明）一樣可能放不下。這張只改了鋪軌 | 3 | 3 | 3 | 1 | 1 | 2.40 |

另外看到的、不是畫面的：`python3 -I tools/golden-checks/doc_numbers.py --check` 在 `main`（`76e4d5d`）就回 1：`docs/OVERVIEW.md` §2 寫存檔版本 103、fixture 104 個，實際是 107 與 108。那是遊戲規劃的檔，這張沒動。

## UNVERIFIED

- 畫面、VoiceOver、放大字級：Linux 看不到。iPhone Pro 橫拿、深色看 PR 裡 `website-screenshots.yml` 的截圖（`testTrackHeightFixes`，只拍一次）；直拿、iPad、小 iPhone、淺色、最大字級、實機都沒看。
- 截圖場景是過河被拒絕的那一段（有橋與隧道兩顆建議），不是作者那一段太陡的；資金無限的局沒有截圖，0 元不寫價格只有 Linux 測試。
