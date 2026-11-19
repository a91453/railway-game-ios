# LIUJIA-REBUY＋REBUY-EVERY-MAP（六家線刪掉後買不回來、每張地圖刪掉再買回來的測試）

派工：協調者，2026-11-18（評分 `docs/priorities/BUG-HUNT-1118.md` 第 3、6 項，在私有庫）。session：雲端工作串「修六家線刪掉後買不回來」，分支 `claude/project-thread-gk1qr2`（疊在 #2477 上）。

決策 528 的「後來（LIUJIA-REBUY）」。只改 GamePresentation；GameCore、存檔版本、golden、ReplayFixtures、決策號都不動。

## 做了什麼

- 修：台灣「六家線＋內灣線」買下後刪六家線，買得回來了，位置和第一次買的一樣。`RealLineLaying.offer(for:)`：拆掉留下的軌道後平常的鋪法全被拒時，照原位（不挪到公司軌道旁邊，`whereItStood`）再鋪一次。原因、量到的數字、沒採用的做法在決策 528 最後一節。
- 測試：`RealLineBoughtAgainTests`，每張地圖每個線組逐條刪掉再買回來（竹中、淡海、羅瓦涅米、福岡、香港機場三綫），本地約 2 分鐘。新地圖要在這裡加自己的線組，沒加 `testEveryOverseasMapHasItsLinesBoughtAgain` 會紅。
- 已驗證（Linux，Swift 6.4，**不是實機**）：見 PR。

## 還留下什麼

1. **（已修，2026-11-18，決策 493「後來」，`docs/handoff/DANHAI-REBUY-PLACE.md`；測試的 `elsewhere` 已拿掉）bug：淡海綠山線刪掉再買回來，站的位置變了（DANHAI-REBUY-PLACE）**。買得到、班次正常，但紅樹林、竿蓁林、淡金鄧公、淡江大學、淡金北新、新市一路、淡水行政中心、濱海義山、濱海沙崙 9 站離第一次買的位置 25–30 m、低 10–17 m（從高架下到地面；濱海義山、濱海沙崙高度不變、只偏 27–30 m）。這次的修正之前就這樣。和 BUG-HUNT-1118 第 4 項「舊存檔先買藍海線、再買綠山線」（DANHAI-OLD-SAVE）是同一個鋪法（綠山線在藍海線之後鋪），所以不只舊存檔遇得到，刪過綠山線再買的人也會。`RealLineBoughtAgainTests.testDanhaisLinesAreBoughtAgain` 的 `elsewhere: ["ntdlrt:V"]` 就是跳過這一項的位置檢查，修好後拿掉。評分併在私有庫 `docs/priorities/BUG-HUNT-1118.md` 第 4 項。
2. 竹中兩條線仍然不同層（ZHUZHONG-LEVEL，私有庫 `docs/priorities/TSING-YI-LEVEL.md`）：這次沒有動竹中第一次買的鋪法。那張單若改了六家線竹中端的平面鋪法，`whereItStood` 這個退路可能就用不到了，但留著無害。
3. 買回來的位置容許 4 m：羅瓦涅米凱米耶爾維線買回來，凱米耶爾維的月台高 1–2 m；香港東涌綫買回來，小蠔灣車廠高 3 m、迪士尼綫欣澳偏 2 m。都在容許內，沒查原因。
4. 整張台灣地圖上（所有線都買下）沒有測「刪掉再買」；只測了各線組自己的小地圖。

## UNVERIFIED

- 沒在 iPhone、iPad 上看過：買回來的六家線在竹中的樣子、收購卡「收購時會先拆掉這條線刪掉時留下的 44 段軌道…」那句。沒有新畫面，照決策 482 不拍截圖。

## 怎麼重跑

```sh
stdbuf -oL .build/debug/GamePresentationTests-test-runner --testing-library xctest "GamePresentationTests.RealLineBoughtAgainTests"
```

量竹中每座月台位置、重鋪路徑每個節點的探針（沒進 repo）：`/mnt/project-files/handoff/LIUJIA-REBUY-probes.patch`（在 BUG-HUNT-1118 的補丁之上多了 `testLiujiaGeometry`，`BUGHUNT_LIUJIA=1`；`testWhyNotAgain` 可用 `BUGHUNT_WHY=tra:LIUJIA`）。
