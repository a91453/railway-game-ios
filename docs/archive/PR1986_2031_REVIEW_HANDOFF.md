# 交接：PR #1986–#2031 審查（審查 L16，0.6.0 (123)、(124) 發版後）

派工單 REVIEW-L16（遊戲規劃第 60 任 session_01YGNNumCi7AYjpiS4ntJZjK，2026-11-11）。規則是「每次發版後派一輪」。這一輪審 L15（`PR1983_1985_REVIEW_HANDOFF.md`）之後合進 main 的 PR，格式同 L15。

- Session：REVIEW-L16（session_01YGNNupozifvTzHdaz6hs68），branch `claude/review-l16`。
- 基準：`main` **3313197**（#2031 的合併）。每個 PR 都讀 merge commit 對 first parent 的 diff，也讀它的決策檔。
- 範圍：`git log --first-parent dc4a436..3313197`，46 個合併（#1986–#2031，沒有 #2022）。
  - 123、124 兩版是同一個 commit aeb3eef（#2015 的合併）。之後合併的 #2013、#2016、#2018、#2023、#2025、#2028 還沒發版，要進下一版的說明（L16-9）。
- 點數（照 HANDOFF §1「多久審查一次」重數）：**25 點**。
  - GameCore 2 點：#2014、#2025（#2025 動到 13 個 GameCore 檔，查過只有註解）。
  - 1 點（21 個）：#1986、#1988、#1989、#1990、#1993、#1996、#1997、#1998、#1999、#2001、#2002、#2004、#2006、#2011、#2012、#2013、#2015、#2016、#2018、#2023、#2028。
  - 0 點：#1994（標題說效能，diff 只有決策 657 與 HANDOFF 一列）、#2003（測試與文件）、#2010（文件）、#2008、#2009（Codex 的模型配方）、其餘 18 個只改文件。
  - 規劃粗數 27 點，差在 #1994、#2003、#2010 沒有程式。
- 分工：
  - 本 session 自己讀 GameCore 的 #2014、#2025，並重跑下面標「核對」的發現。
  - 其餘分四組交給子代理讀程式、跑既有測試：修正前幾輪的（#1988、#1989、#1996、#2011、#2015）；真實路線與劇情（#1990、#2003、#2010、#2006、#2012、#1997、#2002）；App 與 CI（#1993、#1994、#1998、#1999、#2004、#2028）；3D 與聲音（#1986、#2013、#2016、#2023、#2001、#2018、#2008、#2009）。
- 存檔版本、決策編號、golden schema 都**不動**；只改文件。

## 〇、範圍

| PR | 內容 | 點數 |
| --- | --- | --- |
| **#2014** | TYMC-DEADLOCK，決策 666：沒閉塞的行車控制下，擋路又回不了機廠的沒班車空車讓到最近的月台（GameCore） | 2 |
| **#2025** | 改寫來源紀錄與遊戲設計的說法；150 個檔，GameCore 13 個檔只改註解 | 2 |
| #1986 | 決策 653：`.m3dmodel` 第 2 版，模型帶自己的貼圖 | 1 |
| #1988 | FIX-L15-UI，決策 656 | 1 |
| #1989 | FIX-L14 | 1 |
| #1990 | TYMC-REBUILD-GAPS，決策 654 | 1 |
| #1993 | 決策 658：iPad 教學 job 先建置再開機、走法改鎮到鎮 | 1 |
| #1996 | FIX-L13，決策 661 | 1 |
| #1997 | 決策 660：錢不夠蓋時指出附近蓋得起的地點 | 1 |
| #1998 | 決策 659：2D 地圖的街道只選不鋪、教學 UI 測試關掉 log 抄寫 | 1 |
| #1999 | MAC-SMALL，決策 663：觀光頁、票價頁、教學結束 | 1 |
| #2001 | 決策 664：馬達聲 | 1 |
| #2002 | 決策 665：第二批 9 座站房接進 3D 地圖 | 1 |
| #2004 | 決策 667：full lane 的 build job 加 XCTest 暖身 | 1 |
| #2006 | 決策 668：內灣線支線挑戰 | 1 |
| #2011、#2015 | 決策 673：123 的說明與前幾版的更正 | 各 1 |
| #2012 | 決策 671：內灣劇情與三個角色 | 1 |
| #2013、#2016 | 決策 672、674：看得到地下 | 各 1 |
| #2018 | 決策 675：Kenney 音效 | 1 |
| #2023 | 3D 雨絲改在 GPU 畫 | 1 |
| #2028 | 決策 676：最低版本 iOS 26 | 1 |
| #1994、#2003、#2010 | 決策 657（量 Heap，不加依賴）；機捷下午的門檻測試與量測 | 0 |
| #2008、#2009 | Codex 的中式屋頂配方、基隆雨棚（略看） | 0 |
| 其餘 18 個 | HANDOFF、健檢報告、優先表、L15 本身 | 0 |

## 一、結論

| 項目 | 數量 |
| --- | --- |
| P1（當天修） | **0** |
| P2（該修） | **3**：L16-1、L16-2、L16-3 |
| P3（記著） | **17**：L16-4 到 L16-20 |

- 沒有 P1。123、124 已發，沒有東西要撤回。
- **#2014（GameCore）的改法站得住**：
  - 存檔往返：讓路中的每一個 tick 存檔再讀回都相等，讀回後再走 5 tick 也和原本相同（本 session 的暫時測試，已刪）。
  - 批次與逐分相等有 PR 自己的測試；順序都走排序過的 ID 與站序，沒有字典順序。
  - `runTrainEnteringDepot` 抽出 `runDepotEntry` 後逐行對過，行為相同。`standingAside` 多了 `$0 != spare.id`，對原本的備用車讓路沒有影響（備用車不在等路的名單裡）。
  - 留下的是成本與跳站沒量（L16-5）。
- **#2025 沒有改到行為**：Swift 檔（GameCore 13、GamePresentation 29、App 8、測試 9）改的每一行都是註解，用 diff 逐行濾過；`tools/` 改的是寫進紀錄的字串。留下的是驗證紀錄的雜湊（L16-6）。
- **CI 規則沒有被繞過**：#1993、#1998、#2004 沒有放寬測試的逾時、沒有拿掉測試；`continue-on-error` 只在暖身步驟，被暖身的那支仍在正式清單裡跑。但 iPad 教學 job 之後還是紅過一晚（L16-3）。
- **L13–L15 的修正都對得到程式**（下面第三節的表）。App 端的接線（SwiftUI、Metal）只讀程式，UNVERIFIED。#1988 引進一個小退步（L16-7）。

## 二、發現

### L16-1（P2，核對）#1999：邊界外但有車站服務的景點被收起來，名產店按不到

- **位置**：`RailwayGameApp/Views/TourismPanel.swift:31-32`（分組）、`:146-155`（`offMapRow`）；`Sources/GamePresentation/TourismText.swift:172`（`metresOffOwnedGround`）。
- **問題**：景點不在已買的格子裡就算「地圖外」，收進折疊段，那一列只有名字、星等與「約 N 公里」，沒有狀態、車站、人次，也沒有名產店的按鈕。
- **為什麼是問題**：GameCore 判斷景點有沒有被服務不看地權：`servingStation(at:)`（`Tourism.swift:506`）只看 800 m 內有沒有收觀光客的車站，`attractionStation` 還會走纜車與渡輪。邊界外 800 m 內、或用纜車渡輪接到的景點有觀光客與收入，#1999 之前看得到它的數字、能開店，現在整列被收起。已開過店的也看不到、不能升級。
- **重現**（本 session 的暫時測試，在 3313197 上紅，已刪）：`GameWorld.newGame(eventSeed: 3, buysMap: true)`，在已買那格西邊界外 300 m 放一個景點，`attractionRows(in: .english)` 那一列 `offMapMetres == 300`、文字是「About 1 km off your map」，同時 `nextShop != nil`（有店可開）。面板對 `offMapMetres != nil` 的列不畫 `shop(row)`。「邊界外的景點有車站時仍被收起」這一半是讀程式推得，沒有建線重現。
- **修法**：`metresOffOwnedGround` 在 `attractionStation(of:) != nil` 或已有名產店時回 nil（或面板分組多看這兩件）。順帶：一公里以內寫公尺，不要 300 m 寫成約 1 公里。
- **大小**：小。不動 GameCore。

### L16-2（P2，核對）#2012：內灣劇情給的建議和決策 668 量到的相反

- **位置**：`Sources/GamePresentation/NeiwanStory.swift:30-34`（`neiwan.1`）、`:57-61`（`neiwan.6`）、`:74-78`（`neiwan.9`）、`:110-113`（`neiwan.failed`）。
- **問題**：這幾句是集集線的難處（撐過頭幾個月）：「先用短車開」「先別加車」「頭幾個月把車開得省一點」。決策 668 量到內灣線的難處相反：兩節車三年都卡在 33,096 人次、淨利 7,489 萬，到期失敗；四節車或兩列車才金牌。
- **後果**：
  - `neiwan.9`（唯一叫玩家加長的一句）要 50,000 × 75% = 37,500 人次，高於兩節車的上限 33,096。照 `neiwan.1` 用短車的玩家永遠等不到它。
  - 到期失敗後 `neiwan.failed` 叫他下次更省，方向反了。
  - 決策 668 的歡迎詞已拿掉「先用一列短短的列車」，劇情又加回來。
- **重現**：對照 `docs/decisions/668.md` 第二輪的表（Two cars 那一列）與 `NeiwanTargets.riders`；不用跑。
- **修法**：`neiwan.1` 改成「人多，車很快會滿，記得加長」；`neiwan.9` 降到 50% 或 60%；`neiwan.failed` 改講運能；`neiwan.6` 留「票價別太高」。兩種語言一起改。
- **大小**：小。不動 GameCore。

### L16-3（P2，已驗證 run）#1993、#1998 之後 iPad 教學 job 仍紅過一晚

- **位置**：run 42736226266（main cd0fbab，11-10 01:30 UTC 的 full lane）的 iPad job；`RailwayGameApp/UITests/TutorialUITests.swift:134`。
- **問題**：`testBuildingTrackEnablesNextAndSkipEnds` 失敗，「The folded card did not open」。其他 8 支綠，iPhone 四個 job 全綠。前一晚（42702233354）與後一晚（42921933667）是綠的；之後沒有 PR 改這支測試或這個 job。
- **為什麼是問題**：和決策 638 的偶發、決策 659「沒修的」是同一種症狀。三晚紅一晚，「iPad full lane 穩了」還不能下結論；發版前要 full lane 綠，偶發紅會擋發版或被當雜訊。
- **未驗證**：那一輪的 `ipad-tutorial-trace` 沒下載，是不是又落在停頓裡的觸控取消沒有確認。
- **修法**：下載那一輪的 trace，對 134 行那一下的時間看有沒有 stall；再決定 `openCard` 要不要「還沒開才再按一次」，或做決策 659 提的 SF Symbol 暖身。相關的還有 L16-19。
- **大小**：小到中。不動 GameCore。

### L16-4（P3，未驗證）#2006：內灣挑戰的資金沒有在真實地形與高架下量過

- **位置**：`Sources/GamePresentation/BranchLineChallenge.swift:349-351`（資金 2,400 萬）；決策 668「怎麼量」。
- **問題**：報告是平地鋪完 1,800–1,870 萬，只多給 600 萬。歡迎詞叫玩家開「沿真實鐵路」，而沿真實鐵路描的軌道會照著蓋高架與隧道（`DataSourceCredits.swift:380` 的說法）；新竹—竹中現實是高架雙線。決策只寫「會比一千八百萬多」，沒有數字。
- **影響**：錢不夠一次鋪到內灣；可以借錢或分段鋪，不是硬卡，但金牌要第一年淨利 1 億。
- **怎麼驗**：`JijiReportTests` 的 `Route.build` 改用 session 的高度與 `RealRailwayTracing` 的結構，或在 App 裡照歡迎詞描一次。量出來不夠就升 P2。
- **大小**：中。不動 GameCore。

### L16-5（P3）#2014：讓路每分鐘找遍全世界的車站，成本與跳站沒量；門檻測試不在 CI

1. **成本（未驗證）**：`depotBoundMakingWay`（`Sources/GameCore/Railway/Deadlock.swift` 決策 666 那一段）的目標是 `stations.map { ($0.id, nil) }`，全世界每一站（包含別條線、走不到的站），對每個起點各找一次路徑；`resolveDeadlock` 與 `changeBerth` 都沒動作的每個整分鐘都會走到。有擋路的候選車又找不到能讓的月台時，每分鐘重找一次。`passingPlace` 也掃全部車站，但只在死結時。決策 666 只寫台鐵、高鐵、文湖線「報告逐行相同」，沒有量時間。請 HEALTH-124 或下一輪 CIOPT 在大地圖（全台、幾百站）最高倍速量一次；要省就只找這條線的站，或找不到時記住到下一次路網或列車位置改變。
2. **跳站（決策已寫）**：兩天讓路 65 次，有一列連讓 15 站。玩家會看到空車來回跳；123 的說明沒提。
3. **門檻測試**：決策的主要宣稱（第 2 天沒發 12 → 5、下午都有發）靠 `TYMC_AFTERNOON=1 AirportShuttleDepotTests`（約 15 分鐘），預設 `XCTSkip`，CI 不跑。CI 守住的只有小世界的 `RunSpareInTheWayTests`。建議每晚的完整 run 設這個環境變數跑一次，或併進健檢。
4. **行程紀錄**：讓路直接從 `.travellingToStop(1)` 開始，沒有 `logArrival`，所以不進行程紀錄，但算進空車里程。和備用車讓路一致，只記著。
- **大小**：第 1 點小到中，動 GameCore。

### L16-6（P3，已驗證 diff）#2025：驗證紀錄裡的 SHA-256 是手改的；尺寸出處在公開庫看不到了

1. `docs/art/tra-r100/rebuild-verification.json`、`swift-assembly-verification.json`（`configuration_sha256`）、`docs/art/tra-emu700/producer-verification.json` 的雜湊改成改寫後檔案的雜湊。這些檔的意思是「某個 producer commit 重建出這些位元組」；現在記的雜湊，那個 commit 重建不出來。`tools/c341/bundle.py` 等會 `assert git show <commit>:path == 檔案`，照紀錄裡的 producer commit 重跑會失敗。
2. 幾處尺寸的出處（例如 `tra-r100/sources.json` 的高度 3963 mm）從網站名稱改成「reference photo's … value」；數字還在，出處只剩私有素材庫（assets #88）。授權上不需要（只當參考、沒有散布），Wikimedia、官方單位、音源的署名都還在（逐行濾過被刪的行）。
- **修法**：在各 `source-record` 或 README 加一行「2026-11-11 文字改寫，雜湊隨之更新，原紀錄在私有素材庫」，下一次真的重建時讓紀錄重新產生。**大小**：小。

### L16-7（P3）#1988：`LessonFramingLatch` 會晚一步搶走鏡頭；另兩件小事

1. **退步（已驗證：讀程式）**：`Sources/GamePresentation/DeviceFamily.swift:135-143`。步驟出現時若兩鎮都看得到，`done` 留在 false；之後 inset 任何一次改變（`MapView.swift:1131` 的 `onChange(of: framing)`，上方那一欄跳訊息就變），而玩家已把一鎮拖出畫面，就回傳框好的鏡頭，不看 `settling`。決策 656 第 3.3 點寫「過了 2 秒就不再動」不成立。只影響寬視窗的教學鋪軌步驟。測試草稿：
   ```swift
   var latch = LessonFramingLatch()
   XCTAssertNil(latch.camera(for: region, from: far, clearOf: ScreenInsets(), layout: .wide, settling: true))
   XCTAssertNil(latch.camera(for: region, from: start, clearOf: panel, layout: .wide, settling: false), "settled: left alone")
   ```
   修法：檢查遮蓋之前先 `guard settling else { done = true; return nil }`。小。
2. **倍速提示（設計內，UNVERIFIED 觀感）**：`GameSession.swift:1217-1223`，提示顯示時開一個面板再關，`speedLagHintSeen` 重設，提示會再跳一次。HUD 的預報 popover 與人口圖例的說明 popover 沒有掛 `coversTheMap`。
3. `demoLines` 放進 `NewsLog` 後會跟著共享路網檔帶走；LineID 被刪後會不會重用沒查。

### L16-8（P3）#1989：兩支測試證明得比 HANDOFF 說的少

- L14-4：`testNoLineTheListOffersIsRefusedForItsLand` 只算 `realLineOffer(for:).problem`，沒有真的 `build`，也沒有涵蓋環線。
- L14-1：`testATrainTakenOffIsWeighedAgainstItsOwnService` 的停站模式那段直接呼叫靜態函式；session 走得到的 `addPassingLoopToSelectedLine` 沒有測試。補一支走 session 的。小。

### L16-9（P3）#2011、#2015 與下一版的說明

1. 「機場捷運第 2 天下午不再停開」：決策 666 量的是新局、簡單＋行車控制；擬實規則與舊存檔沒量（和 L15-3 同一類）。
2. 「倍速提示不會再把開著的畫面關掉」寫成確定修好；決策 656 自己標 UNVERIFIED。
3. 英中不一：「leave the screen less busy」對「背景少算很多」；md 的 120 版更正有「機廠叫輕軌機廠」，App 卡片沒有。
4. **下一版要寫的**：#2013、#2016（顯示地下）、#2018（音效）、#2023（雨絲）還沒進任何說明；#2028 之後要寫「這一版起需要 iOS 26」（`.github/testflight-whats-new.md` 還是 123，沒有這句，也沒有自動檢查）。

### L16-10（P3）#1990：重試的路沒有快測試；迎面渡線還有三種默默略過

- `testItIsBuiltOnTheFirstNight` 要 `TYMC_FIRST_NIGHT=1`，CI 不設。預設會跑的只走「第一股就放得上」；「被拒 → 換下一股 → 下一輪重試」沒有 CI 測試。補一個兩列車、一座機廠兩股的小世界測試。
- `RealLineAcquisition.swift:1269-1291`：站名不在 `runs.stops`、那站不在 `turning`、`turnsBackBetween` 為 false 時，迎面渡線不鋪也不報錯（L15-5 只補了「放不下」）。迴圈後斷言清單裡每一站都真的鋪了。小。

### L16-11（P3）#2012 的小事

- `neiwan.5`（`NeiwanStory.swift:51-55`）講合興，條件只有運量 25%，沒有 `after: .milestone(1)`；只鋪新竹市區段就可能觸發（觸發時機未驗證）。
- `:70` 彭阿婆的「食飽未？」是台語，客語是「食飽吂？」（未查外部資料）。
- 決策 671 寫阿羅伯「1950–70 年代」，程式與台詞是民國四十幾年；決策沒有「沒選的」、驗證，也沒記新頭像的第三級截圖有沒有給規劃看過。

### L16-12（P3）#1997：只查中心點所在的土地區塊

`BuildingSession.swift:463-468`（`isLandRead`）。佔地跨到還沒讀的相鄰區塊時，報的「只要 NT$…」會偏低。改查佔地四角。`landBlocks` 不是 nil 的那條路沒有測試。小。

### L16-13（P3，已驗證：跑報告）#2002：站房淨空的測試對 9 站裡的 5 站是空的

- `Map3DStationExteriorBatch2MapTests.testEachStandsClearOfTheTrack`：臺南、奮起湖、阿里山、烏樹林、溪湖一條軌道都沒有（`STATION_EXTERIOR_REPORT=1` 的報告：軌道線 0），「沒有三角形在淨空內」「留下至少一半」恆真。決策表的嘉義 0.92、橋頭 0.73 是另一種量法，沒被測試鎖住（測試裡是 0.97、0.79）。
- 「月台在輪廓 40 m 內才代替」（`Map3DStations.swift:311-326`）對林鐵、糖鐵 6 站沒有測試。
- 玩家在那裡描線時 `exteriorCarved` 照樣會切，切到剩不到一半退回套件站房，所以有後路。修法：測試裡斷言軌道非空，嘉義、臺南、橋頭鋪示範路線。中。

### L16-14（P3）#1986：現有的載入路徑都丟掉貼圖；工具測試不在 CI

- `Map3DCityBus.swift:45-65`、`Map3DSceneryProps.swift` 約 190 行、`Map3DGarbageTruck.swift:249` 的 `model(from:)` 重建頂點時不帶 u、v 與 `texture`。第 2 版的檔放進來會是一台全白的車，不報錯。現在 App 裡沒有第 2 版的檔，玩家不受影響。測試草稿：讀 `tools/glb-to-m3dmodel/fixtures/tiny-textured.m3dmodel`，`Map3DCityBus.model(from:)` 之後斷言 `texture != nil`（未跑）。
- `tools/glb-to-m3dmodel` 的 `node --test` 沒有 workflow 在跑，「工具輸出等於提交的 fixture」沒人守。`gltf-validate.yml` 加一步。小。

### L16-15（P3，已驗證：讀程式）#2013、#2016：顯示地下的四件小事

1. `Map3DPreviewScreen.swift:1491-1495` 對 `:1528-1530`：透視網格比場景晚一次 `updateUIView` 才重建；暫停中蓋隧道可能停在舊的。
2. `Map3DXRay.swift:119-142`：島式月台成對的兩座各畫一次同一塊島，重疊後比側式深，三角形多一倍。
3. `Map3DTrainLabels.swift:82-88`：標籤往旁邊移只看 `head.inTunnel`，不看開關；開關關著（預設）時標籤指著空地旁邊。
4. `Map3DTrainLabels.swift:81`：每幀為全部車頭建一個字典，只為查最多 3 個。

### L16-16（P3）#2023：駕駛室在隧道裡仍畫雨絲（既有）；文件連結

- `Map3DMetalView.swift:1653` 用 `underground.isUnderground`，而它要「300 m 內沒有洞口、視野內也沒有洞口」（`Map3DUnderground.swift:41-49`）才成立；短隧道、看得到前方洞口、`.back` 視角都照畫。#2023 原樣搬過來，不是它造成的。要修就改成 cab／window 視角且 `head.inTunnel` 就不畫。小。
- `docs/ARCHITECTURE.md` 新增的段落連到 `docs/research/PERF_3D_RAIN_2026-10-30.md`，main 上沒有這個檔。

### L16-17（P3，未驗證：要實機）#2001：馬達聲的四件事

1. 每次換循環都在主執行緒 `play()`（`GameAudio.swift:314-331`、`:449-455`）。決策 379 量過 `AVAudioPlayer.play()` 會卡 10–30 ms，所以 cue 搬到自己的 queue；馬達一次起步換 7 個、一次進站換 8 個，正好在 3D 跟車時。已 `prepareToPlay` 的要多久沒量過。量到會卡就升 P2。
2. `:323-330`：淡出每次更新都重下一次，600 ms 後的 `pause()` 可能在還有聲音時切斷。
3. `:104-113`：中斷（來電）結束只恢復配樂；定速的車輪聲與雨聲可能不回來（既有，馬達繼承）。
4. `RunningSound.swift:178`、`:182`：跟車每步建兩次全路網的字典（`RealLineStock.setKeys`）。

### L16-18（P3）#2018：資料來源頁沒列 Kenney 的音效；舊音檔還在

- `DataSourceCredits.swift:782-798` 的 `kenney` 只寫兩包模型。CC0 不要求署名，但專案對 Kenney 模型是列的，兩包 License 也寫「Credit would be nice」。`testKenneyCuesAreBundledAndCredited` 的 credited 查的是 `tools/audio/kenney/SOURCE.md`，不是 App 的頁面。`tools/audio/README.md` 的總表也沒有這一包。
- `Resources/Audio/goal-met.wav`（230 KB）仍打包但沒人用，決策 675 自己寫了。

### L16-19（P3）#1993、#1998、#2004：量法與流程的洞

1. `StallSampler`（`RailwayGameApp.swift`）堆疊只取 128 格；主執行緒每條完整堆疊的底部都該有 App 的 `main`，決策 659 卻說沒有 App 的函式到 10%，表示堆疊被截斷。「卡在系統，不是 App」的證據比決策寫的弱（未驗證，沒看 trace 原檔）。
2. iPad job（`ios-build.yml:1063-1081`）沒有暖身步驟；四個 iPhone job 都有（決策 667）。
3. `ios-build.yml:255` 決定 PR 跑不跑 iPad job 的 regex 不含 `TutorialJourneyUITests` 與教學取景的檔（`DeviceFamily`、`IPadPlaytest`），造成 #1993 那次紅的缺口還在。
4. `IPadPlaytestFixesTests.testTheIPadWalkFromTownToTownEarnsItsFirstFares` 後半把「沿一列走沒有收入」用寫死的螢幕點釘成斷言，以後改取景會因無關的理由變紅。
5. `docs/research/LAUNCH_TIMEOUT_2026-11-09.md` 寫街道的種子「要開 3D 才會跑」，其實是 2D 地圖的 `.task`。

### L16-20（P3）#2028 的收尾

- `docs/XCODE_CLOUD_ONBOARDING.md:284` 還寫 iOS 17.0。
- `TestBuild.isTest` 的判斷式沒變（`sandboxReceipt`），只是繞過過時警告；TestFlight 上是否照舊為 true 只能發版後看（HANDOFF 已記）。在 Mac 上跑時收據路徑不同，可能為 false，是 #2028 之前就有的（未驗證）。

### 看過、沒有疑點的

- **#2014**：見結論。`makeWayForDepot` 找不到車站就不動作；`held.removeAll` 與其他出口同一寫法；讓路的車到站後 `execution` 回到 nil，線照常送它進機廠（暫時測試看到：06:06 讓到 M、06:14 再走一次、06:16 停）。
- **#2025**：見結論。`.claude/skills/art-style` 只改措辭。
- **#1990**：`build` 全在 `editTrackAsOne` 裡，`berthInDepot` 在複本上試，失敗不留半套；`berthInDepots` 每輪至少進一列否則結束；舊存檔讀檔不改世界。
- **#2003、#2010**：報告測試是環境變數加 `XCTSkip`，沒有從 gate 拿掉東西；結論有數字支持。OpenTTD（GPL）只取想法，有寫明。
- **#2006**：里程碑實際建站、開車後達成，並做 SavedGame 往返；解鎖沒有條件；`JijiReportTests` 改吃 `Survey` 後集集的清單一字不差。
- **#2012**：劇情從世界推出來，沒有另存進度；`after` 鏈不會死鎖；SVG 是自己畫的。
- **#1997**：沒改價錢、沒動 GameCore；每點都問 `buildingPlacement`；測試真的蓋了房子、對了餘額。
- **#2002**：L14-6、L14-7 的路沿用；OSM 的 ODbL 那一句（#1989 補的）涵蓋第二批；20 個名字不重複；三角形數在上限內。
- **#1993、#2004**：測試步驟的 30 分沒放寬，job 上限加長是因為多了建置一步；暖身之後三輪 full lane 的 build job 沒再出現開 App 逾時。
- **#1998**：App 端只改診斷用的 `StallSampler`（只在 UI 測試旗標下）；`seededStreets(laying: false)` 的結果與 3D 場景的 `roads` 有等價測試。沒有動啟動路徑，沒有新的競態。
- **#1999**：玩家文字兩種語言一致、沒有內部單位；高鐵票價的說法與 `tripFare` 相符。
- **#2028**：`#available(iOS …)` 沒有殘留；`Package.swift`、`project.yml`、pbxproj 都是 26.0（drift check 沒重跑）。
- **#1986**：解析器先查檔頭長度、三角形數上限 15,000、總長度相等才讀；貼圖上限 4 MB；未知版本與旗標拒收；第 1 版的路徑沒動。
- **#2013、#2016**：開關關著時不建緩衝、不填 `buried`；隧道網格只在場景版本變時建；隧道口挖地面對橋、架線、街景的判斷都對過。
- **#2023**：Reduce Motion、混色、seed 重建條件、閃電的索引都對；每幀只有 16 個 float。
- **#2001**：錄音不打包，只打包合成檔；出處（素材名、站名、網址）在 `DataSourceCredits` 與 `tools/audio/README.md`；同時最多 15 個播放器；暫停、超過 60×、不跟車、音效關都不出聲。
- **#2018**：兩包的 CC0 原文都留著；每個 cue 3 個播放器、有最短間隔。
- **#1994**：確認只有文件。決策 657「下一步」的四件（`precedes` 先存分鐘數等）之後沒有人做。
- **#2008、#2009**：App 的場景有引用；#2009 有三角形上限，#2008 只有相對斷言；Commons 照片只當參考。

## 三、前幾輪發現的追蹤（以 3313197 為準）

| 編號 | 現況 |
| --- | --- |
| L13-1 | 修到（#2011：120 原筆改成 10×／60×，123 加更正）。程式照舊，文字與程式一致 |
| L13-2 | 邏輯修到（#1988：`mapCovers`，`GameSession.swift:1218`；直接蓋在 2D 地圖上的 sheet／cover 都掛了）。原機制與修法在 Simulator、實機都沒重現過，UNVERIFIED |
| L13-3、L13-5、L13-7、L13-9、L13-10、L13-11 | 修到（#2011、#1996、#1989） |
| L13-4 | 後半修到（幀緩衝會縮）；前半（每幀建 CPU 陣列，`Map3DMetalView.swift:1260-1284`）刻意留著，要實機量 |
| L13-6 | GPU 緩衝離開近景就放（只在 iOS，UNVERIFIED）；CPU 那份照決策 610 續二留著 |
| L13-8 | 沒處理（光暈的 draw call 要實機量） |
| L14-1 到 L14-10 | 都處理了（#1989）；L14-4、L14-10 核對後不成立（`LineAcquisition.swift:232`、`:258`）。L14-2 的手勢取消沒有 UI 測試 |
| L15-1、L15-2、L15-3 | 修到（#2011） |
| L15-4 | 決策 654 補寫了；程式沒做：已買機捷的舊存檔拿不到 A12 新渡線（下一步 5）、擬實規則下舊線與改建的死結量了沒查（下一步 6） |
| L15-5 | 只補了「放不下就拒絕」（#1990），見 L16-10 |
| L15-6、L15-7、L15-8 | 修到（#1988）；分割畫面等實際版面 UNVERIFIED；引進 L16-7；A4 位置測試仍由測試自己傳框 |
| L15-9 | 第 1 點：#1998 量了、修了背景搶 CPU 與測試自己的負擔，主執行緒的系統冷啟動沒修（L16-3、L16-19）。第 2 點：#1997 改成指出蓋得起的地點 |
| L15-10 | 修到（#2002 接進地圖），見 L16-13 |
| L12-3、L11-8、L9-4／5／7、L10-4 到 L10-13 | 這一輪沒有 PR 碰；L11-8 的 `RunDepot.swift` 仍每次呼叫 `heldRunDepartures`，其餘沒逐條重查 |

## 四、驗證紀錄

- **建置**：`swift build --build-tests -Xswiftc -warnings-as-errors`（Linux，Swift 6.4.0，3313197）乾淨，**VERIFIED**。
- **測試**（`swift test --skip-build`，Linux，**VERIFIED**）：
  - 本 session：`RunSpareInTheWayTests`（2 支）；暫時測試兩支（#2014 讓路中每個 tick 存檔往返，過；L16-1 的折疊列仍有名產店可開，紅），都已刪、沒有 commit。
  - 子代理：修正組 9 個類別 45 支、路線組 5 個類別 22 支（2 支要環境變數的略過）與 `STATION_EXTERIOR_REPORT=1` 的報告、App 組 5 個類別 20 支，0 失敗。3D 與聲音組沒有跑成測試（當時 `.build` 被鎖），那一組全部是讀程式。
- **UNVERIFIED**：
  - 所有 App 端（SwiftUI、Metal、AVAudio）行為、iPad／Mac 的版面、TestFlight 上的 `TestBuild.isTest`。這一輪沒有 macOS，也沒有跑 iOS workflow。
  - 決策 654、659、666、668 與研究文件的量測數字照它們自己的報告引用，沒有重跑（`TYMC_AFTERNOON`、`TYMC_FIRST_NIGHT`、`DEPOT_RETURN_*`、`NEIWAN_REPORT`）。
  - 「新測試在修正前會紅」是讀測試判斷的，沒有還原修正去跑。
  - committed `.xcodeproj` 與 `project.yml` 沒有重跑 XcodeGen 比對。

## 五、沒審到的與原因

- #2008、#2009 的幾何配方本身、`docs/art` 的圖、railway-assets-private 的截圖：0 點或沒有存取，只看引用、測試與出處。
- `Map3DRoadTunnelTests` 的三支新測試（#1996）、`Map3DXRayTests`／`RunningSoundTests` 的測試本體：只看名稱與部分斷言。
- `tools/audio/make_game_audio.py --check`、`tools/glb-to-m3dmodel` 的 node 測試：沒有執行。
- PR 頁面上的附件（截圖、五個角度的說明）：只看 commit、決策檔與 HANDOFF。
- #2025 的 83 個 `docs/` 檔：只濾過被刪的授權、署名、Wikimedia 行與驗證紀錄的雜湊，沒有逐檔讀；也沒有查公開庫裡有沒有那些照片的原圖（HANDOFF 已記同一件）。

## 六、下一輪

- **REVIEW-L17 從 #2032 起**（`main` 3313197 之後）。
- 還沒派的：
  - P2：L16-1、L16-2、L16-3。L16-1 與 L16-2 都小、不動 GameCore，可以一個 PR。
  - P3：L16-4 到 L16-20；L15-4（決策 654 下一步 5、6）、L13-4 前半、L13-8；之前的 L12-3、L11-8、L9-4、L9-5、L9-7、L10-4 到 L10-13。
- 建議：L16-5 第 1 點（讓路的成本）交給 HEALTH-124 或 CIOPT 量；L16-4（內灣資金）與 L16-17 第 1 點（馬達聲 `play()`）量到數字再定級；L16-9 第 4 點寫進下一版 WHATSNEW 的派工單。
