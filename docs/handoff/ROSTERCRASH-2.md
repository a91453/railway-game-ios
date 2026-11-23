# ROSTERCRASH-2：運用表點「編排」閃退（0.6.0 (145) 仍在）

- 派工單：ROSTERCRASH-2（bug）。session_01JMHz9c6pw9chMsbr6aXzVX，分支 `claude/rostercrash-2`。
- 決策：不動。存檔版本、golden、GameCore：不動。

## 進度

做完，沒有留下待辦。

## 做了什麼

**重現**（先紅）：場景 `ScreenshotScene.rosterFleet`（16 條線各一列在跑、8 列加班、4 列沒排，運用表 24 列，開在短列）與 UI 測試 `TrainRosterArrangeUITests`（照玩家的路：建造 → 列車 → 車隊 → 運用表 → 點「編排」）。`ios-build.yml` 的 `only_testing` run 45168244506：iPhone 與 iPad、直與橫都紅，點完「編排」App 一格都不再畫，沒有 crash log。不是 trap，是主執行緒卡死；實機上卡死會被系統結束，看起來就是閃退。

**堆疊**（run 45176008564，`-ui-test-stall-stacks`）：主執行緒停在同一次版面更新裡的 `GraphHost.flushTransactions`，App 自己的函式只有 `NotchClearance`（`clearsTheNotch()`）量框的 action。

**原因**，兩件疊在一起：

1. 運用表的列照「上一次量到的表格寬度」做，放在 `ZStack` 裡會把表格撐在舊寬度。編排頁右邊「還沒排的列車」那欄進來時，表格沒有讓位，整頁比畫面寬出那一欄（iPad 188＋8 點，iPhone 132＋8 點），置中後左右各伸出一半。133 回報的「橫拿時車名在瀏海下」就是這個。
2. 133 之後加的避瀏海邊距（`NotchClearance`）量的是「加了邊距的內容外面那個框」。內容比畫面寬時框跟著往外，邊距變大，內容更寬，框再往外：沒有終點，App 卡死。

**修正**：`Theme.swift` 的 `NotchClearance` 改成透明底佔住讓出的空間、內容疊在上面，邊距推不動被量的框（run 45182644767：iPhone 綠；iPad 不卡了，但還寬出 196 點）。`TrainRosterView.table` 同樣改成透明底上疊列，列撐不住表格（run 45191824052：iPhone、iPad、直橫全綠，含左右邊距的檢查）。

**排除的假說**：#2600 的 CRASH101 類（非同步繪製在主執行緒外叫 main-actor closure）：堆疊裡沒有、沒有 trap、#2600 改完仍重現。Canvas 太大或記憶體：24 列就重現，堆疊在版面不在繪製。分頁切換時工具列多一顆「復原」、每列的無障礙動作、拖曳狀態、重複的 id、`ScrollViewReader.scrollTo`：堆疊裡都沒有，兩處修完即綠。

## 回歸測試

- `TrainRosterArrangeUITests`（兩個方法，直與橫）：來回切三次、檢查提示與右欄都在畫面內、捲動、拖一列待排的車。約 3 分鐘，不進 PR 的 gate（決策 199），full lane 會跑。
- `TrainRosterTests.testTheRosterFleetSceneOpensOnShortRows`（Linux）：場景仍是 24 列、開在短列。

## 留下什麼

- 145 的「這版新增」寫了編排閃退已修（`WhatsNew.swift`），其實沒修好；146 的說明請寫：「修好：車隊的運用表點『編排』不再卡住閃退；iPad 的編排頁不再超出畫面。」（照派工單沒有改 145 的說明與 `.github/testflight-whats-new.md`。）
- UNVERIFIED：實機（TestFlight）。Simulator 上的卡死在兩種裝置都重現並修好，但沒有玩家那台的 `.ips` 可對。
