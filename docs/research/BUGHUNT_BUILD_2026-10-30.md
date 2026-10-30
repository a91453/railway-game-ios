# 公測前抓蟲：建設（BH1，2026-10-30）

派工單 BH1（遊戲規劃第 32 任派），範圍「建設」：軌道（單線、複線、曲線、坡度、拆除）、車站與月台、道路、建物、公車工具（站牌、路線、單行道、隧道）、實景地圖的鋪路、收購真實路線（三鶯、六家／內灣、淡海兩種順序）。對照 `main` 9fb305d。

## 1. 怎麼找的

在 Linux 上用無頭的 `GameSession` 實際操作，照玩家會做的順序，再讀 10/25 之後合併的程式。

| 玩的 | 怎麼玩 | 結果 |
| --- | --- | --- |
| 軌道工具亂玩 | 種子 1 的新遊戲，兩鎮之間一條線、一列車在跑。每局 220 步、6 局，每步隨機做一件事：鋪單線或複線（高度 0／±8 m／16 m，自動／橋／隧道／地面／高架）、加月台、拆軌道（包括有車的）、加待避線、拆車站、復原、重做、讓時間走、存檔再讀。每步檢查：預覽價＝實扣、預覽拒絕就不蓋、被拒絕時世界不變、不會變負債、存讀檔相等；最後存讀檔後各跑一天，兩邊相同 | 沒有失敗 |
| 建物亂玩 | 經營模式，160 步、4 局：隨機種類放在兩鎮附近、拖曳再放、拆除、復原、重做、讓時間走；檢查預覽價＝實扣、預覽可以就蓋得成、拒絕不變、每步存讀檔相等 | 沒有失敗 |
| 收購真實路線 | 實景地圖（含高度），早上 9:17 開始買：三鶯；六家→內灣；內灣→六家；淡海綠山→藍海；只買藍海。每條買下後：扣錢＝報價、存讀檔相等；之後兩小時每 7 分鐘存讀一次，再從存檔與不存檔各跑一天，兩邊相同、沒有死結；最後復原、重做 | 沒有失敗 |
| 收購時錢不夠 | 三鶯線，餘額 $10,000 | 乾淨拒絕：「餘額不足，無法收購三鶯線：需要 $18,553,125，目前只有 $10,000。」世界不變 |
| 高架、地下（規劃加派） | 種子 1 的新遊戲，跨過既有地面線蓋 625 m 高架（+16 m）與隧道（−16 m）；同一處平面交叉；兩端各拉一段 `automatic` 的坡道接回地面（16 m、312 m、470 m）；高架與地下各蓋兩站，開一條線、放一列車；跑 8 小時後存讀檔，兩邊各再跑 20 小時比對；拆有車的高架、拆坡道再復原 | 高架 $192,000、隧道 $320,000，預覽價＝實扣。平面交叉被擋，說明寫「上下要差 8 m，或在交會處接起來」。坡道 16 m 被擋（端點太近）；312 m 被擋，因為 16 m 的高差超過 40‰ 坡度上限；470 m 蓋得成（高架 240 m＋路堤 176 m＋地面 54 m；地下則是隧道 144 m＋路塹 272 m＋地面 54 m）。站、列車、收入（一天 597 人次）都正常，存讀檔後結果相同。拆有車的軌道被擋；拆坡道後沒有死結，復原回到原樣 |
| 平交道（規劃加派） | 讀程式：`Map3DStreets.swift`（決策 263）、`Map3DRealGround.addRoads`、`Map3DStreets.addOwnRoads`、`Map3DStreetLife` | 平交道只在空白地圖的種子街道上畫（3D 的路面、柵欄、停止線），GameCore 沒有平交道：公車與列車互不影響，列車不會被路卡住，在平交道上拆路或拆軌道也互不牽動。見 P3-10～P3-12 |
| 鋪路後復原 | 公車工具的道路模式：鋪路 A，畫一段疊在 A 上的路 B，復原 A，再按鋪路 | **P1-1**（下面） |

另外請兩個只讀程式的代理，看 10/25 之後合併的道路／公車／建物（#1463、#1464、#1469、#1499、#1504、#1507）與收購（#1423、#1447、#1448、#1470、#1477、#1508、#1510、決策 490）。下面標「讀程式」的是它們找到、我核對過程式但沒有在 Linux 上跑出來的。

## 2. P1（已修，同一個 PR）

### P1-1 鋪路草稿在復原後還顯示舊價，實際扣的錢跟按鈕和訊息不同

- **在哪**：`Sources/GamePresentation/RoadDraft.swift` 的 `confirmRoad()` 用畫路時算好的 `roadPreview`；復原與重做（`GameSession.step(to:)`）不重算它。
- **重現**：建設 → 公車 → 道路，拖一段路 A 按鋪路；再拖一段跟 A 重疊的路 B（按鈕寫 $12,800，重疊部分不用錢）；按復原（A 拆掉、錢退回）；按鋪路。扣了 $22,400，訊息還說「路鋪好了，花費 $12,800」。時間在跑時，城市或其他指令讓價錢改變，也一樣。
- **修法**：按鋪路時用現在的世界重算一次；價錢或能不能鋪跟按鈕上的不同，就不扣錢，換上新價，並說「這段路現在造價 $X，再按一次就鋪」。復原、重做之後也重算草稿的價錢。只動 GamePresentation，不動 GameCore、存檔與 golden。
- **測試**：`CityBusToolTests.testAfterAnUndoTheRoadDrawnIsPricedAgain`、`testARoadWhosePriceChangedIsShownBeforeItIsPaid`，在舊程式上 7 個斷言失敗，修好後通過。
- 五面向：玩家：按鈕寫多少就扣多少，不會多扣而不知道。鐵道迷：無。開發：只改按下時的檢查與復原後的重算，GameCore 照樣有最後決定權。美術：無。音樂：無。

## 3. P2（明顯錯但能繞過，公測後修）

### P2-1 實景地圖拆掉沿現有路鋪的自己的路，公車路線在畫面上斷掉（讀程式）

- **在哪**：`Sources/GameCore/City/RoadGrid.swift` `removeRoads` 只比對以格子算的距離（`busRoadMetres`）；但實景地圖的公車路徑是底圖的路網加上玩家的路（`BusRouteEditor.swift` 的 `useOwnRoads(grid.built)`，#1469）。決策 487 之後玩家的路可以疊在城市路格上（`taken`）；拆掉這種格子時格子還是城市的，GameCore 的距離不變就放行，可是畫面的路網少了玩家那條線。
- **重現**：實景地圖，在底圖不算公車路的小巷或產業道路上鋪路（$0），在上面開一條市區公車並放站牌，再到道路模式點那段路拆掉。允許拆，之後 2D 路線畫成斷的、3D 沒有公車，GameCore 仍照舊距離收錢。
- **建議修法**：`tapRoadTool` 的預檢（同檔）用畫面同一張路網重算每條路線的路徑，有斷掉就不給拆並說是哪條路線；GameCore 不必改。測試放 `RoadDrawRealMapTests`。
- **結果（ROADFIX，2026-10-30）**：#1544 修好（`GameSession.routeBroken(byTakingUp:from:)`，`RoadDrawRealMapTests.testARoadACityBusNeedsOnARealMapIsNotTakenUp` 釘住）。
- 五面向：玩家：避免路線莫名斷掉。鐵道迷：無。開發：只改預檢，在 GamePresentation。美術：無。音樂：無。

### P2-2 只沿現有路鋪的路（$0），3D 地圖不重建（讀程式）

- **在哪**：`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift`（約 605 行）與 `Sources/GamePresentation/Map3DBuses.swift`（約 53 行）的簽章用 `world.roads?.allCells.count`；`taken` 的格子本來就在 `cells`，數量不變。
- **重現**：實景地圖，只沿底圖現有的街拖一段路鋪下（$0）；2D 有，3D 沒有，公車路線改走它也不重畫，直到遊戲週數變（暫停時不會）。拆掉也一樣留著。
- **建議修法**：簽章加上 `roads.built.count`（或一個版本號）。
- **結果（ROADFIX，2026-10-30）**：3D 的場景鍵（`Map3DSceneKey`）與公車簽章（`Map3DBuses.Signature`）加上玩家的路（`roads.built`），`RoadCellCountTests` 釘住。
- 五面向：玩家：鋪了看得到。鐵道迷：無。開發：一行。美術：3D 跟 2D 一致。音樂：無。

### P2-3 先買淡海藍海線，綠山線就不再出售，說明還說「真實支線都是你的了」（讀程式）

- **在哪**：`Sources/GamePresentation/RealLineAcquisition.swift` 約 428–432 行（沒有 `ntdlrt:V after ntdlrt:VB` 的班表就 `continue`，但 `sale.bought` 被藍海線設成 true），說明文字約 478 行。
- **重現**：淡海附近的實景地圖，先買藍海線。綠山線從出售清單消失，地圖上沒有別的線時，說明寫「這張地圖上的真實支線都是你的了」。買藍海線的卡片事先也沒說買了就不能再買綠山線。
- **狀態**：#1519（BLG，決策 493）正在開放「先藍海後綠山」，合併後這條自然解掉；若 #1519 沒進公測，至少把說明改成不說「都是你的」。
- **結果（ROADFIX，2026-10-30）**：#1519 合併後已解（main 77b9322）：藍海線買了以後，綠山線照整條線的班表出售（`metroRuns` 的退路），`DanhaiDepotTests.testTheGreenMountainLineIsBoughtWholeAfterTheBlueCoastLine` 釘住；說明文字不會再在只剩綠山線時說「都是你的了」。沒有改程式。先綠山後刪線再買藍海線的情形是 P3-5。
- 五面向：玩家：不會以為綠山線已經是自己的。鐵道迷：兩條線本來都能經營。開發：等 #1519。美術：無。音樂：無。

## 4. P3（小毛病）

| # | 在哪 | 怎麼重現 | 建議修法 | 五面向 |
| --- | --- | --- | --- | --- |
| P3-1 | `RailwayGameApp/Views/RealLineAcquisitionCards.swift:31` `let total = index == 3` | 收購會連帶買地的線（地圖按格子買），價目表多一列「沿線的 N 塊地」，粗體落在「沿線的常客」，「合計」反而不是粗體 | `index == rows.count - 1`。**已修（ROADFIX）** | 玩家：合計看得清楚；美術：粗體在對的列；其餘無 |
| P3-2 | 同檔 24 行，及 `RealLineAcquisition.swift` 約 1205、1226 行 | 凌晨 4 點前收購，卡片與訊息寫「明天首班車起由你經營」，但當天就開（`LineAcquisition.firstServiceDay`） | 依 `firstServiceDay` 寫「今天」或「明天」。**已修（ROADFIX）**：`RealLineAcquired.startsToday(at:)`，`RealLineAcquisitionTests.testALineBoughtBeforeFourRunsFromTodaysFirstTrain` 釘住 | 玩家：說的跟看到的一致；其餘無 |
| P3-3 | `RealLineAcquisition.swift` 約 706 行 `junctionStation` 沒有濾掉機廠 | 在新竹 450 m 內、比新竹站更靠近接點處蓋機廠，再收購內灣線：被拒絕，說「機廠不能當路線的停靠站」，玩家不知道怎麼辦（讀程式） | 加 `!$0.isDepot` | 玩家：不會莫名買不了；其餘無 |
| P3-4 | `RealLineAcquisition.swift` 約 1118、1132 行 | 三鶯線、淡海綠山線的價目表：機廠站的造價算進「N 列車」那一列（合計正確）（讀程式） | 機廠站建好後再取 `built` | 玩家：細目正確；其餘無 |
| P3-5 | `RealLineAcquisition.swift` 約 428 行 | 買了綠山線又刪掉這條線，再買藍海線：只賣濱海沙崙到漁人碼頭那段，綠山線也再也買不到（讀程式） | 收購紀錄在線刪掉時一併看待，或刪線時提醒 | 玩家：少見；其餘無 |
| P3-6 | `Sources/GamePresentation/BusOwnRoads.swift` `joining` | 自己的路疊在單行道上，公車可以沿玩家的路逆向（讀程式） | 疊在單行道上的格子照底圖的方向。**已修（ROADFIX）**：沿單行道（半格內、夾角約 25° 內）的那幾段只照街的方向走，`BusOwnRoadsTests.testARoadAlongAOneWayStreetIsTakenItsWayOnly` 釘住 | 玩家：少見；鐵道迷：無；其餘無 |
| P3-7 | `Sources/GamePresentation/RealRoadCells.swift` 約 181 行 | 離車站遠、地塊還沒讀進來的地方，沿真實的街鋪路照全價收（之後讀進來也不退）（讀程式） | 鋪路前先讀進該處的地塊 | 玩家：照規則免費；其餘無 |
| P3-8 | `Sources/GamePresentation/BuildingSession.swift:383` `BuildingPreviewKey` 沒有語言 | 暫停時切換語言，建物預覽的拒絕理由仍是舊語言，移動位置後才換（讀程式） | key 加 `language` | 玩家：小；其餘無 |
| P3-9 | `Sources/GamePresentation/RoadDraft.swift` | 道路模式選了要拆的一段，復原後那段仍標著；按拆除會被 GameCore 乾淨拒絕 | `step(to:)` 一併清掉 `roadRemoval` | 玩家：小；其餘無 |

| P3-10 | `Sources/GamePresentation/Map3DStreetLife.swift`、`Map3DStreets.swift` | 3D 的平交道柵欄不會放下，路上的車和行人照樣穿過正在通過的列車（`levelCrossings` 只拿來畫，App 沒有用它擋車） | 列車接近時讓那段路的車流停住、柵欄放下；要先讀 motion skill | 玩家：看起來像真的平交道；鐵道迷：台灣平交道有警報與柵欄；開發：只在呈現層；美術：柵欄動畫；音樂：可以加平交道警鈴 |
| P3-11 | `Sources/GamePresentation/Map3DStreets.swift` `addOwnRoads`、`Map3DRealGround.addRoads` | 實景地圖的底圖道路，以及玩家自己鋪的路，在 3D 和地面軌道交叉時沒有平交道（只有空白地圖的種子街道有），路面直接畫過鋼軌（UNVERIFIED，Linux 沒畫 3D） | 讓這兩種路也走 `trackMeeting`（決策 263 的軌道優先） | 玩家：不穿模；鐵道迷：該有平交道的地方有；開發：重用現成的判斷；美術：一致；音樂：無 |
| P3-12 | `Sources/GameCore/City/RoadGrid.swift` `roadQuote` | 玩家鋪的路可以斜著橫越地面軌道或月台，不分角度、不收平交道的錢；GameCore 的公車也不管列車 | 公測後再決定要不要讓平交道進 GameCore（等公車影響、列車延誤），這要新的決策 | 玩家：目前不會因此卡住；鐵道迷：平交道是台灣鐵道的特色；開發：牽涉存檔與決定論，不在公測前做；美術、音樂：同 P3-10 |

## 5. 沒找到問題的

軌道（單線、複線、曲線、坡度、橋、隧道、高架與地下、坡道與坡度上限、拆除、有車的軌道、待避線）、車站與月台、建物（拖曳、試算、扣錢）、收購（三鶯、六家／內灣兩種順序、淡海綠山→藍海、只買藍海、錢不夠、復原與重做、存讀檔後繼續）都照上面的方式玩過，沒有當掉、卡住、存檔讀不回或錢算錯。公車路線的開通與修改，訊息寫的是實際扣的錢，沒有 P1-1 的問題。

## 6. 驗證

- VERIFIED（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors`；`CityBusToolTests`、`RoadDrawRealMapTests`、`BusRoadsRealMapTests`、`UndoSessionTests`、`BusOneWayAndTunnelRealMapTests`、`BusRouteEditorTests` 全過；第 1 節的實玩（草稿測試沒有提交）。
- UNVERIFIED：實機與 Simulator（不用 macOS runner）；高架橋墩、隧道口與平交道在 3D 的樣子（遮擋、穿模）Linux 上沒有畫；標「讀程式」的各項沒有在 Linux 跑出來。
