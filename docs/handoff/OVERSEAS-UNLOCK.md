# OVERSEAS-UNLOCK：0.8.0 內購「全地圖解鎖」（決策 1010）

## 進度

- 做到哪：程式、測試、決策 1010、獨立審查（#2730 issuecomment-7181932192）與修正都完成；11-26 下午照作者改成「任選一區免費、其他區（含台灣）一次買齊」（決策 1010 開頭的改版），PR #2730 草稿。
- 已驗證：Linux `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`OverseasUnlockTests`（14）、`SharedNetworkTests`、`AirRoutesTests`、`OverseasStartLandTests`、`WhatsNewTests` 過；iOS 編譯由 `ios-build.yml` 過。UNVERIFIED：真的購買／恢復（要 Chien 在 ASC 建好 `overseas_maps`，TestFlight 沙盒測）。
- 下一步第一個指令：確認 0.7.0 已「審過」且不再出 0.7.x 修正後，`git fetch origin main && git merge --no-edit origin/main`，把 `Sources/GamePresentation/OverseasUnlock.swift` 的 `firstLockedBuild` 改成最後上傳的 TestFlight build 號 + 1。

## 派工

- 工作串「做 1.1 海外地圖一次解鎖內購」，分支 `claude/project-thread-fc2z9c`，PR #2730。
- 決策 1010；存檔版本、golden schema、GameCore、replay：不動。

## 合併前必做（照順序）

1. 等 0.7.0 **審過**（不是送審）；還要出 0.7.x 修正就等那版出完。理由：testflight 只從 main 出版，合了之後出的 build 都帶鎖。
2. 併 main，`firstLockedBuild` 改成「合併前最後一個上傳的 TestFlight build 號 + 1」（PR 裡填 150；11-26 最新是 147）。`testTheLockIsPastTheFreeBuilds` 的 147 也一起改成那個號。
3. 改完到合併之間不能跑 `testflight.yml`；之後也不要動 `BUILD_NUMBER_OFFSET`（build 號＝run 號）。
4. CI 綠了就合（PR 轉 ready），在 #2118 留言合併、在工作串回 Chien。
5. 0.8.0 送審時，Chien 把內購加進版本頁一起送；ASC 欄位見 PR 描述。

## 已拍板

- 一區免費：台灣、香港、日本九州、芬蘭羅瓦涅米各一區；第一次在實景地圖開新局就選定（開局前確認一次），不能換。空白地圖、教學、挑戰免費、不算。
- 買了或老玩家：全部地區立刻能開，不等航線。
- 匯入的存檔照玩；朋友傳來的海外路網「只看」照舊、「開新局」要解鎖。
- 冬季活動不另外開羅瓦涅米。
- 沒有 `.storekit` 檔；購買用 TestFlight 沙盒測。
