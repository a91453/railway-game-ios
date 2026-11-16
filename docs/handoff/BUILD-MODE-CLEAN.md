# BUILD-MODE-CLEAN

派工單 BUILD-MODE-CLEAN（session_01JMHz9bCQ1fhCXLX4vS8cof，`claude/build-mode-clean`，2026-11-16；派工：#2118 留言 6910182974）。決策 803。分支從 `claude/build-card-phone`（#2298，決策 800）的 head `21a8d75` 開；#2298 合併後這張再併 main。不動 GameCore、存檔版本（107）、golden、ReplayFixtures、SaveFixtures、`project.yml`、String Catalog。

背景：作者看過決策 800 之後說「鋪設軌道介面還是太亂了，精簡一點」。

## 改了什麼（細節與留／收的表在 `docs/decisions/803.md`）

- **建造工具開著時收起**：副站長（正在說第一條路線的步驟時除外）、小地圖、車站上的提醒泡泡與城市請求的標記、票價浮字與滿載章。離開建造就回來。規則 `Sources/GamePresentation/BuildModeChrome.swift`，測試 `BuildModeChromeTests`；用在 `ContentView.swift`（副站長）與 `MapView.swift`（其餘）。教學裡不收。
- **手指拖的時候不出 ✕ ✓ 卡片**，放開才出；旗子照舊。
- **上方只有一個小膠囊**：長度｜高度，加一個小記號（接上既有軌道的連結圖示；拖的時候不能鋪的警告三角形）。原因的字只在卡片。高度提示離開畫面一次就不再出現。
- **卡片**：能鋪時只有 ✕ ✓ 與價格；不能鋪才有原因與最多兩顆建議；建議的短字寫出動的是起點、終點還是兩端。
- **其他建造的卡片**（月台位置、建物、道路、公車、渡輪、加入路線、買地塊、升級軌道）在手機橫拿時字在左、✕ ✓ 在右。
- **地圖出處標示**：卡片改成避開它。
- identifier：沒有改名或拿掉。新增 `map.constructionHUD.joins`、`map.constructionHUD.problem`。`map.constructionHUD` 現在只包那個膠囊與高度提示，不再有原因那一行。

## 還留下什麼

分數照 `docs/research/NEXT_PRIORITIES_2026-10-12.md` §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。

| 問題 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 在地圖上選新路線的卡片（旁邊掛著兩站比較的抽屜，決策 384）在手機橫拿時仍是字在上、按鈕在下；要一起左右排得先決定抽屜放哪 | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 道路與建物用手指拖的時候，✕ ✓ 卡片還是跟著手指（這張只做了鋪軌）；GamePresentation 沒有它們「手指還在拖」的狀態，要先加 | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 被拒絕的那一段橫貫畫面正中、又有兩顆建議時，卡片仍可能壓到它（決策 800 留下的；現在只剩被拒絕時） | 3 | 2 | 3 | 1 | 1 | 2.15 |
| 輔助使用的最大字級加手機橫拿：卡片可能比上下控制項之間還高（決策 800 留下的，沒動） | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 副站長正在說第一條路線的步驟時（玩家選「我自己來」）建造中仍留在原位，還是會擋到；可以改成泡泡說完就收 | 2 | 3 | 2 | 1 | 1 | 1.95 |
| 建造時右下的 3D 鈕、左下的圖層鈕都留著；作者看過截圖若還嫌多，在 `BuildModeChrome` 加一個欄位就能收 | 2 | 4 | 2 | 1 | 1 | 2.20 |

## 截圖（一次，run 43862047491，head 9ec16183，iPhone Pro 橫拿、深色）

圖在 `docs/art/build-mode-clean-2026-11-16/`：`track-height-refused.png`（不能鋪）、
`track-height-refused-en.png`（英文）、`track-height-bridge.png`（能鋪）。看到的：

- 上方只有一個小膠囊（長度｜高度），高度提示沒有再出現；副站長、小地圖都不在畫面上。
- 能鋪：卡片只有 ✕ 與 ✓ 加價格，在右下、不壓軌道。
- 不能鋪：原因一段、兩顆建議，短字寫出「兩端」「起點」；中英文都沒有被截斷。
- 還不好的：這個場景的軌道橫過整個畫面，不能鋪的卡片仍蓋住中間一段虛線
  （卡片比能鋪時大，躲不開一條橫貫的線）；第一顆建議比第二顆窄，左邊沒對齊。兩件都沒在這次改，
  下一位可做：建議鈕同寬（`MapBuildConfirm` 的建議欄給同一個寬度）。

## VERIFIED

- Linux：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`BuildConfirmLayoutTests`、
  `BuildModeChromeTests`、`HeightSlideHintTests`、`NetworkHeightFixTests` 共 33 個過。
- CI（head 9ec16183，已併 main）：`Swift CI (gate)` 與 `iOS App Build`（Xcode 建置與 PR 的 UI 測試）都綠。

## UNVERIFIED

- App 的畫面檔（`RailwayGameApp/Views/`）在 Linux 編不了：建置、UI 測試交 CI（`ios-build.yml`）。
- 畫面、VoiceOver、放大字級：Linux 看不到。只有 `website-screenshots.yml` 的 `testTrackHeightFixes`（iPhone Pro 橫拿、深色，拍一次）；直拿、iPad、小 iPhone、淺色、最大字級、實機都沒看。
- 手指拖的時候沒有卡片、放開才出：UI 測試與截圖都是用點的畫，這一點只有實機看得到。
- 副站長、小地圖、提醒泡泡在建造時收起、離開建造回來：沒有 UI 測試盯著，實機看。
