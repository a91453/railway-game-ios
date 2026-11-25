# PHOTO-MODE 交接

3D 地圖的拍照模式（評分在私有 repo `docs/priorities/NEON-SCRAMBLE.md` 第 1 項，3.55）。決策 987，PR #2686，
分支 `claude/project-thread-vr9xga`。GameCore、存檔版本、golden schema、三種 fixture 都不動。
這個 session 壓縮兩次，照規則做到 #2686 合併就結束。

## 進度

- 做到哪：**功能做完（2026-11-25）。** 相機鈕、三個鏡位（列車、車站、天際線）、暫停、快門存到照片、點地圖收起按鈕、離開。
  決策原本認領 981，和 HK-STAR-FERRY（#2688，先合）撞號，併 main 時改成 987。
- 已驗證：Linux `swift build --build-tests -Xswiftc -warnings-as-errors`；`PhotoSpotsTests`（13）、`WhatsNewTests`、
  `AsyncRenderClosureSourceTests`；`doc_numbers.py --check`。App 在 macOS CI 編過一次（83c15bc 的 Build for iOS Simulator）。
- 下一步：#2686 目前 head 的 CI 綠了就合；合了以後做「還留下什麼」前兩條。

## 做了什麼

- `Sources/GamePresentation/PhotoSpots.swift`：鏡位、下一列車與下一座車站的輪法、車站與天際線的鏡頭（純函式，Linux 可測）。
- `RailwayGameApp/Views/Map3D/Map3DPhotoMode.swift`：模式狀態、存照片（`UIImageWriteToSavedPhotosAlbum`，只加入不讀取）、
  相機鈕、拍照列、`putAway`。
- `Map3DPreviewScreen.swift`：接上去。拍照模式開著時地圖自己的控制項整個不放在畫面上。
- 相片權限說明（`project.yml`、兩個 `InfoPlist.strings`）改成也講遊戲裡拍的照片；專案用 XcodeGen 2.46.0 重產。

## 還留下什麼

- **合併後**：#2118 留言（已合、決策 987、放掉認領）；私有 repo `docs/priorities/NEON-SCRAMBLE.md` 第 1 項的狀態改成已合
  （另開 PR，`guard` 綠自合）。
- **截圖驗收只跑了一次、只拍到一張**（`photo-mode-button`，相機鈕在 3D 地圖上）。`WebsiteScreenshotTests.testPhotoMode`
  在開了拍照模式之後停在「地圖的關閉鈕要不見」：控制項當時只是變透明加上對輔助使用隱藏，UI 測試仍找得到。已改成不放進
  畫面（`putAway`），但照「只試一次」沒有重跑，所以**開著的拍照列、三個鏡位的構圖、點地圖收起按鈕都沒有截圖**，
  `testPhotoMode` 修改後也沒有再跑過。發版後作者實機看；之後誰要補截圖，跑 `website-screenshots.yml` 的 `testPhotoMode`。
- **UNVERIFIED（要實機）**：第一次按快門時 iOS 的詢問與存進「照片」；不允許時改開分享面板；三個鏡位實際的構圖
  （車站 66° 斜角、天際線退到 800 m）；`putAway` 與開關拍照模式的版面動畫（83c15bc 之後才加，等這一版的 macOS CI）。
- 沒做、另外評分的：快門聲、照片上的濾鏡或相框、鏡位存起來下次用、真實攝影點。
- 拍照模式不在親自駕駛中與教學中出現（相機鈕不顯示）；要不要在駕駛艙也能拍另評。

## 要小心的

- 拍照列的三顆鏡位鈕是一顆一顆寫的，不是 `ForEach`：它在 `ViewThatFits` 裡，`AsyncRenderClosureSourceTests`（CRASH101）
  不准那裡有沒標 `@Sendable` 的列閉包。
- 拍照模式自己開始的跟車，離開時會放掉；玩家原本就在跟的車不動（`Map3DPhotoModeState.close()` 回傳要不要放）。
