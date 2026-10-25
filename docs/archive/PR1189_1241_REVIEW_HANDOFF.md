# 交接：PR #1189–#1241 審查 I 組

Session：session_01Mqs95FA7nGrbhR8dXfefX9。遊戲規劃 session_0164nEyu2aMPVTpvQww43kj1 派工，日期 2026-10-25。派工單：審查 main 上已合併的程式 PR，從 #1189 到開工時 main 最新合併的（#1237／#1241）；GameCore 的 PR 自己讀。#1232、#1239 還沒合，由 session_01E4WpZZcxv2EC9rroJFg6ka 另外獨立審查，不在這一輪。

- 審查基準：`main` **2ae0f7c**（#1237 合併後）。
- 範圍：#1189–#1241。點數照 HANDOFF 第 1 節「多久審查一次」計算。
- 上一輪：[PR1137_1188](PR1137_1188_REVIEW_HANDOFF.md)（審查 H）。
- 存檔版本、決策編號、golden schema 都**不動**。GameCore、GoldenScenarios、SaveFixtures、ReplayFixtures 都沒改。
- 兩個 PR：這份文件與 HANDOFF、OVERVIEW 在 `claude/review-i-1189-1241`；六個修正（I1–I6）在 [#1247](https://github.com/a91453/railway-game-ios/pull/1247)（`claude/review-i-fixes`）。
- 以下 **VERIFIED** 都在 Linux 上實跑，用官方 Swift **6.4.0**（`/opt/swift`）。不代表 iOS 或實機的結果。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 範圍內合併的 PR | 42 個 |
| 程式 PR（有點數） | **25 個、28 點**：GameCore 3 個（#1199、#1220、#1225）各 2 點；其他 22 個各 1 點 |
| 0 點（跳過） | 17 個。只改文件：#1190、#1191、#1196、#1197、#1205、#1207、#1209、#1221、#1223、#1224（建模手冊）、#1235、#1237、#1238、#1241；只改 What to Test：#1240；只加模型與它的產生工具：#1203、#1215（`tools/n700s-n700st/` 產生的是私庫的模型包，不是 App 打包的資料） |
| 新發現 | **8 個**，都是 P3；沒有 P1、P2 |
| 已修 | **6 個**：I1–I6（#1247，四個附回歸測試，兩個是 App 的 SwiftUI，Linux 測不到） |
| 沒修，交出去 | **2 個**：I7、I8，見第四節；另有一條 01LARTBY 處理中的備註 |

三個 GameCore PR 由本 session 自己讀。其他的分給四個子代理：3D 繪製（6 個）、列車模型（5 個）、App 功能（5 個）、課程／跟車／CI（6 個）。子代理的發現都由本 session 再讀程式確認；I1、I3、I4、I5 由本 session 寫測試，在 origin/main 的原始碼上跑紅。

## 二、逐 PR

GameCore（各 2 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1199 | 審查 H 的 H1：`buyMapTile` 有路時替新地塊的城鎮開 3×3 種子；`townCentres(of:seed:)` 與 `foundTowns` 用同一個種子與 `.standard` 範圍，格子換算一致；存檔 72 讀檔時 `seedBoughtTilesRoads()` 只補「沒有任何道路城鎮在裡面」的已買地塊，起始地塊有地圖自己的城鎮所以不動，再跑一次不變；長路先照城鎮、再照每個其他車站（`drawn` 去重），順序決定；車站面板 footer 的兩種語言 | 無問題 |
| #1220 | 10i-2 公車接駁，存檔 73：`BusRoute` 的編解碼與 `isValid`（`feederMinutes` 夾到一天，修了獨立審查的擋合併項）、`allocateID` 與 `nextBusRouteID ≥ 1`、`busLegs` 的檢查順序與失敗不改世界、Dijkstra 的決定性（同距離照列與欄）、`refreshBusFeeders`（`nearest.keys.sorted()`、步行範圍排除、最近站牌）、`modeShiftKept` 的分配（乘積上限 1e6 × 1e6 不溢位）、`settleBuses` 的帳（`dailyBuses` 的 breakdown 與 `entryIsValid` 的正負號）、拆站時一起關掉公車路線、`LineAcquisition` 的 `kind` 舊存檔讀成鐵路、`RoadGrid` 與 `landBlocks` 解碼的總格數上限、`PassengerPlanCache` 的 key 帶 `busFeeders` | I8（P3，備註）。公車指令目前沒有 App 呼叫，玩家碰不到 |
| #1225 | 公車平衡：`riderShare` 在算平均分鐘之後才縮放（人數與分鐘用同一批，平均不變）、`dailyDepartures` 的兩種班表、`dailyCost` 不溢位（最多 1440 × 2 × 12.8 M m × 2000）、到站的人也搭公車回家（`countBusRiders(arrived)` 只算終點到站，不算轉乘） | 無問題 |

其他（1 點）：

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1189 | 決策 404：`swift-shards.sh` 的 watchdog（TERM 收掉背景 `sleep`）、`class_seconds`、時間警告、`SWIFT_TEST_WORKERS`（CI 是 1）、log 不重複計數、`SeededStreetPlanTests` 量執行緒 CPU 時間；`swift-shards-selftest.sh` 通過 | 無問題 |
| [#1193](https://github.com/a91453/railway-game-ios/pull/1193) | 教學卡片留在原位：`previous` 的座標換算、`placed` 只在摺疊狀態相同時用、每一步 `.id` 重設、摺疊判斷不看 `previous`（不會開關循環） | **I6（P3），已修** |
| [#1194](https://github.com/a91453/railway-game-ios/pull/1194) | 決策 403 續：側面視角的朝向、鏡頭在視角間重設、沒有月台時退回後方、`Map3DTrains` 的中點與長度、`map3DLookoutStop` 的單位、跟車列的 `ViewThatFits` | **I5（P3），已修** |
| #1195 | 審查 H 自己的修正：`hadStations`、`holdsForPlaces` 的三個用處、`.buildTrack` 的 `drawn: false`；第 1 課與主教學不變 | 無問題 |
| #1192 | `.standIn` 目標：粗分塊跳過、兩個 Metal pass 的畫法、透明屋頂與地下模式、`onPlacedGround` 的強制取值有 `outline.count >= 3` 擋住、scene key 的建物數 | 無問題（太陽陰影畫盒子，和以前一樣） |
| #1198 | 決策 405：18 個 campaign 分片沒有重複、沒有漏掉、類別都存在；GamePresentation tier 仍是整個模組；1020 秒的警告與 selftest；CLAUDE.md 寫 21 個 job | 無問題 |
| [#1201](https://github.com/a91453/railway-game-ios/pull/1201) | 700T 車頭塗裝：五個模型進包、尾車繞垂直軸轉 π、強制解包只碰常數幾何；`tools/train-shape-refresh` 只渲染與檢查，App 不打包它的輸出 | 無問題 |
| #1204 | 審查 H 的 H4–H6：`runOn` 會結束、`addJoins` 之前 `groundPoints` 已填、坡道道路的範圍、標線的橋面判斷、隧道的架空線端點 | 無問題 |
| #1206 | 缺按鈕證明腳本：正規表示式在兩個檔各剛好一處、剩下的仍能編譯、兩份備份不同名、xcresult 要剛好一個失敗且是那句話 | 無問題 |
| #1208 | 決策 403：喇叭（`blowsByItself` 在暫停、關 3D、換跟的車、1× 時重設；wav 名稱與 pbxproj 一致）、3D 拍照（`framebufferOnly` 切換、blit 在 present 之前、BGRA 的位元組序） | 無問題 |
| #1210 | 決策 406：`lanes(after:)`、`steadyGround` 與 `drawnGround` 同一種三角切法、`FileGround.corner` 範圍外退回、`end.along > 0` 擋除以零 | 無問題 |
| #1212 | 底圖檔在背景找：`nonisolated` 的資料、舊紀錄沒有 `baseMap` 照讀、`keepLand` 的條件加了 `roads`、圖磚的南北順序、`setRoads` 的檢查使 `preconditionFailure` 不會觸發 | 無問題（讀路仍在主執行緒，決策 400 已記為下一步） |
| [#1216](https://github.com/a91453/railway-game-ios/pull/1216) | 決策 407：`chunks()` 的退路不會無限遞迴、橋墩在街景之前、`.base` 目標的還原、橋墩配對與 `last`、索引範圍、`isOverWater` 的格子 key | **I3、I4（P3），已修** |
| [#1217](https://github.com/a91453/railway-game-ios/pull/1217) | 決策 408：`variant(of:number:)` 兩條畫法、遠近模型的名稱前綴、`decodedMesh` 的範圍檢查、`refreshHighSpeedRunning` 不動 700T、`decimate.py` 決定性 | **I1（P3），已修**（與 #1234 一起）；後半列的備註見第四節（01LARTBY 處理中） |
| [#1218](https://github.com/a91453/railway-game-ios/pull/1218) | 決策 409：只看朋友路網時每一條存檔路徑都不寫（`saveCurrentGame`、自動存檔三種、「回到」選單、`returnToStart`、`begin` 重設）、新遊戲與只看的流程、`news.isDemo` 擋成就、大小與不信任輸入的檢查、Info.plist、Inbox 清理 | **I2（P3），已修**；沒有會蓋掉或弄壞玩家存檔的路徑 |
| [#1219](https://github.com/a91453/railway-game-ios/pull/1219) | 決策 397 續：輪次編號只認最新一輪、`cloudMarks` 的 key、`fillMarks` 各分支、`syncNow` 的條件、兩種語言 | **I7（P3），交出去** |
| #1222 | 決策 401 續：接點與 run 的迴圈會結束、`calling` 沒有重複的站、`rest` 的範圍、`layDemoDouble` 的對半、依系統挑半徑、`trackNode(at:)` 的 1 m 高差 | 無問題（`layDemoDouble` 中途失敗會留下沒有月台的軌道，單線段已先過 `tracePlan`，不算發現） |
| #1227 | 決策 410：退化三角形的門檻、裙板切割的配對、`NoseShape.read` 不越界、`edges` 排序後決定性、`noseColour` 取代 `painting()` 結果相同、`n700sGFar` 不變 | 無問題 |
| #1231 | 10j-2 淡海輕軌：`workOutRealLineSale`、`realLineOffer` 的 key、第一站貼齊、依系統找可買的線、過夜方向、`metro_runs.json` 的 VB（212 班、過夜 3＋2，在 5 股之內）、pbxproj | 無問題 |
| #1233 | 加四組沒人畫的 `*Classic`，#1234 乾淨地刪掉 | 無問題 |
| #1234 | 列車包：`TrainPack.sets` 有 `n700sG`、兩條畫法都傳 `locked`、鎖住時全部是 700T、遠景是 `highSpeedFar`；測試版開關預設確實是關（d18a880 被 4b54a58 完整還原） | 無問題（I1 的致謝文字因它而過時） |
| #1236 | 定位鈕與圖例（不含 UITests）：`OneShotLocation` 的逾時只在詢問中、`finish` 只跑一次、`isOnButton` 的幾何、Debug 才有的測試碼、`legendMaximumHeight`、圖例先量再捲沒有版面回授迴圈 | 無問題 |

## 三、修了的（#1247）

### I1（#1217、#1234）致謝說「3D 地圖上一半的高速列車」，P3，已修

- **路徑**：設定 → 資料來源。#1234 起白色高鐵（N700S-G）只在列車包裡，App Store 版不會解鎖（`TrainPack.isUnlocked` 要測試版），測試版的開關也預設關。
- **玩家看到**：致謝寫著一半的高鐵是白色的，地圖上一輛也沒有。
- **回歸測試**：`RealRailwaysTests.testEverySourceIsCredited` 多一個斷言：這條致謝要提到「列車包」。在 2ae0f7c 上紅（兩種語言）。
- **修法**：兩種語言改成「列車包裡 3D 地圖上的高速列車，白色車身配深綠色線條：遊戲作者自己做的模型。」

### I2（#1218）存檔列表的匯出還是 JSON，P3，已修

- **路徑**：開始畫面 → 存檔列表 → 某份存檔的「匯出」→ AirDrop 或 LINE。`SaveLibrary.exportFile(of:)` 寫的是 `.alongtheline`，`ExportedListSave` 卻宣告 `exportedContentType: .json`（`StartView.swift:1088`）；決策 409 第 1 點說三個匯出都用遊戲自己的類型，遊戲選單的 `ExportedSave` 已經是 `.alongTheLineSave`。
- **玩家看到**：接收的裝置拿到的是 JSON，要不要提供「用遊戲打開」看系統怎麼認副檔名，要實機確認。
- **回歸測試**：無（App 的 `Transferable`，Linux 測不到）。**UNVERIFIED LOCALLY**，`ios-build.yml` 會編譯。
- **修法**：改成 `.alongTheLineSave`。

### I3（#1216）路線改成高鐵後，高架要等一週才換樣子，P3，已修

- **路徑**：把現有路線改成「高鐵」或給它高鐵車組。`highSpeedTrack()` 看 `line.isHighSpeed`，但 3D 的重建 key（`Map3DSceneKey`）與 `Map3DLineBands.Signature` 都不含它，軌道、月台、停靠站沒變就不重建。
- **玩家看到**：高鐵線底下還是台鐵的梁與橋墩，直到每週重建或下一次別的修改。
- **回歸測試**：`Map3DLineBandsTests.testTheSignatureChangesWhenALineTurnsHighSpeed`。在 2ae0f7c 上紅。
- **修法**：`Signature.Line` 多記 `isHighSpeed`。

### I4（#1216）高架上的路線色帶一半埋在護欄裡，P3，已修

- **路徑**：`Map3DLineBands.offset(on: .viaduct)` 仍是 `5/2 − 0.35 = 2.15 m`，寬 0.3 m，所以在 2.0–2.3 m；#1216 的新護欄在 2.15–2.5 m、高 0.9 m。
- **玩家看到**：近看時高架的路線色帶只剩一半。
- **回歸測試**：`Map3DLineBandsTests.testTheBandOnAViaductClearsTheParapet`（色帶外緣 ≤ 橋面半寬 − 護欄寬，仍在鋼軌外）。在 2ae0f7c 上紅（2.30 > 2.15）。
- **修法**：`deckWidth/2 − parapetWidth − width/2`（1.85–2.15 m）。沒改的：高鐵的橋面寬 8.5 m，色帶仍照 5 m 的橋面放，在橋面偏中間；要照路線的樣子換位置，得把 look 傳進色帶，留給 3D 城市線。

### I5（#1194）站距很近時，車站視角看不到列車進站，P3，已修

- **路徑**：車站視角在列車離站後，繼續看上一站，直到列車走了「車長兩倍 + 100 m」（`stationLingerMetres`）。下一站比這更近時（課程常見的短站距），列車停好了才換到下一站（`Map3DFollow.swift` `map3DLookoutStop`）。
- **玩家看到**：鏡頭停好後才飛到月台，進站那一段一直看不到。
- **回歸測試**：`Map3DFollowViewsTests.testCloseStopsStillShowTheTrainArriving`（80 m 的一段、沒有車廂的車停留 100 m，每秒一個 tick）。在 2ae0f7c 的原始碼上紅（下一站第一次出現時列車已經在等）。
- **修法**：停留距離最多是這一段的一半。

### I6（#1193）iPad 轉向後，教學卡片留在直向時的位置，P3，已修

- **路徑**：iPad（820×1180）一個閱讀步驟，卡片置中在約 (240, 465)；轉成 1180×820，舊框仍放得下，沒有目標時直接沿用，有目標時它是第一個候選、成本相同就勝出（`TutorialCardPlacement.swift` `placement(of:in:available:)`；`TutorialOverlay.swift` 的 `sized`）。
- **玩家看到**：整個步驟卡片都偏一邊，或離它說的地方很遠。iPhone 轉向後舊框通常放不下，很少碰到。
- **回歸測試**：無（App 的 SwiftUI 狀態，Linux 測不到；GamePresentation 的沿用是刻意的）。**UNVERIFIED LOCALLY**。
- **修法**：`bounds.size` 一變就清掉 `placed`，重新放。

## 四、沒修、交出去的

| # | PR | 嚴重度 | 內容 | 為什麼沒修 | 交給誰 |
| --- | --- | --- | --- | --- | --- |
| I7 | #1219 | P3 | **線上時也說「連上網路後會自動上傳」**。回到開始畫面時 `returnToStart` 寫自動存檔並同步；這一輪剛把檔案放進 iCloud 容器，立刻再列一次，`ubiquitousItemIsUploaded` 還是 false，`fillMarks` 標 `.waiting`（`SaveSync.swift` 約 429 行），狀態列說「1 個存檔等待上傳到 iCloud，連上網路後會自動上傳。」，要到下一輪（回前景、背景或按「立即同步」）才變 | 這句是決策 397 續刻意選的（同一句涵蓋離線與上傳中，`docs/decisions/397.md` 135 行），改字要原作者決定；也可以在剛上傳的那一輪幾秒後再列一次，或做決策 397 下一步的 `NSMetadataQuery`。只讀程式，**UNVERIFIED**：iCloud 多快開始上傳只有實機知道 | 決策 397 的作者，兩台實機驗證時一起（與 H7 同時） |
| I8 | #1220 | P3（備註） | `BusRoute` 解碼與 `busRoutesProblem` 不檢查 `id ≥ 1`；`id` 0 或負數只要小於 `nextBusRouteID` 就照讀 | 公車指令還沒有 App 呼叫，只有改過的存檔會有；要動 GameCore 的驗證，讀檔規則改變照派工交出去 | 決策 400 的作者線，下次動 `BusRoute.swift` 時一起 |
| — | #1217 | 備註 | **01LARTBY 處理中**。`Map3DTrainSets.swift:349-358` 的 `n700sG()` 把中間的 C、D 單元都朝前畫；作者的組法是 A B C D E ｜ E D C B A，後半每節各朝自己的方向，所以第 9 節 D 的集電弓罩和第 4 節在同一端，沒有鏡像 | 和 88.1 的車尾亂飄同一區 | session_01LARTBYik4n6iAeQXeQs8z4（`claude/fix-n700sg-tail-drift`） |

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| `swift build --build-tests -Xswiftc -warnings-as-errors`（origin/main 2ae0f7c 與 #1247） | **VERIFIED**，乾淨 |
| I1、I3、I4、I5 的回歸測試 | **VERIFIED**：四個都在 2ae0f7c 的原始碼上紅，修了之後綠 |
| `swift test --skip-build --filter "Map3DFollowViewsTests\|Map3DLineBandsTests\|RealRailwaysTests\|Map3DDriverHUD\|Tutorial"`（#1247） | **VERIFIED**，98 個，0 失敗 |
| `swift-shards-selftest.sh`、分片類別不重複、都存在 | **VERIFIED**（子代理） |
| I2、I6 | **UNVERIFIED LOCALLY**：App 的程式，交給 `ios-build.yml` 編譯；轉向與分享清單要實機看 |
| I7、I8 與其他沒問題的 PR | 只讀程式、追了呼叫路徑 |
| 完整測試、iOS 的建置、UI 測試、實機畫面 | 交給 CI（`ci.yml` 的 tier、`ios-build.yml`）與實機，**UNVERIFIED LOCALLY** |

## 六、五方

- 玩家：沒有會丟存檔、當掉或卡住的問題；I5（課程短站距看不到進站）、I6（iPad 轉向）最容易碰到，已修。
- 鐵道迷：I3 高鐵線該是高鐵的高架，已修；N700S-G 後半列不是鏡像組法，01LARTBY 處理中。
- 開發：三個 GameCore PR 沒有問題（I8 只是讀檔驗證少一條，玩家碰不到）；修正只動 GamePresentation 與 App，不動存檔、重播與 golden。
- 美術：I4 色帶不再被護欄吃掉；高鐵橋面的色帶位置留給 3D 城市線。
- 音樂：無（#1208 的喇叭聲沒有問題）。
