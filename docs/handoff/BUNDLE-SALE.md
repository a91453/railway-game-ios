# BUNDLE-SALE（收購改成共用車站的線綁在一起賣）

## 做了什麼

- 派工：協調者，作者 2026-11-18 確認的規則。session：工作串「收購改成共線綁在一起賣」，分支 `claude/project-thread-hhmsgs`。
- 決策 862。存檔（108）、golden（77）、GameCore、fixture 不動；只動 GamePresentation 與 App 的收購畫面。
- 共用車站的真實路線自動成組（`RealLineBundle.groups(of:)`，同系統、有同名車站，或由第三條線串起來），整組一個報價、一個指令、一步復原
  （`RealLineLaying.offer(for:)`、`GameSession.acquireRealLines`、`PlayerCommand.acquireRealLines`）。
  目前算出：台灣「六家線＋內灣線」「淡海綠山線＋藍海線」、香港「機場快綫＋東涌綫＋迪士尼綫」、羅瓦涅米兩條、福岡三條；其餘單賣，行為不變。
- 鋪設順序＝遊戲列出路線的順序，和每晚體檢量的世界相同，體檢預算沒動。
- 舊存檔已單買一條的：不改，剩下的綁成一組賣。
- 畫面：路線面板一組一列、收購卡逐條列價加整組合計、完成卡標題為整組、描線提示報整組價格。
- 測試：新 `RealLineBundleTests`；`TimetableCheckupAllBoughtTests` 的線組改讀遊戲算出的（`sharingGroups`），整組用 `buyTogether` 買。

## 還留下什麼

- **UNVERIFIED**：收購卡與完成卡的樣子沒有圖。截圖只試一次（`WebsiteScreenshotTests.testLinesSoldTogether`）：路線面板那一列拍到了，
  收購卡那張沒拍到（測試等的價格列在卡片下半、還沒捲到；元素樹顯示卡片已排好兩條線與價格），照規則不重跑，測試已改成等第二條線那一列。
  iPhone、iPad 上實際看卡片、實際買一組，等下一版 TestFlight。**要看的畫面**：收購卡（兩條、三條線逐條列價會不會太長，
  橫拿的 iPhone 上價格明細與合計要往下捲才看得到）、完成卡（標題「…等 N 條路線」與各線一行）。
- 沒有新的 UI 測試：收購卡的識別碼沿用（`line.acquire.<network>`、`acquire.buy`），多了 `acquire.together`、`acquire.line.<n>`。
- 低階的單線 API（`realLineOffer(for:)`、`acquireRealLine(_:)`）留著：五十多個測試檔與截圖場景用它一條條買，也是舊存檔那種狀態的測法。
  玩家走的三個入口（路線面板、車站面板、描線提示）都經過線組，買不到線組裡的單一條。
- 整組沒有折扣，價格是各線相加；香港機場三綫的門檻因此是三條的總價。要不要調，屬於經濟平衡（`economy-balance`），沒有評分。
- 線組以「同系統＋同站名」判定。兩個不同系統在同一站（例如台鐵與捷運）不會綁；它們本來就各鋪各的站，沒有出過共站問題。
  日後若同一系統有兩條線只是站名相同、實際不同站（目前沒有），會被誤綁，那時在目錄把站名分開。
- 給協調者：下一版更新說明可寫一句「共用車站的路線改成一起收購」。
