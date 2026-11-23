# TYMC-REBUILT-DEADLOCK 交接

## 進度

- 做了什麼：機捷改建後簡化＋管制整線死結（HEALTH-144，#2592）的根因找到並修掉（決策 934）；145 更新說明加了一行。
- 已驗證（雲端 Linux，debug）：`tymc-rebuilt` 簡＋控兩天 146/333、26 列不解 → 4/333、0 卡死（雜湊 `47c2cf1d97fe86ca`）；`tymc` 新局與修之前逐位元相同（12/333，`a75128dc9f995c4b`）；`FoulingClaimTests` 3 個過；golden、重播、存檔測試一個值都沒變。
- 下一步的第一個指令：沒有待辦；要再量就照決策 934 §2 的指令。

## 做了什麼

- 派工：協調者 2026-11-23（#2118）。分支 `claude/tymc-rebuilt-deadlock`。決策 934；存檔版本、golden schema、fixtures 都不動。
- 根因（決策 934 §3）：不是決策 919 選的路。停在蘆竹出入庫渡線上的回送空車，車身侵入正線；後面出庫的空車在跟車，它的 claim 把前面那列綁在自己站著的軌道上，兩列互等，其餘的車排在後面。919 只是把時間挪到兩列車剛好碰上。
- 修法：`Sources/GameCore/Railway/RouteNeeds.swift` `settleClaims`，claim 不綁佔著侵入它路徑的軌道的車。
- 回歸測試：`Tests/GameCoreTests/FoulingClaimTests.swift`。
- 量測入口：`DepotReturnReportTests.testTheTaoyuanAirportLineRebuilt` 現在也認 `DEPOT_RETURN_FROM`，可以從 `DEPOT_RETURN_SAVE` 存下的世界接著量（整段要二十多分鐘，從第二天 14:00 的存檔接只要約 80 秒）。

## 還留下什麼

- HEALTH-144 另外兩格沒有變好：`tymc` 新局 12/333（修之前之後雜湊相同，是 TYMC-QINGPU-FULL，見 `docs/handoff/TYMC-QINGPU-FULL.md`）；`tymc-old` 修之後 6/333、0 卡死。
- 決策 577 的解死結為什麼不認得「兩列車互相被 claim 綁住」的循環，沒有查。之後再出現沒有人佔軌道卻互等的死結，先看這個。
- 量測用的暫時開關（關掉 919、關掉這條規則、印每列車佔哪幾段）沒有合進來；在分支 `claude/tymc-rebuilt-deadlock` 的 `442830b` 還看得到。

## UNVERIFIED

- 實機與 iOS 模擬器（雲端是 Linux）；完整測試留給 CI（PR 加了 `full-ci`）。
