> iPhone 橫拿三件畫面修正（派工單 IPHLAND，`claude/iphone-landscape-fixes`，決策號不動，2026-10-31）：側邊面板頁的標題在 compact height 時改放在導覽列下方一列、和面板一樣寬（`PanelTitlePlacement`，`Theme.swift` 的 `panelTitle`），修掉車站卡站名被工具列夾成一兩個字與審查 L2-2；實景新局右側的空框是小地圖（沒有軌道與車站、或畫面已經看到整張地圖時不畫，`MiniMap.isShown(beside:)`）。Linux `MapFocusTests`、`MiniMapTests` VERIFIED；畫面靠截圖驗收，iPad 與 iPhone SE 沒拍。

> 鋪軌拖曳卡頓（派工單 TRACELAG，[決策 521](decisions/521.md)，`tracelag-trace-preview`，100.2）：拖曳每步重讀高度檔的地面區塊，已改成每塊只讀一次；第二個 PR（`tracelag-build-once`，決策 521「續」）讓預覽副本不在每段之後清點等車的旅客。描線預覽把整串蓋兩次：單線、不分段的描線已改成沿用描線時蓋好的副本（UIFIX，決策 521「續二」）；分段描線與雙線仍蓋兩次，留在「續二」的下一步。描線預覽看起來像兩條（底下亮的真實路線、雙線光暈疊深）已由 TRACE2 改成只看到一條（決策 521「續三」）；那兩種的計算仍蓋兩次。實機 UNVERIFIED。

> main full lane 連三次紅（派工單 FLANE，session_01YGNNuovKC4vUNueQF95y3C，`flane-full-lane`，2026-10-31）：`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 是測試過期（決策 510 給月台長度 Stepper 加了 identifier，它的按鈕改叫 `network.platformCars-Decrement`，舊的 `== 'Decrement'` 找不到），已改。`ShellLayoutUITests.testTheStatusBarKeepsItsWidthAsTheDaysGoBy` 的 6000× 其實選到了（失敗訊息讀到 6000×），是等待唯一一次查詢卡在 App 的幾秒停頓裡；`chooseSpeed` 改成等完再讀一次 label。`FinanceCompositionUITests` 紅過兩種：447891f 的「Timed out while evaluating UI query」是模擬器上 App 主執行緒 50 秒停頓（`ui-smoke-trace`），沒改程式；分支上 only_testing（run 41195369563）是按「資料」的觸控 150 ms 後被取消（trace「touch cancelled」，接著 885 ms 沒畫面，正是站長泡泡 7 秒到時收起），照 HUDAlignmentUITests 的做法沒開就再按一次。兩者都不是 3acace6..447891f 的退步：Linux 上貨運場景與 6000× 午夜在 3acace6 和 447891f 一樣快，7ac6649、3acace6 的 trace 也有 10–37 秒的停頓，前兩輪 `second`／`lessons` 紅的四支（LineRoutePreference、HUDAlignment 站長泡泡、MapInteraction 改站名、Settings 音量）各只紅一次、下一輪就綠。**還沒查到的**：full lane 裡 App 為什麼常有幾秒到幾十秒的主執行緒停頓（錄影看貨運場景是建物圖層畫出來前那段）；要在 Mac 上用 Instruments 量，Linux 量不到。

> 從 3D 按「建設」（派工單 BUILD3D，[決策 517](decisions/517.md)，`build3d-return`，2026-10-31）：照舊在 2D 蓋，從 3D 來的按「完成」回到 3D 原本的視角（`Map3DBuildReturn`）。在 3D 裡直接鋪軌只做了評估，留給之後：照決策 517「下一步」的四步（先做 3D 點選、再解決鋪完要等場景重蓋、再只做路網的平面鋪設、最後看實機數據）。實機上回 3D 的樣子、截圖驗收暫緩（ui-review §3），UNVERIFIED。

> 收購的真實路線換上該線自己的車（派工單 ACQSTOCK，[決策 536](decisions/536.md)，`claude/acqstock-real-trains`，2026-11-01）：只改表現層，收購前後 3D 是同一款車（台鐵支線 DR1000、六家沙崙 EMU 區間車、淡海輕軌、北投支線 C371），卡片與路線列寫車名。**沒做的**：性能維持收購時的（評估見決策 536「性能」）；節數仍是 GameCore 的（北投支線 6 節、三鶯 3 節，真車 3、2 節）；2D 列車顏色沒換。實機 UNVERIFIED。

> DR3100 柴聯自強號（決策 511，session_01YGNNuo4eEH6JS6x5CwJ3LG，`dr3100-service`，2026-10-30）：`dieselExpress` 三節以上改用 45DR1000 的外型、DR3100 自己的塗裝（`Map3D45DR1000.Livery.dr3100`，近遠景）；真實地圖的縱貫線北段、宜蘭線、北迴線每天多跑 209／221／238／246 四班 DR3100 三節（`tra-dr3100-schedule.json`）。**沒做的**：臺鐵示範（決策 240）裡這四班仍在「台鐵 自強／莒光」線上用推拉式 12 節跑；要改得在 `TRADemo.kinds` 加一條 DR3100 線並重跑 `TRADemoTests`、`TRADemoDayTests`（見 `docs/decisions/511.md`「還沒做的」）。DR3100 自己的外型（中間的 DR3150 無駕駛室、20.274 m）也還沒有。實機外觀與幀數 UNVERIFIED。

> Codex 45DR1000 靜態 studies（公開 draft #1530 ↔ 私庫 draft #33）：`docs/art/45dr1000-2026-10-29/README.md` 與 sources.json 記 DRC1025 2006–08 版本、來源和推估。公開 recipe 原只加 studies 近遠景；2026-10-30 DR1000 session（session_01YGNNupCW2YCoD2nXrEiuNh）在同一 PR 把營運的 `dieselRailcar`／新的 `dieselRailcarFar` set 換成這款（每節兩端駕駛室，2～3 節照常由 `Map3DRealTrains` 與 `set(forKey:count:)` 決定，未改路由；遠景側窗切成三段讓夜間客室窗會亮，三角形 1,536→1,584）。NEXT_PRIORITIES §22.2 第 17 名「`dr1000` 車種」（升存檔、`TrainType`）是另一件，未做。revision-2 重做使用者否定的首版正面；revision-3 將窗下橘帶由 0.10 m 加厚至照片推估的 0.18 m，使用者認為側面應可接受。revision-4 producer `533f9370598b0f5b101ebfafb37adf7cbd376959` 又依正面原圖修斜肩車頂箱、燈圈、貫通門上框和兩側橘色下緣，私庫 `revision-4/` 留完整素材，前三輪只留 PNG／README／來源。新正面外觀接受、營運整合與 45DR1000 Metal／裝置仍 UNVERIFIED，不得以 Linux viewer 或通用 Simulator build 當本車裝置驗收。不合併／auto-merge／TestFlight。

> Codex E200 鳴日號風格塗裝（2026-10-29）：[基準／單元／選用限制與重建](art/e200-mingri-style/README.md)。只新增既有 E200CK 機車及標準／尾客車的近遠 studies，原車／共用車／營運映射保持。沒有獨立玩家塗裝選用機制，合併不會自動出現在遊戲；使用者外觀接受、營運接入及真機仍UNVERIFIED。公開 [PR #1480](https://github.com/a91453/railway-game-ios/pull/1480) 仍 OPEN／ready；素材 [PR #25](https://github.com/a91453/railway-assets-private/pull/25) 已合併，實際 producer 與驗證見自有文件。

> Codex 普悠瑪 TEMU2000 studies 外觀續修（[公開 draft #1456](https://github.com/a91453/railway-game-ios/pull/1456)，2026-10-29，revision-2 producer `2cb46a3660bb500549e81098c66421e8163ee479`）：[公開查證／重建／外觀自檢](art/temu2000-2026-10-29/README.md)、[素材 draft #23](https://github.com/a91453/railway-assets-private/pull/23)。使用者明確否定 revision-1 `02d61687` 的歪燈與塗裝；revision-2 左右燈位、下燈座、風擋雨刷及加寬雙紅線已修，使用者對此新 producer 外觀接受仍 UNVERIFIED。10 個近遠單元、2 個八車 assembly、私庫每輪 20 張 PNG；舊版重檔在同 PR 刪除。營運 `puyuma`／`puyumaFar` 全頂點欄位雜湊不變，沒有替換映射；技術 VERIFIED，iOS Metal／動畫／效能 UNVERIFIED。車側大幅圖形、白頰曲率與屋頂設備仍待改善。無 GameCore、存檔、fixtures、購車、班表變更。

> 台北捷運 C371／C381／610 接進營運（派工單 BS，決策 461，`claude/taipei-metro-c371-c381-610`）：各線照實際配車，高雄、桃園、台中改叫 `metroGeneric` 但畫面不變；[對照圖](art/taipei-metro-461-2026-10-28/README.md)。留下的：實機幀數與 500 m 換遠景；#1342 若後合，保留 `Map3DC371`／`Map3DC381` 的 `far` 分支並重跑 `tools/train-models/run.sh OUT --lock`（見 [決策 461](decisions/461.md) 的下一步）。

> Codex C371／C381雙車續修（公開draft #1342／工作#1341）：[現版／main格式核對](art/c371-c381-2026-10-27/README.md)、[接手／重建](art/c371-c381-2026-10-27/CROSS_ACCOUNT_HANDOFF.md)。兩型外觀均待驗收，先前推定C371已接受撤回。修肩部曲面／圓角燈腔／鼻下設備；T/M裸模型與原屋頂／輪組位置保護。已整合main8be22423的studies，standard529模型／3,127,704頂點不增加。新railway-assets-private各車獨立revision-1，各19PNG／最新模型與viewer，不新增history或ZIP；完整真前包仍在舊reference-private #103固定63b44693／素材e791fdb7。原#103只作前版交接，新素材draft互鏈見#1342。無營運映射／GameCore／存檔／fixtures變更；不合併／auto-merge／TestFlight。

> 共用做車工具與新 skill（派工單 AC）：`tools/train-models/`（匯出、預算與雜湊檢查、七向圖用模型光、離線預覽，[README](../tools/train-models/README.md)）、`.claude/skills/rolling-stock/SKILL.md` 已改成原生做法，新車只用這個工具。列車畫面四項的第 1–3 項（夜間亮燈、遮蔽烘焙、車窗反光）等 10/31 公開測試之後由規劃派，用同一個工具拍改前／改後（`renderer.js` 的 `features` 旗標是接口）。

> Codex C341（issue [#1322](https://github.com/a91453/railway-game-ios/issues/1322)，公開draft [#1323](https://github.com/a91453/railway-game-ios/pull/1323)）：[來源／外觀／重建與整合範圍](art/c341-2026-10-27/README.md)。四附件與Blair C341外觀原圖已看；獨立DM/T/M/反向DM，六輛21,036三角用合法原生組裝，不寫超限M3DM。完整素材／真第一至第三版／viewer／ZIP在私庫同名分支新目錄。僅四單元靜態註冊，沒有C341專用營運映射，合併不會自動換遊戲車輛。已保留新合併EMU800註冊及route bus末項；GameCore／存檔／fixtures不動。工程尺寸／單元方向與隱藏設備仍資料不足，真機Metal／效能／動畫與完整碰撞未驗；最新CI、衝突及私有互鏈見issue，不合併／auto-merge／TestFlight。

> Codex E1000 #1296第二版：使用者否定2be9daca車頭，已撤回舊自評；重修圓頂／橫向圓鼻／低雙風擋／小側窗／曲面燈座與內收下裙。真前版為2be9daca／私庫58e929e7，非更早簡模；同相機比較、局部裙板差異與設備payload證據見自有文件。PP #1291修正69a6eb7f已合入此分支，兩PR維持draft，最新CI另查，不視為使用者接受／真機／推拉動畫驗收。

> Codex EMU500 #1310：[來源／色票／單元／重建交接](art/emu500-2026-10-27/README.md)。使用者第七版回饋「稍微好一點」並要求遊戲色；第八版用現有暖白／綠松／藏青／暖黃，收細貫通框與門窗層、柔化下裙／連結器外框，輪組／車頂實際三角位置與編組保持。真前版完整保留，最終全量匯出；只用 EMU3000 作同尺度色票／霧面比較。原生四車14,880三角，其他車型／route bus末項約定不改。仍僅靜態素材，合併不會自動出現在營運列車；Metal／效能／動畫及全碰撞未驗。最新producer／SHA／CI見互鏈draft #1312 ↔ 私庫#92及issue。GameCore／存檔／fixtures不動，不合併／auto-merge／TestFlight。

> Codex PP #1291 CI修正：新增PP註冊移到既有route bus之前，保留route bus最後的索引約定；原失敗Map3DBusesTests已在舊head重現。同步最新main，模型幾何不變；既有61c6969c素材producer仍有效，最新程式CI看本PR新head。E1000車頭外觀另在#1296修訂，不能沿用2be9daca已符合自評。

# 交接

> Codex G12／R21 原生 studies（公開 draft [#1485](https://github.com/a91453/railway-game-ios/pull/1485) ↔ 私庫 draft [#26](https://github.com/a91453/railway-assets-private/pull/26)，producer `723d08f8`）：revision-1 `b073c6c6` 整體外觀、revision-2 `69de18da` 正面均遭使用者否定；revision-3 `501f339a` 自檢發現前端白帶被底架遮住而撤回，revision-4 `aa1fb2c8` 解遮擋。現版再依 R21 原圖加兩端實體燈座、角燈孔、可見連結器及長端小型警示牌；保留低白帶、正向黃黑 V、扶手與短端白 V。只用 1960 首批臺鐵 R20 型 EMD G12 的 R21 橘色時期；原圖、估算、比對、重建與四種狀態見 [G12 交接](art/g12-2026-10-29/README.md)。公開只放配方、工具、來源與一張總覽，完整近遠景與 viewer 在私庫 `g12/revision-5/`（前四輪僅留 PNG／README／來源）。現有 SceneKit R20 與全部營運映射不變；此 producer 的使用者外觀接受、營運接入、iOS Metal／真機均 **UNVERIFIED**。不合併／auto-merge／TestFlight。

> Codex E1000雙端PP（#1294）：[來源／外觀／營運／重建](art/e1000-pp-2026-10-26/README.md)。獨立E1000近遠配方，以未合併PP #1291固定61c6969c為stacked base，私庫#87固定1f81f7c。只換pushPull機車，PP客車/E500/EMU與其他服務payload保護；兩端E1000、後機180°、後端貫通道相接。官方規格16.5/17.211m、寬2.885/車高3.904m；輪徑與軸距推估。完整包私有、公開一張總覽。兩PR皆合併並重建才改App，靜態展示不代表推拉控制/真機/動畫。CI看本輪同head，不合併/auto-merge/TestFlight。

> Codex PP客車（#1282）：[來源／外觀／營運與重建交接](art/pp-coaches-2026-10-26/README.md)。四種PP近遠獨立配方及雙端已接受E500第三版＋12客車完整靜態展示（更正11a70d3c漏尾機，尾端同原生旋轉180°）。只有原`pushPull`接點中間客車改PPT1000，E1000兩端、可變節數、列車包／classic／解鎖與回退保持；PPH/PPC/PPM未逐車接營運，E500＋PP未接E500營運。E500CK/MINGRI/STAR客車與既有模型實際payload保護。公開唯一總覽，完整素材／viewer／ZIP在互鏈私有draft；最新同提交CI看PR，不以Linux靜態驗證當真機／動畫／推拉控制。GameCore、存檔與fixtures不動，不合併／auto-merge／TestFlight。

> Codex E500 原生重建第三版（issue #1255）：[自有外觀／營運接點／重建交接](art/e500-refresh-2026-10-25/README.md)。使用者圈選中央格柵排與正面過寬平台：僅修屋頂為連續六格外殼、收窄降低並貼合真車頂；68913f4f第二版完整保持，私庫revision-3全量重出。非屋頂與弓機構三角bytes保護。僅 E500CK／MINGRI／STAR 專用近遠景；其他包／解鎖／回退與 GameCore 不動。完整素材私庫、公開一張總覽，互鏈 draft PR 與同head CI 見 issue；靜態幾何不等於真機動畫。

> 讀者：每一個新開的 session，以及接手某條線的 session。先讀 [OVERVIEW.md](OVERVIEW.md)，再讀這份。
> 這份記錄「誰在做什麼、做到哪、下一步交給誰」。規則細節以 `docs/ARCHITECTURE.md` 的決策為準，優先順序以 `docs/research/NEXT_PRIORITIES_2026-10-12.md` 為準，號碼以工作登記 #231 為準。

> N700S／N700ST 靜態素材候選（#1202）：公開重建配方與外觀交接見 `docs/art/n700s-n700st/README.md`，完整模型與可下載 viewer 在私庫同名 draft PR。車殼修訂版已通過最終 GLB 的 watertight 檢查；尺寸、台車錨點及實車編組仍未校準。本輪沒有接入遊戲，合併後也不會自動顯示。後續確認工程尺寸與排列，再做 Metal 真機驗收及遊戲接入。
> #1214 接續塗裝：N700S-G 是原始 N700S 藍線改遊戲藏綠的靜態變體；橘色 N700ST 保留。詳見 `docs/art/n700s-n700st/README.md`。此工作不更動 GameCore 或目前遊戲內列車，合併也不會自動顯示。（2026-10-25：決策 408 把 N700S-G 重建成遊戲的畫風，接進營運，見 §7.3。）
> 作者 2026-10-16：「把所有沒交接在 main 的用 PR 在 main 做交接，防止之後新 session 不知道怎麼做。」交接只放在 session 之間的訊息或 PR 說明裡的，都要搬到這裡。

> EMU3000 專用原生重建與遊戲替換（Codex，issue #1226）：[外觀／單元／重建交接](art/emu3000-refresh-2026-10-25/README.md)。第二版依使用者「有點怪」回報再修：縮短圓厚車鼻、收窄下移風擋、斜列圓燈／尾車兩紅標示燈、灰色冷氣格柵；原3ab84550的revision-1保留，第二版同尺度對照與完整包為revision-2。白車身、炭黑罩面、細綠松肩線；8角色與12節、EP3/7/10、近／遠景及實際營運dispatch。公開PR合併後標準未鎖定的EMU3000會使用新配方，私有GLB只是同版靜態交付。與#1227已協調共用接點，後合併保留兩者；GameCore／存檔／fixtures不動，既有非EMU模型逐bytes保護。真機Metal／效能／動畫與完整碰撞仍未驗證，最新CI看互鏈draft PR／#1226，不把Linux通過當裝置驗收。

> Codex E500製程文件化（#1255）：[跨AI案例與固定版本交接](art/native-vehicle-modeling/CASE_STUDY_E500.md)。使用者已接受producer85647d0a第三版外觀；記錄連續六格屋頂殼、正面過寬底座、真第二／三版、非屋頂保護、重建與分層驗證。模型公開draft #1256 ↔ 私庫#84在本次文件接手時尚未合併，固定來源不假設main已有配方；本輪不改已接受模型／素材。合併模型PR並重建App才更新E500CK／MINGRI／STAR；真機與動畫仍未驗。

> 分區看得到效果（派工單 ZONE2，[決策 514](decisions/514.md)，`zone2-zoning-status`）：分區圖層分出會蓋、等車站成長、離車站太遠、目前不缺。量到的：用途有人要時第一棟第 1 天、第五棟第 3 天，不慢；問題是範圍（大方框六成在 800 m 外）與需求（第一條線住宅需求第 1 天就轉負，預設的住宅分區幾乎不蓋）。留下的（規劃第 36 任 10/31 定）：另開一個 PR、目標下一版，做決策 514「下一步」第 2 項（拖曳時先把 800 m 外畫灰）與第 1 項的最小做法（分區工具預設選需求最高的用途）；住宅需求的 GameCore 平衡先不動。ZONE2 已壓縮一次、不接新工作，由規劃另派。量法用 `ZoningReportTests`，截圖情境 `ScreenshotScene.zoning`（`WebsiteScreenshotTests/testZoningOutlooks`）。實機 UNVERIFIED。

> 地圖上少一點東西（派工單 UICLUTTER，[決策 510](decisions/510.md)，`uiclutter-map`，2026-10-30）：景點依縮放收起、不搶車站與軌道的點擊，警告每站一個、地圖上最多幾個、其餘收進左上角的徽章。Linux `MapClutterTests` VERIFIED；也修了 iPhone 橫拿整平失敗時藥丸、橫幅、右側面板與「哪裡人多」圖例疊在一起（橫幅改短句、圖例在藥丸出現時收起）。#1583 已 merge #1582 後的 main。截圖 run 41165534178 看過 7 張，另 2 張（整平失敗、觀光景點）的測試已修，實作 session 壓縮兩次停下，遊戲規劃第 37 任接手：截圖 run 41168313459 看過，iPhone 橫拿藥丸、短橫幅、「哪裡人多」圖例不互蓋；觀光景點那張拉近到嘉義山區時畫面裡沒有景點星星（畫面裡可能本來就沒有景點），**實機看實景地圖中距離時景點星星有出現**。iPhone 13 直拿沒截圖，實機看實景地圖拉遠與車站旁的景點。

> 列車運用表入口與拖拉編排（派工單 ROSTER2，[決策 512](decisions/512.md)，`roster2-drag`）：路線頁、列車卡直接開運用表；「編排」裡長按車名拖到別條線改派、長按預定格左右拖改自有時刻表。在路上的車不能改派、自有時刻表只在停在第一站時能改；路線車的錯開、跑完再改派、在路上改時刻要新 GameCore 指令或升存檔，見決策 512 的下一步（甲～丁，預覽 `docs/art/roster2-drag-2026-10-30/next-steps.svg`）。長按拖曳在 Simulator 與實機的手感 UNVERIFIED。

> 鋪軌被擋時說出原因、隧道深度（派工單 GEOMSG，[決策 513](decisions/513.md)，`geomsg-track-reason`）：作者 99.1 南澳的「0 公尺｜97 → 65 公尺」是描線的端點在真實隧道裡、地面下 183 公尺，超過 GameCore 的地下 64 公尺；地下改成 1,024 公尺（高架 64 公尺不變），被擋時卡片說是哪一個條件。第二個回報（南澳北溪到朝陽的短描線「0 公尺｜↕ 0」與 40‰）：新端點被釘在隧道口山坡、橋頭河岸的粗地面上，改成可以在路堤或路塹上（-10.5～+7.5 公尺），截短的長隧道照全長算，`TrackRise` 路的終點一定有樣本；整段沒有坡度時卡片畫那段真實路線。第三個回報（南澳站放不下 16 節月台、35‰）：描線經過真實車站時那段排成平的。留下的：拒絕原因加「坡度超過上限」一類交給決策 515（ALISHAN），南迴還沒量最深的端點（決策 513 的下一步）；實機在南澳沿北迴線往隧道描一段、在朝陽前描一小段、描過南澳站放 16 節月台，看卡片有長度與價錢、建得起來。Linux `TrackGeometryProblemTests` VERIFIED；實機 UNVERIFIED。

> 公測前介面盤點（派工單 UIA，`claude/ui-audit-beta`，2026-10-30）：[`research/UI_AUDIT_2026-10-30.md`](research/UI_AUDIT_2026-10-30.md)。各功能的入口與步數、iPhone 橫拿與 iPad 直橫拿的遮擋。公測前只修了 A1（「資料」可以再打開上個月的月報）；B1–B10 公測後由規劃照順序派，最前面是 B1（iPhone 打開「路線」看不到線）、B2（☰ 後三列只有圖示）、B3（iPhone 教學卡把目標切在半行）。截圖在 railway-assets-private 的 `game-art-previews/docs/art/ui-audit-2026-10-30/`。

> 公測前抓蟲・營運（派工單 BH2，`claude/bughunt-operations`，2026-10-30）：[`research/BUGHUNT_OPERATIONS_2026-10-30.md`](research/BUGHUNT_OPERATIONS_2026-10-30.md)。沒找到 P1。P2-1（跳過夜晚途中存檔，讀回以 ×6000 跑）在同一個 PR 修了（`GameSession.worldToSave`，`NightSkipTests` 釘住），發版前在實機按「跳到早上」後切出 App、關掉再繼續，看速度是原本的；P2-2（分組清單的上一條／下一條順序不對）與 P3 三項留給公測後。

> 公測前抓蟲「建設」（派工單 BH1，`claude/bughunt-build`，2026-10-30）：[`research/BUGHUNT_BUILD_2026-10-30.md`](research/BUGHUNT_BUILD_2026-10-30.md)。P1 一個已修（鋪路草稿在復原後還是舊價，扣的錢跟按鈕不同）；P2-1～P2-3、P3-1～P3-12（含高架、地下、平交道）公測後由規劃照順序派，最前面是 P2-1（實景地圖拆掉沿現有路鋪的路，公車路線斷掉）。P2-3 等 #1519。

> 新台幣 PR-0（派工單 NTD0，`ntd0-money-format`，2026-10-30）：玩家看的金額都經過 `EconomyText.swift` 的格式函式（`Money.currencySymbol` 是唯一的 `$`），測試斷言改用同一組函式，人數改 `groupedText`；盤點與 PR-1 要乘 3 的 GamePresentation 常數寫在 [`research/NT_DOLLAR_SWITCH_2026-10-27.md`](research/NT_DOLLAR_SWITCH_2026-10-27.md) §5.2 PR-0 的「做完了」。PR-1（GameCore、存檔 76、決策 499）由規劃派。

> 公測前抓蟲：經營與存檔（派工單 BH3，`claude/bughunt-economy-saves`，2026-10-30）：[`research/BUGHUNT_ECONOMY_SAVES_2026-10-30.md`](research/BUGHUNT_ECONOMY_SAVES_2026-10-30.md)。沒有找到 P1，也沒有 P2；P3-1～P3-4（月報標題不看現金、從資料開月報後回地圖、讀檔後上個月月報不見、回報問題在無限資金的局寫餘額）留到公測後。§6 是新台幣換算前的平衡基準，PR-2 用同樣的指令量「改之後」。實機 UNVERIFIED。

> 公測前抓蟲：貨運、挑戰與劇本、分享與 Game Center（派工單 BH5，`claude/bughunt-freight-challenges`，2026-10-30）：[`research/BUGHUNT_FREIGHT_CHALLENGES_2026-10-30.md`](research/BUGHUNT_FREIGHT_CHALLENGES_2026-10-30.md)。沒找到 P1。P2-1（從朋友的路網開新局會帶過朋友未領的市府補助、星等與貨運未入帳收入）在同一個 PR 修好了；留下 P3-1～P3-9，公測後由規劃照該文件 §4 的順序派。

> 公測前抓蟲「公車與車輛」（派工單 BH4，`claude/bughunt-vehicles`，2026-10-30）：[`research/BUGHUNT_VEHICLES_2026-10-30.md`](research/BUGHUNT_VEHICLES_2026-10-30.md)。修了 P1-1（3D 公車的回程鋪不上時當掉）；P3-1～P3-3（復原掉正在編輯的公車線、減少公車不退錢沒說、空白地圖鋪捷徑後 2D 公車線畫舊路）與 §5 還沒有的功能（跟公車的視角、2D 會動的公車、收購真實公車）公測後由規劃派。真實地圖上 3D 公車實機 UNVERIFIED。

> 公測前抓蟲「卡住」（派工單 BH9，`claude/bughunt-hang`，2026-10-30）：[`research/BUGHUNT_HANG_2026-10-30.md`](research/BUGHUNT_HANG_2026-10-30.md)。修了 P1-1（大型永久死結時死結搜尋對每列車重算整條線，120 站 40 車一 tick 1.8 s → 56 ms）；P2-1～P2-7（收購卡、回開始畫面存檔、每指令的死結泡泡、跳過夜晚試跑仍在主執行緒；欠錢轉自由模式卡住〔轉 BH3〕；存檔失敗出不去；停著的車擋路沒提示）與 P3 五項公測後由規劃派。App 主執行緒各項實機 UNVERIFIED。

> 公測前抓蟲「當機」（派工單 BH8，`claude/bughunt-crash`，2026-10-30）：[`research/BUGHUNT_CRASH_2026-10-30.md`](research/BUGHUNT_CRASH_2026-10-30.md)。沒有 P1；修了 P2-1（車型目錄小圖寬度為 0 時 `Int(NaN)` 閃退，`RollingStockCatalog.sideWindows`）。P3-1～P3-4（極端指令參數的整數溢位）公測後由規劃派；P3-5（座標放大的存檔讀檔很慢）已轉 BH9。要再跑模糊測試：`CRASH_FUZZ=<cases>` 跑 `CrashFuzzTests`（見文件 §6）。

> 有功能沒按鈕、有按鈕沒功能（派工單 BH7，`claude/ui-gaps`，2026-10-30）：[`research/UI_GAPS_2026-10-30.md`](research/UI_GAPS_2026-10-30.md)。只讀程式；沒有改程式（沒找到沒接上的按鈕或漏翻）。玩家到不了的 GameCore 指令只有兩個：G1 收購真實公車路線（決策 400 的 10i-4，還沒派，公測後要新卡片）、G2 每條線停站秒數（決策 207 刻意不給）。B-1（設定裡「規則」一列點了沒反應）與 §4 的 D1–D15（補 UIA 沒列的入口步數）公測後由規劃照順序派，D6、D11、D12 跟 UIA 的 B7、B2、B6 一起做。

> 新手教學盤點（派工單 TUT，`claude/tutorial-review-2026-10-30`，2026-10-30）：[`research/TUTORIAL_REVIEW_2026-10-30.md`](research/TUTORIAL_REVIEW_2026-10-30.md)。公測前只修了 A1（「點『車站…』看誰在搭車」打開在「旅客與運量」組）；其餘步驟對照 main 都指得到、按鈕字都對。留下的是該文件 §4 的 B1–B7（教學的路線面板和平常不同、實景地圖沒教、iPad 直拿沒走過教學、錢的事沒教等），公測後由規劃照順序派；B3 發版前要在 iPad 直拿實機走一次第 1 關。

> 公測前抓蟲：3D 載入、App 生命週期、語言（派工單 BH6，`claude/bughunt-3d-lifecycle-text`，決策號不動）：[`research/BUGHUNT_3D_LIFECYCLE_TEXT_2026-10-30.md`](research/BUGHUNT_3D_LIFECYCLE_TEXT_2026-10-30.md)。沒找到 P1；P2-1（3D 地圖不受 xxxLarge 字級上限管，要 Simulator 確認）與 P3 兩項公測後由規劃派。發版前實機要看的十項在該文件 §3。

> 公測前效能盤點（派工單 PERF，`claude/perf-tiers`，決策號不動）：[`research/PERF_TIERS_2026-10-30.md`](research/PERF_TIERS_2026-10-30.md)。這輪只修了兩層雨的重畫次數（3D 跟地圖的格數、2D 限每秒 30 次）。留下的：「自動」在「少像素」之後再加「少陰影與反光」「穩定 30 格」兩步，主執行緒造成的掉格不降畫面（§4 丙，公測後拿實機回報再做）；其餘依 §5 的順序。實機要看的數字在 §6。

> 車庫開放給所有玩家（派工單 GAR，[決策 492](decisions/492.md)，`claude/garage-train-viewer`）：設定裡「車庫」一列打開決策 434 的列車展示；列車包沒解鎖時包裡的車不列。截圖驗收暫緩；發版前在 iPhone 直橫、iPad 直橫各開一次車庫（設定 →「車庫」），看那一段與畫面能開、能關、不跑版，App Store 設定（列車包開關關著）的選車清單沒有包裡的車。Linux `Map3DShowcaseTests` VERIFIED；Simulator 與實機 UNVERIFIED（`TrainShowcaseUITests` 在 full lane）。

> iPad 直拿的兩站比較卡（派工單 SPD，[決策 491](decisions/491.md)，`claude/station-pair-drawer-portrait`）：路線面板開著時比較卡改站到地圖右下角按鈕上方、讓開建設工具列；橫拿不變。截圖驗收暫緩；發版前在 iPad 直拿新增路線點兩站看（下一步見決策 491）。Linux `StationPairDrawerLayoutTests` VERIFIED；實機 UNVERIFIED。

> 鋪路畫的和鋪好的不同（派工單 RDW，[決策 487](decisions/487.md)，`claude/road-draw-preview-mismatch`）：實景地圖上拖過城市道路格子的段落，現在也鋪成玩家的路（不收錢）。作者暫停截圖驗收；發版前在實機看：彰化田中大社路旁（或任何實景地圖的巷弄旁）用「建設 → 公車 → 道路」拖一個方框和一條帶圈的路，鋪好後的線要和預覽一樣；點底圖沒路的地方，要說「在地圖上拖過要鋪路的地方」，不是「城市的路」；整段沿現有的路拖，按鈕寫「沿現有的路 X，不用錢」。Linux 測試 `RoadDrawRealMapTests`、`RoadGridTests` VERIFIED；實機 UNVERIFIED。

> 乘客需求模型對照（派工單 DEM，研究，`claude/demand-model-research`）：[`research/DEMAND_MODEL_COMPARISON_2026-10-29.md`](research/DEMAND_MODEL_COMPARISON_2026-10-29.md)。用北捷 2025 各站進站與 2025-10 完整 OD 量過現行模型；建議方案 A（居民與工作分開給權重，GameCore 開關、升存檔），B（起訖距離衰減）排在 A 之後；轉運站（台北車站、板橋）轉乘點數上限另外量。實作都還沒派，順序見該文件 §6。

> 截圖測試修好與截圖驗收（派工單 SHOTFIX，#1541，`claude/fix-screenshot-regressions`）：`WebsiteScreenshotTests` 的貨運、統計圖、路線兩層、收支組成四個測試在 run 41044755386 全綠（只跑這四個；整個 class 會超過「Take the screenshots」的 30 分鐘）。截圖驗收（決策 480、486、477）找到的三個問題沒有修，公測後由規劃派：(1) iPhone 橫拿經濟明細只有約 270 點高，支出甜甜圈的下半與它的圖例永遠不能同時看到，週支出那張上方看到的是收入的圖例；(2) 標題被截斷：「整個路網」頁的導覽列只剩「整個…」，貨運站面板標題只剩「西」；(3) 路線清單捲動後，固定的搜尋／篩選／排序列被導覽列切掉一半（chart-line-rows）。截圖在 run 41044755386 的 artifact `website-screenshots`（保留到 11/13）。`testFreight` 的車隊總覽仍然捲不動，留下 `debug-fleet`，沒有 `freight-train`。

> 收支組成甜甜圈圖（派工單 DONUT，[決策 480](decisions/480.md)，#1474，`claude/finance-composition-donut`）：截圖驗收照作者 2026-10-29「截圖先暫停拍攝 明天要發前再做而且我自己也可以截圖」延到發版前。留下的：發版前在分支或 main 手動跑 `website-screenshots.yml`（`WebsiteScreenshotTests.testFinanceComposition` 拍日收入、日支出、選住票價、週支出四張；橫拿、深色、繁中），照 `docs/research/UI_UX_REVIEW_2026-10-28.md` §5 只看截圖答七題、每輪修最嚴重三個、最多三輪；淺色與 iPhone SE 寬沒有自動拍，要實機看。設計預覽在 `docs/art/finance-composition-2026-10-29/`，不要刪。

## 怎麼用這份

- **開工前**：讀第 1、2、3 節，確認要做的事沒有人在做，作者也沒有說「先不要動」。然後照 CLAUDE.md 在工作登記 #1579 登記。
- **工作登記又換了 issue**（2026-10-30）：#1041 約 2,360 則，接近上限，遊戲規劃第 36 任開了 #1579（工作登記（三））。從此本文件寫「#1041」或「#231」的現行規則都指 #1579；2026-10-30 以前的紀錄留在 #1041。#1579 接近 2,400 則時，照下一條換。
- **工作登記換了 issue**（2026-10-22）：#231 滿 2,500 則留言，GitHub 不再接受新留言，改用 #1041。這份文件裡其餘寫「#231」的地方，從此都指 #1041；2026-10-22 以前的紀錄留在 #231。#1041 接近 2,400 則時，遊戲規劃開下一個 issue，並改 CLAUDE.md、AGENTS.md、GEMINI.md、`full-lane-watch.yml` 與 `tools/ci-watch/full_lane_watch.py`。
- **收工時**：做到一半、留給之後、交給別人的事，寫進這份的對應一節（或寫進該決策的「下一步」，並在這裡留一行指過去），跟最後一個 PR 一起合併。只寫在 session 訊息、PR 說明或 #231 留言裡的交接，下一個 session 看不到。
- **交接給另一個 session**：用 send_message 傳的內容，也要在這裡留一份。
- 已經做完、沒有人需要照著做的交接，搬進 `docs/archive/`（OVERVIEW 第 6 節的封存表）。

## 1. 常駐的 session 與角色

作者 2026-10-20 把常駐 session 減成一個：遊戲規劃兼派工。合併協調不再常駐，§1.2 留作合併與發版的檢查清單。

**2026-10-21 起遊戲規劃也合併**（作者原話：「你的權限跟我一樣高／開發新功能一次最多3～4個session同步進行／Pr也不要一次開太多 不然會一直解合併衝突／或是等runner 綠了就合併 紅了就修／另外好像很久沒做pr review了 先優先做／再進行新功能依優先順序逐個進行」）：
- PR 綠了遊戲規劃照 §1.2 合併；紅了交回那個 PR 的 session 修。
- 新功能的實作 session 同時最多 3–4 個，照 NEXT_PRIORITIES §22 的順序一件一件開；開著的 PR 也不要多，免得一直解衝突。
  - 作者 2026-10-25：「你先派好了 好像3～4個session沒關係 沒有撞到相同的部分」：3–4 個可以同時派，條件是它們不改同一批檔案；改同一塊的（例如都動 LineAcquisition）照順序一個合了再派下一個。
- PR 審查比新功能優先。上一輪是 #786–#872（§7.1）。
- **多久審查一次**（2026-10-22，作者：「多少pr要做一次pr review 因為有時候只是加入文件跟codex加模型而已你五方比較」）：**數程式的 PR，滿 30 點開一輪審查**。GameCore 的 PR 算 2 點；GamePresentation、App、CI 腳本、資料工具（`tools/` 會產生打包資料的）、`Web/` 的程式算 1 點；只改文件、只加模型或素材（Codex 的模型包、`Map3D*Kit` 的配方）、只改測試的算 0 點。上一輪是審查 L（#1510–#1578，分兩段：L1 #1510–#1549，28 個程式 PR、29 點，[`archive/PR1510_1549_REVIEW_HANDOFF.md`](archive/PR1510_1549_REVIEW_HANDOFF.md)，P1 0、P2 1（L1-1：拆自己的路時每條公車線算兩次，點按卡約 2 秒）、P3 2；L2 #1551–#1578，21 個程式 PR、22 點，[`archive/PR1551_1578_REVIEW_HANDOFF.md`](archive/PR1551_1578_REVIEW_HANDOFF.md)，P1 0、P2 1（L2-1：站長的「跟我做 5 分鐘教學」沒先存目前這局）、P3 4）；下一輪從 #1579 起數。再上一輪是公測前審查 REV（#1496–#1509，[`archive/PR1496_1509_REVIEW_HANDOFF.md`](archive/PR1496_1509_REVIEW_HANDOFF.md)）與審查 K（#1288–#1385，[`archive/PR1343_1385_REVIEW_HANDOFF.md`](archive/PR1343_1385_REVIEW_HANDOFF.md)）。
  - 量的（2026-10-22，main 最近 60 個合併，約 10 小時）：文件 13、只有素材／測試 6、程式 41（其中 GameCore 5）。#962–#1017 共 51 個 PR、37 個程式、41 點：已經超過，下一個空位先開審查 D。
  - 為什麼 30 點：一個審查 session 看 30 個程式 PR（每個 diff 約 5–10 千 token）大約 15–30 萬，在第一次壓縮（約 32 萬）之前看完；上一輪 #873–#944 一次 72 個，A6–A11 到現在還開著。
  - 五方（權重照 NEXT_PRIORITIES §19；選項：A 每 30 個 PR、B 每 50 個 PR、C 每 30 點、D 每天一次、E 每 60 點）：
    | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --- | --: | --: | --: | --: | --: | --: |
    | A 每 30 個 PR | 4 | 3 | 2 | 2 | 1 | 2.70 |
    | B 每 50 個 PR | 3 | 3 | 2 | 2 | 1 | 2.40 |
    | **C 每 30 點** | **4** | **5** | 2 | 3 | 1 | **3.35** |
    | D 每天一次 | 3 | 3 | 2 | 2 | 1 | 2.40 |
    | E 每 60 點 | 2 | 2 | 2 | 2 | 1 | 1.85 |
    - 玩家：bug 早一點被抓到；每 30 點約半天一輪，不會拖到玩家先碰到。
    - 開發：不把審查花在文件與模型上；一輪在一個 session、壓縮前看完；GameCore 算兩倍，因為它有存檔與重播的風險。
    - 美術：模型與素材在自己的 PR 照 art-style 檢查，不進程式審查（各選項差不多）。
    - 鐵道迷：產生真實資料的工具算進來，出處與授權會被看到（C 才有）。
    - 音樂：無。
- **多久做一次 CI 優化**（2026-10-22，作者：「要幾點ci優化 30/60點還是有更好的」）：**不數點數，看數字過線才開**；遊戲規劃每次巡查本來就看 main 的 `ci.yml`，順便對下面的線，任何一條過線就開一個 CI 優化 session；都沒過線的話，每週也量一次。CI 慢不慢跟合了幾個 PR 關係不大，跟加了多少測試、哪個 shard 變長、哪個 UI 測試開始時好時壞有關。
  - 線（2026-10-22 量的現況寫在括號裡）：
    - main 的 `ci.yml` push run 超過 30 分（現在 18–28 分）。
    - 最長的 shard 超過中位數的 1.5 倍（`swift-shards.sh` 的 `classes_of` 該重排）。
    - pull request 的 iOS gate，UI 測試超過約 6 分（CLAUDE.md、決策 199）。
    - full lane 任何一個 job 接近它的時間上限（差不到 10 分）。
    - main 的 `ci.yml` run 的 Annotations 裡有 Swift 分片「near its 20-minute limit」或「about to reach its 20-minute limit」的警告（決策 404：job 用到 17 分〔決策 405；原本 15 分〕、或 18 分 30 秒還沒跑完就印）。
    - 同一個測試 7 天內沒有程式原因紅了 2 次（不穩的測試，照 diagnosing-bugs 查）。
    - pull request 的 macOS job 常常排隊超過 20 分。
  - 2026-10-25 量的（決策 411「其他的線」）：rest 19m44s → 重排（決策 411）；PR 的 iOS gate UI 步 7.3–11.8 分（過 6 分線；決策 412 把閘門從 7 支減到 4 支，估計中位數 5.1 分）；full lane 的 build job 的 UI 步離它的 75 分只差 10–13 分；慢的 runner 上三分之一的 Swift job 過 17 分，要靠共用 build（`docs/research/CI_SHARED_BUILD_2026-10-25.md`，等規劃決定、作者同意加 action）。
  - 2026-10-25 CI 瘦身稽核（`docs/research/CI_PRUNE_2026-10-25.md`，session_01P66bY6nFU891b1C3sYwkRU）：每晚的兩個排程不是重複，已刪的功能也沒留下測試，維持。規劃的決定：`wasm-probe.yml` 只在 PR 跑、`release-archive.yml` 的 PR 路徑縮小（#1252，已合併）；main push 照 PR 的規則選 tier，加每晚一輪完整 `ci.yml`（選項 D，決策 413，#1253）。共用 build（A 案）排在 413 之後。
  - **共用 build（A 案）**（2026-10-25）：規劃 session_0164nEyu2aMPVTpvQww43kj1 照五方選 A（3.20），作者授權 `upload-artifact`／`download-artifact`；session_01PYmwuwjTbABUGgzdQhEhG7 實作（`claude/ci-shared-build`）：`swift-build` job build 一次並上傳 `.build`，分片下載後只跑測試，gate 多讀 build 的結果。做法、驗證與量到的數字在 `docs/decisions/411.md`「續篇：共用 build」；研究在 `docs/research/CI_SHARED_BUILD_2026-10-25.md`。之後：量一週，再考慮減回 17 片。
  - 五方（權重同上；選項：A 每 30 點、B 每 60 點、C 每週一次、D 看數字過線才開、E D 再加每週量一次）：
    | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --- | --: | --: | --: | --: | --: | --: |
    | A 每 30 點 | 2 | 2 | 2 | 2 | 1 | 1.85 |
    | B 每 60 點 | 3 | 2 | 2 | 2 | 1 | 2.15 |
    | C 每週一次 | 3 | 3 | 2 | 2 | 1 | 2.40 |
    | D 過線才開 | 4 | 4 | 2 | 2 | 1 | 2.95 |
    | **E 過線才開＋每週量** | **4** | **5** | 2 | 2 | 1 | **3.20** |
    - 玩家：CI 快，修正和新功能就早一點進 TestFlight；沒問題時不花一個 session 去優化。
    - 開發：照點數開，常常開了沒事做，或該修時還沒到點；看數字才打到真的慢的地方。每週量一次，抓慢慢變長、還沒過線的趨勢。
    - 美術、鐵道迷：無（各選項一樣）。
    - 音樂：無。
- 仍是作者的：TestFlight 發版（發不發、什麼時候發；作者說「發」之後由遊戲規劃替作者按，§1.2）、Apple 帳號與 App Store Connect、secrets、加依賴、copyleft 或沒授權的程式碼，以及 CLAUDE.md 所有的「never」（不自己跑 `testflight.yml`、不開 auto-merge、不 force-push `main`、不取消 `main` 的 push run）。原因是額度：常駐 session 每一輪都要重讀整段對話，連被 PR 事件或排程叫醒也一樣，對話越長越貴。舊的遊戲規劃 session 開了兩天，用量已經碰到每週額度的警告。舊文件裡寫「派工 session」的地方，現在都是遊戲規劃。

| 角色 | 現在的 session | 做什麼 | 交接 |
| --- | --- | --- | --- |
| 遊戲規劃（兼派工） | 第 36 任（2026-10-30 16:50 UTC 起，第 5 層；交接在 §2.0「第三十六次換手」）；再之前第 35 任 session_01YGNNukwV4BudeNCor4i52r（10-30 13:20–16:50，壓縮 3 次）；再之前 作者 10-28 在 claude.ai 手動開的新規劃（三個 repository；現況在 §2.0「第二十四次換手」）；再之前 session_01YGNNupfaTiuQSAJ5tsf5a4（10-28 00:20–05:15，第 3 層，壓縮 3 次後換手）；再之前 session_01YGNNunBu1rxrPwN6bsA7g2（10-27 16:45–10-28 00:20，第 2 層，壓縮 2 次後換手）；再之前 session_01YGNNunheBBBwyekk4Pq7b4（10-27 14:3x–16:45，第 1 層，壓縮 3 次後換手）；再之前 session_01YGNNuovwuBJPdZWXamkhEp（10-27 05:45 起；壓縮 3 次後寫了第二十次換手，作者 13:5x UTC 說「你可以先全面接管了」，續任到第 4 次壓縮前；之後作者從 claude.ai 開新規劃，現況在 §2.0 最前面）；再之前 session_01YGNNuoQekRm2qcVxoPT8ME（10-27 02:16–05:40，壓縮 2 次照 §1.1 換手）；再之前 session_01CWaJGHR4DnSwosLCzJ2Tts（10-26 10:30–10-27 02:10，壓縮 3 次）；再之前 session_01TH2DNkW2meh3EZJ1vxBczC（10-26 03:45–10:30，壓縮 3 次，第 3 次後換手）；再之前 session_01TS89hbaHPJiFJycqrKiK5z（10-25 21:40–10-26 04:00，壓縮 2 次照 §1.1 換手）；再之前 session_01KvN8GrLosqRswrXMQgVQir（10-25 15:35–19:55，壓縮 2 次照 §1.1 換手）；再之前 session_0164nEyu2aMPVTpvQww43kj1（10-25 12:56–15:30，壓縮 2 次照 §1.1 換手）；再之前 session_0138XhXTjToUd3fpKV7kebeH（10-25 05:05–12:40，壓縮 5 次，作者說「交接」）；再之前 session_01B2kaku5NRz2J2CMzc8z3cZ（10-24 23:13–10-25 05:05，壓縮 2 次照 §1.1 換手）；再之前 session_019yHzrc1rgGJgdXSSwRNqgM（10-24 15:07–22:50，壓縮 2 次照 §1.1 換手，已封存）；再之前 session_013dJ7tvDYJnhe7XjXCE5cNi（10-24 08:17–14:00，壓縮 2 次照 §1.1 換手，已封存）；再之前 session_017HD7Krh51WqqzXjy6949Pq（10-24 06:32–08:00，壓縮 2 次照 §1.1 換手）；再之前 session_01AxcyajwHdF6j4ryDMghASM（10-24 05:00–06:30，「第八次換手」，已封存）；再之前 session_01XsVqbA1A5wGtJbuAa881oT（10-24 01:30–05:00，「第七次換手」）；再之前接暫代的 session_01PGibJmGNcvu2d7dJWWhWVb（10-24 00:35–01:30，已封存），再之前 session_01H5RHAwnA69n8EfAUSUrH52（10-23 00:10–10-24 00:35），再之前 session_014nUBHbE9mSK4qXHHgm8xCQ（10-22 22:30–10-23 00:10），再之前 session_01UsF4QYCGrzSeNSFq11i8Wu（18:15–22:30），再之前 session_01Ddr2wiXx1Xhn2m9qNBDnDh、session_01CHQg7B6JqzbScGSjyDwHos（2026-10-22 起，照 §1.1 換手，作者：「要不要全部所有換個session了 都一直在壓縮了」→「好，照表換」；換手時的現況在第 2 節最前面；前任 session_014rYHMtmqA5bEMkBBuKu6PV（10-21 至 10-22，作者：「那你需要先接手嗎太長了」）、session_01NiR5WLMFjMJBktQAMkfmkm（10-21）、session_01WW7o3decEv5LY59nYVqnDN（10-20 至 10-21，作者：「接手 角色表中遊戲規劃的工作」）、session_01V1xd3H9vNkuZoSA3czNfGm（10-16 至 10-18）、session_018D6gYU1yiZMtxSmNNU1K17） | 從玩家、鐵道迷、開發、美術、音樂五個角度決定優先順序與設計，開實作 session 並派工，綠了的 PR 照 §1.2 合併（2026-10-21 起），收作者轉來的玩家回報與 bug（§1.3），寫 TestFlight 的 What to Test，維護 NEXT_PRIORITIES、PLAYER_FEEDBACK 與這份 | 第 1.1、1.3 節 |
| Threads 開發日誌（看進度） | 排程「Threads 開發日誌（看進度）」（台灣時間每晚 21:43 檢查，2026-10-27 規劃五方決定恢復，作者：「我不知道 你自己決定」「排程要看每日進度我也不確定有固定時間發文」）。它只檢查，不一定寫：#1041 最後一則「Threads 草稿交付：涵蓋到 main <sha>」之後，合進 main、玩家看得到的 PR 滿 3 個，或發了新的 TestFlight，才由規劃開寫作 session（Sonnet）；不夠就什麼都不做。現在綁 session_01YGNNunBu1rxrPwN6bsA7g2 的是 `trig_01KEzqJPTdvXeUFCNUy8go3Z`；第二十三次換手時前任代建綁新任的，新 id 在 #1041；綁前任的 `trig_019CQWcaMbiqRpfDwdNvV2qR` 已刪。排程的綁定改不了：換手時現任用同一份 prompt（`get_trigger` 讀得到）建一個綁自己的，再刪掉舊的。更早留下、停用但刪不掉的 `trig_01M2rwYPRRjTwQTC5g6QaW9v`、`trig_01ABYQAarHbVxBbEShiVWDr3` 不會觸發，作者要清可以在排程列表刪 | 寫這段期間的串文草稿，用 SendUserFile 交給作者；草稿不寫日期與時間點；交完在 #1041 留「Threads 草稿交付：涵蓋到 main <sha>」，再封存自己；不 commit、不發布 | `docs/research/THREADS_WRITING.md`（寫法、規則、發到哪一版；新的寫作 session 先讀它）；最早的派工單照 2026-10-14、10-15、10-16 的寫作 session |

不再常駐（2026-10-20 停用）：合併協調 session_01QoA24EvFCFbmbcM1EwaZT7（前任 session_016sNs4eeZwga9hz1CCHkpmX）、派工 session_01MJ7sdeid5DAFjSVbTkmdi3（前任 session_01AaAj4wvJMxJQuLWAoYu6S8）。兩個都從 2026-10-17 起沒有動作。

**額度**（作者 2026-10-20 同意的做法）：
- 實作 session 同時 2–4 個。GameCore 的完整 tier 本來就最多 2 個，macOS runner 也只有 5 台，開更多只是排隊。
- 實作 session 做完一件就收工：在 #231 留合併紀錄、把沒做完的寫進這份。不要留著等下一件。
- **做完就封存**（作者 2026-10-23：「以後只要完成開完pr 檢測／有記錄231 與交接手冊 還有後續檢查都通過就能進入封存了防止之後太多session」）：一個 session 的 PR 開了、CI 綠了、#1041 留了「可合併」或合併紀錄、沒做完的寫進這份，後續檢查也過了，就封存（`archive_session`；要回來可以 `unarchive_session`）。session 列表才不會越堆越多。
- **換手時改舊 session 的標題**（作者同日：「記得把舊遊戲規劃session的標題修改 不然每次都點錯」）：被接手的 session（規劃或實作）封存前，標題改成「【舊・已換手】<角色>（日期）→ 改用 <新 session id>」，現任的標題以「★ 現任：」開頭，作者在列表裡才不會點錯。
- 常駐 session 的對話太長（大約超過 20–30 萬 token）就照 §1.1 換手，靠這份接手，不靠舊對話。
- **壓縮前就換、壓縮幾次一定換**（2026-10-22，作者：「壓縮到一定次數後幫我更換新session 指派的也一樣」→「我是設定400k壓縮耶 你再評估一次」；由遊戲規劃五方決定）：
  - 壓縮點：`CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000` 乘上 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80`，約 **32 萬 token** 時壓縮（不是 40 萬）。壓縮後剩一段摘要，原話與量到的數字會丟。
  - 看自己用了多少：`get_session`（不帶 session_id）的 `external_metadata.context_usage.used_tokens`。量得到，所以主要看 token，壓縮次數只當最後一道。
  - **遊戲規劃：第 3 次壓縮快到時換**（2026-10-25 改，原本是「壓縮 2 次就換」；比較在下面「回頭看（2026-10-25）」）。第 2 次壓縮後，`used_tokens` 到約 **30 萬**（壓縮點約 32 萬）就寫交接 PR（§2.0），照 §1.1 換手，不等第 3 次真的壓縮。條件：(1) 作者每句會影響工作的話，當下寫進 #1041 或該 PR，不等交接；(2) 平常每個規劃的文件 PR 都順手更新 §2.0，交接時只補最後一段；(3) 第 3 圈對作者說過什麼、某個 PR 該不該合不確定時，先查 #1041 與文件，查不到就問作者，不靠印象；(4) 壓縮後發現記錯事、重做已做的事，就提早換。新任只讀第 1 節、§2.0 與第 3 節最上面幾列，其他要用時再讀。
  - **回頭看（2026-10-25，作者：「怎麼感覺每次接手好像都實際壓縮一次後過沒多久就交接好／還是要等到第二次鄰近壓縮才交接」→「那如果鄰近第三次再交接可以嗎」→「五方評分決定」）：改成第 3 次快到時換，加上面四個條件。**
    - 量的：session_01B2kaku5NRz2J2CMzc8z3cZ 10-24 23:13 開工，第 2 次壓縮約 10-25 03:25，一圈約 2 小時；剛壓縮完已用約 13 萬（摘要、CLAUDE.md、重讀的文件），所以第 2 圈比第 1 圈短，作者才覺得「沒多久就交接」。照第 2 次壓縮後才寫交接，#1219、#1220 的審查結果是摘要之後才補進 §2.0。
    - 和 10-22「B 規劃 3 次」（1.55，上面）不同的地方：那時 session 不知道自己壓縮過幾次（摘要不說），規劃的狀態也多半只在對話裡；現在次數記在 #1041、狀態在 PR、CI、#1041 與 §2.0，第 3 圈會走樣的只剩對話裡的原話，條件 (1)(3) 擋這一塊。
    - 五方（權重照 NEXT_PRIORITIES §19；選項：A 第 2 次壓縮後才換〔原本〕；B 第 2 次快到時換；C 第 3 次快到時換＋條件）：
      | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
      | --- | --: | --: | --: | --: | --: | --: |
      | A 第 2 次後 | 3 | 3 | 1 | 1 | 1 | 2.10 |
      | B 第 2 次快到 | 4 | 3 | 1 | 1 | 1 | 2.40 |
      | **C 第 3 次快到＋條件** | **4** | **4** | 1 | 1 | 1 | **2.65** |
      - 玩家：換手的空檔（作者還沒開新任時，沒人合併、派工）一天從約 3–4 次減到 2–3 次，修正和新功能早一點到 TestFlight；B、C 的交接都趁記得時寫，漏事比 A 少。第 3 圈記錯事的風險由條件擋，合併本來就還有 CI 與獨立審查。
      - 開發：換手成本佔比從約 35% 降到約 25%（上面「次數的比較」），作者少開一次 session；A 的交接照兩代摘要寫，細節會掉。
      - 美術、鐵道迷、音樂：無。
  - **回頭看（2026-10-22 22:55 UTC，作者：「幫我回頭看一下最近幾個session 想問一下現在的壓縮換session 次數還需改嗎」）**：次數不改，改的是規劃怎麼省 token。
    - 量到的（`get_session` 的 `context_usage` 與 `usage`）：前任規劃 session_01UsF4QYCGrzSeNSFq11i8Wu 做了約 4 小時 15 分、壓縮 2 次、約 $19；新任 session_014nUBHbE9mSK4qXHHgm8xCQ 開工 22 分鐘就用到 28.6 萬（壓縮點約 32 萬）、約 $7.9。實作：決策 358（session_01DQGby5PQyfvKAmzTey1zVE）一個 PR 壓縮 1 次、約 $12.7；決策 359（session_0134bAxAfAEENYWu1NaK1RWW）壓縮 1 次、約 $7.8；10-22 下午到晚上的 8 個實作 session 有 5 個在一個 PR 裡壓縮 1 次，沒有一個到 2 次，「1 次後不接新的」都照做，沒有記錯事的例子。
    - 規劃用得快的原因：每次訂閱 PR 會收到兩則約 2–3 千 token 的事件說明，每則「轉 ready」「合併」「CI 完成」也各一則；開工讀 #1041 全部留言約 2.5 萬。
    - 改法：(1) 規劃**不訂閱實作 session 的 PR**，靠它們在 #1041 留「可合併」並 send_message，加上規劃自己的巡查（send_later）；(2) 規劃自己開的文件 PR 不訂閱，推上去後巡查時看一次 check run 就合；(3) 新任讀 #1041 只讀上一則「遊戲規劃接手」之後的留言，更早的照 §2.0；(4) 實作 session 的規則不變。
    - 五方（選項：A 不改；B 規劃改成壓縮 3 次才換；C 次數不改、規劃少收事件；D 實作改成壓縮 2 次前都能接新工作）：
      | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
      | --- | --: | --: | --: | --: | --: | --: |
      | A 不改 | 3 | 2 | 1 | 1 | 1 | 1.85 |
      | B 規劃 3 次 | 2 | 2 | 1 | 1 | 1 | 1.55 |
      | **C 少收事件** | **4** | **4** | 1 | 1 | 1 | **2.65** |
      | D 實作放寬 | 3 | 2 | 1 | 1 | 1 | 1.85 |
      - 玩家：C 讓規劃同樣的額度能合更多 PR、派更多工；B、D 多一代摘要，派錯工、合錯 PR 的機會變大。
      - 開發：規劃的 token 大多花在重讀事件說明，不是做事；C 直接砍掉這部分，次數照舊就不用重算 §1 的表。D 讓實作在摘要後接新工作，續作反而要重讀一半文件。
      - 美術、鐵道迷、音樂：無。
  - **回頭看（2026-10-24，作者：「要先看每個session壓縮的頻率跟長度 你覺得要改嗎」）：400k 與 2 次不改，加一條量得到的線。**
    - 量的：10-21 以來 103 個 session 的 `get_session` 的 `usage`。壓縮次數用「`cache_write_tokens` 減 `context_usage.used_tokens`，每次約 24 萬」推估，這個換算是拿 10-22 兩個確定壓縮 2 次的規劃（01UsF4 61 萬、014nUB 72 萬）校正的，不是逐次數的。
    - 遊戲規劃 8 個：10-22 照規則的 4 任每任 2–7 小時、$15–22、約 2 次；沒照做的 3 任：10-21 的 01NiR5 12 小時 $81 約 8 次、014rYH 17 小時 $90 約 11 次，10-23 的 01H5RH 24.5 小時 $120 約 16 次（逐筆數紀錄是 12 次，推估偏高約三成，線照樣有效）。
    - 實作 94 個：沒壓縮 33、約 1 次 31、約 2 次 18、3 次以上 12（13%，多在 $30–60，決策 313 的 session_01Y25x9NJSKmAuP1M1K3Sf3C 15 小時 $120 約 16 次）；中位數約 2.2 小時、$11。
    - 原因：照做時成本與換手都合理；出事的都是 session 不知道自己壓縮過（摘要不說次數），#1041 也沒有人留過「壓縮第 N 次」。
    - **線**：`cache_write_tokens − used_tokens` 超過約 **48 萬**，就當作壓縮 2 次（約 72 萬是 3 次）。遊戲規劃每次巡查用 `get_session`（不帶 id）看自己，過了 48 萬、`used_tokens` 又到約 30 萬就照 §1.1 換手（2026-10-25 起）；也看做中的實作 session，過了 48 萬就請它照下一條收尾。實作 session 推 PR 前看自己一次。「壓縮第 N 次」的留言照舊，這條是保底。
    - 五方（選項：A 不改；B 窗口改 300k；C 次數改 1 次；D 不改窗口與次數、加量得到的線）：
      | 選項 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
      | --- | --: | --: | --: | --: | --: | --: |
      | A 不改 | 2 | 2 | 1 | 1 | 1 | 1.55 |
      | B 300k | 2 | 2 | 1 | 1 | 1 | 1.55 |
      | C 1 次 | 3 | 2 | 1 | 1 | 1 | 1.85 |
      | **D 加線** | **4** | **5** | 1 | 1 | 1 | **2.90** |
      - 玩家：規劃壓縮十幾次後記錯事、派錯工的機會變小；B、C 都擋不住「不知道自己壓縮過」。
      - 開發：量得到、不靠記得；照這條線，這三天三任規劃與 12 個實作 session 大約少花三分之二。B、C 讓照規則做的 session 也更常換手。
      - 美術、鐵道迷、音樂：無。
  - **實作 session：壓縮 1 次就不接新的**，只把手上這個 PR 做完；**壓縮 2 次就停**，做到能停的地方（推上去、PR 開好），沒做完的寫進這份，send_message 告訴遊戲規劃，由它開新 session 接手。實作 session 只在推 PR 與 CI 事件時被叫醒，重讀的次數少，壓縮一次的損失比重開一次（重讀文件約 15–20 萬）小。
  - 每個 session 被壓縮後的第一件事：在 #231 留一行「session_…：壓縮第 N 次」（N 從自己在 #231 的上一則數起），次數記在 #231，不靠對話記得。遊戲規劃巡查時看這些留言，到次數還沒停的就提醒。
  - **次數的比較**（2026-10-22）。估算的前提：約 32 萬壓縮；壓縮後的摘要約 5 萬（沒量過）；新的規劃開頭約 20 萬（實測 205,140）、實作約 15 萬（推估）。所以一個 session 能做的量：開頭到第一次壓縮，加上每次壓縮後約 27 萬。換手的固定成本：新任的開頭，加上約 3 萬寫交接（規劃還要一個交接 PR）。
    | 次數 | 規劃能做的量 | 換手成本佔比 | 摘要疊幾代 |
    | --: | --: | --: | --: |
    | 1 | 約 39 萬 | 約 59% | 1 |
    | 2 | 約 66 萬 | 約 35% | 2 |
    | 3 | 約 93 萬 | 約 25% | 3 |
    | 4 | 約 120 萬 | 約 19% | 4 |
    實作 session 的開頭較小，佔比略低，排名相同。摘要疊越多代，記錯的機會越大；實例：前任規劃壓縮多次後，叫 session_018gQPWzopcCfuR9gTAApKTj「汽機車分走旅客第 2 步合併後收工」，其實那件早已合併，它正在做的是第 12 名（2026-10-22）。
    五方各給 1–5 分，權重照 NEXT_PRIORITIES §19（玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）：
    | 次數 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --: | --: | --: | --: | --: | --: | --: |
    | 1 | 3 | 2 | 1 | 1 | 1 | 1.85 |
    | **2** | **4** | **4** | 1 | 1 | 1 | **2.65** |
    | 3 | 3 | 3 | 1 | 1 | 1 | 2.10 |
    | 4 | 2 | 2 | 1 | 1 | 1 | 1.55 |
    - 玩家：派錯工、合錯 PR 最後都變成玩家看到的 bug 或延遲；1 次換太勤，合併等交接；3 次以上記錯的機會變大（上面的實例）。2 次兩邊都輕。
    - 開發：1 次時一半以上的用量花在換手；2 到 3 次省下的約 10 個百分點，抵不過多一代摘要記錯要重做的成本；實作的程式在 git 裡，記錯的是量測與理由，2 次後交接最划算。
    - 美術、鐵道迷、音樂：無，三者對每個次數都一樣，不影響排名。
    - 結論：規劃與實作都是 2 次。實作另加「壓縮 1 次就不接新的」。
  - **壓縮點（`CLAUDE_CODE_AUTO_COMPACT_WINDOW`）100k–900k 的比較**（2026-10-22，作者：「100k～900k與次數下去比較 用這個專案來看最推薦的」）。同樣的估算：壓縮在 80%；每一輪多約 3 千 token，每一輪都重讀整段，所以成本約和平均長度成正比；成本指數是「每做 1 千 token 的事要重讀幾千 token」，只用來互相比，不是金額。表裡是規劃（開頭 20 萬）、壓縮 2 次就換：
    | 窗口 | 壓縮在 | 開頭讀完後還剩 | 每次換手前做的量 | 成本指數 | 換手佔比 | 每做 100 萬壓縮幾次 |
    | --: | --: | --: | --: | --: | --: | --: |
    | 100k | 8 萬 | 讀文件時就壓縮 | — | — | — | — |
    | 200k | 16 萬 | 讀文件時就壓縮 | — | — | — | — |
    | 300k | 24 萬 | 4 萬 | 約 42 萬 | 68 | 35% | 約 5 |
    | **400k** | **32 萬** | **12 萬** | **約 66 萬** | **77** | **26%** | **約 3.7** |
    | 500k | 40 萬 | 20 萬 | 約 90 萬 | 89 | 20% | 約 2.9 |
    | 600k | 48 萬 | 28 萬 | 約 114 萬 | 101 | 17% | 約 2.3 |
    | 700k | 56 萬 | 36 萬 | 約 138 萬 | 114 | 14% | 約 2.0 |
    | 800k | 64 萬 | 44 萬 | 約 162 萬 | 127 | 12% | 約 1.7 |
    | 900k | 72 萬 | 52 萬 | 約 186 萬 | 140 | 11% | 約 1.5 |
    實作 session（開頭約 15 萬）排名相同。五方（權重同上）：
    | 窗口 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |
    | --: | --: | --: | --: | --: | --: | --: |
    | 100k、200k | 1 | 1 | 1 | 1 | 1 | 1.00 |
    | 300k | 3 | 3 | 1 | 1 | 1 | 2.10 |
    | **400k** | **4** | **4** | 1 | 1 | 1 | **2.65** |
    | 500k | 4 | 3 | 1 | 1 | 1 | 2.40 |
    | 600k | 3 | 3 | 1 | 1 | 1 | 2.10 |
    | 700k–900k | 2 | 2 | 1 | 1 | 1 | 1.55 |
    - 玩家：太小（300k 以下）壓縮太勤、細節常丟，派錯工的機會大；太大（600k 以上）每一輪要在很長的對話裡找東西，容易漏看，回應也慢。400k–500k 兩邊都輕。
    - 開發：每週額度是真的限制（舊規劃兩天就碰到警告）。成本指數 400k 比 300k 多 13%，但 300k 的規劃讀完文件只剩 4 萬就壓縮；500k 比 400k 多 16%，只少一點換手；700k 以上多五成到八成。
    - 美術、鐵道迷、音樂：無。
    - **結論：維持 400k，規劃與實作都壓縮 2 次就換**。比窗口更有效的是把開頭讀的量變小：新任規劃只讀第 1 節、§2.0、第 3 節最上面幾列與 NEXT_PRIORITIES §22.1、§22.2（推估約 10 萬），同樣 400k 就多出約 10 萬可以做事。
- 研究、寫文件可以用較低的思考強度；GameCore 的難題用高的。
- 對話到一定長度就自動壓縮：`.claude/settings.json` 的 `autoCompactWindow` 是 400000（2026-10-20，作者：「你四方思考後決定」）。雲端 session 另外帶 `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=80`，所以實際大約在 32 萬 token 時壓縮（推算，沒有實測）。壓縮會把舊對話摘要，作者的原話、量到的數字要在壓縮前寫進 PR、#231 或這份。不要這個設定時，刪掉那一行就好。
  - Claude Code 只讀 session 根目錄的 `.claude/settings.json`。同時掛好幾個 repo 的雲端 session，根目錄是上一層，讀不到 repo 裡這一行。所以作者也在雲端環境加了環境變數 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000`（2026-10-20），它比設定檔優先，不管掛幾個 repo 都生效。
  - 要確認一個 session 有沒有套用，執行 `env | grep COMPACT`。
  - 要改值，兩處一起改。

### 1.1 遊戲規劃

- **做決定的方式**（作者 2026-10-14「我不再做決定，都以這個當預設」，10-15 加音樂，10-20 加鐵道迷）：五個角度（玩家、鐵道迷、開發、美術、音樂）各一行理由寫進 PR；鐵道迷看真實度與資料來源，和真實鐵路無關就寫「鐵道迷：無」；其他選項的預覽留在 PR；然後就做。作者自己保留：TestFlight 發版、Apple 帳號與 App Store Connect、secrets、加依賴、用 copyleft 或沒授權的程式碼。
- **排序**：NEXT_PRIORITIES §22（2026-10-22，把還沒做的全部放進一張表，取代 §19、§21 的順序；權重照 §19：玩家 30、開發 25、美術 15、鐵道迷 15、音樂 15）。§14 是舊的權重（鐵道迷＋產品），§15 是參考庫還沒做的項目與 2026-10-16 的順序。
- **一條線一次一個 PR**：前一個合併再開下一個（§14.4）。同時跑全套 Swift CI 的 GameCore PR 最多 2 個；開 PR 前先看 #231 與開著的 PR 還有沒有名額。
- **每次發版**：
  - 發版前：改 `.github/testflight-whats-new.md`（它只在上一版之後有改動時才會被用，沒改就是自動列出的 PR 清單）。
  - 發版前，同時改 App 裡的「這版新增」卡：`Sources/GamePresentation/WhatsNew.swift` 的 `WhatsNew.entries`（兩種語言、只寫玩家能做什麼；上一則已發出去就在最前面加新的一則、id 用當天日期，還沒發就改最前面那則；步驟在決策 415）。
  - 發版後：看 `testflight.yml` 的 run 號與 commit，記進 `docs/research/PLAYER_FEEDBACK.md`。版本號是 0.5.0 (run 號.1)。
- **踩過的坑**：
  - 不要憑記憶說版本號，查 `testflight.yml` 的 run。2026-10-16 把 66.1 當成 64.1。
  - 發版前要收工時，叫 session「做完再停」，不要叫它把做一半的東西留給之後（作者 2026-10-16：「記得不要暫停讓他們做完」「不要限制 可以任意開 pr 但就是收工」）。
  - session 停下來，不一定是因為發版。重開之前先讀那個 session 自己的紀錄與 #231。例：語言選單是作者說「先不要動」才停的，不是發版；後來作者本人在那個 session 回「四方決定要不要繼續」，才重開成 #727。
  - 給實作 session 的派工單要對照 art-style §7 的現行規則：參考庫的模型「任意組合、成品跟原本不同」，不是「能搬就搬」。
  - 同時開好幾個 session，它們會在幾分鐘內登記同一個決策號（2026-10-16：三個都登記 256；2026-10-17：#774 與 #776 都用 271，照登記先後 #776 改成 272）。派工單裡直接寫好號碼；或開完之後看一次 #231，照登記先後重排並留言。

- **作者提新事時，先排序再動手**（2026-10-24，作者：「我一直很怕我一提你就做了 沒先考慮其他順序」）：作者提一件新功能或改動時，先回三件事：它在 NEXT_PRIORITIES §22.2 排第幾（或該排第幾）、提前做會擠掉哪幾件、建議（照排、提前或先不做），作者說好再派。只有 bug、玩家回報的當機卡頓、或本來就排最前面的，才直接派。
  - 例：Game Center（§22.2 約第 40 名）與 iCloud 存檔是作者明說才提前的，前任沒有說它們跳過了約 30 件；Codex 列車接進營運（第 16 名）曾被派在還沒派的 10e「斷路接起來」之前，後來補派 391 第二個 PR。
  - **只重排還沒開始的事**（作者：「可是叫他停不就白做了等他先做完一個段落吧」）：已經在做的 session 不叫停，讓它做到能停的地方（commit、push、開 PR）再換順序；做完的東西開 PR 留著，不要丟。
- **換手**（2026-10-16，作者：「你太長了接手」）：遊戲規劃的對話太長時，開新 session 接手。新 session 的派工單要寫清楚現在進行到哪、等誰；每日開發日誌的排程改到新 session；在 #231 留言；第 1 節表格的 session 改成新的。
  - **2026-10-27 改了**（作者：「遊戲規劃也可以自己開 到鄰近第7.8次的時候需要我自己開再說」「遊戲規劃的模型永遠都選opus 5.5高」）：
    - 規劃可以自己用 `create_session` 開下一任，`model: "claude-opus-5-5"`。
    - 開之前用 `get_session`（不帶 id）看自己的 `lineage.depth`（上限 8）。下一任會到第 7 層時，改請作者在 claude.ai 開。
    - `create_session` 沒有設 effort 的參數：作者從 app 開的 session 是 `effort_level: "high"`，session 開的看不到這一欄。所以「高」只有作者開的才確定。
    - 下面 2026-10-24 那條只在快到第 7 層時適用。
    - 規劃自己開下一任後，在 #1041 和對話裡請作者到 app 把新 session 的強度改成「高」；作者不方便改時，就請作者從 claude.ai 開。實作 session 不用改強度（作者 2026-10-27：「結果還是需要我自己改高」）。
  - **實作 session 照難易度選模型**（2026-10-27，作者：「根據派工單難易度 給session決定opus 或是sonnet」）：`create_session` 的 `model` 一定要寫，不寫就沿用規劃的 Opus。
    - `claude-sonnet-5-5`：只寫文件、研究整理、抓資料、照現成寫法的小 UI 改動、單純的測試或 workflow 調整。
    - `claude-opus-5-5`：動 GameCore、決定性或存檔，新決策要寫程式的，3D、美術、聲音，難查的 bug 和 CI 紅。拿不準就選 Opus。
    - 派工單和 #1041 的登記寫上用了哪個模型。Claude Pro 的模型由作者在 Pro 選，派工單裡寫建議的模型。
  - **下一任由作者從 claude.ai 直接開，不要由 session 用 `create_session` 開**（2026-10-24）：session 開的 session 會多一層，到第 8 層就不能再 `create_session`、`send_later`、建排程（session_01PGibJmGNcvu2d7dJWWhWVb 就是第 8 層，只剩合併、留言、`send_message`），規劃就不能派工。換手時前任把交接寫進 §2.0、開文件 PR，再請作者在 claude.ai 開一個新 session，貼上一句「你是遊戲規劃兼派工，照 docs/HANDOFF.md §1 與 §2.0 最上面一段接手」。實作 session 照舊由規劃開（規劃那時是第 1 層，實作是第 2 層）。

### 1.2 合併與發版的檢查

（合併協調 session 2026-10-16 寄來的交接原文，整理成條列。2026-10-20 起沒有常駐的合併協調。2026-10-21 起遊戲規劃照這一節合併（§1）；作者在別的 session 裡授權它合併，或要發版時開一個短 session 確認，那個 session 也照這一節。）

**權限**：遊戲規劃（作者 2026-10-21 授權），或作者本人在那個 session 裡授權了的 session，才合併（CLAUDE.md 的「never merge a PR」只在這時放寬）。不開 auto-merge、不 force-push、不碰 `testflight.yml`；只有作者在遊戲規劃 session 裡說「發」時，遊戲規劃替作者按（下面「發版前」）。

**每個 PR 合併前確認**（`pull_request_read` 的 get 與 get_check_runs）：
- 不是 draft，`mergeable_state` 是 `clean`。
- check runs 全部是 success 或 skipped，沒有 in_progress。
  - 決策 265 之後，PR 的 `Swift CI (gate)` 會等同一個 commit 的 `iOS App Build`，iOS 紅了 gate 就紅；所以 gate 綠就代表 iOS 也綠了。
  - iOS 失敗、重跑通過之後，gate 不會自己變綠：對 CI 那一輪按 Re-run failed jobs（`actions_run_trigger` 的 rerun_failed_jobs）。
  - 「Remember that this change passed」顯示 skipped 是正常的：同一個改動前一輪已經跑過。
  - PR 舊 commit 的 `Swift CI (gate)` 是 skipped、旁邊有一個 `Superseded by a newer push?`：那一輪被新的 push 取代了，看 head 那一輪（決策 329）。head 上的 gate 是紅的、訊息寫「cancelled because a newer push replaced」，也是同一回事。
  - 分片 log 裡的「swift build was killed by signal … Building once more」是工具崩潰後自動重建（決策 329），不是測試失敗；同一個 job 再崩潰一次才會紅。
  - Xcode build 有時跑兩輪，兩輪都要看。
- main 最新一次 push 的 `ci.yml` 是綠的（`actions_list` 的 list_workflow_runs，條件 ci.yml、branch main、event push）。cancelled 是被新的 push 取代，不算紅；要看最新一個跑完的。決策 413 起 push 跟 PR 一樣只跑它的 tier，每晚 01:37（event schedule）那輪才跑全部分片：那輪紅了也算 main 紅。

**PR 綠了就不再推小修**（作者 2026-10-27：「為什麼審核過了你還給我按重跑😠」）：審查時發現的錯字、文件、格式這類小事，PR 已經綠了就不推，每推一次整套 CI 重跑。在 PR 留言記下，等之後另一個本來就要改那些檔的 PR 一起帶。只有 CI 紅了，或真的會出錯（程式行為錯、資料錯、會誤導下一個 session 的交接）才推。審查要改的，最好在 CI 還沒跑完前一次推完。

**合併**：
- 用 `merge_pull_request`，merge_method 用 `merge`，`expectedHeadSha` 填 head 的完整 40 碼。
- 合完在 #231 留一則：PR 號、head 與合進 main 後的 sha。再用 send_message 通知那個 PR 的 session。

**批次**：
- 一批 3–5 個綠的 PR，兩批之間等 main 的 `ci.yml` 綠。
- 只改 docs，或只改 UI 測試、CI 腳本的 PR，可以隨時合。
- 先合正在等的那一個：有 PR 為了解衝突重跑 CI 時，先不要合另一個也改 OVERVIEW、ARCHITECTURE 或這份的 PR，否則它要再解一次（2026-10-21：先合 #876，#875 第二次衝突）。

**GameCore 名額**：
- 同時最多 2 個要跑完整 tier（23 個 job：決策 405 的 21 個、決策 411 續篇的 build job 與決策 495 的 campaigns-19）的 PR 在跑 CI。改 `.github/scripts/swift-shards.sh` 這類 CI 腳本也算完整 tier。
- session 問能不能推：當下在跑的完整 tier 不到 2 個就答可以。
- GameCore PR 的 base 比另一個已經合進去的 GameCore 改動舊時，請它 merge main（不要 rebase），重跑完整 tier 再合。

**決策號與文件衝突**：
- 兩個 PR 撞同一個決策號（329 起是兩個 `docs/decisions/<N>.md` 同名），照 #231 登記的先後，後登記的改號；ARCHITECTURE、OVERVIEW 衝突（改 1–328 的「後來」時還會有）：請該 session 自己 merge main 解。
- 存檔版本與決策號以 main 加上 #231 還沒釋出的登記為準，取最大值加一。

**full lane**（`ios-build.yml` 把 iPhone UI 測試全部跑一次：兩個 iPhone job 加 iPad 教學，約 42–45 分鐘，佔 3 台 macOS）：
- 合併後不用手動跑（決策 265）：`ios-full-lane.yml` 在合了會影響 App 的 PR 之後自己啟動，最多每三小時一次。10-14 到 10-16 的 67 小時裡 full lane 跑了 42 次，只有 7 次是它啟動的，佔全部 macOS 用量的 34%。
- 只在兩種情況用 `actions_run_trigger` 手動跑（run_workflow，workflow `ios-build.yml`，ref main）：
  - 發版前要用的 HEAD；
  - full lane 紅了，要二分的 commit。
- 只改 docs、`Tests/`、`tools/` 的 PR 不影響 App，不用重跑。
- 要發版的 commit 必須自己有一輪綠的 full lane。

**full lane 紅了**（決策 329 起，`full-lane-watch.yml` 會在 #1041 自動留言：第一次紅、紅燈裡又有新的 job 或新的測試紅、綠回來；留言列出紅的測試。2026-10-25 以前只比 job，同兩個 job 裡換不同的測試紅就不留言。看到就照下面做）：
1. 用 `actions_list` 的 list_workflow_jobs 找出失敗的 job。
2. 用 `get_job_logs`（return_content 設 false）拿到 log 網址，用 curl 下載到 scratchpad。
3. 用 `grep -aE "error: -\[|' failed \(|Executed [0-9]+ tests, with"` 找出失敗的測試與行號。
4. 跟上一輪綠的 full lane 比：`git log --first-parent <綠>..<紅>`，再用 `git diff --name-only <merge>^1 <merge>` 看每個 PR 改了哪些檔。
5. 從 commit 的 `Claude-Session:` trailer 找到做那個 PR 的 session，用 send_message 交給它。附上 run、job、測試名、行號、錯誤訊息和可疑的 PR。
6. 對方可以用 `ios-build.yml` 的 `only_testing` 分段驗證（例如開 `claude/bisect-*` branch）。修正 PR 綠了就合，全部修完再跑一輪 full lane。
7. 發版前紅了：立刻告訴作者「先不要發」，並說明原因。

**發版前**（作者 2026-10-23：「改成我說可以發你才能替我發」。發不發由作者決定；作者在遊戲規劃 session 裡說「發」之後，遊戲規劃照下面確認，都綠才用 `workflow_dispatch` 在 `main` 跑一次 `testflight.yml`，輸入照作者上一次發版的 run，作者另外指定的話照作者說的。不是綠的就告訴作者哪裡紅，等作者再說一次才發。作者也可以自己按。實作 session 一律不碰。第 84 版（2026-10-23）遊戲規劃去按時被 session 的權限檢查（自動模式，理由「正式發布」）擋下，由作者自己按；要遊戲規劃替作者按，作者須在那個 session 的權限設定允許啟動 `testflight.yml`，否則照舊告訴作者「可以發（commit X）」與輸入，請作者按）：
- **作者先發、遊戲規劃後報（作者 2026-11-01：「以後都這樣我自己先試 你再告訴我結果省效率」）**：作者想發就自己按 `testflight.yml`，不等完整 `ci.yml` 與 full lane。遊戲規劃照常替那個 commit 跑完整 `ci.yml` 與 full lane（還沒跑的話），跑完把結果報給作者；紅的寫原因、會不會影響玩家，並記進 PLAYER_FEEDBACK。所以 What to Test 和「這版新增」卡不能等作者說「發」才寫：遊戲規劃每合一批玩家看得到的 PR，就在同一批（或緊接的 PR）更新 `.github/testflight-whats-new.md` 與 `WhatsNew.entries` 最前面那一則（寫成「下一版」，版號照上一版加一），讓作者任何時候按都是對的。103.1 就是作者先按、這兩份還停在 102.1：App Store Connect 的 What to Test 由遊戲規劃把寫好的文字交給作者貼上，App 裡的卡沒有 103.1 那一則，下一版的那一則把 103.1 的新增一起寫進去。遊戲規劃自己替作者按（作者說「發」）時，下面的條件照舊。
- **先寫 What to Test**：`.github/testflight-whats-new.md` 寫好這一版給玩家看的說明（照 83.1 的格式：新增的、修好的、沿用的、請幫忙看），合進 main，這個合併的 commit 才是要發的 commit。沒寫就不說「可以發」：`testflight-changes.py` 只在這個檔案自上一版之後改過才用它，否則填 PR 標題，作者不要那個（84.1 漏寫，作者：「每次都改我這個 說了幾次」）。
- **同一個 PR 改「這版新增」卡**：`WhatsNew.entries` 最前面那一則寫這版給玩家的新增與修好的（兩種語言；決策 415 的步驟）。沒改的話更新上來的玩家看到的是上一版的內容，或沒有卡。
- 要發的 commit 就是 main HEAD，它要有一輪綠的**完整** `ci.yml`（跑了全部分片的：每晚台灣 01:37 那輪，或用 `workflow_dispatch` 手動跑的；push run 從決策 413 起只跑它的 tier，不算），它自己的 full lane 也要綠。HEAD 是當天晚上之後才合的，就手動跑一輪 `ci.yml`（`actions_run_trigger` 的 run_workflow，workflow `ci.yml`，ref main）。
- 看 #1041 最後一則 `full-lane-watch.yml` 的自動留言：最後一則是「紅了」、「又有 job 紅了」或「又有測試紅了」、之後還沒有「綠了」，就是 main 的 full lane 還紅著，先不發（決策 329）。
- 確認的時候如果 main 又合了改 App 的 PR，要在新的 HEAD 重跑 full lane。這時可以取消舊 commit 用 workflow_dispatch 跑的 full lane，讓出 macOS runner（上限 5 個）。
- 確認後通知遊戲規劃與作者「可以發（commit X）」，並請各 session 發版前別再合改 App 的 PR。
- **健康報告**（作者 2026-10-24：「健康報告也開始做」；作者不看程式碼，「我也不知道你有沒有做錯」）：說「可以發」時一起給作者一張白話的紅綠燈表，不寫程式名詞。用 🟢 綠、🔴 紅、⚪ 還沒驗：
  | 項目 | 看什麼 |
  | --- | --- |
  | 規則與存檔 | 這個 commit 完整的那輪 `ci.yml`（golden、舊存檔、replay） |
  | 畫面與操作 | 它自己的 full lane（iPhone、iPad 的 UI 測試） |
  | 發版 | `release-archive.yml`，或上一次 TestFlight 用同樣設定成功 |
  | 這版改了什麼 | 照 What to Test，三到五行 |
  | 測試管不到、要作者在手機上看的 | 決策裡寫 UNVERIFIED 的（實機 GPU、手感、樣子） |
  | 風險 | 有沒有碰到存檔、帳號、隱私、entitlement、伺服器；有的話，獨立審查的結果 |
  紅或⚪的寫原因與要不要擋發版；作者已經先發的，報告照樣給，並記進 PLAYER_FEEDBACK。
- **獨立審查**（作者 2026-10-24：「重要的 PR 加一次獨立審查」）：會碰到存檔讀寫、帳號、隱私、entitlement、伺服器，或付費的 PR，合併前另開一個沒參與製作的 session 審查。只給它 PR 號與 CLAUDE.md，不給製作過程的結論，請它用白話回報「什麼情況會出事、玩家看到什麼、多嚴重」，結果附在健康報告。最重要的幾個（例如加 Game Center／iCloud 的 entitlement），作者可以另外用自己的 Claude Pro 帳號再看一次，提示照 2026-10-24 遊戲規劃給作者的那段。
- 作者在收到「可以發（commit X）」之前就發了，要在 PLAYER_FEEDBACK 記下實際發的 commit 與它 full lane 的結果（72.1：作者 10:47 UTC 發 8c305a6，它的 full lane 才剛開始、後來紅；與全綠的 c3a3ec7 只差一個 UI 測試檔，App 相同。審查 #785 第二節）。
- 發版後在 #231 寫「發版凍結解除」。

**巡查**：用 `send_later` 排下一次巡查，訊息寫清楚要查哪個 run、綠了做什麼、紅了做什麼。計畫改了，就用 `delete_trigger` 刪掉舊的巡查。

**工具**：
- GitHub MCP（先用 ToolSearch 載入）：`pull_request_read`、`merge_pull_request`、`actions_list`、`actions_get`、`actions_run_trigger`（run_workflow、cancel_workflow_run）、`get_job_logs`、`add_issue_comment`（#231 只留言）、`list_pull_requests`。
- claude-code-remote：`send_message`、`send_later`、`delete_trigger`。
- scratchpad 裡 clone 一份 repo，查合併範圍、PR 改的檔、session id：`git log --format=%b A^1..A^2 | grep -o 'session_[A-Za-z0-9]*'`。
- GitHub 留言結尾都要加 Claude Code 的 footer；不寫 `@claude`。

**踩過的坑**：
- #701 的景點標記在買地選格時吃掉點擊。PR 自己的 gate 沒測到，到 full lane 才紅。這種情況要請 session 先用 `only_testing` 跑它改到的 UI 測試，再合。
- UI 測試時好時壞：開局鏡頭 2 秒內還在動（#719）、教學第 15、16 步一下就過去（#714）、時刻列要看當下的行車狀況（#712）。不要重跑碰運氣，要叫 session 把測試修穩。
- 作者也會自己合 PR。查之前先看 state，可能已經 merged；也要留意 main 已經往前走了。
- 發的是 main HEAD。full lane 測過的 commit 如果被新合的 App PR 蓋過，HEAD 要自己再跑一輪綠的 full lane。
- #701 拿了 #700 已經用掉的決策 249。合之前要看決策號有沒有撞。
- 刪 bisect branch 會被自動模式擋下，交給作者刪。
- 不要取消 main 的 `ci.yml` push run。只能取消自己用 workflow_dispatch 跑的 full lane，或 PR 的 run。
- #697 把選單從 6 列改成 8 列，SettingsUITests 跟著紅了三支（#706 改回 6 列）。改版面的 PR 要預期 full lane 會連帶紅。

### 1.3 派工（遊戲規劃兼任）

（派工 session 2026-10-16 寄來的交接原文，整理成條列。2026-10-20 起由遊戲規劃兼任。）

**職責**：
- 接作者轉來的 TestFlight 玩家回報與 bug，到最新 main 查證，有問題就用 `create_session` 派修正 session，結果轉告作者。
- 也盯 main 的 full lane（iOS App Build／ios-full-lane），紅了就派人修。決策 329 起紅了會在 #231 自動留言（`full-lane-watch.yml`），不用自己一直去 Actions 頁面看。
- 不合併 PR，合併是作者的事（§1.2）。

**查證**：
- `git fetch origin main` 之後 grep 相關程式，先分清楚是 App 的 bug、過時的測試，還是已經修過。
- 用 GitHub 工具看 run 與 job 的 log。job 還在跑時拿不到 log（404），先看各 step 的 conclusion。

**派工單**一律用繁體中文，要寫這些：
- 作者原話，加上截圖的文字描述（子 session 看不到圖）；
- 現況，寫到檔案和行號；
- 要做什麼；
- 先寫一個在 origin/main 會失敗的測試，再修；
- 不改 golden、SaveFixtures、ReplayFixtures 的值；
- 要協調的對象：改同一個檔案的 session；GameCore 的完整 tier 同時最多 2 個；
- 驗證方式：本機只跑快速檢查；UI 測試只用 `ios-build.yml` 的 `only_testing`；
- 決策號：派工單寫好號碼（#231 的登記就是預約），PR 只加 `docs/decisions/<N>.md` 一個檔，不改 ARCHITECTURE 的最後、OVERVIEW 的決策列與 §9（決策 329，2026-10-21 晚）。不用再先在 main 放「### N. （預約）」一節，合併後也不用補 §9 的索引。以前每個 PR 都接在 ARCHITECTURE 最後、改 OVERVIEW 同一行；10-21 改成預約一節也擋不住，相鄰的預約節還是同一處（#934 三次衝突；三天 49 個 merge main 的 run，41 個是這兩份，佔 PR 的 Linux 用量四成，`docs/research/CI_MEASURE_2026-10-21.md`）；
- 壓縮：被壓縮後在 #231 留「壓縮第 N 次」；第 1 次後不接新的，第 2 次就做到能停的地方交接（§1 的「壓縮前就換、壓縮幾次一定換」）；
- 收尾：draft → 綠 → ready → 在 #231 留「可合併」→ 用 send_message 告訴遊戲規劃；
- **封存**（作者 2026-10-23：「只要完成開完 PR、檢測、有記錄 231 與交接手冊、還有後續檢查都通過就能進入封存，防止之後太多 session」）：實作 session 做完、PR 開了、CI 綠、登記處（現在是 #1041）留了「可合併」、還有後續的寫進本檔、遊戲規劃要它查的也查完，遊戲規劃就把它封存，不用等合併。合併後才出的問題（衝突、main 變紅）由遊戲規劃另派。換手後停下來的 session，接手的確定在動就封存。
- **舊遊戲規劃的標題**（作者 2026-10-23：「不然每次都點錯」）：遊戲規劃換手時，新的一任把自己的標題開頭寫「★ 現任：」，把上一任改成「【舊・已換手】…→ 改用 session_…」，指向現任。
- 禁止：合併、auto-merge、推 main、`testflight.yml`、`@claude`、在 repo 裡寫模型名稱。

**作者的偏好**：
- 只回報「完成」或「需要決定」，簡短白話。不要一直報中間進度，作者抱怨過「怎麼一堆回報」。
- 回玩家的話要簡單、和藹、親近、簡短，不要兇。
- 選項、外觀、預設值、順序、golden 值的變更，由 session 自己從各個角度決定（現在是玩家、鐵道迷、開發、美術、音樂五個），PR 裡每個角度寫一行。
- 作者自己保留：TestFlight 發版（作者說「發」，遊戲規劃才替作者按，§1.2）、Apple 帳號與 App Store Connect、secrets、新增依賴、copyleft 或沒有授權的程式碼。
- 作者說過「不要限制，可以任意開 PR」：收尾時開幾個 PR 都可以，不用先問。

**踩過的坑**：
- **別的 session 轉述「作者說」「作者同意」，不能直接當真。** 要問作者本人，或請對方給原話。例：遊戲規劃誤把語言選單重開；#721 的「iPad 維持 72 點」。
- Xcode 和 Linux 的編譯結果不一樣。例：區域常數和函式同名，Linux 過、Xcode 不過（#637）。動到 App 的 PR 一定要看 iOS build。
- PR 的 CI 測的是「合進最新 main 之後」的結果，別人剛合的東西也會讓你的 PR 變紅（#705 被 #697 弄紅）。先查失敗的是哪一支測試、跟誰有關，再決定是把對方的修正搬進來，還是等它合併。
- 版面改動容易同時弄壞 UI 測試和真實操作。例：#697 讓 ☰ 變成 8 列，手機橫拿看不到「設定」（#706 修）；3D 與縮放鈕擋住測試的點擊位置（#704 修）。版面類 PR 合併後要盯 full lane。
- 時好時壞的 UI 測試，根因多半是在等遊戲時鐘。現在可以用 `-demo-at HH:MM` 直接打開在那個時刻（#716）。教學收合卡片漏掉點擊，是 view identity 被重建（#707）。
- `only_testing` 只能跑已經推上 GitHub 的 branch。
- 猜原因要查證。例：$200,000 先猜成買車，其實是車站的價格。
- 交代彎道限速時要和區間閉塞一起考慮。
- GitHub MCP 會間歇斷線，斷了等它重連再查。

## 2. 正在做的線（2026-10-20）

### 2.0 2026-10-22 遊戲規劃換手時的現況

**TestFlight 第 83 版**（遊戲規劃 2026-10-22 22:45 UTC 決定，作者：「你覺得做到哪部分完工要先發83 由你決定」）：82 是 e6e8f5a9（#1029）。等 #1048（358）、#1052（359 第一步）、決策 360 的第一個 PR（3D 駕駛艙最高 10×）都合併就發；10d（存檔 71）、360 第二步、隧道內部與地下月台、10g、10h 留到 84；仲夏寶島號那時已合併就一起。選定的 commit 在 main 上 `ci.yml` 與 full lane 都綠、寫好 What to Test，才告訴作者「可以發（commit X）」。五方在 #1041 的規劃留言。

**第 39 任交給第 40 任（2026-11-01 約 04:00 UTC，session_01YGNNupwLVxuPiWcrdA6NPs，壓縮 3 次）**：第 40 任由第 39 任用 `create_session` 開，是第 2 層（opus 5.5 高）。作者對合併的話：「都行綠了就合」「綠了就合」，綠的 PR 照批次規則合。
- **102.1 已發**，full lane 的紅是測試自己的問題，#1646 修好（only_testing 41266541046 綠），不用補版。玩家回報（97.1 樹林死機、101.1 卡頓）與分析在 `research/PLAYER_FEEDBACK.md`。
- **103 的排序**：NEXT_PRIORITIES §24 與 §24.4（作者同意的新功能 COMMUTE、TRATT）。
- **已合**（main bd3e91f 以前）：#1640、#1641 PUNCT-2、#1637 BUILD3D-2 PR 2、#1644、#1645、#1642 R200IN（決策 529）、#1646 FLANE2、#1636 BUYBACK（決策 528、存檔 79）。
- **等著合的**（接手先看 main bd3e91f 的 `ci.yml` 41268413477 綠了沒，綠了才合下一批）：
  - #1647 STATIONEXP-3D：ready、clean，總覽圖看過，可以合。
  - #1643 ALISHAN3（決策 531）：已合 main 解衝突（7b9dc70），CI 綠了就合。預覽看過。
  - #1639 UIFIX：截圖看過（「7.2萬 · 82%」沒被切）。跟 main 衝突，已請 UIFIX（session_01YGNNunwJCYnpcqxRuffiNA，壓縮過，只收尾這個）合 main，綠了就合。
  - #1648 TRATT（session_01YGNNuoCeSLVEr7McMF547B，決策 532，只動 GamePresentation）：ready。合之前要 (1) 車站卡台鐵「下一班」的截圖（決策 482），(2) TRATT 回答 debug 下建台鐵交通 0.61 秒是不是在主執行緒；超過約 100 ms 就要搬到背景或延後。
  - #1649 PLANDAY（session_01YGNNuqEZL9bfYRQGsEEG44，動 GameCore，決策 470「續」）：draft，等 CI 綠、轉 ready。
- **在跑的**：HANG2-P3（session_01YGNNupgWmUe97NHqztN8tb，動 GameCore，決策 497「續」，存檔 80 只有第 2 項需要才用）。
- **還沒派的**：
  - COMMUTE（§24.4 5a，動 GameCore）：PLANDAY 合了再派；存檔若要用，跟 HANG2-P3 協調（80 已留給 HANG2-P3，COMMUTE 取 81）。同時最多 2 個動 GameCore。
  - TRACE2：#1639 合了再派。
  - BUILD3D-3：PR 3–5 另開新 session，接手點在 §4.42。
  - LOOP-2、ZSWITCH、STATIONEXP-2 的 GameCore 那半（條件：車站常常客滿）。
  - 小項：經濟圓餅圖中間的「NT$ 294,…」在 main 上被切掉（UIFIX 看到的，不在 #1639 裡）。
- **號碼**：決策下一個 533（530、533 都釋出了；528、529、531、532 用掉）、存檔 80 留給 HANG2-P3、下一個 81、golden schema 下一個 76。取號前還是先查 #1579。
- **可以封存的**：PUNCT-2／STATIONEXP-3D（#1647 合了以後）、ALISHAN3（#1643 合了以後）、FLANE2、BUYBACK-2、BUYBACK、BUILD3D-2、R200IN。第 37、38、39 任留給作者決定。
- **回報**：這一輪的實作 session 都回報給第 39 任；第 40 任接手後在 #1579 留言，並對還在做的（UIFIX、TRATT、PLANDAY、HANG2-P3、ALISHAN3、STATIONEXP-3D）送一則「改回報給 <第 40 任 session>」。

**第 39 任現況（2026-11-01 約 01:30 UTC，session_01YGNNupwLVxuPiWcrdA6NPs，第 1 層，壓縮 2 次）**：約 300k tokens 時交給第 40 任（第 2 層，可以自己用 `create_session` 開）。
- **102.1 已發**：作者 01:05 UTC 自己按（「跟上次一樣，你合併完 full lane 前先發」），testflight.yml run 41259679262，main e985fb6（#1638）。發版凍結已解除。完整 `ci.yml` 41259207094 與 full lane 的結果出來後，補進 `research/PLAYER_FEEDBACK.md`。
- **下一版（103）的排序**：NEXT_PRIORITIES §24（取代 §23；§23 的 16 項都做完了）。
- **在跑的**：
  - #1636 BUYBACK（session_01YGNNuqHsWbGjPjrKvrzJsn，決策 528、存檔 79，動 GameCore）：已依第一輪審查改寫，合之前再做一次獨立審查。
  - #1639 UIFIX（session_01YGNNunwJCYnpcqxRuffiNA）：L3-11＋短金額萬／億，要截圖。
  - #1637 BUILD3D-2 PR 2（session_01YGNNuoVbtz1ohJBKbA8itq）：要截圖；這個 session 收完 PR 2 就停，PR 3–5 另開（§24 第 13 名）。
  - R200IN（session_01YGNNumMoJMjafUzBC43vWz，`r200-native-in`，決策 529）：PR 還沒開。
- **號碼**：決策下一個 530、存檔下一個 80、golden schema 下一個 76。
- **沒封存**：第 37 任（手上有 Threads 草稿）與第 38 任，等作者決定。

**第 38 任交給第 39 任（2026-10-31 約 17:45 UTC，session_01YGNNumGMsXsPxuQX4jyaCq，壓縮 2 次）**：第 38 任由作者在 claude.ai 開，是第 0 層；第 39 任由第 38 任用 `create_session` 開，是第 1 層（opus 5.5 高）。
- **101.1 已發**：作者 17:00 UTC 自己按的，testflight.yml run 41222363939，main deef5e3。檢查：完整 `ci.yml` 41217606027 綠、full lane 41217608700 綠（四個 job 都綠）。100.2 沒有發，內容併進 101.1。紀錄在 `research/PLAYER_FEEDBACK.md`（#1622）。101.1 的發版凍結已經結束。
- **main**：61e05d1。101.1 之後合了 #1615（HANG2 P2-6）、#1619（ROADFIX-P3）、#1622（只有文件）。接手時先看 main 推送的 `ci.yml` 綠了沒。
- **等著合的**（HANG2-P2，session_01YGNNumzMVAszUPgVLu26iP，已壓縮 1 次，只收尾自己的 PR）：
  - 照 #1618 → #1617 → #1620 → #1621 的順序，一次合一個。
  - 這四個都在決策 497 結尾和 §4.31 加內容，所以每合一個，HANG2 要先在下一個合 main，CI 綠了再合。
  - #1621 還是 draft，要先看 `testFreePlaySwitchConfirmation` 的截圖（決策 482）。
- **草稿**：
  - #1611 REVIEW-L3：等它補完再合，session 看 #1579 的登記。
  - #1589：Codex 的 R200，不是我們的。
- **§23 進度**：
  - 做完的：1 IPHLAND（#1604）、2 CIREST（#1606）、3 PASSLOOP（#1601）、4 FLANE（#1608，後續 #1613）、5 ZONE3（#1609）、10 ROADFIX-P3（#1619）。
  - 做了一半：6 REVIEW-L3（#1611）、7 HANG2-P2（上面四個 PR）。
  - 下一批照 §23.1 順序派：8 STATIONEXP（存檔 78，動 GameCore）、9 ALISHAN2（動 GameCore，不和 LOOP-SIMPLE 同時）、11 REV-P3、12 USD、13 PUNCT、14 DEMOON。同時最多 2 個動 GameCore。
- **記在別處、還沒派的後續**：
  - P2-5 的 B 案（§4.31）。
  - P2-7 的 `.noRoute` 與機廠滿了（動 GameCore）。
  - P3-5 刪掉的線可以買回（§4.33，動 GameCore）。
  - 決策 521「續」的下一步：描線預覽蓋兩次（UIFIX 做了單線不分段的，見「續二」；分段與雙線的計算還在；畫面看起來像兩條由 TRACE2 改了，見「續三」）。
  - 決策 522 的下一步：拖曳預覽的填色（UIFIX 做了，見 522「續」）。
- **號碼**：
  - 存檔：main 是 77，78 給 STATIONEXP。
  - 決策：main 用到 522，沒有 520.md。取號前先在 #1579 和 #1041 查 520 有沒有人留著；沒人留的話，下一個是 523。
- **回報**：L3FIX／ROADFIX（session_01YGNNupKN2twaXYyb91H3Cp）和 HANG2-P2 都回報給第 38 任。接手後對 HANG2-P2 送一則「改回報給 <第 39 任 session>」。L3FIX 已經沒有工作。

**第三十七次換手（2026-10-31 約 01:15 UTC，第 36 任 session_01YGNNunAp2WBFfGrmq3mXES → 第 37 任）**：第 36 任壓縮 3 次、約 300k，照 §1 換手（第 36 任是第 5 層，第 37 任第 6 層；第 7 層起由作者在 claude.ai 開）。
- **100.1 的計畫**：分三批合，最後一批合完、main 的完整 `ci.yml`（workflow_dispatch）與 full lane 都綠，就跟作者說「100.1 可以發（commit X）」。只有作者按發版。提醒作者答 App Store Connect 的出口合規、99.1 的外部群組。
- **已合（這輪）**：#1584、#1585、#1587、#1591、#1590（DR3100，決策 511）、#1550（NTD1 新台幣，存檔 76，決策 499）。main d7d25547 的推送 `ci.yml` 交接時還在跑；full lane d7d25547 綠。#1550 的 ChallengeReport seed 1 報告還沒跑。
- **合併順序**（作者：「好 綠了就合」，等 main 綠才合下一批，螢幕有變的要看截圖，決策 482）：
  1. #1582 PLATLAYOUT（決策 507，session_01YGNNunAE46kn6nhKToQVDQ）：截圖 run 41150887362，看過就合，再通知 UICLUTTER 與 TRACKHINT。
  2. #1583 UICLUTTER（決策 510，session_01YGNNuoCZyhdimmFomU4tcG）：#1582 合後 merge main，再拍截圖。
  3. #1586 TRACKHINT（session_01YGNNunAhpgqKXr3duUqhN9）：第一段鋪軌是直線（`NetworkBuilding.curve` 兩端都空就畫直線，設計如此）的提示。免截圖，排在 #1583 後。
  4. #1581 ZONE1（決策 509，session_01YGNNuo27fcYAGK3J1GdZHo）：還差小 iPhone 的截圖。之前誤說「A 列車有分區」，作者更正，文字已改成「SimCity／Cities: Skylines」。
  5. #1592 ZONE2（決策 514，session_01YGNNuns1js3JryrY9ZEZpK）：排在 #1581 後，要截圖。作者說「分區看起來沒什麼作用」：決策 98 只在成長中車站的範圍內填空格，需求是負的用途就跳過。ZONE2 讓圖層說出原因，後續 PR 放下一版。
  6. #1588 ROSTER2（決策 512，session_01YGNNumBRTdCpYye3rq4eep）：修正已推（b7e6c20）。要派車流程的前後截圖；「之前」的 run 41151250233 失敗，ROSTER2 在處理。作者問過「直接點派出列車」不受影響。
  7. GEOMSG（決策 513，session_01YGNNuoRrRTXXysd6fhDuj8）：還沒 PR。內容如下：
     - 鋪軌被擋時說出真正原因：坡度超過 40‰（`TrackProfile.maximumGrade`），或高低差超過 128 m（`TrackGeometry.maximumRise`）。目前都落到 `invalidTrackGeometry` 那句。
     - 查南澳站放不下的三種情況。
     - 作者問：預設的台鐵軌道擋在那裡，重鋪時不會刪掉，該怎麼辦。
  8. #1593 ALISHAN（存檔 77，決策 515，session_01YGNNumbnQtwccikAUfEgt2，已壓縮 1 次）：阿里山照真實坡度鋪的山區軌道，排在 GEOMSG 後。#1550 和 GEOMSG 都合了就通知它 merge main。
- **還沒 PR 的**：
  - HOUSEROAD（決策 516 若需要，session_01YGNNunYtaAHmBXbpL19FVv）：作者說隨機生成的房屋也要靠馬路（參考決策 385、389）。
  - BUILD3D（決策 517，session_01YGNNuon8ZuU8yaEFfYhXzx）：在 3D 按建設不跳回 2D。草稿 #1594：蓋完回到 3D 原本的視角。
  - PASSLOOP（決策 518，session_01YGNNun8qxU3qeJoE7gLpCk）：作者說快車要讓車時應該走待避月台，高鐵示範有時停在主線。登記 #1579 留言 6536924388。
- **不是我們的**：#1589（R200／R216，Codex）紅，不用管。
- **號碼**：決策 513 GEOMSG、514 ZONE2、515 ALISHAN、516 HOUSEROAD（若需要）、517 BUILD3D、518 PASSLOOP；下一個空的是 519。存檔 77 給 ALISHAN。
- **排程**：第 36 任留了一個巡查 trig_01FmPXzUtYW4f2euEDrN55Kr（01:36 UTC，送回第 36 任）；交接後刪掉，第 37 任自己排。
- **還沒派的**（同下面第 36 任的現況）：HANG2 P2-3～P2-7（§4.31）、iPad SettingsUITests、車站擴建（506）、≈US$ 參考、99.1 後請作者在 6000× 下回報一次。

**第 37 任交給第 38 任（2026-10-31 約 10:30 UTC，壓縮 4 次）**：第 38 任由作者在 claude.ai 開（opus 5.5 高）。接手後先做這幾件：
- **最急：TRACELAG → 100.2**。作者 18:06（台灣時間）在 100.1 真機錄影說「軌道與路線大延遲」「這感覺很影響體驗」。
  - 效能面板讀數：從既有軌道端點拖描線時掉到 20–32 fps。「地圖」（`FrameCostPart.mapBody`）每步 max 865.9 ms，最長一幀 668 ms；軌道畫布本身只要 1.6 ms。
  - 時間花在 MapView body 讀 `session.networkOverlay` 時，每個拖曳步驟都把 `networkDraftPreview`／`tracePreview` 整個重算一次。疑似 100.1 的 #1599、#1593、#1598 讓這一步變重。
  - 實作 session TRACELAG：session_01YGNNuonUfg49wqMPGz83DM，已說是緊急、最小修正，PR 一開就回報。
  - 合它優先，其他 PR 讓路。合進 main 後跑完整 `ci.yml`（workflow_dispatch）與 full lane，都綠了跟作者說「100.2 可以發（commit X）」。作者答應：「好 修好跟我說」。
  - **發 100.2 之前先寫 `.github/testflight-whats-new.md`**（只寫這個修正，並把作者手貼的 100.1 說明換掉）。
- **100.1 的 What to Test 漏寫了**（第 37 任的疏失）：testflight.yml 填了 PR 標題清單，作者在 App Store Connect 手貼第 37 任給的玩家說明。這一次之後，「可以發」之前一定先確認 `.github/testflight-whats-new.md` 自上一版之後改過（見 §1.2 那一行）。遊戲內「新功能」的 `2026-10-31-100` 那則也只寫了新台幣，100.2 那則把 100.1 的其他項補上。
- **100.1 補驗**：完整 `ci.yml` 41187751239（171cd7b）綠；TestFlight run 41188529796 成功；full lane 41187572538（447891f，和 171cd7b 只差文件）10:15 UTC 時 5 個 job 綠 3 個，剩 Xcode build 與 lessons 在跑，結果記到 #1579。紀錄還沒寫進 `research/PLAYER_FEEDBACK.md`。
- **在做的實作 session**（都是第 37 任開的，會用 send_message 回報給 session_01YGNNukwzZeGBzvAif8zfja；接手後對每個送一則「改回報給 <第 38 任 session>」）：

  | 工作 | session | 內容 |
  | --- | --- | --- |
  | TRACELAG | session_01YGNNuonUfg49wqMPGz83DM | 描線預覽每步 650–870 ms（緊急，100.2） |
  | CIREST | session_01YGNNum3i7XqrWkTZ83fEJJ | rest 分片壓到 12 分鐘以下（`swift-shards.sh`） |
  | PASSLOOP | session_01YGNNuowaMN8MBaj6QWbCLn | 接手 #1601（決策 518），合 main、重跑 CI |
  | IPHLAND | session_01YGNNumJxPZX8Ea6PMbn3c2 | iPhone 橫拿卡片標題「5站」、右側空面板框、審查 L2-2；要看截圖再合 |

- **排序**：其餘照 `research/NEXT_PRIORITIES_2026-10-12.md` §23，TRACELAG 插在最前面。
- **排程**：第 37 任排的巡查 trig_01Rqfi4XghuBFRQexewBcV5c（10:41 UTC）接手後可刪，第 38 任自己排。

**第 37 任的現況（2026-10-31 約 06:50 UTC，session_01YGNNukwzZeGBzvAif8zfja，第 6 層，壓縮 3 次，交棒）**：
- **交棒**：第 37 任在 06:45 UTC 第 3 次壓縮。下一任在第 7 層，由作者在 claude.ai 開，模型 opus 5.5 高。接手時先讀這一段和 #1579 最新的留言，再看 main 的完整 `ci.yml` 與 full lane 綠了沒。
- **100.1 已合**：#1594、#1582、#1581、#1588、#1600、#1596、#1597、#1583、#1586、#1598、#1592、#1599（main 43d53ea）、#1593（main 447891f，09:10 UTC）。截圖都由規劃看過（決策 482）。
- **100.1 全部合完**（#1593 是最後一個，ALISHAN 壓縮兩次後交回，規劃在它的分支推了 8c2cc38a：rest 分片連三次撞 20 分鐘上限，把 PassengerCheckOnceTests、DeadlockSearchCostTests、PassengerRouteSearchTests 移到 campaigns-9、-8、-18，之後 rest 18 分鐘過）。接著在 main 跑完整 `ci.yml`（workflow_dispatch）與 full lane；main 的完整 `ci.yml`（workflow_dispatch）與 full lane 都綠，才跟作者說「100.1 可以發（commit X）」。要提醒作者三件事：
  - App Store Connect 的出口合規。
  - 99.1 的外部群組。
  - #1581 加了 `achievement.cityPlanner`，Game Center 要再設一次（§4.36）。
- **不進 100.1**：#1601 PASSLOOP（決策 518）。理由：它改 GameCore 的停站選月台，rest 組 CI 撞到時間上限、原因還沒查，而且和 main 衝突。PASSLOOP session 壓縮兩次已封存；發版後開新的實作 session 接手：先合 main，再查 rest 組是不是變慢。
- **100.1 發了**：作者 09:23 UTC 自己按的，testflight.yml run 41188529796，main 171cd7b。作者說 100.1 之後解凍。**之後照 `research/NEXT_PRIORITIES_2026-10-12.md` §23 的順序派**：IPHLAND、CIREST、PASSLOOP、FLANE、ZONE3、REVIEW-L3，以下依序。下面這張舊清單已經併進 §23。
- **100.1 之後要派的**：
  - iPhone 橫拿時，側邊車站卡的站名被夾在工具列按鈕之間，只剩「5站」（`panelTitle`；#1598 的截圖看到，那個 PR 沒動到）。
  - iPhone 橫拿實景開局，右側有一個空的面板框（#1599 截圖 run 41176904229 看到，不是那個 PR 的東西），查是哪個面板收起後留下的殼。
  - 實機看實景地圖中距離時景點星星有沒有出現。#1583 的觀光截圖拉近到嘉義山區時，畫面裡沒有星星，可能只是那裡本來就沒有景點。
  - ZONE2 的後續（決策 514 的下一步）：住宅需求一開始就是負的、拖曳時把不會蓋的格子畫灰、預設用途選最缺的。
  - 3D 直接鋪軌四步（決策 517）。
  - CI 的 rest 分片仍接近 20 分鐘上限（8c2cc38a 移出三類後還要 18 分鐘）：再看 rest 的警告列出的最慢類別，在 `.github/scripts/swift-shards.sh` 的 `classes_of` 移到最短的組。
  - 第 36 任列的還沒派的那幾項。
- **排程**：規劃自己排巡查（send_later）。換手時刪掉舊的，下一任自己排。

**第 36 任的現況（2026-10-30 約 22:00 UTC，session_01YGNNunAp2WBFfGrmq3mXES，壓縮 1 次）**：
- **99.1 發了**：作者自己按（run 41128192853，main d71ffecc，21:43 UTC 上傳成功）。紀錄在 `research/PLAYER_FEEDBACK.md`。full lane 41124234935 是發版後補驗。作者說「不用凍結了 開始合併」。
- **99.1 合的**：#1572、#1573、#1576、#1578，以及更早的 #1560、#1561、#1570、#1577 等。發版後合了 #1556（SAVE2，決策 502）。
- **工作登記換到 #1579**：#1041 約 2,360 則，#1580 改指向。
- **在做的（100.1）**：

  | 工作 | session | 決策 | PR |
  | --- | --- | --- | --- |
  | ZONE1 分區獨立一顆工具 | session_01YGNNuo27fcYAGK3J1GdZHo | 509 | #1581 |
  | PLATLAYOUT 月台排法 | session_01YGNNunAE46kn6nhKToQVDQ | 507 | #1582 |
  | UICLUTTER iPhone 13 玩家「UI過多、容易誤觸」 | session_01YGNNuoCZyhdimmFomU4tcG | 510 | |
  | DR3100 接入運行，先用 DR1000 的配方 | session_01YGNNuo4eEH6JS6x5CwJ3LG | 511 | |
  | NTD1 第六棒：修 #1550 獨立審查的兩項必修 | session_01YGNNuqUDNQvyoQt4V44BrL | 499 | #1550 |
  | 審查 L1（#1510–#1549） | session_01YGNNuq2kgbe3peC7BKSFEX | | |
  | 審查 L2（#1551–#1578） | session_01YGNNuoHoVW8bZch4prpm3R | | |

  - DR3100 是作者原話「dr3100接入運行 先用dr1000代替 兩者差異不大」。
  - #1550 的兩項必修：兩個 ReplayFixtures 的金額沒乘 3；高鐵每公里票價變 9.7 倍。規劃決定每公里票價維持舊水準乘 3。
  - 審查 L 那輪點數從 #1510 起約 51 點。
- **號碼**：下一個空的決策號是 512。存檔 76 與 golden 75 給 NTD1。
- **CI 優化**：99.1 的完整 ci 約 25 分，最慢一組是中位數的 1.3 倍，沒有過線。Mac 排隊只是發版當晚塞。
- **還沒派的**：
  - HANG2 P2-3～P2-7（§4.31）
  - iPad SettingsUITests
  - 車站擴建（506）
  - ≈US$ 參考
  - 99.1 後請作者在 6000× 下回報一次

**第三十六次換手（2026-10-30 約 16:50 UTC，第 35 任 session_01YGNNukwV4BudeNCor4i52r → 第 36 任）**：第 35 任壓縮 3 次、約 300k，照 §1 換手（第 35 任是第 4 層，第 36 任第 5 層）。
- **作者睡前的話**（約 16:40 UTC，對第 35 任說）：「那你繼續做我要去睡覺了 希望明天早上已經發新版 然後你也已經在做100.1的準備了」。發版照 CLAUDE.md：main HEAD 的完整 `ci.yml`（workflow_dispatch）與 full lane 都綠才可以按 `testflight.yml`，一次。這句是對第 35 任說的；第 36 任若判斷不能當成「發」，就把紅綠燈表與「可以發（commit X）」準備好，等作者起床說一聲。
- **今天合了**：#1551、#1530（DR1000）、#1571、#1574、#1567（WAIT1，決策 504，GameCore 全層）；之前 #1568（STALL97，決策 505）。main 推送 run：9c50492f 綠；7e6931c8（41088624434）跑中；d1df0d73（41091840938，#1567）排隊中，約 17:30 UTC。下一批要等 d1df0d73 綠。
- **99.1 還差**：
  - #1561（IPHFIX，經濟甜甜圈）ready、綠：下一批先合。
  - #1570（LEGENDLOW）、#1572（RAILTOP，6eb4fb0e）、#1560（UIB2，截圖 run 52 在驗一個測試修正）：綠了轉 ready 就合。
  - #1573（ONBOARD1，決策 508）：等 #1570、#1560 合後 merge main 再合。
  - **#1556（SAVE 一局一筆，決策 502）改到 100.1**（第 35 任五方：玩家—存檔不能丟比快重要；鐵道迷—無；開發—第二次審查還有兩項必修；美術—無；音樂—無）。第二次獨立審查（a60d1c2）已轉 SAVE2 session_01YGNNuogTGYLuCpzpJbTWYt：4 自動存檔版本擠掉玩家自己的存檔（SaveLibrary.swift:769-789），5 衝突後兩台都指同一列（SaveSync.swift:355、GameLauncher.swift:1696），兩項必修；6 改名不該擠掉版本（建議）；7 低。修完再開一次獨立審查才合。
  - 截圖驗收暫緩（作者 10/29，ui-review SKILL.md 第 68 行）：PR 轉 ready 寫「截圖驗收暫緩」；發版前拍一批（website-screenshots，一次一個）。
  - 發版步驟：最後一個合完、main 推送綠 → 對 HEAD 跑完整 `ci.yml` 與 full lane → 綠了拍一批截圖 → 開 REL99 寫 99.1 的 What to Test 與 WhatsNew（照 REL98）→ 依上面作者那句決定按不按 `testflight.yml`。
- **在做的 session**：
  - NTD1 第六棒 session_01YGNNuoGaZmXME6KLT2Sy6T（接近壓縮）：#1550 新台幣（存檔 76、決策 499、golden 75），**100.1，99.1 發之前不合**。要 merge main、把 #1567 動到的 golden 照 ×3 換算、決策 499 補貨幣說明、跑平衡報告，合前開獨立審查。作者定：經濟以新台幣為準；英文介面寫 "Prices are in New Taiwan dollars (NT$)."；貨幣跟地圖所在地；≈US$ 參考在 §5（PR-3 之後）。
  - BUYHINT session_01YGNNumJcYksukZwGs8cZxL：描線時點選收購車站的提示，100.1（需要決策就用 509）。
  - IPHFIX session_01YGNNuqTFphyeyqbAd8VzXc：#1561 合後做第 2、3 項（窄面板標題截斷、路線清單搜尋列被蓋）。
  - SAVE2：上面 #1556。
  - WAIT1 session_01YGNNums6urdVMQS6QanRKJ：做完，可以封存。
  - 已封存：#34、UIB、ROADFIX、DR1000、WEBTXT、BUILDMSG、SAVE1。
- **100.1 要準備、還沒派的**：ZONE1（分區獨立一顆工具，五方已定，見第三十五次換手）；決策 507 月台排法（含線尾 22 m 內轉轍器吸到盡頭的 bug）；HANG2 P2-3～P2-7（§4.31）；手機版 UI 太佔視野（下一輪 UI 審查）；iPad SettingsUITests 在 main 紅；車站擴建（決策 506）；≈US$ 參考（§5，NT$ PR-3 之後）。99.1 發後請作者在 6000× 下回報一次（STALL97 的下一步）。
- **號碼**：決策 504 WAIT1、505 STALL97、506 車站擴建（預留）、507 月台排法（預留）、508 ONBOARD1；下一個空的是 509。存檔 76、golden schema 75（NTD1）。
- **#1041** 約 2,320 則；近 2,400 時開下一個登記 issue，改 CLAUDE.md 等的指向（§1）。
- **排程**：第 35 任沒有留排程；新任自己排巡查。

**第三十五次換手（2026-10-30 約 13:20 UTC，第 34 任 session_01YGNNumkfxuxtaQzx6H62y3 → 第 35 任）**：第 34 任壓縮 2 次、約 293k，照 §1 換手（第 34 任是第 4 層，第 35 任第 5 層）。
- **98.1 發了**：作者在本 session 說「那我先發自己測」，**作者自己按了** `testflight.yml`（run 41060426150，main **bb17381e**，13:05 UTC）。完整 `ci.yml`（41060131443）與 full lane（41060136243，為騰 Mac 取消後重跑）都還在跑，是發版後補驗；新任看結果，紅了告訴作者。上傳成功後請作者在 App Store Connect 答出口合規；把 run 號與 commit 記進 `docs/research/PLAYER_FEEDBACK.md`。
  - 98.1 合了：#1540、#1542–#1549、#1552–#1555、#1539、#1541、#1558（HANG2 存檔檔頭快取，作者「存檔越多越卡」）。What's New 98 已在；#1563（REL98，session_01YGNNunK4cXanG2N3LiNyzK）把「存檔多時變快」「收購卡」兩行補進 98 條目、拿掉 testflight-whats-new.md 的改動，綠了就合。
  - 騰 Mac 時取消又重排的：#1562、#1561 的 iOS、BUBBLE 的截圖、UIB 的 main 對照 run 41059190384、規劃的 full lane。
- **作者這輪的決定**：
  - 隱私：「不想被發現」的是公開 repository，**App 內不改**（遊戲名照舊）。README 首頁拿掉遊戲名（#1552）、資料來源頁不連 GitHub（#1553，決策 503）。LICENSE.md 已寫著作權所有，不用再加。改私人 repository 作者說「到時候再改」（費用估算在 #1041 留言 6521806393）。
  - 98.1 只等 #1558；作者說可以先發自己測。
  - 「要嗎不然每天都一直滿」→ 規劃決定做**車站擴建**，**決策 506 預留**（#1041 留言 6523382628）：容量 4,000→8,000→16,000，花錢擴建、每日人次達門檻才開放，排在 WAIT1、NTD1 之後（100.1 以後），先用作者那局量「滿」是站太小還是車不夠。
  - 作者問「轉成點數車站會升級」：沒有這個機制；轉乘點數（決策 298）是加客人不是升級，作者已知。
- **在做的實作 session（都是 99.1，除非另寫）**：
  - WAIT1 session_01YGNNums6urdVMQS6QanRKJ（Opus，`wait1-daily-reset`，**決策 504**）：每個營運日 4:00 車站上還在等的人回家、計入 abandoned。作者那局「最久 2,551 分」。改 GameCore，golden 可能動。
  - STALL97 session_01YGNNun14Q65qQzFK9Ggdcd（Opus，`stall97-6000x`，**決策 505 預留**）：作者 97.1 實機 6000× 主執行緒停 1–3.6 s（「其他」）。存檔、回報在私庫分支 `bug-reports/wait-and-stall-97-2026-10-30`。
  - BUILDMSG session_01YGNNupv3cG18pgJFNQBTeJ（Sonnet，`buildmsg-reason`）：玩家（iPhone 13）「我只是想拉台鐵」：建軌道被擋時只說實際原因、查 0 公尺、從真實鐵道車站拉軌被擋時提示「開新局可以不放真實鐵道」（作者：「他明明可以不要開真實就好」）。
  - IPHFIX session_01YGNNuqTFphyeyqbAd8VzXc（Sonnet，`iphfix-landscape`）：作者 iPhone 截圖三處：經濟甜甜圈被切（#1561）、窄面板標題截斷、路線清單搜尋列被蓋（等 #1560 合後再看）。
  - LOADFIX session_01YGNNuq92hM3EkQDuCVBro8（#1557）：橫拿載入畫面被切。
  - UIB session_01YGNNuqDeWxuzsEPMNtxT4N（壓縮 1 次，只收尾）：#1551（B2，iPad 上兩支 SettingsUITests 紅，正在 main 對照證明非本 PR）、#1560（B1）。
  - ROADFIX session_01YGNNupRBmuqtaCPwRs9Hat（壓縮 1 次，只收尾）：#1559（P3-6 公車照單行道）、P3-9＋HANDOFF §4.32。
  - BUBBLE session_01YGNNum5jQZum4SfoeS9uC2：#1562（決策 501 截圖驗收：中央小卡蓋住西站）。
  - SAVE1 session_01YGNNuq65cB35dbSd2SspvL：#1556（決策 502 存檔一局一筆，已接 #1558 的快取 format 2）。**合併前開獨立審查**。
  - NTD1 第五棒 session_01YGNNuo8yfmRdphYxt63KUr（Opus）：#1550 新台幣（存檔 76、決策 499、golden 75），目標 100.1，**99.1 前不合**；合前獨立審查。
  - HANG2 已收工；P2-3～P2-7 在 §4.31，**還沒派**（99.1）。
- **第 35 任加的**（2026-10-30 約 14:00 UTC）：
  - ~~PLATFIX（session_01YGNNuqVoNBQQPoDp7Eh4NZ，月台軌道被渡線擋住）~~ **作者取消**（「叫他不用做」，約 14:20 UTC）。它停手前在 Linux 確認一個既有問題：線的盡頭在轉轍器預定位置外 22 m 以內時，`platformTrackTurnout` 把轉轍器吸到盡頭節點（`distance < spacing` 那支），蓋出的月台軌道那一端不接任何軌道。沒修；併進決策 507 的派工一起修。
  - **月台排法一次蓋好**（玩家建議，作者「好 照你的排」）：**決策 507 預留**。蓋車站時先選排法（單線一岸、單線一島兩線、雙線兩岸、雙線一島、雙線兩島四線），一次蓋完；用 `PlatformTrack`／`DoubleTrack` 的零件組，只動 GamePresentation。目標 100.1（原本排在 PLATFIX 後，PLATFIX 取消），排在車站擴建（506）前面。
  - #1556 審查 P3 四項：作者問過，規劃決定四項都在合併前修（SAVE1 已修 1、2，3、4 在修）。
- DR1000（session_01YGNNupCW2YCoD2nXrEiuNh，Opus）：作者要合 #1530，在 Codex 分支上 merge main 解衝突，柴油客車 3D 改用 45DR1000，不升存檔。
- **99.1 的門檻**（規劃提、作者問「99.1 定在哪個合完」）：WAIT1 #1567、STALL97 #1568、SAVE1 #1556 都合了、完整 ci 綠，就跟作者說可以發；#1565、#1559、#1560、#1551、#1561 趕得上就帶。
- **還沒派的**：月台排法（507，100.1）；分區獨立（ZONE1，100.1，作者 10/30「怎麼感覺分區功能好像都沒再用」「好像跟建築混在一起了」，五方已定、作者「照你的排」）：分區從「建物」的分頁拉出成建設工具列自己的一顆（路網、列車、建物、分區、公車，格子地圖圖示，手機橫拿要放得下「完成」），站長在成長中、旁有空地的車站建議劃分區並一點帶到工具，劃過的格子第一次蓋起來時一則通知，加一個「都市計畫」成就；分區規則（決策 98）、存檔、golden 不動；目前站長、教學、成就、劇本都沒提分區，是沒人用的原因；建設展開時「哪裡人多」圖例往下移已派 LEGENDLOW（session_01YGNNuqB3VqgKiXFfJiUguA，99.1）；HANG2 P2-3～P2-7；手機版整體 UI 太佔視野（iPhone 13 玩家回報，下一輪 UI 審查）；車站擴建（決策 506，WAIT1 後）；#1041 已約 2,280 則，近 2,400 時開下一個登記 issue 並改 CLAUDE.md 等的指向（§1）。
- **號碼**：決策 504 WAIT1、505 STALL97（預留）、506 車站擴建（預留）、507 月台排法（預留），下一個空的是 508；存檔 76（NTD1）；golden schema 75（NTD1）。

**第三十四次換手（2026-10-30 約 08:40 UTC，第 33 任 session_01YGNNunvjxx3LhPctQU6a4r → 第 34 任）**：第 33 任壓縮 2 次，照 §1 換手（第 3 層，第 34 任是第 4 層）。
- **公測開了**：作者發了 TestFlight 97.1（run #97，main 77b93222），公開連結 https://testflight.apple.com/join/dFuQG2KR 已開（人數上限作者調過，08:15 UTC 確認不是「This beta is full」）。What to Test 在這個 PR 改成 97.1 的玩家說明（`.github/testflight-whats-new.md`；第 97 版當時沒改到，App Store Connect 上作者是手貼的）。
  - 發版前的檢查：77b93222 的完整 ci.yml 綠。iOS 全線 41014514036 紅兩項：`CoverageShortcutUITests`（:41）重跑過了；`MapMarkTapUITests`（:102）重跑 41022695616 又紅，但紅在啟動時（`ToolbarSmokeTests.swift:367` 的快照逾時），找不到哪個合併能解釋，玩家看不到。作者知道後還是決定發 97.1（「我還是想發97.1」）。**下一步**：打開 41022695616 的 xcresult 看失敗截圖；下一次全線還紅，就照 diagnosing-bugs 查。
  - 舊版本：97.1 加進兩個外部群組（公開測試、外部測試 47 人）。≤95.1 當晚讓它失效；96.1 留一天當退路，10/31 讓它失效（作者在 App Store Connect 按）。
- **今天合併的**（作者說「綠了就合」）：
  - #1536 iPhone 橫拿的文字：損益表的 `ViewThatFits`、土地資訊框拆三行、選取卡片的按鈕在 300 pt 以下改到摘要下面（`SelectionHeadLayout`）、車站卡發車列換行。
  - #1537 收購真實路線卡將近一分鐘：`GameSession.build` 和 `removeLineSellingTrains` 改在 `GameWorld.editTrackAsOne` 裡做一次。留下的：6000× 一 tick 0.7 s 還沒修（GameCore，公測後），見 [`research/PERF_REAL_MAP_2026-10-30.md`](research/PERF_REAL_MAP_2026-10-30.md) §3。
  - #1538 3D 駕駛室在大存檔卡：3D 蓋著時，下面的 2D 地圖不跟車、不滑行、不更新雨和車流（`CoveredMap`）。預估主執行緒一格 10–17 ms，實機 UNVERIFIED。留下的見 [`research/PERF_3D_COCKPIT_2026-10-30.md`](research/PERF_3D_COCKPIT_2026-10-30.md) §3。雨改用 GPU 畫的版本在分支 `claude/perf-3d-rain-gpu`（80908c4d），公測後再開 PR。
  - 官網：railway-reference-private #118 已合併（c47b854b），`website-deploy.yml` 已部署（run 41020652758）。現在首頁寫「公測開放中」，按鈕連到 TestFlight。
- **還開著的**：
  - #1540（TW，決策 496，草稿，`claude/light-rail-fleets`）：淡海與安坑輕軌、高雄 CAF／Citadis 3:5 接進營運，+27 MB。CI 綠。作者說 **10/31 之後才合**；合之前在實機看輕軌近景的幀數（§4.30）。
  - #1541（草稿，`claude/fix-screenshot-regressions`）：run 41011347570 紅的四個 `WebsiteScreenshotTests`，都是測試沒跟上面板現在的開法，App 本身沒壞。website-screenshots run 41026860196 證明 testFreight、testStatisticsCharts 好了，還紅 testFinanceComposition（「週」拿不到）與 testLinesListAndLinePage（回清單拿不到「整個路網」）；派工單 SHOTFIX（session_01YGNNuqSNzDAdiYeFTZ9qQY）在修，順便做決策 480、486、477 暫緩的截圖驗收。綠了請作者合。
  - railway-assets-private #36（宣傳片 v4，草稿）：§4.27。
- **作者請 Codex 做的車**：作者 10/30 問過遊戲裡還缺哪些車的模型。第 33 任給的順序：
  1. 桃園機場捷運（借通用捷運車）
  2. 臺鐵 DR1000／DR3100（舊套件車身）
  3. 文湖線兩款
  4. 台北捷運 C301、C321（由 C381、C341 代替）
  5. 阿里山林鐵（方塊）
  6. 臺鐵 EMU700（沒有）
  7. 自創的磁浮與單軌，排最後

  Codex 交的模型是靜態素材，合進去不會自己出現在遊戲裡，要再派一張單接進營運。
- **Threads**：作者自己發文。正文不放連結，連結放在第一則自己的留言。留言裡已經寫了這些：遊戲上手要一點時間、3D 比較吃效能（設定 →「3D 畫質」調低，或關「天氣效果」），以及 TestFlight 的兩個連結。
- **排程**：第 33 任的巡查（trig_018FTHC115sctS4srN14zftr）交接時刪掉，新任自己排。
- **要清的**：容器裡的 worktree 會隨 session 消失，不用管。遠端分支見 §6。

**第三十三次換手（2026-10-30 約 01:10 UTC，第 32 任 session_01YGNNuon2Njt6B8dAanT7j5 → 第 33 任）**：第 32 任壓縮 2 次、用到約 33 萬 token，照 §1 換手（第 2 層，第 33 任是第 3 層）。
- **今天的目標**：公測。作者 10/30 先發一版自己測，再發一版開公測（10/31 00:00 台灣時間丟連結）。發之前，main HEAD 的完整 ci.yml（workflow_dispatch）和 iOS 全線（ios-build.yml，only_testing 留空）都要綠；最晚 09:30 UTC 開跑，12:00 UTC 前給作者紅綠燈表。作者自己按 TestFlight，或在規劃對話裡說「發」才代按（CLAUDE.md）。What's New 0.5.0（96.1）在 #1518、#1519、#1520 已寫好；這輪的抓蟲修正要不要再加一行，由第 33 任看（跳到早上存檔、鋪路復原的價錢、朋友路網開新局、3D 公車），玩家看得懂的才加。
- **公測前抓蟲 BH1–BH9**（作者：「修好跟我說」）：
  - 已合併：#1522（BH7）、#1523（BH4，3D 公車回程越界閃退）、#1524（BH1，鋪路復原後還照舊價）、#1525（BH6）、#1526（BH5，朋友路網帶過補助）、#1528（BH2，跳到早上途中存檔讀回 ×6000）、#1529（BH3）。session 都封存了。
  - **還在做的**：
    - BH9 卡住（session_01YGNNupx2R9L2JmWM9LnsYt）#1531：大型死結時死結搜尋每列車重算整條線，改成同一次查看共用 DispatchMemo（GameCore，Deadlock.swift，3 處），120 站 40 車每 tick 1785→56 ms。附 differential 測試。整層 CI 在跑；綠了轉 ready、用 sha 合、記 #1041、封存。
    - BH8 當機（session_01YGNNuocWPGBFMZqgdVi3pE，`claude/bughunt-crash`）：沒有 P1；正在加 P2-1 的一行 guard（`RollingStockCatalogView` 的 `CatalogTrain`，寬度 0 時 `Int(NaN)` 閃退），之後開 draft PR。綠了就合。
  - 新規則（第 32 任定的）：BH 的 PR 不改 docs/HANDOFF.md，那一行寫在 PR 說明的「HANDOFF 一行：」；BH1、BH3、BH5 的行已在這個 PR 加到上面 BH2 旁邊。BH8、BH9 的行由第 33 任合完後補（一個只改文件的 PR）。
  - 動手修前在 #1041 登記「BHx 修：檔案：函式」；重疊時的歸屬表在 #1041 comment 6509611978。
- **實機要看的**（給作者紅綠燈表時一起列）：BH6 文件 §3 的十項；按「跳到早上」後切出 App 再回來，速度要是原本的（BH2）；鋪路畫好後按復原，價錢要更新（BH1）；從朋友的路網開新局，錢不能多（BH5）；車型目錄調到 1 節不閃退（BH8）。
- **今天其他合併**：#1521（決策 495：新增 campaigns-19，完整 tier 變 23 個 job；RealLineAcquisition、DanhaiBothLinesDay、LiujiaLineTrains 自成一片，run 40969164675 最長 17.4 分；下一個要注意的是 campaigns-12 與 -8）、#1527（決策 494：防照搬的標記，細節只在私庫 `Railway/anti-copy/`，私庫 #117 已合）。
- **公測後待辦**（加在「第三十一任接手」那段之上）：
  - 非正式版標示（防搬第二階段）：上 App Store 前做；要讀發版時注入的值，先發一版只給自己的 TestFlight 驗證再給大家（作者問過，第 32 任建議公測後）。
  - 資料來源與授權總盤點：App 打包的每份資料對一次來源與授權（作者問「遊戲裡有沒有別人的記號」）。
  - 新台幣 PR-0～PR-3（存檔 76，App Store 前約 11/14）：BH3 文件 §6 是「改之前」的基準。
  - 各 BH 文件的 P2／P3、UI_AUDIT B1–B10、UI_GAPS G1／B-1／D1–D15、TUT B1–B7、PERF 丙（「自動」再加「少陰影與反光」「穩定 30 格」兩步）。
- **排程**：第 32 任的巡查 send_later 交接時刪掉；新任自己排（約 30–40 分一次）。Threads 排程已停（作者 10/29 說最後一次）。
- **作者的狀態**：只有手機，給結論不要叫作者跑指令；語氣溫和；PR 和留言不寫另一個同類 App 的名字。作者很在意「當機和卡住」與 session 之間有沒有重工，每次合併後看其他 PR 有沒有變 dirty（GitHub 遇衝突就不跑 CI）。

**第三十二次換手（2026-10-29 約 14:45 UTC，第 31 任 session_01YGNNukxseY7eMCvXhjtc4X → 第 32 任）**：第 31 任壓縮 2 次、用到約 29 萬 token，照 §1 換手。
- **發版**：作者已自己發 95.1，testflight.yml 跑在 a7b958c（run 40862262994，綠）。和 6ff5ffe 只差 What's New 多一行「車隊清單從車卡上也拖得動」。作者 10/30 會先自己發一版測，再發一版開公測（10/31 0:00 台灣時間丟連結）。發之前要確認 main HEAD 的完整 ci.yml 和 iOS 全線都綠；作者自己按 TestFlight，或在本對話說「發」才代按。6ff5ffe 的 ci.yml 全量重跑後綠（40866614287）；iOS 全線紅（40866617267），紅的是兩支不穩的 UI 測試，#1498 已修。
- **今天合的**：#1495（視覺技術研究，docs/research/VISUAL_TECH_RESEARCH_2026-10-29.md）、#1496（路線清單橫放收一列，決策 486）、#1497（rest shard 搬類別）、#1498（UI 測試改穩）、#1499（實景地圖鋪路照畫的鋪，決策 487）、#1500（GeoJSON 輸出給 geolibre.app）。
- **還在做的**（綠了就用 REST 轉 ready 並合併，合了在 #1041 記、告訴作者，再封存）：
  - #1501 FPS（session_01YGNNuphxaPGPV7TDzRjjop）：3D 跟車 10× 掉幀，決策 485，已 merge main，CI 跑中。
  - LJB（session_01YGNNuqJftBtg8BZnJg1nrk）：先買內灣線再買六家線，六家線列車卡在竹中。作者說「修好跟我說」。
  - GTK（session_01YGNNumjTnb7ozdTjHu7Gwv）：垃圾車和回收車的 3D 模型破圖。
  - BLD（session_01YGNNuoJrjdfniv6NV8wn7e）：2D 放置建築時 fps 掉到 11–14。
  - UIF（session_01YGNNuoNKMExihpF16p4VC6）：#1498 已合，等它把單支重複驗證跑完並結案。
- 這些都合進去後，在 main HEAD 用 workflow_dispatch 跑完整 ci.yml 和 iOS 全線，綠了給作者紅綠燈表。
- **排程**：第 31 任的巡查 `trig_01QDkvQkddhwX49C25FVXkWw`（15:04 UTC）和 Threads `trig_01SRe5chbpKMHHWobCAKky9A` 綁在第 31 任身上。新任用同樣的 prompt 建綁自己的（`get_trigger` 讀得到），再刪掉舊的。作者說 10/29 是最後一次 Threads 更新日誌，以後直接發宣傳片，所以 Threads 排程可以停掉。
- **作者的狀態**：觸及率低，有點想放棄，也怕公測（覺得流量被另一個同類 App 吸走了）。語氣放溫和，不要催。PR 和留言都不要寫出那個 App 的名字。
- **作者只有手機**：要看的東西給圖或結論，不要叫作者跑指令。
- **環境**：設定腳本第 3 行把 `mcp__claude-code-remote__add_repo` 當成殼層指令執行，每次開機都 exit 127。不影響工作，已告訴作者可以去刪。
- **95.1 之後的待辦**照舊：演示模式改成只在內部版、需求選項 A、私庫搬家等（見下面「第三十一任接手」）。

**第三十一任接手（2026-10-29 約 07:30 UTC，session_01YGNNukxseY7eMCvXhjtc4X，作者在 claude.ai 開，第 1 層）**：第 30 任 session_01YGNNuq4nxQrJ1jQ182c4Yz 沒掛到 repo、拿不到 GitHub 權限，已改名「【舊・已換手】」並封存，由本任照下面兩段接。
- 排程改綁本任：Threads `trig_01SRe5chbpKMHHWobCAKky9A`、95.1 截止後步驟 `trig_01SoyLas1SRJJ7kXE2Anw5La`（10:05 UTC）、巡查 `trig_01T8BqMeAidkdpVvhHfFhNzA`（之後約 45 分一次）；第 30 任的三個已刪。下面「第三十次換手」列的排程 id 都已不在。
- **GeoJSON 輸出（派工單 GEO，已做，作者 10/29 交代）**：`tools/geojson-export/` 輸出車站、路線、機廠、底圖道路和遊戲 64 m 道路格子，作者拖進 geolibre.app 檢查位置；怎麼跑與怎麼打開見該資料夾 README。不在遊戲裡，沒動 App 與 GameCore。
- **防搬（作者 10/29：有人 clone 公開 repo 重新打包成 App）**，95.1 之後做：
  - A 案盤點：派工單 PRIV（session_01YGNNuow8p93HA9KfQDJLmf）在寫 `docs/research/PRIVATE_ASSETS_SPLIT_2026-10-29.md`。內容是把編 App 必需的美術、模型、資料移到私庫，CI 建置時再拉進來。計畫要作者點頭才動手。
    - 盤點已寫好（重開的 PRIV，session_01YGNNunCs4CpTF415GeYCpT）：[`research/PRIVATE_ASSETS_SPLIT_2026-10-29.md`](research/PRIVATE_ASSETS_SPLIT_2026-10-29.md)。**結論：建議先不搬**。原因有三：今天的資料全在 git 歷史裡，一行 checkout 就能放回最新程式；Swift 裡的 3D 美術搬不走；CI 和每個 session 要長期付代價。改成先做陷阱資料與非正式版標示。真的要搬時照該文件第 1–9 節做：私庫 `railway-game-data-private`、deploy key、疊回原路徑，作者的步驟在第 4 節。作者點頭前什麼都不搬。
  - 陷阱資料與非正式版標示（作者：「也一起排」）：95.1 發完再派一個 session（避免和發版檢查搶 macOS runner），不動 GameCore、存檔、golden。
    - 陷阱資料：在打包資料或程式裡放一兩筆只有本專案有、玩家看不出來的小東西，被整包照搬時可以當證據。不能讓鐵道資料變錯（鐵道迷）。哪幾筆是陷阱只寫在私庫，不寫在公開 repo。
    - 非正式版標示：自己編的 App 顯示「不是正式版本」。CLAUDE.md 規定 app ID 不寫進 repository，所以要用發版時注入的值來判斷（例如 `testflight.yml` 現有的變數），不在程式裡寫死 ID。Simulator 的 UI 測試和官網截圖不能被這個標示擋住。玩家看的文字只說「請從 App Store 下載正式版」，不說原因。
    - 五方各寫一行，取決策號（取號前先看 #1041）。
    - **進度（10/30，派工單 AT）**：陷阱資料已做（決策 494；細節在私庫 `a91453/railway-reference-private` 的 `Railway/anti-copy/`，改寫或重新產生 App 打包的資料前先讀它）。非正式版標示還沒做，公測後、上 App Store 前再做。
- WEB：私庫 PR #116 作者已在 07:23 UTC 自己合了（只換「實景示範」1 張）；官網要作者按 Deploy website 才會換。其他圖等新截圖出來，WEB 另開新的 draft PR。

**第三十次換手（2026-10-29 約 07:30 UTC，session_01YGNNunHRtNkV8GUzm1ppB7 壓縮 2 次、用量約 200k → 本任用 `create_session` 開的新規劃，第 6 層）**：作者說「發版前先換手」。照下一段「第二十九任做到哪」接。
- 新規劃先讀第 1 節、本段與下一段，再讀 #1041 從「遊戲規劃第 29 任（session_01YGNNunHRtNkV8GUzm1ppB7）壓縮第 1 次」往後（那則應為第 2 次，後面有更正），然後在 #1041 留言接手。
- **排程**：舊規劃綁的三個排程交接時刪掉，新規劃用下一段的內容自己重建：巡查 `trig_013c3pyZ1Qe5jjHewLeFhjFR`、send_later `trig_01Bd29roNgtBwevFHqupTZ2F`、截止後步驟 `trig_01K55gV9iJnxVzHyHJ9QECha`（10:05 UTC）。Threads 排程 `trig_01QgYcPfTjYME47gSRMSQ6mA`（每天台灣 21:43）也綁舊規劃：新規劃用 `get_trigger` 讀它的 prompt，建一個綁自己的，再刪掉舊的。
- 在跑的 session（下一段的表）已被告知改向新規劃回報。
- 新規劃是第 6 層，還能再開一任（第 7 層）；再下一任由作者在 claude.ai 開（§1.1）。

**第二十九任（session_01YGNNunHRtNkV8GUzm1ppB7，2026-10-29）做到哪**：和下面不同時以這段為準。
- **95.1 今晚發**（作者 10/29 14:30：「我趕在晚上再發95.1好了」）：
  - 合併截止從 10/30 04:00 UTC 提前到 **10/29 10:00 UTC（台灣 18:00）**，已在 #1041 公告。截止前綠而且 ready 的 PR 照常合，之後只合 95.1 的 What's New，其他留到下一版。
  - 截止後的步驟：
    1. 派 Sonnet session 把 `.github/testflight-whats-new.md` 與 `WhatsNew.swift` 最前面那則（id `2026-10-29-94`）改成 95.1，只寫 94（`cd93d78`）之後合的，綠了合進 main。
    2. main HEAD 跑一次 `website-screenshots.yml`（可和 full lane 同時跑），或請作者自己拍（作者：「我自己也可以截圖」）。照片不刪。
    3. main HEAD 用 `workflow_dispatch` 跑完整 `ci.yml` 與 `ios-build.yml` full lane（full lane 約 1.5–2.5 小時）。
    4. 都綠了，給作者健檢紅綠燈表。作者在**新規劃這一任**的對話說「發」，才按 `testflight.yml`，只按一次、用 main HEAD。
  - 預計：台灣 18:45 起跑檢查，21:00–22:00 給健檢表。
- **作者 10/29 的新規則**：
  - 「不用再管你合就合」：綠的就合，照 §1.2 一批 3–5 個，main 綠了再合下一批。
  - 「壞了就修 好了就封存」。
  - 「記得先交接再封存，照片不要刪」：session 把沒做完的寫進本檔、在 #1041 說了才封存；已拍的截圖、預覽、宣傳素材、Actions artifact 都不刪。
  - 「截圖先暫停拍攝 明天要發前再做而且我自己也可以截圖」：PR 不跑 `website-screenshots.yml`、不等截圖驗收（ui-review §3 已寫暫緩，#1475），發版前再拍。
  - 「修補的都繼續 不要擋道macOS runner都行」：每個 PR 同時最多一個手動 `only_testing`；PR 自己的 iOS App Build 在跑時不重複手動跑。
  - iOS 最低版本維持 17（作者：「太複雜就先算了」），不升 18。
  - HUD 不加圖表（作者：「Hud 畫面的 還是目前不需要」）。
- **本任合的**（記在 #1041）：#1463（BUS）、#1460（M）、#1454 與 #1468（Codex 高雄）、#1465（FL94）、#1469（ROAD PR 2）、#1467（CJ）、#1470（SY 三鶯線卡住，作者已被告知修好）、#1473（UIREV ui-review skill）、#1474（DONUT）、#1475（UIREV 續篇）。最後一批 #1474、#1475 合完，main `286d7a2` 的 push `ci.yml` 在跑，綠了才合下一批。main `d2a2b0a` 的 full lane（run 40823424641）全綠。
- **在跑的 session**：

  | 代號 | session | 做什麼 | 合的時機 |
  | --- | --- | --- | --- |
  | SHOT | session_01YGNNumMhqmw96pGQJnVgtY | #1471（決策 477）：地圖標籤避開站名、車隊清單拖得動、全台入口 | 截止前綠就合 |
  | VIZ | session_01YGNNuosyKEgJgsVUGFPhbW | #1472（決策 478）：三張載客圖。要先併 main、用 XcodeGen 重產 xcodeproj（#1474 已合） | 截止前綠就合 |
  | LP | session_01YGNNunF7F1xm5bcPAv9pcL | #1476（決策 481）：路線頁拆成清單＋每條線的頁、分組、「需要注意」篩選。HANDOFF 改用 §4.22 | 截止前綠就合；#1472 先合的話它併 main，把載客圖搬到路線頁 |
  | SY | session_01YGNNum2FZBg4ueDbGp3gEf | #1477（決策 479）：收購三鶯線時一起蓋三峽機廠。只動 GamePresentation。已壓縮 2 次，做完就停 | 截止前綠就合 |
  | VID | session_01YGNNukoWqi8apoMDtJNZ3x | #1461 宣傳素材（draft）。在跑的 promo run 40825762656 讓它跑完，之後不再開截圖 run | 素材齊了再合 |
  | WEB | session_01YGNNunk52JnVx6sBsWD3uS | 官網截圖，私庫 PR #116（draft），等新截圖 | 截圖補齊後請作者合私庫 PR 並 Deploy website |

  不碰：#1342、私庫 PR #103、Codex 的 draft（#1456 等）。
- **HANDOFF §4 重號**：#1472 用 §4.20，#1475 已合的是 §4.21，#1476 改用 §4.22。之後加 §4 小節的 PR，合 main 前先看最大號。
- **號碼**：決策 477 SHOT、478 VIZ、479 SY 機廠、480 DONUT、481 LP、482 UIREV；下一個是 483（先看 #1041）。存檔 76、77 照上一段的保留。
- **之後要寫進規劃文件的**：
  - 決策 476（ROAD）的下一步 3、4 在 HANDOFF 加一行指過去。
  - ui-review 第 10 節「列車：圖標還是車型」已在 #1475；圖表的鐵道味建議只列不改，最滿列車條改成一節車廂的填滿度那條，LP 決定先不做（決策 481 第 9 項）。
- **作者問過、答了、已做**：geolibre.app（MIT，網頁 GIS）可以拿來檢查資料位置，不放進遊戲。資料工具的 GeoJSON 輸出已做（`tools/geojson-export/`，見上面）。

**第二十九次換手（2026-10-29 約 04:10 UTC，session_01YGNNumk6UqdBm6JrBhsdZY 壓縮第 3 次 → 本任用 `create_session` 開的新規劃，第 5 層）**：照下一段「第二十八任做到哪」接。
- 新規劃先讀第 1 節、本段與下一段、#1041 從「session_01YGNNumk6UqdBm6JrBhsdZY 壓縮第 3 次」往後，然後在 #1041 留言接手。
- **排程**：舊規劃綁的 `trig_0126L4oXAtbbCmVaPcJfyR4q`（巡查）與 `trig_01Jverg8SDc6haaSZzEUsWwm`（10/30 01:00 UTC，原 94.1 檢查，改看 95.1）交接時刪掉；Threads 每日排程 `trig_01NzMKnCRdBjC6csJMQEPJVy` 若還綁舊規劃，新規劃用 `get_trigger` 讀 prompt、建綁自己的、刪舊的。巡查自己排（約 45 分一次）。
- 在跑的 session（下一段的表）已被告知改向新規劃回報。
- 新規劃是第 5 層；下一任到第 7 層時改請作者在 claude.ai 開（§1.1）。

**第二十八任（session_01YGNNumk6UqdBm6JrBhsdZY，2026-10-29）做到哪**：和下面不同時以這段為準。
- **94 已發**：作者自己按的（`testflight.yml` run 40803620174，`cd93d78`，0.5.0 (94.1)），目前只作者自測。94 的 full lane（run 40802613854）紅 2 支 UI 測試，由 FL94 修（#1465）。
- **合併截止 10/30 04:00 UTC（台灣中午）**：之前綠的 PR 都進 main，紅的規劃修；之後出 **95（95.1）**：
  1. 截止後派人把 `.github/testflight-whats-new.md` 與 `WhatsNew.swift` 最前面那則（id `2026-10-29-94`）改成 95.1，只加 94 之後合的。
  2. main HEAD 跑完整 `ci.yml`（`workflow_dispatch`）與 full lane。
  3. 兩個都綠，給作者健檢報告，請作者決定發不發；作者在**本對話這一任**說「發」才按 `testflight.yml`（一次、main HEAD）。
- **10/31 公開連結**：完整 `ci.yml` 綠、full lane 綠、兩天沒有新閃退回報、作者實機看過；用 94 或 95 由作者決定，公開連結作者自己開。
- **作者要被告知的**：(1) 三鶯線修好（「修好跟我說」）；(2) 官網截圖補齊後一起換（「等補齊再一起換」）；(3) 94 健檢結果（已告訴：紅，FL94 修）。
- **本任合的**（記在 #1041）：#1457（What's New 94）、#1459（PLAYER_FEEDBACK 10/29 四列）、#1458（P 稽核表）、#1462（FREEZE，50 站凍結量測）、#1464（ROAD PR 1，決策 476，main `781f881`）。#1464 合完 main 的 push `ci.yml` 在跑。
- **在跑的 session**：

  | 代號 | session | 做什麼 | 合的時機 |
  | --- | --- | --- | --- |
  | SY | session_01YGNNum2FZBg4ueDbGp3gEf | 三鶯線收購後列車卡在長壽山（作者回報，派車問題），最優先，PR 標「［95］」 | 綠就合，合了告訴作者 |
  | FL94 | session_01YGNNumMEp9zTcEPv6nuiXW | 94 full lane 那 2 支（#1465，draft，等 only_testing） | 截止前綠就合 |
  | ROAD | session_01YGNNuqCofc3bZTNaFHght7 | 玩家道路 PR 2（鋪法，只做 A），重疊照決策 468 的接法 | #1463 合後才開 |
  | VID | session_01YGNNukoWqi8apoMDtJNZ3x | 宣傳素材 #1461（決策 475）；修 testFreight、testTourism；完成後再跑截圖並 `send_message` WEB 新 run | 94 後 |
  | WEB | session_01YGNNunk52JnVx6sBsWD3uS | 官網截圖，私庫 PR #116（draft） | 截圖補齊後請作者合私庫 PR 並 Deploy website |
  | M | session_01YGNNukvbEqFLMsPED4XHuY | #1460（決策 473，載入進度與取消） | 95 之後 |
  | BUS | session_01YGNNupkE1PnsnNDofKd6rJ | #1463（決策 474，單行道、隧道） | 95 之後；不接新工作 |
  | CJ | session_01YGNNumLcrSFbAyyoYDWRL9 | 決策 472 | 95 之後開 PR |

- **號碼**：決策 472 CJ、473 M、474 BUS、475 VID、476 ROAD；下一個從 477 起（先看 #1041）。存檔版本 75；76 留給新台幣 PR-1、77 留給機廠與終點站停車場。
- **新介紹影片**（作者：「我想給你剪片」「就是新的介紹影片」）：換掉首頁 `along-the-line-intro-16x9.mp4`（37.5 秒）。照 `Website/tools/trailer/` 的 trailer.html 樣式，iPhone 框裡放作者實機錄影＋新截圖，45–60 秒、1080p、遊戲的聲音。作者在規劃對話上傳片段（每段 10–15 秒、30 MB 以下）；片段放 railway-assets-private，剪好先給作者看，再開私庫 PR。還在等作者上傳。
- **玩家回報**：作者轉給規劃，規劃記進 `docs/research/PLAYER_FEEDBACK.md`（不寫個資）、分類、派工，回報順序與 PR。
- **作者說過**：「好 號誌效能94後派」→ 95 之後派 GameCore 號誌效能（Opus）；道路「五方決定對遊戲性最好的而不是為了趕工」。
- **95 之後的合併順序**：#1463 → #1460 → CJ → ROAD PR 2，然後派號誌效能。
- **之後補**：`tools/train-models/hashes.lock.json` 少兩個景物鎖：`scenery-busStopPole` `3bff96f2cccef641`/58、`scenery-postBoxes` `bbb71fc344060bd2`/108。
- **10/31 後的順序**（接第二十七任那段）：公開測試的回報 → CJ → P 稽核表的 1、2、3、6 項 → M → L-3～L-7 → 跟隨公車視角 → 新台幣 PR-0、PR-1（存檔 76）→ 預覽提示可收購 → 機廠與終點站停車場（存檔 77）→ 節慶、3D 動物與無人機秀、資料來源頁補日期 → 安坑輕軌 → 環狀輕軌。

**第二十八次換手（2026-10-28 約 22:00 UTC，session_01YGNNumoD1XSP8eSkjabCvp 壓縮 2 次、用量約 210k → 本任用 `create_session` 開的新規劃 session_01YGNNumk6UqdBm6JrBhsdZY，第 4 層）**：照下一段「第二十七任做到哪」接。
- 新規劃先讀第 1 節、本段與下一段、#1041 從「session_01YGNNumoD1XSP8eSkjabCvp 壓縮第 2 次」往後，然後在 #1041 留言接手。
- **排程**：Threads 每日排程 `trig_01NzMKnCRdBjC6csJMQEPJVy` 綁在舊規劃；新規劃用 `get_trigger` 讀它的 prompt，建一個綁自己的，再刪掉舊的。舊規劃的巡查排程交接時已刪，新規劃自己排（約 45 分一次）。
- **在跑的 session**：只有 CF（session_01YGNNuqWY2PSBocJBUDh9eW，決策 470，10/31 後合），已被告知改向新規劃回報。
- **main**：`03c911f`（#1450）的 push `ci.yml` 交接時在跑；綠了才合下一批。這份交接的 PR 也由新規劃照 §1.2 合。
- **還在等作者**：10/30 台灣中午截止與 94 版（下一段）。作者在新規劃那邊回答。
- 新規劃是第 4 層；開到第 7 層時改請作者在 claude.ai 開（§1）。

**第二十七任（session_01YGNNumoD1XSP8eSkjabCvp，2026-10-28 晚）做到哪**：和下面不同時以這段為準。
- **作者 2026-10-28 定 10/29–30 是「使用者優化與 bug 修復」**：照 UI 健檢（`docs/research/UI_UX_REVIEW_2026-10-28.md` §3 的 16 件）修既有畫面，不開新功能。
- **本任合的**（照 §1.2，記在 #1041）：#1433（BX，full lane 那 9 支）、#1436（CA，UI 健檢研究）、#1438（CC）、#1443（CE，財務圖表）、#1442（CD，決策 469）、#1434（BP-2，決策 465）、#1444（CB，審查 L-1、L-2）、#1439（BZ，決策 468）、#1441（CE，UI 健檢 O、G、E、F）。main `9213b20` 的 full lane（run 40728356732）全綠，BX 的修正驗證過了。
- **HANDOFF 重號**：#1442（CD）與 #1439（BZ）都加了 §4.17；BZ 合 main 時把自己的改成 §4.18。之後加 §4 小節的 PR，合 main 前先看最大號。
- **不穩的測試**：「捏合開 3D」的 UI 測試在 main `cca7013` 的 full lane 與 CE 第一次 only_testing 紅、`9213b20` 的 full lane 綠。7 天內再紅一次就照 diagnosing-bugs 派人修穩（§1 的 CI 線）。
- **10/31 前的 UI 健檢都合完了**：#1445（CG，健檢 B，觸控範圍 44 點，main `7e72db8`）、#1450（CH，決策 471，健檢 K，跟隨列與財務面板不再每個 tick 重算，main `03c911f`）。CG、CH 已封存。
  - 規劃代為決定（CG 問）：地圖列車卡的膠囊（3-2）這次只到約 27 點高，10/31 前不加大排距；10/31 後和健檢 N 一起重排卡片時補到 44（五方在 #1041）。
  - `testTheStationTagsPencilRenamesAtOnce` 在 #1445 的 only_testing 紅過一次（空白鍵沒打進欄位，慢 runner），單跑綠；和「捏合開 3D」一起看，7 天內再紅就派人修穩。
- **還在等作者回答**：合併截止要不要改成 10/30 台灣中午；改的話當天下午 main HEAD 的完整 `ci.yml` 與 full lane 都綠就請作者發 94，作者晚上實機看，10/31 公開連結用 94，94 有問題就用 93.1。作者沒回答前照舊（10/31 用 93.1 或當時已發的版）。
- **10/31 後才合**（PR 都是 draft，標題寫著）：#1446（BO，決策 467，Meshy 第一批＋glTF-Validator 進 CI，作者已同意，§7.4）、#1447、#1448（BY，三鶯線）、#1437（Codex 台中綠線）、CF（session_01YGNNuqWY2PSBocJBUDh9eW，決策 470，#1451）。為了讓出 macOS runner，本任取消過這幾張的 PR iOS run（例如 #1447 的 run 40734596376，gate 因此紅）：10/31 後一張一張重跑 iOS run，再對 gate 按 Re-run failed jobs。BO、BY 都壓縮 2 次停了，10/31 後開一個照顧 session 收尾三張。
- **10/31 後的順序**（規劃定）：公開測試的回報 → CF、BO、BY 收尾合併 → UI 健檢 N（車站面板 20 段）→ P（事件×通道回饋稽核；**表已出**：`docs/research/FEEDBACK_AUDIT_2026-10-29.md`，下一步是照它最後一節先做 1、2、3、6 項再跑實機清單，不再另開稽核）→ M（載入畫面的進度與取消）→ 審查 L 的 L-3～L-7（L-1、L-2 是 #1444）→ **跟隨公車視角** → 新台幣 PR-0、PR-1（存檔 76）→ 預覽提示可收購 → 機廠與終點站停車場（存檔 77）→ 台灣節慶研究、3D 動物與無人機秀、資料來源頁補資料日期 → 安坑輕軌 → 環狀輕軌。
- **跟隨公車視角**（作者 2026-10-28 問「要加跟隨公車視角嗎 把列車那套移過來就好」，規劃答 10/31 後、排第 7）：
  - 怎麼做：`Map3DFollow` 從 `Map3DTrains.Head` 算鏡頭（後方、後上方、駕駛座、側面、車站五種），公車沒有 Head。`BusMotion`（決策 400 10i-6）在 GamePresentation 已有確定的公車位置與方向，補一個公車的 Head 轉接，`GameSession` 加跟隨公車（照 `followTrain`、`stopFollowingTrain`），`FollowBar` 顯示路線與下一站；公車在班次頭尾會淡出，跟到淡出時換同路線的下一班或回到一般視角。只動 GamePresentation 與 App，不動 GameCore、存檔。約一個 PR。
  - 五方：玩家（多一個看城市的角度，但 10/31 前修好卡頓與畫面更多人受益）；鐵道迷（公車不是主角，加分少）；開發（列車那套可以重用，公車淡出與駕駛座視角要另外處理）；美術（近看公車要模型夠細，公車套件已有）；音樂（無）。

**第二十七次換手（2026-10-28 約 15:30 UTC，session_01YGNNuknN8czzHmJ7zU9h3R 壓縮第 3 次 → 本任用 `create_session` 開的新規劃，第 3 層）**：下一段（第二十六次換手之後）就是交接內容，新規劃照它接。
- 新規劃先讀 #1041 最後 30 則與本段、下一段，然後在 #1041 留言接手。
- 在跑的 BX、BP-2、BO、BY、BZ 已被告知改向新規劃回報。
- 新規劃是 session_01YGNNumoD1XSP8eSkjabCvp。Threads 每日排程改成綁它的 `trig_01NzMKnCRdBjC6csJMQEPJVy`；舊的 `trig_01X6aHx44xiCGGvXkU78pcGd` 與舊規劃的巡查排程已刪。
- 10/31 公開連結的條件：(1) main HEAD 的完整 `ci.yml` 與 full lane 都綠（full lane 等 BX 修好）；(2) 93.1 兩天沒有新的閃退回報；(3) 作者實機看過。三樣都到了，才請作者在 App Store Connect 開公開連結。公開連結是作者的事，規劃不按。
- 這任 session 是第 2 層，新規劃第 3 層；到第 7 層時改請作者在 claude.ai 開（§1）。

**第二十六次換手之後（本任 session_01YGNNuknN8czzHmJ7zU9h3R，2026-10-28 晚）**：和下面不同時以這段為準。
- **93.1 已發**：作者 13:29 UTC 按的（run 40696855122，`cca7013`），出口合規作者答。完整 `ci.yml` 綠；full lane 紅 9 支 UI 測試（PLAYER_FEEDBACK 93.1），由 BX 修。發版凍結已在 #1041 解除。
- **作者 2026-10-28 定**：
  - 不改成直接上 App Store（「算了還是上TestFlight 好了我懶」），照原計畫 **10/31 開公開 TestFlight**，10/29–30 只修 bug。App Store 之前要做的（E1 正式版拿掉隱藏開關、商店截圖、隱私權頁、上架資料）等作者說要上架再提。
  - 捷運收購的後續先後（「好 照這樣排」）：(1) GameCore 的機廠／終點站停車場，讓收車時終點站要停 6–25 組的線（淡水信義、松山新店、板南、環狀、中和新蘆、機場線、高雄紅橘、台中綠線、淡海綠山線）能收購。Opus、要升存檔版本，排在新台幣 PR-1（存檔 76）之後，所以是 77，10/31 後派。(2) 安坑輕軌早上 6 點停住的原因。(3) 高雄環狀輕軌的單向繞圈。文湖線不做。三鶯線不加機廠：它的 12 組車終點站放得下，卡的是派車效能，BY 在修。
- **本任合的**（照 §1.2，記在 #1041）：#1422、#1429、#1428（作者）、#1430、#1431、#1432（BW，決策 438 續篇，466 釋出）、#1418（BR，`72b7351`，full lane 三個 iPhone job 重新分配；BR 已封存）。
- **在跑的 session**（都 10/31 後才合，BX、BP-2 除外）：
  - **BX**（session_01YGNNupvk2a84QNp2vhJTPR，Sonnet）：full lane 那 9 支。修好前不開公開連結。
  - **BP-2**（session_01YGNNumsbvdDUbdhhgfgCkW，決策 465）：編輯後主執行緒停頓。
  - **BO**（session_01YGNNuqASY5sxbk5kKzVByD，Opus）：Meshy 第一批接進 3D 地圖，`Map3DMeshSimplifier` 補三件；glTF-Validator 作者沒同意前不加。
  - **BY**（session_01YGNNumbM7yQYmUdtepxynG，Opus）：三鶯線，派車重算路徑的 GameCore 效能修正（結果要逐位元不變），再加回 `LINES`、`urbanLines`，`Map3DSanying` 接營運。
  - **BZ**（session_01YGNNun7niN3kzJtkLN8GL6，Opus，branch `claude/trace-overlap`）：描線接上已有軌道＋真實路線讓位（下面「描線與收購並存」的第 1、3 件）。作者說「既有問題先修」，目標 10/30 前可合，排在 BX 之後。
  - session 暫時 5 個（比 4 個多一個）：BO、BY 10/31 後才合，不搶 CI。
  - 待合：#1433（決策 464 補丁，UI 測試預設不跳速度提示）、#1434（BP-2）。綠了就照 §1.2 合。
- **描線與收購並存**（作者 2026-10-28 問「照真實路線畫會跟已經鋪好的重疊」「還是之後只開放收購 我不知道」，規劃定：兩種都留）：
  - 描線碰到同一條真實路線上已經有的軌道（自己鋪的、收購的、示範的）：那段跳過、兩端自動接上，接著往後描，不算錢。碰到別條線的軌道照舊停下並說明原因（`RealRailwayTracing.swift`，現在是一律停在那段前面）。
  - 描到可以收購的線：預覽多一行「這條線可以直接收購（$X，含列車與真實班表）」。
  - **真實路線讓位給玩家**（作者同日：「像是文湖線已經預設鋪好 玩家按延真實鐵路不是會多一條」）：實景地圖上的真實路線與真實列車只是畫面（決策 304，不載客、不擋車、不進存檔），描線在規則上不衝突，但畫面上會疊兩條線、兩套車。改成：玩家軌道沿真實路線鋪過的那段，底下那段真實路線不畫；那條線的車站大多被玩家車站取代時，它的真實列車不畫，只蓋一小段時只在那段不畫；拆掉玩家軌道就畫回來。現在只有設定裡整體的「真實鐵路：自動／淡化／隱藏」（`RealRailways.TrackStyle`）。文湖線另有 35 m 急彎描不下的限制（決策 400），不在這一件。
  - 只動 GamePresentation，不動 GameCore 與存檔。作者同日改口「這個問題算既有問題先修」：描線接上已有軌道與真實路線讓位由 **BZ 現在做**；預覽提示可收購留到 10/31 後。
  - 五方：玩家（想省事就買，想自己蓋就描）；鐵道迷（台鐵幹線、高鐵、大部分捷運買不到，只開放收購就蓋不了）；開發（只改描線與預覽）；美術（預覽多「已有」「可收購」兩種標示）；音樂（無）。
- **10/31 後要派**（順序）：新台幣 PR-0、PR-1（存檔 76）與預覽提示可收購 → 機廠與終點站停車場（存檔 77）→ 台灣節慶研究、3D 動物與無人機秀、資料來源頁補資料日期 → 安坑輕軌 → 環狀輕軌。

**第二十六次換手（2026-10-28 約 12:15 UTC，session_01YGNNuqBYkjv4r12NahDH4X 壓縮第 3 次 → 本任用 `create_session` 開的新規劃，第 2 層）**：和下面不同時以這段為準。

新任開工：
- 讀第 1 節與這一段。
- 先用 `add_repo` 加 railway-reference-private 與 railway-assets-private。
- #1041 從「session_01YGNNuqBYkjv4r12NahDH4X 壓縮第 3 次」往後讀。這一任合的與派的都記在 #1041，從第二十五次換手那段往後。

**93.1 今晚發**（作者：「還是順便有綠的都加入 反正我大概9點多才要發」，台灣 21:xx ＝ 13:xx UTC）：
1. 合 #1424（BS，決策 461，台北捷運 C371／C381／C341／610 照實際配車，head `29eb160`）與 #1423（BT，決策 462，六家線、內灣線都能收購、竹中六家線月台架高，head `8abdd15`）。兩個都等 Xcode build，Swift 已綠；session 會自己改 ready 並 `send_message` 規劃。照 §1.2 合，合後封存 BS（session_01YGNNukixzoSrgvZpoo21mP）與 BT（session_01YGNNuozVE7YV18bpitdwBA）。趕不上的留 94，不擋發版。
   - 這批 main 已有 #1415（`3431a04`）、#1421（`57c18d6`）、#1425（`8b158ef`），push 的 `ci.yml` 跑中。加上 #1423、#1424 共 5 個，合完要等 main 綠。
2. 最後一個合完，在 main HEAD 用 `workflow_dispatch` 跑完整 `ci.yml`，再跑 full lane（`ios-build.yml`，發版 commit 用手動）。
3. 兩個都綠，告訴作者「可以發（commit）」。作者在**新任**這邊說「發」才按 `testflight.yml`（一次、main HEAD）。
4. 發完寫 What to Test，要放：
   - 6000× 停頓（#1414、#1415，決策 459）；編輯後仍可能停頓（BP-2 還沒修，下面）。
   - 決策 460（§4.15）：4 GB iPhone 開 3D 會不會閃退、記憶體；M 系列 iPad 的畫質；iPad 的像素；舊機實際跑到的速度。
   - 台北捷運各線的車（#1424）；竹中先後買六家線、內灣線（#1423）。
   - Kenney 針葉樹、灌木、儲槽（決策 458）；台北車站、101、高雄車站兩棟共構大樓（決策 457 後來）。
   - 再來是 PLAYER_FEEDBACK 記 93.1，提醒作者回答出口合規。
5. Threads：排程 `trig_01DmgURkgMM1RxCUQPhn6eSv`（每天 21:43 台灣時間）綁本任。新任用同一份 prompt（`get_trigger` 讀得到）建一個綁自己的，再刪掉這個。發了 TestFlight，它就會開寫作 session。

**在跑的 session**（新任用 `send_message` 告訴它們改向新任回報；共同規則：不動 #1342、私庫 #103，壓縮 1 次不接新工作、2 次停）：
- **BU**（session_01YGNNuprdU1h3hhSZn6UjES）：玩家回報 90.1「站牌與實際位置不一致、路線沒照真實路線」。
  - 公車資料本身是對的：`real_buses_Taipei.json` 解出臺北車站各站牌在 25.046、121.513 附近。
  - 假說：`RealWorldFrame` 把全島當平面、錨點在島中央，台北偏約 1 km（`RealWorldExpansion` 決策 167）。
  - BU 也把這批玩家回報寫進 PLAYER_FEEDBACK。給 94。
- **BV**（session_01YGNNumnQtaMdPM5echyBfu，Sonnet）：作者要的「你的手機跑不到那麼快」提醒。
  - 決策 226 的小點保留；主動跳一次「這張地圖在這台裝置上大約只跑得到 ×N」，附「改成 ×N」與「知道了」。
  - 太燙時改說「裝置有點燙，遊戲先放慢」。不說手機舊，不限制速度。給 94。
- **BR**（session_01YGNNumq4dA2CQatfUojyhs，#1418 draft，CI 重新分配）：等 full lane run 40668230502 的 second job 量時間；綠了它會改 ready 並回報。

**93.1 之後要派**：
- **BP-2**（編輯後主執行緒停頓）：91.1、92.1 的 iPad (A16) 玩家建站、新設路線、買車、連轉乘站都會卡 0.5–0.7 秒。量法與存檔在 §5 那一列（#1425）。開新 session（Opus），決策號重新預約（463 已釋出）。
- **BO**：Meshy 第一批接進遊戲，Opus。glTF-Validator 進 CI 是加依賴，作者同意了沒以 #1041 為準，沒有就先問。
  - 同時處理 `Map3DMeshSimplifier`（決策 420）接到畫面要補的三件：誤差上限、單面板不被壓扁、背景建好並在裝置上快取。
  - 列車不用它：有配方的列車自己做遠景版（決策 420、422、426、432、433；rolling-stock skill）。
- **三鶯線**：#1422（Codex，draft，只是研究）的後續；素材庫 PR #19 作者合。派工單 BY（session_01YGNNumbM7yQYmUdtepxynG）做了開放收購（`claude/sanying-line`）與 3D 的兩節車（`claude/sanying-line-trains`，決策 466），兩個都 10/31 後合；號誌效能剩下的見 §5「捷運收購」那一列。
- **市區公車 PR 2**（決策 438：沒有車站的市區路線要畫出來、能編輯）：玩家回報的「舊存檔沒有公車」是決策 428、440 已修的重複回報；「不經車站的公車」要等這個 PR。
  - 派工單 BW（session_01YGNNunvxsQfGwrTyJyF7zb，`claude/city-bus-ui-438`）做了；之後要看的三件在決策 438 續篇的「下一步（PR 2 之後）」。

**還要看的**：
- 審查點數從 #1386 起約 22／30，滿 30 開下一輪。
- 編號：決策到 462（461 BS、462 BT）。BU、BV 若預約了，以 #1041 為準；新號取 #1041 未釋出預約的最大＋1。存檔 75、golden schema 不動。
- 玩家 3 是 iPad (A16)（作者 10-28）；91.1 報告的 iPhone15,5 當作另一台。

**排程**：本任的巡邏（`trig_01Jpuzfkf7tVgTJsPgP9kQg8`）在交接時刪掉，新任自己排（約 45 分鐘一次）。

**第二十二次換手（2026-10-27 約 16:50 UTC，session_01YGNNunheBBBwyekk4Pq7b4 壓縮第 3 次 → 本任用 `create_session` 開的新規劃 session_01YGNNunBu1rxrPwN6bsA7g2，第 2 層）**。新任開工：讀第 1 節、這一段、下面「第二十一次換手之後」那段；#1041 從「遊戲規劃（session_01YGNNunheBBBwyekk4Pq7b4）壓縮第 3 次」（16:4x UTC）往後讀。和下面不同時以這段為準。

- **新規則（作者 2026-10-27「不顯示網站名稱」）**：作者給過一個整理交通開放資料的第三方網站。它的名稱與網址**哪裡都不寫**：repository、私庫、檔名、branch、PR、commit、#1041。要提就寫「一個整理交通開放資料的第三方網站」。有一個舊的遠端 branch（`claude/` 開頭、名字含那個網站、結尾 `-tdx-map`）帶著這個名字，session 沒有刪 branch 的權限，**請作者刪**；已關閉的 #1363 標題與內容已改掉。
- **這一任合的**（照 §1.2，記在 #1041）：#1355（Y，決策 437 垃圾車，main `b46fb0c4`）、#1360（AF，示範與挑戰關掉的功能總表 → NEXT_PRIORITIES §22.18，`a8955802`）、#1358（X，決策 436 月台小物，`dca2bb25`）、#1364（AG，TDX 即時資料類別對照 `docs/research/TDX_LIVE_DATA_MAP_2026-10-27.md`，`0f2a1cbc`）、#1367（AJ，新台幣研究 `docs/research/NT_DOLLAR_SWITCH_2026-10-27.md`，`d5310656`）。Y、AF、X、AG、AJ、AC 都已封存。
- **在跑的 session**（新任接手後用 `send_message` 告訴它們改向新任回報；共同規則：不動 #1342、私庫 #103，壓縮 1 次不接新工作、2 次停）：
  - **AB**：session_01YGNNumUf3EJH6FgPtuEpvW（Opus），**#1365**（決策 438、**存檔 75**，市區公車 GameCore），**ready**，head `98b673cf`，全 tier 綠。動存檔，**合併前要獨立審查**（下一項）。AB 已壓縮 1 次，只處理審查要的修改。
    - 平衡：AB 判 CONCERNS，規劃選 (a)：#2、#5 量市區路線時不算轉乘；加 #10「有轉乘的市區路線 ≤ 同走廊決策 400 接駁」。#10 小超（淨額 +0.8%、每人公里 +6%），判輕微 CONCERNS，接受，不改值。**PR 3 的觸發條件**：任一走廊的市區路線淨額超過接駁 10% 以上。都寫在決策 438。
  - **AB 審查**：session_01YGNNumdHxUmcMjMuG3ToUU（Opus），本任交接時開，只給 PR 號與 CLAUDE.md，結果留在 #1365 並 `send_message` 給新任。審過、沒有要改的就照 §1.2 合。
  - **AE**：session_01YGNNupMuLMyw9biXB952o2（Opus），**#1361**（決策 440），**ready**，head `dfd69a5c`，CI 綠。土地全給的台灣實景（舊存檔 `landBlocks == nil`、實景示範兩個、平溪線挑戰新局）也開道路與公車；只改 GamePresentation（`CountryLookup` 台灣 → `.available`，新局 `enableRoads`）。平溪線挑戰照開公車（五方在決策 440）。實機：主執行緒讀道路在 Linux debug 0.43 秒，裝置上 UNVERIFIED。
    - 碰到舊存檔，**獨立審查** session_01YGNNumNo4tKxtLBUCTgJnt（Opus，16:33 UTC 開）會在 #1361 留結果並回報。審過就合。
    - **順序**：AB（#1365）先合，AE 再 merge main（兩邊都改 `RoadsTurnOn.swift` 一帶，衝突就由 AE 解）。AE 已壓縮 1 次。
  - **AD**：session_01YGNNuoLcfAoBA6h9zn3q2t（Opus），決策 439，§22.16 列車的遮蔽陰影烘焙、夜燈、車窗與車身質感，一項一個 PR。**每個 PR 都要同時更新 `.claude/skills/rolling-stock/SKILL.md`**（§4「統一的夜間亮燈還沒做」那句、§6，加一行車頭方向幕；作者問「1357 還要吸收總結列車製作方式更新嗎」，規劃答由 AD 每個 PR 順手改，作者「好 照這樣做」）。合併前看 skill 有沒有跟著改。
    - 2026-10-27：第 2 項（遮蔽陰影烘焙）是 #1373（決策 439）。AD 壓縮過一次，做完就停；第 1 項（夜燈）、第 3 項（車窗與車身質感）未開始，從哪裡接寫在 `docs/decisions/439.md` 的「下一步」。
    - 2026-10-27：第 1 項（夜燈）由 AR（session_01YGNNumNuGqtdahN2CHsi39，決策 449，`claude/train-night-lights-ar`）做；沒做完的（遠景盒子車的燈與窗、更多方向幕、頭燈照地、隧道裡亮燈）寫在 `docs/decisions/449.md` 的「下一步」。
  - **AH**：session_01YGNNumzJG7K5DTHJpvMp7L（Opus），**#1366**（draft，決策 441），NEXT_PRIORITIES 10p：每個機廠旁的三股道檢修庫、彰化扇形車庫的轉車台。只改 GamePresentation，沒動 AD 的著色器檔。決策 441 已寫「實機要去哪裡看」。AH 已壓縮 1 次。
  - **AI**：session_01YGNNum4o6fTLwq4cU6JWQf（Sonnet），`claude/ui-text-no-usd`，地價說明 4 處的「美元」／"dollars" 改成只寫「$」（`PopTravel.swift:89`、`PopulationLegendView.swift:287`、`:432`、`Localizable.xcstrings`）。還沒開 PR。綠了就合。
- **新台幣**（作者 2026-10-27：「那要出幣值轉換嗎 設定頁面有新台幣」「我是說要出嗎」「那要先說明是美金嗎」「可是這樣未來更多玩家轉換不就更困難 現在只有50位玩家而已」）：
  - 規劃決定：要換成新台幣，**送 App Store 審查之前做完**（公開 TestFlight 10/31，App Store 約兩週後）。換之前介面只寫「$」，不說是哪國的錢（就是 AI）。設定頁沒有幣別選項（查過 main），也不加：只有一種錢。
  - AJ 的研究（#1367）建議 **B 案：NT$3＝$1**，所有錢的數字乘 3，舊存檔讀入時乘 3（`Money.init(from:)` 用 `@TaskLocal` 的倍數；`pricingBalance`（1<<60）不乘）。高鐵改用真實票價表（台北—左營 NT$1,490），要重新平衡。AJ 指出存檔換算是自動的，玩家多寡不影響換算成本；真正的成本是對外的截圖與評論。
  - 分四個 PR（細節在研究文件）：PR-0 GamePresentation 的金額格式整理；PR-1 GameCore（Opus，全 tier，重錄 9 個 replay，附腳本證明新值＝舊值 × 3，決策 442 起、存檔 76）；PR-2 高鐵票價與平衡；PR-3 介面「NT$」與繁中大數字。
  - AJ 留給規劃的兩題，本任的答案（五方：玩家不想在公開測試第一天看到錢突然變三倍；鐵道迷要真實票價；開發要等 AB 的存檔 75 落定；美術、音樂無）：
    1. 10/31 先帶「$」出去；AB、AE 合併後派 PR-0 與 PR-1；PR-1 在 10/29–30 修 bug 的時段之後、送 App Store 之前（約 11/14）合。
    2. 繁中大數字換成「萬／億」，放在 PR-3，送 App Store 之前。
  - PR-1 進行時，暫停合併會新增金額常數的 PR。號碼派工時再在 #1041 預約（決策取當時最大＋1，存檔 76）。
- **TDX**：AG 用 `tdx-check.yml` 查了基本與進階 API（不扣點），對照表在 `docs/research/TDX_LIVE_DATA_MAP_2026-10-27.md`；資料在私庫 #108（draft，`Railway/tdx-live-2026-10/`，8.5 MB，**作者合**）。找到的缺口（公車班表、票價、首末班）已交給 AB 的決策 438 下一步；捷運班距 TRTC／KRTC／TYMC／TMRT／NTMC；YouBike 6,799 站；停車場台北 673、高雄 757。
- **Y 的網站致謝**：垃圾車資料（`DataSourceCredits.taipeiGarbageTrucks`）與 Meshy 那行的 `credits.html` 在私庫 #106（draft，**作者合**）。
- **編號**：決策 436、437 用掉；438（AB）、439（AD）、440（AE）、441（AH）預約中；**下一個空的是 442**。存檔 75 給 AB，**76** 留給新台幣。golden schema 沒動。
- **還要看的**：main 下一次 full lane（4d5c7994 之後那輪，run 40530426324）三個 job 的時間（估 build ≈60／75、second ≈45／55、lessons ≈42／55）與 `ShellLayoutUITests.testTheStatusBarKeepsItsWidthAsTheDaysGoBy`。又紅就派人查，不是 runner 慢。
- **排程**：本任的 `send_later` 巡邏在交接時刪掉，新任自己排（約 45 分鐘一次）。Threads 排程已由本任改綁新任（第 1 節那列）。
- **等作者**：
  - 刪上面那個結尾 `-tdx-map` 的遠端 branch；合私庫 #106、#108（作者 10-27 已合）。
  - TestFlight 92 什麼時候發、公開連結的時間。
  - Meshy 約 49 點在 11/4 前用掉；TDX 11/1 重置。
  - 實機：E500 推拉、普悠瑪、AE 之後舊存檔的公車與道路、平溪線開局的延遲、AH 之後的機廠。
  - 玩家 1 的公車路線預覽截圖、91 的 fps 回報。

**第二十五次換手（2026-10-28 約 08:25 UTC，session_01YGNNupX9CPMXwaBoNU5tma 壓縮第 2 次、約 300k → 本任用 `create_session` 開的新規劃，第 1 層）**：和下面不同時以這段為準。

新任開工：
- 讀第 1 節與這一段。
- `create_session` 只帶得進 railway-game-ios，所以先用 `add_repo` 加 railway-reference-private 與 railway-assets-private。
- #1041 從「session_01YGNNupX9CPMXwaBoNU5tma 壓縮第 2 次」往後讀。狀態快照在 #1041 comment 6464024607。

**本任合的**（照 §1.2，記在 #1041）：#1404（ひと駅複查）、#1405（BJ Kenney 報告）、#1396（BD，full lane 時限）、#1406（BG，標線、人行道、小綠人）、#1403（BF，模型包瘦身）、#1400（BH，速度不倒回、示範背景讀道路）、#1407（BM，`run.sh --night-lights`）、#1411（NEXT_PRIORITIES 7c、7d）。main `ci.yml` 與 full lane 綠到 `8be2242`；#1400、#1407 這批（`12b5013`）合完還沒看到 `ci.yml` 結果，新任先看它綠了再合下一批。TestFlight 92 已發，出口合規已答。

**在跑的 session**（新任用 `send_message` 告訴它們改向新任回報；共同規則：不動 #1342、私庫 #103，壓縮 1 次不接新工作、2 次停）：
- **BK**（session_01YGNNun8RfEVUbCYxFcr7kV，決策 454，92.1 實景 81 站卡頓）：已找到
  1. 06:00 停 12–14 秒：`PassengerRouteMemo` 只記一張圖，凌晨的空圖把白天的圖擠掉。修法是多記上一張，結果逐位元相同，預計 1 秒內。PR 還沒開，請它先推。
  2. 6000× 時模擬 tick 平均 0.24 秒（預算 0.1 秒）：不在這次修，寫進 HANDOFF。
  3. 主執行緒 500 ms 停頓：`StationMasterView` 在主執行緒重算建議、舊世界副本在主執行緒釋放。**已由 #1415（派工單 BP，決策 459）修**：角落讀新聞已經算好的這一小時的建議，被換掉的世界在背景放掉；實機 UNVERIFIED。
  綠了照 §1.2 合，把 2、3 的結論轉告作者，然後封存。
- **台北地標**（作者開的 session_01YGNNupg9BaQswnXKhfrkdv，決策 457，#1409 draft；私庫 #115、素材庫 #13 由作者合）：作者要「你分別挑呈現出最好的…挑完再融合淡色」。第 3 版四欄對照（第 1 輪／Blender／上一版結合／新版）出來後用 `SendUserFile` 給作者看；作者滿意才 ready、合。之後同一路線更新既有的台北車站、101、高雄車站（決策 457「後來」），圖也要給作者看。
- **遠景方塊 instancing**（作者開的 session_01YGNNunmjyoeMSdTvYbyZJm，決策 455）：#1408（第一步）、#1410（第二步 Metal），都是 draft。ready 且綠就照 §1.2 合，#1408 先。
- **BL**（session_01YGNNuqUpKkygZmLQmiFyYw，素材庫與私庫照盤點刪檔 D1–D4、J2、J3、J10）：卡在要作者批准 `add_repo`（railway-game-ios、railway-reference-private）。請作者批准或回它；私庫的刪檔 PR 由作者合。

**等前一項合併再派**：
- Kenney 三件（針葉樹、灌木、儲槽）接進 `Map3DModelPack`：派工單 BN 做了（決策 458，`claude/kenney-trees-tanks`，PR #1417）；glTF-Validator 進 repo／CI 是加依賴，由作者決定（規劃另外問）。實作 session 壓縮兩次後停在這裡：#1417 若 CI 綠了還是 draft，由規劃（或接手的 session）改 ready、在 #1041 留「可合併」；七向圖在素材庫 PR a91453/railway-assets-private#17，作者合。
- J7：`site_archive_clean` 的路徑改到 `taiwan-rail-reference-clean`（Sonnet）：BK 合併後。
- 7d（NEXT_PRIORITIES §22.2）：`Map3DChineseRoof` 接進 civic-kit、residential-kit，把「zip 屋頂＋blender-buildings-v1 比例＋OSM 外框」寫進兩個 SKILL.md，補 §c.12 小口磚雙色、雨遮、冷氣室外機（Opus）：決策 457 合併後。
- 7c 第一批（Opus），有 Blender 參考的車站：臺中、新竹、花蓮、臺東、板橋、南港；高鐵桃園、新竹、台中含新烏日、台南、左營。作者看過台北這輪滿意才派；第二批（基隆、嘉義、臺南與老站、林鐵糖鐵站）最後。作者 10-28「好 照你的建議排」。
- 6000× 模擬效能：照 BK 寫進 HANDOFF 的那段。

**還要看的**：
- BH 跑 only_testing 時 `RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 紅過一次、重跑綠。下一輪 full lane 又紅就派人查。
- 下一版 What to Test 要放：#1403（第一次開 3D、記憶體）、#1406（標線、人行道、小綠人）、#1400（速度不倒回、示範不頓）。
- 審查點數從 #1386 起算，目前 11 點（docs PR 不算），滿 30 開下一輪審查。
- 編號：存檔 75 是 main 上最新；決策檔到 451，452–457 在 #1041 有預約（454 BK、455 遠景方塊、457 台北地標），新號取 #1041 未釋出預約的最大＋1。

**排程**：
- 本任的 `send_later` 巡邏在交接時刪掉，新任自己排（約 45 分鐘一次）。
- Threads 排程綁本任（`trig_0189X2fiQbWqxG8CCat2Lzbb`）。新任用同一份 prompt（`get_trigger` 讀得到）建一個綁自己的，再刪掉這個。
- 新任是第 1 層，之後照 §1 自己用 `create_session` 開下一任。

**第二十四次換手（2026-10-28 約 05:15 UTC，session_01YGNNupfaTiuQSAJ5tsf5a4 壓縮第 3 次後 → 作者在 claude.ai 手動開的新規劃）**：和下面不同時以這段為準。

新任開工：
- 讀第 1 節、這一段與下面的「第二十三任中途記錄」。
- 確認自己有 railway-game-ios、railway-reference-private、railway-assets-private 三個 repository。
- #1041 從「遊戲規劃（session_01YGNNupfaTiuQSAJ5tsf5a4）壓縮第 3 次」往後讀。
- 換手時在跑的，新任接著看：
  - **TestFlight 92**：作者 10-28 05:03 UTC 自己按的（run 40635737393，commit `e17eb67`，「我自己按了懶得等BD」），沒等完整 CI 與 full lane。跑完告訴作者結果，提醒在 App Store Connect 回答出口合規；PLAYER_FEEDBACK 記 92。請作者在實機看記憶體與第一次開 3D 的卡頓（K1-1 還沒修）。
  - **`e17eb67` 的完整 `ci.yml`**（run 40634094606）與 **full lane**（ios-build.yml run 40634118390）：作者要「綠了再跟我說」。紅了就照 §1.2 查是不是 #1396 那種 Runner 慢、Xcode 啟動逾時。
  - **BD**（session_01YGNNukhJnBuFzBv2ipaCEu，#1396，放寬 full lane second／lessons 時限）：為了讓 TestFlight 先跑，規劃取消了它的 only_testing 與 PR 的 iOS 檢查；它的排程（05:50 UTC）會在 TestFlight 跑完後重跑並回報規劃。綠了照 §1.2 合（發版已發，凍結解除）。
  - **BE**（session_01YGNNuqRXtKiryx6cvywWqR）：研究文件，用評分比較 Kenney、KayKit、Quaternius、Polyfork 與其他免費素材網站哪些適合這個專案。等它交 PR 號、前三名、授權疑慮，綠了合。
- **排程**：
  - 本任的 `send_later` 巡邏在作者開新任後刪，新任自己排（約 45 分鐘一次）。
  - Threads 排程現在綁本任（`trig_01LArs38ecmjdL3rJtNHDJxa`）。新任用同一份 prompt（`get_trigger` 讀得到）建一個綁自己的，再刪掉這個。
- **之後開新規劃**：照 §1 回到規劃自己用 `create_session` 開。新任由作者手動開，`lineage.depth` 以 `get_session` 讀到的為準，到第 7 層再請作者開。
- **審查點數**：從 #1386 起數。#1387、#1388、#1389、#1393 各 1 點，#1394 改 GameCore 2 點，共 6 點；滿 30 點開下一輪。
- **發版後要派**：
  - K2-3～K2-9、K1-1（審查交接檔）。
  - 資產盤點（不含發佈板）。
  - 免費素材試做：Kenney、KayKit、Quaternius、Polyfork，先參考 BE 的評分。每包先放授權全文與來源，判定能不能進遊戲；Quaternius 與 Polyfork 的檔案照 railway-assets-private 的 `AGENTS.md` 不再散布。

**第二十三任中途記錄（2026-10-28 約 05:00 UTC，session_01YGNNupfaTiuQSAJ5tsf5a4，壓縮 2 次）**：和下面不同時以這段為準。
- 本任合的：#1387（92 的 What to Test）、#1388（`-ui-testing-paused` 在 `-tutorial-step` 之後仍有效）、#1389（`rest` shard 重新分配）、#1390、#1392（審查 K2、K1）、#1391（素材改放 railway-assets-private）、#1393（BA，換公車模型後列車夜燈不亮，K2-1）。
- TestFlight 92：作者說 BA、BB 擋發版。BB 是 #1394（K2-2，#1385 乘客路線搜尋的記憶體上限）；合了之後在 main HEAD 手動跑完整 `ci.yml` 與 full lane，都綠才告訴作者「可以發」，作者說「發」才按 `testflight.yml`（§1.2）。
- #1394 留下的低優先（不擋發版，有玩家回報大路網卡頓再做）：合成 200 站比 #1385 的 main 慢約 40%（282 → 394 秒，仍比 #1385 之前的 1,061 秒快），記在 §5 AQ 那一列；Linux debug 下作者那局慢約 17%（53 → 62 秒，release 不變），原因多半是每次禁用搜尋都重新加總標籤數，改成逐次累加即可。
- **下一任規劃由作者在 claude.ai 手動開**（作者 10-28：「下一個遊戲規劃讓我自己手動開 因為我要把railway assets privacy 加入」「但只限下一次 加入後 後面規劃一樣照原本第7或8再給我就好」）：只有下一任這一次，因為 `create_session` 只能帶一個 repository，要讓新任一開始就有 railway-game-ios、railway-reference-private、railway-assets-private 三個。之後照 §1 換手，規劃自己用 `create_session` 開，到第 7 層才請作者開。
- 發版後要派：K2-3～K2-9、K1-1（審查交接檔）、資產盤點（不含發佈板）、免費素材（Kenney／KayKit／Quaternius）試做。

**第二十三次換手（2026-10-28 約 00:20 UTC，session_01YGNNunBu1rxrPwN6bsA7g2 壓縮第 2 次後 → 本任用 `create_session` 開的新規劃 session_01YGNNupfaTiuQSAJ5tsf5a4，第 3 層）**

換手時沒有在跑的派工 session，所以照 §1 在約 300k 之前提早換。

新任開工：
- 讀第 1 節與這一段。
- #1041 從「session_01YGNNunBu1rxrPwN6bsA7g2 壓縮第 2 次」（10-27 22:1x UTC）往後讀。
- 這一段和下面不同時，以這一段為準。

**本任合的**（都照 §1.2 合，記在 #1041）：

| PR | 內容 | main |
| --- | --- | --- |
| #1366 | AH，決策 441，機廠 | `34caf726` |
| #1369 | AI，介面不寫「美元」 | `f6767d56` |
| #1370 | Threads 交稿前去浮水印 | `27dcbba2` |
| #1365 | AB，決策 438，存檔 75，市區公車 | `00b172ec` |
| #1371 | AK，決策 442，實景台灣 22 縣市 | `573c5747` |
| #1361 | AE，決策 440 | `08e63ad3` |
| #1374 | NEXT_PRIORITIES §22.19 slop-taipei | `d66ea8cd` |
| #1373 | AD，決策 439，列車遮蔽烘焙 | `c059ea90` |
| #1375 | AN 研究，`docs/research/TAIWAN_STREETSCAPE_2026-10-28.md` | `e0e946cb` |
| #1372 | AM，TrainShowcase UI 測試 | `7a7736c2` |
| #1377 | AN，決策 445，行人號誌 | `353300d9` |
| #1376 | AL，改速度不丟 tick，決策 143「後來」 | `b7e11c0f` |
| #1378 | AP，決策 446，機車 | `909a8e20` |
| #1379 | AO，決策 447，路口標線 | `3545505b` |
| #1382 | 中途交接 | `f70a4cb4` |
| #1380 | AO，決策 447 續，巷子標線型人行道、騎樓 3.64 m | `8ecb9405` |
| #1381 | AS，決策 450，車窗反光與不鏽鋼光澤 | `9279b453` |
| #1383 | AR，決策 449，夜裡列車統一亮燈；AR 壓縮 2 次停手，規劃接手看 CI 後合 | `8d0f614d` |
| #1384 | AT，決策 451，3D 淡色調柔（融合版）、紅綠燈與平交道保留原色 | `ae88dee7` |
| #1385 | AQ，乘客路線搜尋加快約 6 倍、逐位元相同（GameCore） | `cdb5bba0` |

- #1362（Codex 台北捷運 610）是作者合的，main `7c160fad`。
- 最後一批是 #1383、#1384、#1385。下一批要等 main 的 `ci.yml` 在 `cdb5bba0` 轉綠。
- 本任開的派工 session 都已封存：AB、AD、AE、AH、AI、AK、AL、AM、AN、AO、AP、AQ、AR、AS、AT。

**編號**
- 決策 446、447、449、450、451 已用掉。
- 決策 448 沒用到，AQ 已釋出。
- 還預約著的：443、444（新台幣 PR-0、PR-1，存檔 76）。
- 下一個空的決策號是 **452**。
- 存檔 75 已被 AB 用掉，76 留給新台幣。golden schema 沒動。

**作者說過的話，本任記下的**（都在 #1041）：
- TestFlight 92：「晚點發」。等作者說了才準備；還沒說。
- 公開 TestFlight 連結：維持 10/31 0:00（台灣時間）。
- Meshy：剩下的點數「暫時不需要」，不派 Meshy 的工作。
- Threads：
  - 91.1 那篇已在 10-27 21:00（台灣時間）發出。
  - 排程的基準是 main `1bfc97d`。
  - 交稿前要用 watermarks-remover 去浮水印（`docs/research/THREADS_WRITING.md` §2）。
- 新台幣 PR-1：要在寫實與簡單兩種規則的存檔上都證明「新值＝舊值 × 3」，兩種規則也都要看平衡。
- slop-taipei：
  - 順序寫在 NEXT_PRIORITIES §22.19：AN → AO → AP → 基隆河的橋。
  - 前三項已合，基隆河的橋還沒派。
- TDX：
  - 歷史資料已在私庫 `Railway/tdx-snapshot-2026-10/`，**不要整段重抓**。
  - 只補 10/27 以後的新日子，一天約 0.65 點。
  - 公車與捷運用 `$top` 抽樣。
- 6000×：維持，五方在 #1041。#1385 合了之後，06:00 的 tick 在 Linux release 從 32.5 s 降到 5.2 s。
  - 請作者在下一版 TestFlight 用高雄那局（私庫 branch `bug-reports/clock-stuck-2026-10-27`）重看。
  - 還跟不上，就派「跟不上時狀態列顯示實際倍速」，只改 GamePresentation。
  - 剩下的加速方向寫在 §5 的 AQ 列。
- 淡色：作者說「好 就融合版」（決策 451）。淡色和原色的繪圖負擔一樣。實機若還嫌淡，就往原色調 `Map3DLook.city`／`close` 的常數。

**排了、還沒派**
- 基隆河的橋（§22.19 第 4 項）。
- 決策 445 的下一步：音響號誌、行人先行、紅燈倒數、依路寬算閃爍時間。
- 決策 446 的下一步：人行道上的停車、改成模型包的實例。
- 決策 447 的下一步：路口鋪面、路名牌、公車站周圍紅線、路面文字。
- 決策 449 的下一步：隧道裡亮燈、頭燈照地、遠景盒子車的窗（`docs/decisions/449.md`）。
- 新台幣 PR-0、PR-1（決策 443、444，存檔 76）：10/29–30 修 bug 的時段過後、送 App Store（約 11/14）之前派。

**等作者**
- 刪三個遠端 branch：
  - `claude/old-taiwan-roads-pending`；
  - `claude/old-taiwan-roads`；
  - 結尾 `-tdx-map` 的那個。
- 私庫的預覽 PR #111（決策 451 的全部預覽）是草稿，等作者決定要不要合。
- TestFlight 92 的時間。
- 實機要看的：
  - AE 的道路與平溪線開局；
  - AH 的機廠；
  - 離島；
  - AD 之後 3D 開啟多 0.34 s；
  - AN 的行人號誌與幀數；
  - 高雄那局 06:00 的停頓（#1376、#1385）；
  - E500、普悠瑪；
  - 夜燈（#1383）、車窗反光（#1381）、融合版淡色（#1384）。

**排程**
- 本任的 `send_later` 巡邏，等新任排好自己的才刪。
- Threads 排程 `trig_01KEzqJPTdvXeUFCNUy8go3Z` 綁本任。本任用同一份 prompt 建一個綁新任的，再刪掉它；新的 id 記在 #1041。

**第二十一次換手之後（規劃 session_01YGNNunheBBBwyekk4Pq7b4，2026-10-27 15:10 UTC 更新）**。這一任由前任用 `create_session` 開（第 1 層），14:3x UTC 接手；前任 session_01YGNNuovwuBJPdZWXamkhEp 已封存。下一任接手時讀第 1 節、這一段、下面第二十一次那段；#1041 從「遊戲規劃（session_01YGNNunheBBBwyekk4Pq7b4）壓縮第 1 次」（14:56 UTC）往後讀。和下面不同時以這段為準。

- **合併了**（都照 §1.2，記在 #1041）：#1353（Z，市區公車與鋪路設計，main `62d07104`）、#1350（列車展示點擊層，`16a1fa8e`）、#1354（AA，台鐵誤點分析，`ee9ee88d`）、#1351（full lane 重新分配，`ecba996a`）。Z、AA 已封存。
- **還要看的**：main 下一次 full lane 三個 job 的時間（估 build ≈60／75、second ≈45／55、lessons ≈42／55），以及 `ShellLayoutUITests.testTheStatusBarKeepsItsWidthAsTheDaysGoBy` 會不會又紅。又紅就不是 runner 慢，要派人查。
- **在跑的 session**（完成或卡住時用 send_message 回報給規劃；規則同下面 X、Y）：
  - **X**：session_01YGNNupvEG51nsSxuFBEV7j，決策 436，3D 月台小物。14:48 UTC 壓縮第 1 次，不再接新工作。
  - **Y**：session_01YGNNumE4CxFH7Ph9aNZWQh，決策 437，傍晚的垃圾車，draft #1355（私庫那半是 railway-reference-private#105）。
  - **AB**：session_01YGNNumUf3EJH6FgPtuEpvW（Opus），決策 438、**存檔 75**，市區公車的 GameCore（#1353 設計的 PR 1）。綠了**先開獨立審查 session**（只給 PR 號和 CLAUDE.md），審過才合。
  - **AC**：session_01YGNNupqwZ1Fm3WTAm4Hfz5（Sonnet），`claude/train-model-kit-ac`，共用的做車工具與 rolling-stock skill 改寫（NEXT_PRIORITIES §22.16 第 4 項）。決策原則上不動。
  - **AD**：session_01YGNNuoLcfAoBA6h9zn3q2t（Opus），§22.16 第 2 → 1 → 3 項（列車遮蔽陰影烘焙、夜燈、車窗與車身質感），一項一個 PR，拍圖用 AC 的工具。決策預計 439。作者：「沒差能做就先做」。
- **編號**：決策 439 預計給 AD，下一個空的是 **440**；存檔 **76**（75 給 AB）；golden schema 沒動。
- **審查分工**（作者問「檢視pr 要你跟session都開嗎」，規劃決定，五方在 #1041）：
  - 規劃只做 §1.2 的合併檢查，不逐行審。
  - 審查點數滿 30 時，另開審查 session（#1288 起到 15:00 UTC 約 20 點）。
  - 動到存檔、帳號、隱私、權限、伺服器或付費的 PR，合併前另開獨立審查。
- **Threads**：改成看進度才寫（第 1 節那列），恢復了。`docs/research/THREADS_WRITING.md` 已跟著改。
- **巡邏**：用 `send_later` 一條接一條，約 45 分鐘一次；每次觸發後先排下一次，再刪用過的。換手時新任排自己的，舊的刪掉。
- **排了、還沒派**：
  - §22.17 是 AA 建議的兩張：本週準點率 3.20；停站抖動加設備事故 2.90，要升存檔。都排在 10/31 之後，PR 2 要等 AB 合併、存檔 75 落定。
- **等作者**：
  - 91.1 實機確認：E500 推拉、普悠瑪、舊存檔的公車與道路。
  - 決策 440（#1361）實機確認：平溪線挑戰與實景示範開局時在主執行緒讀車站周圍的路（Linux debug 134 塊 0.43 秒），實機開局會不會多卡；作者 10/12 的平溪線存檔按「打開道路與公車」後讀到街道、可開公車。
  - 玩家 1 的公車路線預覽截圖。
  - 91 的 fps 回報。
- **作者問過、答了、沒有要做的**：
  - geoBoundaries 等邊界與名稱來源：OSM、Wikidata 已在用；Natural Earth 可用；Census、ONS 等 §22.2 第 24 名才用；geoBoundaries 是 CC BY-SA，先不用。
  - 作者錄的「實際地圖」畫面：那是另一個 app 用 Apple 地圖的 3D 實景，不是開放資料。遊戲不改用它：拿不出來給自己的 3D 城市用，畫風也不合。
  - 推之前本地跑什麼：照 CLAUDE.md，只跑快的檢查，不改規則。

**第二十一次換手（2026-10-27 約 14:25 UTC，session_01YGNNuovwuBJPdZWXamkhEp 續任後壓縮第 4 次 → 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段、下面第二十次那段（含「續任」）；#1041 只讀「遊戲規劃（session_01YGNNuovwuBJPdZWXamkhEp）壓縮第 4 次」（14:11 UTC）那則之後的留言。和下面不同時以這段為準。

- **分工改了**：作者 14:1x UTC 說「又要開什麼新session 就開」「要派session就派」，所以規劃自己用 create_session 開實作 session，不必等作者說。派工單的寫法照下面 X、Y、Z、AA。模型照 §1.1 依難易度選 Sonnet 或 Opus；X、Y、Z、AA 開的時候還沒有這條，都是 Opus。下一任規劃也可以由規劃自己開（§1.1；本 session 是第 0 層）。Claude Pro 只在這個帳號額度不夠時才派（作者：「Pro等不夠的時候再用」）。Pro 派過的 M2、N、T、V、M3 都有在 #1041 登記、留壓縮和「可合併」，也都寫了 HANDOFF。
- **不能動**：Codex #1342（C371／C381）和私庫 PR #103（同一件的私庫那半）。作者：「除了pr1342 跟隱私資料夾103不能動」。
- **開著的 PR**（都是本任開的；綠了照 §1.2 合併）：
  - **#1350**（`claude/showcase-tap-back`，head `0e2689aa`）列車展示：隱藏按鈕後點畫面，按鈕回來（決策 434 修正）。和 idle mode 的幕一樣，隱藏時蓋一層透明的點擊層（`trainShowcase.reveal`）；隱藏時不能轉鏡頭。換手時 PR 的 CI 和手動 `only_testing=TrainShowcaseUITests` run 40516816314 都還在跑。綠了：把 run 號寫進 PR 說明，轉 ready，合併；紅了就查。
  - **#1351**（`claude/full-lane-rebalance-1027`，head `b6a8b88f`）full lane 重新分配。build job 的 UI 步驟撞到 75 分鐘上限：五輪裡 build 52.4–75.2 分、second 26.9–34.2、lessons 31.4–37.7。所以把 `HUDAlignmentUITests`、`LineDraftSummaryUITests` 移到 second，`LineRoutePreferenceUITests` 移到 lessons。用同五輪估的最壞值：build 約 60.6／75、second 44.8／55、lessons 42.3／55。只改 workflow，綠了就合；合併後 main 的下一次 full lane 驗證三個 job 的時間。
  - `ShellLayoutUITests.testTheStatusBarKeepsItsWidthAsTheDaysGoBy` 在 91 的 full lane 判斷是 runner 慢。下一次 full lane 它若又紅，就不是 runner 的問題，要查。
- **在跑的 session**（本任 14:09–14:12 UTC 用 create_session 開的，都在 #1041 登記了。共同規則是：不動 #1342／私庫 #103，壓縮 1 次不接新的、2 次停。完成或卡住時用 send_message 回報給 session_01YGNNuovwuBJPdZWXamkhEp。**新任接手後，用 send_message 告訴這四個 session 改向新任回報**）：
  - **X**：session_01YGNNupvEG51nsSxuFBEV7j，`claude/platform-props-436`，**決策 436**。3D 月台近景小物：停車位置標、月台邊燈、回收桶、台鐵車頭方向幕（NEXT_PRIORITIES §22.15 第 1 項），在 GamePresentation／Map3D。
  - **Y**：session_01YGNNumE4CxFH7Ph9aNZWQh，`claude/garbage-truck-437`，**決策 437**。傍晚的垃圾車與資源回收車：〈給愛麗絲〉用決策 343 的合成器做，車用 Meshy 垃圾車模型（§22.12 第 2 項）；會加模型並重產 `.xcodeproj`。
  - **Z**：session_01YGNNup4WomZDkri2osruHG，`claude/city-bus-roads-design-z`。獨立市區公車與玩家鋪路的設計研究（§22.13 第 2、3 項），只寫文件。
  - **AA**：session_01YGNNuodq14g1Y2MbNjvt3U，`claude/tra-delay-analysis-aa`。用私庫 341 天的台鐵誤點算真實分布，對照遊戲的誤點，只寫文件和 `tools/tra-delay-analysis/`（不放原始資料）。
- **編號**：決策 436、437 已預約，下一個 **438**。存檔 74、golden schema 都沒動。
- **巡邏排程**：本任的 `trig_014rH8DLdKX6xgyXaEAvJ9pz` 綁本 session。新任建自己的巡邏（約 45 分鐘一次），在 #1041 留「遊戲規劃接手」後，本任刪掉自己的排程。
- **點數**：Meshy 剩 99（留 50，可用約 49），11/4 重置；TDX 11/1 重置。M3 之後，TDX 扣點的事都做完了；「不扣點清單」（M3 第 4 步，`tools/not_fetched_yet.json`，約 52 個 run，要放新資料夾）還沒抓，適合在額度不夠時派給 Pro。
- **下一步候選**（空出位置時）：
  - 91 的 fps：等作者在裝置上的回報。
  - Meshy 剩下的點數：11/4 前用掉。
  - TDX 不扣點清單。
  - 車輛包的 3D 預覽：10/31 後，用 `Map3DShowcase`。
  - §22.12 第 3–5 項：地標、機車、夜市攤車，用 Meshy 的模型。
  - §22.14 第 3 項：車窗雨滴。
  - X、Y、Z、AA 的 PR 照 §1.2 審、合。

**第二十次換手（2026-10-27 約 13:20 UTC，session_01YGNNuovwuBJPdZWXamkhEp 壓縮 3 次、用了約 29 萬 token，照 §1「第 3 次壓縮快到時換」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「遊戲規劃（session_01YGNNuovwuBJPdZWXamkhEp）壓縮第 3 次」那則之後的留言。分工照第十九次換手：寫派工單 .md（SendUserFile）給作者貼到 Claude Pro、Antigravity 或 Codex；作者說「直接開新session」時才用 create_session 開（本任的 U、W 是這樣開的，兩個 session 已封存）。和下面不同時以這段為準。

- **續任**：寫完這段後，作者說「你可以先全面接管了」，本 session 繼續當規劃，到第 4 次壓縮前再換手。續任後 91 的 full lane（run 40502803331）紅了兩支：`TrainShowcaseUITests` 是真的 bug（隱藏後點畫面，按鈕不回來），修在 `claude/showcase-tap-back`；`ShellLayoutUITests.testTheStatusBarKeepsItsWidthAsTheDaysGoBy` 判斷是 runner 慢（這輪測試總時間 4304 秒，前三輪 3004 到 3681 秒）。
- **這一任合的**：#1336（派工單 S，決策 432）、#1340（派工單 T，決策 433）、#1339（Codex，EMU900 模型）、#1343（派工單 V：速度選單共用的 `chooseSpeed`，StartSaveFlow 的原因寫在 #1343）、#1344（派工單 U，決策 434：演示模式的「列車展示」，`Map3DShowcase`／`TrainShowcaseScreen`）、#1345（What's New 與 `.github/testflight-whats-new.md`，本任合）、#1346（派工單 W，決策 435：EMU900 接進 3D，區間車照 `Map3DTrainSet.localTrain(number:)` 9:6:5 分 EMU900／EMU500／EMU800，真車十輛；決策 432 的單雙號規則被取代）、#1347，和文件 #1335、#1337。
- **TestFlight 91**（0.5.0 (91.1)）：main `1bfc97d`，`testflight.yml` run 40503126701 是**作者自己按的**（「跟昨天一樣 我先按 自己測」），full `ci.yml` run 40502799356 綠。full lane run 40502803331 換手時 iPad、second、lessons 都綠，build job 還在跑：**新任先看它**，紅了照 §1.2 和前一個 full lane（a3adcbe0，run 40495033681 全綠）比，告訴作者會不會影響 91。發版記錄在 `docs/research/PLAYER_FEEDBACK.md` 的「0.5.0 (91.1)」，回饋表還空著。
- **開著的**：Codex #1342（C371／C381 靜態模型，draft），作者決定要不要。
- **已派、作者拿著派工單**：派工單 M3（TDX 第三批，Claude Pro Sonnet）：高雄捷運 LiveBoard 平日假日各一天；市區公車取樣進私庫新資料夾 `Railway/tdx-bus-history-2026-10/`（上限 100 MB）；台鐵誤點從 2026-01-14 往前補到 `tdx-snapshot-2026-10/` 滿 300 MB；再來是 `tools/not_fetched_yet.json` 的不扣點清單。TDX 點數 11/1 重置，餘額由作者看。作者決定 TDX 先於 Meshy。
- **下一步候選**（五方排過，依序）：
  1. 91 的幀數：新近景模型很重（EMU900 是原本的 3.4 倍、EMU800 3.8 倍、C341 1.76 倍、莒光 4.4 倍）。作者回報卡的話，先縮短近景距離，或加一層中景。
  2. Meshy 剩約 104 點，11/4 重置前用掉；幀數確認後再做「Meshy 小物接進 3D 街景」。
  3. 真車車間 0.6 m 間隙（W 提的）；EMU700 還沒有模型。
  4. 10/31 後列車包購買頁的 3D 預覽：直接用決策 434 的 `Map3DShowcase`（輸入是要擺哪些車，不綁演示模式）。
  5. 11/1 後整理 TDX（誤點分布、路線形狀），不扣點。
  6. 沿用：台南地下化的舊 `tra.json`、E1 延後。
  - 不做：NEXT_PRIORITIES §22.14 第 2 列「慶祝的粒子效果」（五方 2.55，比同時段其他項的 3.50 低）。
- **號碼**：決策 433、434、435 用掉，下一個 436（先看 #1041 有沒有人預約）；存檔 74、golden 74 不動。審查點數約用 14／30。
- **排程**：本任的巡邏 trigger 換手時刪了，沒有留別的；新任自己建（約 40–50 分鐘一次）。

**第十九次換手（2026-10-27 約 05:40 UTC，session_01YGNNuoQekRm2qcVxoPT8ME 壓縮 2 次、用了約 30 萬 token，照 §1「第 3 次壓縮快到時換」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「遊戲規劃 session_01YGNNuoQekRm2qcVxoPT8ME 壓縮第 2 次」那則之後的留言。分工照第十八、十七次換手（不開實作 session，寫派工單給作者貼到 Claude Pro、Antigravity 或 Codex，規劃只審，綠了照 §1.2 合）。和下面不同時以這段為準。

- **新規則**：PR 綠了就不再推小修（§1.2「PR 綠了就不再推小修」）。本任在綠了的 #1325 推了一個 HANDOFF 的錯字與 workflow 說明，CI 整套重跑，作者不高興。
- **這一任合的**（main 的 `ci.yml` 在 de09b0c（#1326）的 push run 綠）：
  - #1319（派工單 I，決策 428：舊存檔可以打開道路與公車）；
  - #1324（派工單 K，決策 429：路口號誌分 4 組錯開相位，週期 70 秒）；
  - #1312（Codex，EMU500）、#1320（Codex，EMU800）、#1323（Codex，C341）：都只加模型。#1323 和 #1312 在 `Map3DModels.swift` 的註冊順序衝突，本任合 main 解了：EMU500 在前、C341 在後，市區公車照舊最後；
  - #1326（派工單 L，決策 430：莒光號的五個列車組換成 #1306 的莒光自動門客車，最後一節加尾燈，各加遠景版），作者自己合的。客車近景 6,476、遠景 4,008 個三角形，十二節一列近景是原本的 4.4 倍；幀數 UNVERIFIED，太重的話下一步是更輕的遠景客車或縮短遠景距離。
- **等合的：#1325**（派工單 M 的前置：`tdx-check.yml` 放行 `/api/historical/`，CLAUDE.md 加 `Railway/tdx-snapshot-2026-10/`，HANDOFF 加一行），head 50175eab368788e5a9edab93f07ff79f1273cf40，已 ready，本任審過。
  - 改了 workflow 檔，所以 Xcode build 也跑。04:30 那輪紅在 `StartSaveFlowSmokeTests.testBackToStartWorksWithLargeTextWhileTheClockRuns`（`StartSaveFlowSmokeTests.swift:554`「Missing menu row: menu.saveGame」，run 40450049689）。這個 PR 不碰 App，同一個測試在 #1326 那輪是綠的；本任 05:15 按了一次 Re-run failed jobs（照 §1.2 只按一次）。
  - 重跑綠了：iOS 綠之後 gate 不會自己變綠，對 CI 那一輪（run 40450049714）再按一次 Re-run failed jobs，綠了照 §1.2 合。
  - 重跑還紅：這個測試是真的壞了，不是這個 PR 的；寫派工單修它（下面「不穩的 UI 測試」）。作者要先合 #1325 的話，告訴作者紅的原因，由作者決定。
  - **要趕**：TDX 的訂閱點數 11/1 重置，派工單 M 抓歷史誤點資料要靠這個 PR。
- **派工單（作者手上有原文，本任的 scratchpad 新任拿不到）**：
  - **M**（Claude Pro，Sonnet）：TDX 點數 11/1 重置前，把參考庫還沒有的鐵道資料抓進私庫 `Railway/tdx-snapshot-2026-10/`。用 `tdx-check.yml`（金鑰是 repository secrets，session 不用看到），一次一個路徑，最多同時 3 個。扣點的優先：台鐵、高鐵的歷史誤點，再來線形、車站出入口與設施。遊戲 repository 只開文件 PR。#1325 就是它的前置。
  - **N**（Claude Pro，Sonnet）：Meshy 點數 11/4 重置前，用文字轉 3D 做一批遊戲還沒有的街景與鐵道小物（平交道、號誌機、車擋、機車三款、垃圾車、夜市攤車、街角小物），放私庫 `Railway/meshy-batch-2026-10/`，不接進遊戲。登入用 `meshy auth login --device`，不用金鑰；花點數前報一次價，留 50 點。不上傳參考庫的圖或模型（art-style §7）。作者問過要不要拿 Meshy 重做現有模型：本任答不用，只做沒有的。
  - **O**（Antigravity，Gemini 4.0 Pro，作者問「中還是高」，本任答高）：3D 地圖放上高雄車站，決策 **431**（本任已在 #1041 預約），branch `gemini/kaohsiung-station-431`。在 `Map3DTaipeiLandmark` 加 `kaohsiungMainStation`；規格從 osmtoday 的 OSM 檔讀；只做新站房、天棚、舊站房，商辦與旅館大樓不做；近看 ≤6,000、遠看 ≤2,500 個三角形；預覽放私庫 `Railway/game-art-previews/docs/art/kaohsiung-station-2026-10-27/`。
  - 換手時 M、N、O 都還沒有 PR。PR 來了照派工單的驗收審。
- **決定了的**：
  - §22.14 第 2 項慶祝粒子：**不做**（五方加權 2.55，比同時段其他項的 3.50 低），動態規則不變。已記在 #1041，NEXT_PRIORITIES 還沒改：下一個規劃的文件 PR 順手把 §22.14 第 2 項標成「不做（2026-10-27）」。
  - 作者貼來的 Grok Bot 與各家訂閱的分析：現在不訂 Grok。
- **不穩的 UI 測試**：`StartSaveFlowSmokeTests.testBackToStartWorksWithLargeTextWhileTheClockRuns` 紅第二次（上面 #1325）。#1325 的重跑若還紅，就照 #1315 的寫法（讀到連兩次一樣的畫面再點）寫一張派工單，和下面列的 `LessonUITests.swift:619`、`RealWorldMapUITests.swift:797`、`TutorialJourneyUITests.swift:213` 一起改。
- **封存不了的 session**：session_01JMHz9ak2m1w5LYWDgoQWqS（派工單 I）、session_01JMHz9YG6gwHn5qzj9T7myX，`get_session` 都說找不到，應該是作者 Claude Pro 帳號的 session。請作者自己封存。
- **號碼**：決策 428、429、430 已用，431 給派工單 O；下一個可用的是 432，取之前再查一次 #1041。存檔版本 74，golden schema 74，都不動。
- **審查點數**：從 #1288 起數，約 10 點（加了 #1319、#1324、#1326），還沒到 30。
- **排程**：本任沒有還會觸發的排程，`list_triggers` 是空的。每日 Threads 排程照舊暫停。
- **TestFlight 91**：作者還沒說要發。

**第十八次換手（2026-10-27 約 02:10 UTC，session_01CWaJGHR4DnSwosLCzJ2Tts 壓縮 3 次，照 §1 換 → 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「遊戲規劃 session_01CWaJGHR4DnSwosLCzJ2Tts 壓縮第 3 次」那則之後的留言。分工照第十七、十六次換手（不開實作 session，寫派工單給作者貼到 Claude Pro 或 Antigravity，規劃只審、小修自己推、綠了照 §1.2 合）。和下面不同時以這段為準。

- **本任合併的**（都照 §1.2，每個在 #1041 有一則）：
  - #1286、#1287（派工單 A、D）；審查 J 三段：#1290（J1）、#1293、#1297、#1298（J2 與疑點已修）；#1295（派工單 E，決策 424 續修）；#1300（決策 424 續修二，3D 公車在背景排）。
  - TestFlight 90：#1301（What's New）、#1303（PLAYER_FEEDBACK 記 0.5.0 (90.1)）。
  - Codex 的模型：#1291（PP 客車）、#1292（TEMU2000）、#1296＋#1302（E1000，決策 425：推拉式自強號改兩端 E500，E1000 留著）、#1306（莒光客車）、#1307（TEMU1000 車頭）。
  - #1304（TW3D 參考包列進 CLAUDE.md）。
  - #1308（派工單 F，決策 426：3D 普悠瑪接上 TEMU2000，`centreCars` 掛鉤）。
  - #1313（PLAYER_FEEDBACK 90.1 回饋，NEXT_PRIORITIES §22.13）。
  - #1314（派工單 G，決策 427：列車包的 E1000 經典外觀開關，預設 E500，每一列都換）。
  - #1315（派工單 H：狀態列 6000× 測試改穩。原因：iOS 26 的 Menu 會重建選項列，測試拿著已經不存在的元素（kAXErrorInvalidUIElement）；改成讀到連兩次一樣的畫面再用座標點）。
  - #1317（§22.14，另一款鐵道 App 致謝頁的五方評分）。
- **main**：`ci.yml` 在 fba9303（#1306）push run 綠；86bbb7e（#1317）的 push run 換手時在跑（#1315 的被它取代，是正常的）。
  - full lane 在 1b40e4f 紅兩次（run 40396358204、40413958561）。兩次都紅了 #1315 修的那支；第二次還多紅一支 iPad 的 `TutorialJourneyUITests/testTheWholeTutorialOnAnIPad`，原因還沒查。
  - d7f1b47（#1314）的 full lane run 40434847565 換手時在跑。新任看結果：綠了就是 #1315 的真證明；還紅就照 §1.2 比對。
- **還開著的 PR**：
  - #1311（Codex，EMU3000 黑色改石板藍灰，ready）：HANDOFF.md 的衝突本任用合併 commit 566861d 解了，兩段都留。換手時 CI 在跑；只改模型配色，作者說合才合。
  - #1312（Codex，EMU500 研究，draft）：作者沒說就不動。
  - Codex 另外登記了 EMU800 原生模型（`codex/emu800-native-2026-10-27`），PR 還沒開；作者直接派的，照舊作者說合才合。
- **派工單 M（TDX 資料下載，session_01JMHz9cdHzysPWNWgnQK685，2026-10-27）**：資料在私庫 `Railway/tdx-snapshot-2026-10/`（台鐵、高鐵、台北捷運的線形、出入口、站內設施；還沒接進遊戲）。**台鐵歷史誤點（唯一扣點、11/1 重置）已抓 90 天**：2026-07-29 到 10-26，24 個檔、6,443,530 筆、gzip 後 77.5 MB（`TRA_LiveTrainDelay_*.jsonl.gz`，每行 `TrainNo`／`StationID`／`DelayTime` 分鐘／`SrcUpdateTime` UTC）；用 #1325 放行的 `/api/historical/`，`Dates=a~b` 範圍可用，4 天一段。10/23、10/24 兩天的筆數明顯少，原因不明。實際扣了多少點不知道（workflow 看不到餘額），作者可比對 TDX 會員頁的餘額。**派工單 M2（同一個 session，11/1 前第二批）又往前補到 2026-01-15**：49 個檔、13,895,457 筆、gzip 170 MB，合計 285 天（01-15 到 10-26，沒有缺天）、約 247 MB，私庫資料夾 238 MiB／300 MB；含春節 2/14–2/22（筆數正常）。筆數明顯少的天：07-11（20,300，最少）、05-02／05-03、04-04／04-05、06-20、06-01、02-04、04-02，原因不明；誤點特別多的天：03-27（55.8% 的事件誤點）、06-18、06-26。更早的日子沒抓（平台約可回溯 550 天，每天約 0.9 MB，資料夾還剩約 60 MB 的位置）。M2 的第 1 步探路已做（`tools/historical_probe.json`）：市區公車 A1（`Bus/RealTimeByFrequency/City/*`，有車速）與 A2（`RealTimeNearStop`）台北、新北有，高雄有但晚幾天（10-26 是空的，10-20 有）；N1 預估到站與台北捷運看板沒有（`LiveBoard` 只收 TYMC／KRTC／KLRT）；高雄捷運 `LiveBoard`、台鐵 `LiveBoard`、國道車流有。**派工單 M3（同一個 session 之後的 11/1 前第三批，session_01JMHz9ZGciiRn5MtAnctD5W，2026-10-27）做完扣點的部分**：
  (1) 高雄捷運 `LiveBoard`：週三 10-21（51,582 列）和週六 10-24（51,104 列）進 `tdx-snapshot-2026-10/`；一天約 19.6 MB 原始、0.4 MB gzip、一個 run、約 20 秒，一天在 `$top=1000000` 內抓得完。
  (2) 市區公車：新資料夾 `Railway/tdx-bus-history-2026-10/`（8 個檔，79.9 MB／100 MB），台北週三 10-21、週六 10-24，高雄週四 10-15、週日 10-18，A1（取 40 萬列）與 A2（取 30 萬列）。**歷史 API 不能過濾**：`$filter`（含巢狀欄位、`RouteUID` 加 `Direction`）、`$select`、`$skip`、`RouteName=` 都被忽略，路線放進路徑是 404；有用的只有 `Dates`、`$top`、`$format`。所以「台北、高雄各 5 條經過大站的路線」做不到，樣本是平台回的前 N 列（時間橫跨整天，但不是整天；列的順序隨 `$top` 變，不能重抓來延伸）。台北 A1 一天超過 100 萬列（超過 29 MB gzip，抓 100 萬列約 4 分鐘），一整天就裝不進 100 MB；高雄 10-18 的 A2（257,359 列）是完整的一天。台北 A1 10-21 是那個 100 萬列探測的前 40 萬列。每個檔的路線在 `tools/sample_routes.json`；有沒有經過台鐵或捷運站沒查。
  (3) 台鐵歷史誤點往前補：14 個 4 天檔，2025-11-20 到 2026-01-14（56 天、4,051,075 筆、49.5 MB），合計 341 天（2025-11-20 到 2026-10-26，沒有缺天，接縫 01-14 15:59:53 UTC 到 16:00:05 UTC 乾淨）、24,390,062 筆、296.9 MB gzip；私庫資料夾 298.65 MB 十進位（`du -sh` 286M），停在 300 MB 之前。新增這段沒有明顯少的日子（最少 12-01：67,051 筆，是中位數 72,288 的 93%）；誤點最多的日子：12-06（54.1% 的事件誤點、84,483 筆，最大 266 分）、01-09、12-24；最大單筆誤點 12-26（568 分）。平台在 11-20 還有資料，只是資料夾滿了，再往前要新資料夾。
  (4) **不扣點清單沒做**（`tools/not_fetched_yet.json`：其他七家捷運與輕軌各七種資料、台鐵 `TrainType`、`Line`、高鐵 `Station`，約 52 個 run）；快照資料夾只剩 1.3 MB，要放新資料夾。不扣點，11/1 後也能抓。
  點數：沒有作者給的前後讀數，M3 用了幾點不知道（31 個 run：2 天捷運看板、8 個公車探測、7 個公車樣本、14 個台鐵區段；其中一個探測抓了 100 萬列）。M、M2 的點數也不知道（作者說的 190 是 10-26 的讀數，不是 M2 的起點）。私庫 draft PR #100（M、M2）、#104（M3）。高鐵沒有歷史誤點（404）。
  建議下一步：用歷史誤點校正誤點分布，用線形校正路網；公車若真要依路線取樣，要先把 `tdx-check.yml` 的讀取時間拉長整天抓下來再離線切（整天約 30 至 120 MB gzip；不在 M3 範圍，沒改 workflow）。
- **派工單 N（Meshy 小物，session_01JMHz9YNsEBucukq6a1ujJ1，2026-10-27）**：17 個文字轉 3D 的模型在私庫 `Railway/meshy-batch-2026-10/`（鐵道號誌與平交道警報、機車三款、垃圾車與資源回收車、夜市攤車與帆布與燈泡串、天公爐、紅燈籠、紅綠郵筒、站牌柱、兩款腳踏車），**還沒接進遊戲**。有兩組：`glb/` 是低面數版（smart topology，約 270–1,430 面，缺點多），`glb-hq/` 是高品質版（標準模式，8 萬到 68 萬面，最大的 7 個已 remesh 到約 10 萬面；**挑選用這一組**）。下一步：**照私庫 `INTEGRATION_HANDOFF.md` 做**（怎麼拿檔案、`front`／`length_m`、每個模型要處理什麼）。已實測：`tools/glb-to-m3dmodel/convert.mjs` 收有貼圖的 Meshy GLB 並自己取色（8 色以內），低面數版 `glb/` 直接轉得成；高品質版因為超過 15,000 面被拒絕、而且轉換器不減面，所以缺的只有「把 `glb-hq/` 減到預算內」這一步（只試過兩個：垃圾車用 Meshy remesh 減到 1,374 面〔5 點〕，`convert.mjs` 轉成功，比低面數版好，但輪子變六角形塊；機車 `scooter-125cc` 減到 532 面〔5 點〕，`convert.mjs` 也轉得成，但車身碎尖片、把手參差、輪子多邊形，不建議只靠 remesh 壓機車；免費的做法（0 點）：遊戲轉換器已鎖定的 meshoptimizer 1.3.0 `simplify`（先烘色再減再重新上色），機車減到約 1,441 面輪子是圓的、可用，但機車預算要從 600 放寬到約 1,500，垃圾車輪子會碎（Meshy remesh 較好），遊戲內建 `decimate.py` 對這種零碎網格卡住（私庫 `INTEGRATION_HANDOFF.md` 第 4 節）；其餘沒減，要作者同意點數或工具）。缺點（號誌四燈、夜市攤車自帶頂棚等；綠郵筒、天公爐重生過，垃圾車與外送機車用 retexture 修過色）寫在該資料夾的 `00_READ_ME_FIRST.md`。**下次用 Meshy 生模型先讀該資料夾的 `LESSONS_AND_HANDOFF.md`**：不要把面數壓死，用標準模式生、之後再減面。Meshy 點數 11/4 重置：開工 1,149、用掉 1,050、剩 99（留 50，可用約 49）；CLI 生成不是免費的，免費重試要在 app 按重新生成。
- **派工單 I 做中**（舊存檔可以打開道路與公車）：session_01JMHz9ak2m1w5LYWDgoQWqS，branch `claude/new-session-8vlwcp`，登記了決策 428，PR 還沒開。內容：
  - 加一個像 `.buildStationRoad` 的玩家指令，打開道路。
  - 空白地圖用世界原本的城鎮當種子；實景地圖讀底圖的路（`readRoads`，要 `landBlocks`）。
  - 公車工具在沒道路時顯示說明與「打開道路與公車」，按了要確認一次。
  - 說明頁加「道路與公車」一段。
  - 新決策「舊存檔可以打開道路與公車」，400.md 補一句。
  - 不升存檔版本，不在讀檔時自動打開。
  派工單原文在本任的 scratchpad，新任拿不到，作者手上有。它會動 GameCore（`RoadGrid.swift`），所以 CI 是完整 tier。PR 來了照派工單的驗收審：用 `SaveFixtures` 的副本讀進來、執行新指令、`allowsBusTool` 變 true，fixture 本身不能改。
- **排好但還沒派的**：
  - §22.13：
    - 1 是派工單 I；
    - 2「不接車站的市區公車」（2.60）和 3「玩家自己鋪路」（2.45）要一起設計，排在 §22.12 第 1 項之後。
  - §22.14：
    - 1 行駛聲用真錄音（3.15）：只用 CC0／CC BY，作者下載到私庫，因為雲端 session 連 Freesound 是 403；排在垃圾車那項之後。
    - 2 慶祝粒子（3.10）：本任問過作者「要不要現在寫成派工單」，還沒答。Vortex 是 MIT，加依賴要作者同意，不然就移植程式碼、保留授權聲明；減少動態效果打開時不放粒子。
    - 3 駕駛視角的窗上雨滴（2.70）。
    - 4 3D 環境音（2.40）。
- **還沒查的不穩 UI 測試**：
  - 和 #1315 同一種寫法（點 6000× 的選項列）、還沒改的有 `LessonUITests.swift:619`、`RealWorldMapUITests.swift:797`、`TutorialJourneyUITests.swift:213`。紅了就照 #1315 的改法，可以一張派工單一起改。
  - `StartSaveFlowSmokeTests.testBackToStartWorksWithLargeTextWhileTheClockRuns` 紅過一次，原因還不知道。
- **決策 425 還剩一項**：查官方或私庫的編組資料，確認推拉式自強號兩端是否都是 E500。莒光的 `E500CK` 另案。
- **TestFlight 91**：作者還沒說要發。要發時照 CLAUDE.md：那個 commit 的完整 `ci.yml`（每晚的或手動的）和 full lane 都綠才按。What's New 由規劃寫。
- **號碼**：決策 426、427 已用，428 由派工單 I 登記；下一個可用的是 429，取之前再查一次 #1041。存檔版本 74，golden schema 74，都不動。
- **審查點數**：從 #1288 起數，大約 7 點，還沒到 30：
  - #1290、#1295、#1298、#1300、#1302、#1308、#1314 各 1 點；
  - 模型、文件、只改測試的 PR 算 0 點。
- **排程**：本任沒有還會觸發的排程，`list_triggers` 是空的。每日 Threads 排程：新任照 §1 表格建一個綁自己的。

**第十七次換手（2026-10-26 約 10:30 UTC，session_01TH2DNkW2meh3EZJ1vxBczC 壓縮 3 次，第 3 次後照 §1 換 → 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段、下面「第十六次換手」裡作者的新分工；#1041 只讀「遊戲規劃 session_01TH2DNkW2meh3EZJ1vxBczC 壓縮第 3 次」那則之後的留言。和下面不同時以這段為準。

- **分工照第十六次換手**：不開 Claude Code 實作 session（作者明說才開）。規劃寫派工單（scratchpad 的 .md，用 SendUserFile 交），作者貼給 Claude Pro（$20，5 小時額度）或 Antigravity；規劃只審查，小的自己改好推上去，綠了照 §1.2 合。已確認：Claude Pro 能用作者的帳號推 branch、開 PR，但只能推到它被指定的 branch（`claude/new-session-xxxx`），不是派工單寫的 `claudepro/...`，沒關係。作者 10:10 UTC 說 5 小時額度只用了 34%：一張派工單大約用 15–20%。
- **派工單的寫法**（這一任的經驗）：
  - 一張只做一小步，寫明先讀哪幾個檔（含約略行號）、要做的、不要做的、決策檔怎麼寫（號碼沿用就寫「不新增」）、驗收、流程。
  - 數字自己先查過再寫進去：A 那張寫「最多等 10 秒」，結果和要修的 `menuRow`（每次查詢 2–4 秒）同一個問題，規劃自己補推 ee4416a 改成 12 次／40 秒。
  - 寫明 `swift test --filter` 的輸出要看第一個 `Executed`：最後一行是 GameSim 的 0 個測試。
- **TestFlight 89**（c005788）：full lane 重跑綠，已告訴作者可以給測試者。What to Test 在 #1041。
- **本任合併的**（都照 §1.2）：
  - #1273（決策 419）、#1277、#1278（決策 421 V1、V2）、#1280（決策 422）。
  - 第一批派工：#1283（決策 424 C1，公車沿真的道路走）、#1284（決策 423 第一步，`JourneyPlan`）、#1285（決策 424 C2，站牌編號與路名、箭頭、真站牌、摘要），合完 main 是 ab02fb9。
- **第二批，換手時還在跑 CI**：作者的 Max 週額度剩 5%（10-27 22:00 台灣時間重置），本任停用了巡查 `trig_01XRMqqn2htUi4JciiftWBnC`。#1286、#1287 由作者在兩個都綠後自己合（main ab02fb9 的 `ci.yml` 已綠）。新任先看這兩個合了沒，沒有就照 §1.2 合。
  - #1286：選單 UI 測試改穩（派工單 A），只改 `StartSaveFlowSmokeTests.swift`，head ee4416a。作者說他沒傳 A，可能是把 A 當 D 貼了；做得對，照合。
  - #1287：車站面板的「怎麼搭」（決策 423 第二步，派工單 D），head 12880dc。已審：本機 build 用 `-warnings-as-errors` 乾淨、`JourneyPlanTests` 15 支過、`doc_numbers` 過。`StationPanel.swift` 的 SwiftUI 只有 iOS CI 編得到，外觀 UNVERIFIED。
- **派工單 E 做完了，PR 等審**（決策 424 續修，branch `claude/new-session-kfvuy0`，PR 號碼在 #1041 的登記）：公車工具選了車站就在背景讀真站牌與道路圖塊（`GameSession.readBusesAhead(for:)`、`BusRoads.readAhead(round:)`），主執行緒只拿結果。量到真站牌是大頭（release 約 0.8 s），道路網的建圖只省了一部分，數字與沒選的做法在 `docs/decisions/424.md`「續修」。手機上順不順是 UNVERIFIED，作者在 TestFlight 看。
  - 已做（決策 424 續修二，PR #1300）：3D 的 `Map3DBuses` 改在背景排（`Map3DBuses.Layer`），畫格不再建道路網。
- **派工單 R（審查 J）已交作者**：給 Claude Pro，#1242 起已合併的程式 PR 分三段審。
  - 每段一個 PR，交接檔是 `docs/archive/PR1242_<最後一號>_REVIEW_HANDOFF.md`。
  - P1、P2 的小修它可以順手推；動 GameCore、存檔、golden 的只寫不修。
  - 最後一段會改 §1 的「上一輪」。
  - 新任審過它的 PR 再合；它找到的問題照等級派工。
- **作者的 Pro 週額度**（10-26 10:20 UTC）還有 90%：Max 重置前的工作都給 Pro（E、R）。它開的 PR 先放著，等新規劃審。
- **接著可以派的**（照 §22.2 與五方，都不動 GameCore）：
  - 決策 423 第三步：地圖上標出選中方案的那幾段線（423.md「下一步」）。
  - §22.2 第 13 名：車站卡的下一班分月台列，只列 15 分鐘內的。
  - 第 18 名：票價旁的需求提示、借錢前的試算。
  - 第 22 名：客流強度、未滿足需求排行。
  - 3D 的 `Map3DBuses` 建道路網搬到背景：已做（決策 424 續修二，PR #1300）。
- **號碼**：下一個決策號 425；存檔版本 74；golden schema 74，都不動。
- **審查點數**：從 #1242 起數。前任交接時約 25 點，本任合的 #1273、#1277、#1278、#1280、#1283、#1284、#1285 各 1 點，加上 #1287 共約 33 點，已滿 30。這一輪由派工單 R 做（見上）。
- **排程**：
  - 巡查 `trig_01XRMqqn2htUi4JciiftWBnC` 綁本任，新任不用管，以自己看到的為準。
  - 每日 Threads `trig_01E7R3dQWAdVTBb8fmpYK7cy` 綁本任（暫停）：新任照 §1 表格建一個綁自己的，再刪掉這個。

**第十六次換手（2026-10-26 約 04:00 UTC，session_01TS89hbaHPJiFJycqrKiK5z 壓縮 2 次，照 §1「第 3 次壓縮快到時換」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「遊戲規劃 session_01TS89hbaHPJiFJycqrKiK5z 壓縮第 2 次」那則之後的留言。和下面「第十五次換手」不同時以這段為準。

- **作者 2026-10-26 的新分工**（原話：「這批完整做完合併後 就先這樣 max 20x週額度 已經到90%／這批做完接下來會想請你派工 給使用gemini3.8flash/4.0pro的 antigravity 與20usd pro方案的Claude／你只負責審查他們寫的程式碼哪裡需改善 幫他們改 或請他們改」「兩個都只有20usd方案」）：
  - 下面「做中的」這一批（419、421、422）做完合併後，**不再用 `create_session` 開 Claude Code 實作 session**（除非作者明說，像 421、422 就是作者說了才派的）。
  - 規劃照 NEXT_PRIORITIES §22.2 的順序寫**派工單**，交給作者貼給 Antigravity（Gemini 3.8 Flash／4.0 Pro）與 Claude Pro（$20 方案）。一張只做一小步：寫明要讀哪幾份文件、要改哪幾個檔、驗收怎麼量，一個 PR 做完。Flash 做資料、文件、畫面小修；較難的邏輯給 4.0 Pro，少用。要改 GameCore、升存檔或要跑很多 CI 的拆成幾個小 PR，拆不開的先留著。
  - 它們各自開 branch、draft PR，在 #1041 留言；規劃**只審查**：小的直接改好推上去，大的寫在 PR 請它們改，不來回很多輪；綠了照 §1.2 合併。
  - 還沒確認：這兩個工具能不能用作者的 GitHub 帳號推 branch、開 PR（規劃 10-26 問過，作者還沒答）。不能的話請作者把改好的檔案或 diff 交來，規劃幫忙開 PR。
  - 第一批派工單還沒寫：新任在這一批合完後寫，用 SendUserFile 交給作者。
- **本任合併的**（都照 §1.2）：#1271（決策 417，fba7cfe）、#1274（卡頓量測與顯示層驗證的方案，1731950）、#1275（決策 420，e7cde95）、#1276（放空模式 UI 測試改成「點不到」，434988e）；更早的 #1263–#1270、#1272 見 #1041。
- **卡頓與引擎**（作者 2026-10-26）：暫時不全面換引擎；「先修現有問題」與「長期是否自研」分開。方案 `docs/research/FRAME_TIME_AND_ENGINE_SPIKE_PLAN_2026-10-26.md`；作者同意 V1＋V2（決策 421），**V3 暫不開工，不改正式架構**。87.1 卡頓的原因還沒實機證明（決策 417 的更正）。421 的結果要等 PR 合併、發版、作者在實機跑過 V2 的固定場景才有。
- **做中的 session**：
  | session | 做什麼 | 下一步 |
  | --- | --- | --- |
  | session_01BCNSXuGMywCQSnXQsRSLPk | #1273 讀檔不卡畫面（決策 419），ready，必要的檢查都綠 | **先不合**：手動 `only_testing` run 40257225657 兩次各紅不同的開局測試（`RealWorldMapUITests.testARealWorldGameStartsFromAPlaceAndIsSavedAsOne`、`StartSaveFlowSmokeTests.testBackToStartWorksWhileTheClockRuns`、`testThePerformanceMenuStaysStillAndChoosesWhileTheClockRuns`）。最近 40 次紅的 iOS run 裡它們只在這個 PR 紅過，而 PR 改的正是開局／讀檔路徑，所以已退回請它找根因、修好後 `only_testing` 再跑一次。它說綠了再照 §1.2 合，合了改標題「【完成】…」後封存（它壓縮過 1 次） |
  | session_01H8xMujQgowiH5kZoNEySyX | 決策 421：#1277 V1（畫面節奏紀錄跟問題回報走）、#1278 V2（固定測試場景），都 draft | 綠了先審：V1 的 2D 指標不能叫「實際呈現時間」、驗收有嚴重停頓次數、最長停頓與重複測試；V2 鋪 20 條線在實機要多久。先合 #1277，#1278 合入 main 後再合。合了封存 |
  | session_01Jr3d9cuxajZ4UJWPfHBbe1 | 決策 422：700T 與 N700S-G 的遠景版（從近景配方產生，照 420 的做法），branch `claude/hsr-far-422` | 等它說可合併；看遠景與近景的顏色是否一致（舊的 highSpeedFar 是橘帶、近景是綠帶）。合了封存 |
- **main**：`ci.yml` 在 434988e（#1276）push run 綠。full lane：d9c3c68d 紅（放空模式測試，#1276 修了）；e7cde950 的 full lane 交接時在跑，新任看結果。
- **號碼**：決策 421、422 已登記；下一個決策號 423；存檔版本 74；golden 不動。
- **審查點數**：本輪從 #1242 起數，約 25 點，滿 30 點開審查（§1）。
- **排程**：本任的巡查 `trig_01RkWgm8r8H2PTCAvWfyvwvx`（04:07 UTC，綁本任）新任不用管；每日 Threads 排程 `trig_01UGGwsMqKc741AThnJkMQ72` 綁本任（暫停）：新任照 §1 表格建一個綁自己的，再刪掉這個。
- **已封存的 session**：01KWqgRo（418）、01LPDBFT（417）、014ZfTTK（420）、01695GDi、01YTRwth、01FPF497、01EbPNSQ、01J7edxy、013NAE9F。

**第十五次換手（2026-10-25 19:55 UTC，session_01KvN8GrLosqRswrXMQgVQir 壓縮 2 次、用了約 30 萬 token，照 §1「第 3 次壓縮快到時換」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「session_01KvN8GrLosqRswrXMQgVQir（遊戲規劃）壓縮第 2 次」那則之後的留言。和下面「第十四次換手」不同時以這段為準。

- **本任合併的**（都照 §1.2）：#1250（第十四次換手）、#1253、#1247、#1239（10j-3 捷運收購）、#1257、#1249（成就圖 B）、#1259（N700S-G 後半列鏡像）、#1260（高鐵示範開局卡住：道路改在背景讀）、#1258（決策 411 續篇共用 build：一個 build job、分片下載，full tier 變 22 個 job）、#1262（「這版新增」卡，決策 415，a3aa4355）。#1254 依作者「1254」合了。#1255 是 Codex 的 issue，不是 PR。
- **main**：`ci.yml` 在 15c6b60a（#1258）push run 40220465155 綠（build job 約 4 分、分片約 13 分）；a3aa4355（#1262）的 push run 交接時在跑。full lane：15:45 那次（run 40208469846，11164318）smoke job（`Xcode build (iOS Simulator)`）紅、其他三個綠；a3aa4355 的 full lane run 40227525036 交接時在跑，新任看結果，紅的話照 §1.2 判斷是不是 01ATrwF1 修過的那幾支。
- **每晚完整 `ci.yml`（決策 413，cron `37 17 * * *` UTC）**：10-25 17:37 那次沒有觸發（19:40 看過，已記在 #1041）。新任 10-26 17:37 UTC 後再看一次；連兩晚沒跑就查 `on.schedule`（GitHub 對新加的排程常延遲或略過）。發版需要一次全綠的完整 run（每晚或手動 `workflow_dispatch`）加綠的 full lane。
- **做中的 session**（都壓縮過 1 次：做完這個就封存，不再派新工）：
  | session | 做什麼 | 下一步 |
  | --- | --- | --- |
  | session_01J7edxy3rWsd9gKqSFMyPa4 | #1261 放空模式（決策 414），draft；iOS 閘門第一輪紅，修正 209cef2 已推 | 已告訴它：#1262 先合了，所以要在 #1261 合入 main、把放空模式加進 `WhatsNew.entries` 最前面那一則（`Sources/GamePresentation/WhatsNew.swift`），綠了回報「可合併」。合了改標題「【完成】…」後封存 |
  | session_013NAE9FMP5UoYatwP4b4DrJ | #1263 10i-5 自己畫公車路線（決策 400 續篇），draft | 等「可合併」；合了改「【完成】…」後封存 |
  兩個都有自己 20:11、20:14 UTC 的 check-in，可合併時會 send_message 給本任；本任收不到了，新任接手後對兩個 session 各發一則「規劃換人，之後回報給 <新任 id>」。
- **本任的 check-in `trig_012fcTzJ5mEazBmAY5BpHw1H`**（20:30 UTC，綁本任）：新任不用管它，以自己看到的為準；它叫醒本任時本任只會看到已換手。
- **還沒派的**（照五方挑）：
  - ~~I8~~、~~#1260 剩下的（資料晚到時 `install` 在主執行緒讀道路）~~：session_01YTRwthhkJVsLn8wkaagJ8p 做了（`claude/i8-and-load-roads-off-main`，決策 400「續篇：讀檔的兩件小修」）。~~還剩：`begin` 讀一個路沒讀的舊存檔時仍在主執行緒讀路~~：session_01BCNSXuGMywCQSnXQsRSLPk 做了（`claude/load-off-main-419`，決策 419：繼續、讀存檔、回到自動存檔、匯入都在背景解碼與讀路，讀得慢時有讀取畫面）；剩下的見 `docs/decisions/419.md`「還沒做的」。
    - **#1273（決策 419）未完，session_01BCNSXuGMywCQSnXQsRSLPk 壓縮第 2 次停下（2026-10-26）**：`StartSaveFlowSmokeTests.testBackToStartWorksWhileTheClockRuns` 在分支上 only_testing 兩次紅（run 40257225657 第 1 次、A/B 的 40269192400），同時同設定的 main `815f121`（40269194954）三個測試全綠；`testRealWorldMapUITests` 那個開局測試只紅過一次，`checkMenuStaysStillAndChooses` 的那次紅是開選單的時序（錄影證實）。紅在 `menuRow`（StartSaveFlowSmokeTests.swift:569「Menu row never came to rest」）。量到的差別：XCUITest「Find menu.*」步驟的間隔，分支紅的兩次中位數 3.58 s、1.62 s（最長 10.49 s），綠的幾次 0.47–1.12 s；App 自己的畫格數（`ui-smoke-trace`）兩邊差不多，所以慢的是回答無障礙查詢，不是畫面。疑點（未證實）：`RailwayGameApp.swift` RootView 加的 `.allowsHitTesting(!launcher.isLoadingSave)`（觀察 `isLoadingSave` 讓整個畫面樹多算）。下一步：拿掉 RootView 那行，只靠讀取畫面與 `open()` 的 `guard !isLoadingSave` 擋重複點，再用 `ios-build.yml` 的 `only_testing=RailwayGameUITests/StartSaveFlowSmokeTests/testBackToStartWorksWhileTheClockRuns` 分支與 main 各跑一次（最多 2 台 macOS）；兩邊一樣慢就是 runner，照 §1.2 可合，只有分支慢就繼續往 App 追。測試加固（等可點的列連兩次相同才記 `opened`）不放進 #1273，由 game-planning 另派。#1273 還沒標「可合併」。
  - 公車：10i-4（收購公車）、10i-6（2D／3D 地圖上的公車），見 `docs/decisions/400.md` 計畫表第 7–9 列；10i-5 是 #1263。10i-3（真實公車資料，`tools/real-buses/`、`RealBuses`）已做，10i-4 要用的欄位寫在 400.md 的「下一步」。
  - NEXT_PRIORITIES §22.2 第 22 名（路網流量分析）、第 27 名（轉乘規劃）。
  - I7（iCloud 文字）留給決策 397 的作者。
- **不合的**：Codex 的 #1256（E500）、#1230（TEMU1000）都是 draft，作者沒說就不動。
- **作者問過、已答**：NLSC 地形圖做精確 3D 地形「現在不需要」（五方：開發成本高、玩家看不出差別，留到 3D 地圖有地形需求時）。
- **每日 Threads 排程** `trig_01HSSMpemZaSC9PBohhHFWGM` 綁本任（暫停）：新任照 §1 表格建一個綁自己的，再刪掉這個。
- **已封存的 session**：01P66、018TnoJq、012tPP、01ATrwF1、0142CcDj、011wf5gK、01NmGg4S、01PYmwuw。

**第十四次換手（2026-10-25 15:30 UTC，session_0164nEyu2aMPVTpvQww43kj1 壓縮 2 次、用了約 29 萬 token，照 §1「第 3 次壓縮快到時換」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「session_0164nEyu2aMPVTpvQww43kj1（遊戲規劃）壓縮第 2 次」那則之後的留言。和下面「第十三次換手」不同時以這段為準。

- **88.1 的 full lane 還是紅**（run 40192919013，c4fc5b6）。第 1 次紅 3 支舊的不穩測試；14:03 重跑（只能一次）後，smoke job 121190221952 在 70 支裡只紅 1 支：`SharedNetworkUITests.testAFriendsNetworkOffersBothChoicesAndJustLookOpensIt`（兩次都紅）。second、lessons、iPad 都綠。15:25 已告訴作者：只剩「打開朋友分享的路網」這一個畫面沒證明，給不給測試者（export compliance、測試群組）由作者決定。01ATrwF1 已收到這支要優先修。
- **做中的 session**：
  | session | 做什麼 | 下一步 |
  | --- | --- | --- |
  | session_01ATrwF1t4xfwDoTrLvMvRAY | 把 full lane 不穩的 UI 測試修穩（branch `claude/steady-full-lane-ui-tests`），順便查 `full-lane-watch.yml` 為什麼沒在 #1041 留言；壓縮過 1 次 | 每支用 `only_testing` 綠 2 次再開 PR；PR 合了就封存，不再派新工 |
  | session_01Pz4Th4Hr8SAr6iP9gm4sqC | #1246：iOS PR 閘門從 7 支減到 4 支（決策 412），draft | 綠了轉 ready、留「可合併」；合了就封存 |
  | session_01P66bY6nFU891b1C3sYwkRU | 找可以刪的 CI（作者 15:0x 問「有些 ci 沒必要了可以刪除嗎」）：研究文件 `docs/research/CI_PRUNE_2026-10-25.md` | 只寫研究；要改「什麼時候測、測多少」的，交回規劃用五方決定 |
  | session_0142CcDjX1nJjUuRGNLypRMA | #1249：遊戲內成就清單改用 Game Center 的 38 張圖（決策 396 續二，五方選 B：沒解鎖的用 0.5 透明度） | 綠了照 §1.2 合 |
- **五方已決定**（#1041 15:00 UTC 留言）：共用 build 選 A（build 一次、各分片下載，3.20 分）；成就圖示選 B（3.70 分）。
- **共用 build A 還沒派**：等 #1246 合併、01Pz4 封存後，照 #1246 寫進 HANDOFF §1 的做法開新 session；動到 `ci.yml`、`swift-shards.sh`，開工前和 01P66 協調。依據：`docs/research/CI_SHARED_BUILD_2026-10-25.md`（決策 411）。
- **等 main 綠後合併的一批**（照 §1.2；main 的 `ci.yml` 在 7fb4715b 綠，79847dc（#1242）15:25 還在跑）：
  - #1247：審查 I 的修正，head e519313，CI 綠。
  - #1248：審查 I 的交接；下一輪審查從 #1242 起數點數。
  - #1239：10j-3 捷運收購，head 0915f4bf，GameCore，draft。轉 ready，CI 重跑綠了再合；一次只合一個 GameCore PR。
  - #1246：01Pz4 15:21 UTC 說可合併（已轉 ready，head 99f16b6，CI 全綠；新閘門 4 支的 UI 步實測 3.8 分，原本中位數 9.0）。合了就把 01Pz4 改標題「【完成】…」後封存。
  - #1229、#1242（Codex 的 EMU3000）已經由別人合併。#1230（TEMU1000）還開著。
- **還沒派的小修**：N700S-G 後半列沒鏡像（審查 I 找到，見 #1248），只動 GamePresentation。#1245 已修車尾亂飄，實機還沒確認（UNVERIFIED）。
- **已封存的 session**：01E4Wp、01LARTBY、01Mqs95。
- PLAYER_FEEDBACK 88.1 已記 full lane 第 2 次、#1245、成就圖 B（這個換手 PR）。
- 前任派的 session_01WBDhnK83mWG9wSxuSHvAtC（#1232 已合）、session_01XiqjNzLz2SSc77KCXZVXxN（#1236 已合）做完了還沒封存：新任改標題「【完成】…」後封存。
- 每日 Threads 排程 `trig_019Me4PBGfWMxcBwc5TAkXRx` 綁本任（暫停）：新任照 §1 表格建一個綁自己的，再刪掉這個。本任沒有其他還會觸發的 check-in。
- 審查點數：下一輪從 #1242 起數（#1248）。
- **01ATrwF1 找到的**：高鐵示範第一次開地圖時，CI 模擬器的主執行緒卡住 28–58 秒（`RealWorldMapUITests.testTheHighSpeedDemoOpensOnTheMapAndRuns` 改成等它）；原因是 `begin` 在主執行緒讀道路，修在 `claude/hsr-first-map-stall`（§5 那一列）。SharedNetwork 那支紅的原因已經找到（橫放時按鈕在明信片下方；慢速拖曳從 Just Look 按鈕上起手，誤按開了遊戲），修在 af5cba3（`claude/steady-full-lane-ui-tests`）。

**第十三次換手（2026-10-25 12:40 UTC，session_0138XhXTjToUd3fpKV7kebeH 壓縮 5 次，作者說「交接」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段；#1041 只讀「session_0138XhXTjToUd3fpKV7kebeH（遊戲企劃）壓縮第 5 次」那則之後的留言。和下面「第十二次換手」不同時以這段為準。前任超過 §1「第 3 次壓縮快到時換」才換，下一任照表在第 3 次壓縮前換。

- **88.1（0.5.0）發版中，main 凍結**（10-25 12:25 UTC 起）。發版 commit 是 main 的 **c4fc5b6**（#1240 What to Test 的合併）：`ci.yml` run 40192915948 綠；它自己的 full lane（`ios-build.yml` run 40192919013，作者 12:23 手動開）還在跑，預計 13:30–13:50 UTC 結束，smoke 那個 job 最慢。
  - 作者問「我可以跟昨天一樣先按嗎」，前任答可以：作者自己對 main（c4fc5b6）按 `testflight.yml`，但 export compliance 和加到測試群組要等前任或新任回報 full lane 綠。作者按了沒，交接時還不知道；新任先問作者或看 `testflight.yml` 的 run。
  - full lane 紅在和這版無關的測試：那個 job 重跑一次（87.1 的先例），第二次還紅就當真的。最近 main 的 full lane 紅過、每次不同的四個 UI 測試（看起來是 flaky）：`RealWorldMapUITests.testTheHighSpeedDemoOpensOnTheMapAndRuns`（ToolbarSmokeTests.swift:302 逾時）、`SharedNetworkUITests.testAFriendsNetworkOffersBothChoicesAndJustLookOpensIt`、`SettingsUITests.testTheCityPreviewLoadsItsPageAndCloses`（fcf06977，run 40176501060），`HUDAlignmentUITests.testTheStationMastersBubbleKeepsTheLines`（a2f0ef91，run 40160679685）。full-lane-watch 沒在 #1041 留過言，值得查；89.1 前可以派一個 session 把這四個穩下來。
  - 發完：在 `docs/research/PLAYER_FEEDBACK.md` 記「0.5.0 (88.1)」的 run 與 commit，#1041 留「發版凍結解除」。
  - 前任排的 check-in `trig_01TtNgLAmrJsC91EjAMPxQMa`（13:20 UTC，綁前任）會叫醒前任看 full lane；新任不用管它，以自己看到的為準。
- **這份換手的 PR 等 88.1 按下去（或 88.1 確定不發）才合併**：先合會讓 main HEAD 離開 c4fc5b6，發版 commit 就得再跑一次 full lane。
- **解凍後一批合**（照 §1.2，GameCore 的完整 tier 最多同時 2 個）：
  - #1237（規則：預覽改版只留 PNG）。
  - #1232（自有建築第二批，**存檔 74**，head cb8a9991）：住戶掉的原因 01WBDhnK 查清了（規則沒改），完整 tier 綠就合，進 89.1。
  - #1239（10j-3 捷運收購，head 0915f4bf，draft）：解凍後轉 ready，審過再合。
  - #1229、#1230（Codex 的 EMU3000、TEMU1000）：下一版，免費車，不進列車包。
- **89.1 的其他線**：檢修庫與彰化的轉車台（NEXT_PRIORITIES 10p）改由派工 AH 一起做（#1366，決策 441）；Codex 原本的認領（`codex/depot-3d-facilities-2026-10-25`，沒有 commit）已釋出。合併後要實機看。示範模式是否自動解鎖列車包、10j-4 都排在後面。三翼的公車接駁（#1220、#1225）還沒有 UI，所以沒進 What to Test。
- **列車包**（決策 338 續二）：作者選「己＋買之前看得到」；測試版的開關預設關。N700S-G 在包裡：解鎖後單號高鐵畫成 N700S-G，沒解鎖全是 700T。
- **session**：01XiqjNz、012tPP、01WBDhnK 做完或壓縮過，不再派新工；01F2tq、01B5oz 已封存。私庫 #83 已合併（95a20451），預覽的規則在 #1237。
- 每日 Threads 排程：新任照 §1 表格建一個綁自己的，舊的刪掉（作者沒說要開就維持暫停）。
- **新任接手**（session_0164nEyu2aMPVTpvQww43kj1，12:58 UTC）：作者 12:34 UTC 已對 c4fc5b6 按了 `testflight.yml`（run #88，也就是 88.1），所以這份 PR 可以合。full lane run 40192919013 還在跑（iPad 綠，smoke、second、lessons 跑中）；綠了才告訴作者可以做 export compliance、加測試群組。前任的 check-in `trig_01TtNgLAmrJsC91EjAMPxQMa` 已刪，由新任的 send_later 接手。每日 Threads 排程改成 `trig_019Me4PBGfWMxcBwc5TAkXRx`（綁新任，暫停）；綁 0138Xh 的 `trig_015YTCruhYjwCBX7PCCHV4fn` 與綁 01B2ka 的 `trig_01ER4MLsumedKaDcP7aeTCNW` 已刪。

**第十二次換手（2026-10-25 05:05 UTC，session_01B2kaku5NRz2J2CMzc8z3cZ 壓縮 2 次、`used_tokens` 約 25 萬，照 §1「第 3 次壓縮快到時換」→ 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、這一段、第 3 節最上面幾列；#1041 只讀「session_01B2kaku5NRz2J2CMzc8z3cZ 壓縮第 2 次」那則之後的留言。和下面「03:30 的現況」不同時以這段為準。

- 合併了（10-25 03:30 起）：#1221（規劃文件）、#1219（iCloud 同步狀態，397 續 2）、#1220（10i-2 公車接駁，**存檔 73**）、#1218（10k 分享路網，決策 409）、#1217（決策 408，700T 與 N700S-G）、#1222（401 續：示範鋪真實路線的複線、急彎、跳站）；私庫 #75（408 的預覽）。main 的 `ci.yml` 在 adb309a、a2f0ef9、b6d517d 都綠；#1218（1eb0b1f5）、#1217（588ac076）、#1222（caf6db6e）這一批合併後的 run，新任先確認綠了再合下一批。
- #1217：作者 04:57 UTC 在 408 的 session 說「對準就能了 目前看起來都ok」，規劃查過那個 session 的對話紀錄。公開 repo 沒有作者的 GLB 或 m3dmodel（branch 的 10 個 commit 都查過）。
- 做中的 session：
  | session | 做什麼 | 下一步 |
  | --- | --- | --- |
  | session_01AgGAnZn9Gz1YEgMy2Sv8Hu | 公車接駁平衡調整（400 續篇，GameCore 完整 tier） | 目標：一條路線讓車站旅次多 5–25%；量了才調，寫調之前與調之後的表。存檔維持 73，要升會先問。**調好之前先別發版**。「可合併」且綠就照 §1.2 合 |
  | session_0184ajQAx9BPLKw475Jw1G5U | **決策 410** 列車建模升級：結合 700T 與 N700S-G，照 §7.3 的工作單 | PR 寫「先別合併」：總覽圖轉給作者，作者說好才合。`refresh-*` 與 N700S-G 的 checksum 不變；中間車 ≤ 2k、頭車 ≤ 4k 三角形 |
- 接著可以派（GameCore 的完整 tier 同時最多 2 個，現在只有公車平衡這一個）：
  - 10j-2：捷運營運價值，改 LineAcquisition。#1220 已合，可以派。
  - 10d：升存檔 74。
  - 橘色 N700ST：作者問的，另開 PR，用作者私庫的 n700st 模型＋`tools/hsr-trains-408/decimate.py`＋700T 的轉向架，見 §7.3「下一步」。排在 410 之後。
  - 作者說 Game Center 和好友功能現在不做。
- 審查：下一輪從 #1189 起數程式 PR 的點數（§1），滿 30 點開一輪。
- 巡查：本任的 send_later trig_016b4ZSaAWScqYYZ2zPM5RiD（05:22 UTC）打到本任。新任開工後關掉它，用自己的 send_later 接手。
- 作者 10-25 04:1x 說「交給你了我要去午休了」。

**2026-10-25 03:30 UTC 的現況（session_01B2kaku5NRz2J2CMzc8z3cZ 壓縮 2 次；照 §1 當天改的規則，續任到第 3 次壓縮快到才換）**。換手時新任開工：讀第 1 節、這一段、第 3 節最上面幾列；#1041 只讀「session_01B2kaku5NRz2J2CMzc8z3cZ 壓縮第 2 次」那則之後的留言。和下面不同時以這段為準。

- 合併了：#1216（10f 高架橋種類，決策 407，main 8e8a959a）、私人庫 #74（b83461c5）。main 的 `ci.yml` 在 883bd7b、fc59484e、8e8a959a 都綠，full lane 也綠。
- 開著的 PR 與做中的 session（都還沒封存的就是做中）：
  | PR／session | 內容 | 狀態與下一步 |
  | --- | --- | --- |
  | #1219（session_016rkfLSmFLTJKBXhegJeXfx） | iCloud 存檔看得到有沒有同步：狀態列、每份存檔標示、「立即同步」（決策 397 續 2） | 獨立審查（#1219 留言 6392984109）沒有擋合併的問題。但這個 PR 就是要顯示有沒有同步，所以已請原 session 先修兩條「建議修」：(1) 讀不到上傳狀態時 `?? true` 會把還沒上傳的顯示成「已同步」，改成 `?? false`；(2) 另一台較新版本的存檔還沒搬進來時，不要說「等待上傳」，分成自己一種狀態。「可不修」記進 397 的「下一步」。修好、綠了、留「可合併」就照 §1.2 合、封存，再告訴作者用 `docs/ICLOUD_SAVE_SETUP.md` 第 5 步在兩台裝置上試。作者說「改善這裡就好了」：只改顯示，**不改同步什麼時候跑**；PR 提的 NSMetadataQuery 改法是給作者選的後續，不先做 |
  | #1220（10i-2 公車接駁，存檔 73） | 公車接駁進 GameCore | draft。獨立審查（session_01TYmxCHzCq3RuUbc9CoETBL，#1220 留言 6392952447）有 **1 條擋合併**：公車路線很長時（例如兩段各 200 km、一天一班），`feederMinutes` 超過 1440，`BusRoute.isValid` 卻要 ≤ 1440。結果指令照樣成功、存檔也寫得出去，但讀檔被拒，玩家等於掉存檔。修法：`refreshBusFeeders` 把分鐘夾到一天（或放寬 `isValid`），補一個最長路線存了再讀的測試。建議一起修：`nextBusRouteID` 要照其他計數器走 `allocateID`／`idsExhausted`，並檢查 ≥ 1。新任派一個 session 修這兩項，綠了再合。平衡 CONCERNS：實景地圖一條公車線讓車站旅次多 19–51%（目標 5–25%），空白地圖只多 0.04%、公車一天虧約 $5,880。綠且審查沒有阻擋就 ready、合併，再派公車平衡調整；**調好之前提醒作者先別發版**。10j-2 和它都改 LineAcquisition／acquisitions，等它合併才派；10d（存檔 74）也在它之後 |
  | #1217（session_01Bbe7HnLfcUGdoE2VRgZgoU，決策 408） | 高鐵 700T 與 N700S-G 各跑一半、E200 換新車頭 | PR 寫著「先別合併」：等作者看過 N700S-G 預覽說好。作者選的是「作者自己的模型減到每節約 5k 三角形＋遊戲配色」；**作者的原始 GLB 和私人庫的完整 N700S-G 網格不能進公開 repo，任何 branch 都不行**。重做步驟與照片檢查點在這個 PR 的 HANDOFF §7.3（合併後才在 main） |
  | #1218（session_01RarzebNWdkEundHGJDzTBf，決策 409） | 10k 分享路網：自己的檔案類型、明信片預覽、開新局或只看 | 碰檔案類型與匯入（存檔讀取），合併前開獨立審查 |
  | session_01NLyU4ovZGrFRoFpC1iA1Fx | 決策 401「下一步」(b) 的示範鋪軌 bug：平行鏈失敗時默默退成單線、`traceMinimumRadius` 40 m 弄斷文湖線與環狀輕軌、停站段跳過中間的軌道 | 還沒開 PR；「可合併」且綠就合 |
- **#1217 合併後派決策 410**（作者 10-25：「等等我看過後 你照 700T 與n700sg升級現有的列車建模 要結合兩者有點 然後現有建模只取好的部分 太差都可以刪除」）：照 700T 與 N700S-G 的做法升級現有的程序列車模型，取兩者的長處；現有模型只留好的部分，太差的可以刪掉重做，但每種營運中的車種都要有模型。`refresh-*` 的 checksum 不變；中間車 ≤ 2k、車頭 ≤ 4k 三角形；每一項附前後對照。
- 作者 10-25 說好友功能或 Game Center 現在不做。Game Center 可以之後另列一項（約 2 點），作者提了才加進 NEXT_PRIORITIES §22.2。
- 巡查的 send_later：trig_01E7MS1p3o3Y1Tb37rRNQcxr（04:05 UTC，打到本任）。換手時舊任關掉自己的，新任用自己的 send_later 接手。

**第十一次換手（2026-10-24 22:50 UTC，session_019yHzrc1rgGJgdXSSwRNqgM 壓縮 2 次 → 作者從 claude.ai 開的新規劃）**。新任開工：讀第 1 節、下面「新任接手後的現況」、第 3 節最上面幾列；#1041 只讀「session_019yHzrc1rgGJgdXSSwRNqgM 壓縮第 2 次」那則之後的留言。

**第十次換手（2026-10-24 14:00 UTC，session_013dJ7tvDYJnhe7XjXCE5cNi 壓縮 2 次 → 作者從 claude.ai 開的新規劃）**。和下面不同時以這段為準。新任開工：讀第 1 節、這一段、第 3 節最上面幾列；#1041 只讀「session_013dJ7tvDYJnhe7XjXCE5cNi 壓縮第 2 次」那則之後的留言。

- **第十一次換手之後**（session_01B2kaku5NRz2J2CMzc8z3cZ，10-24 23:20 UTC）：合了 #1206（missing-button 證明，main 1050bca5）、#1208（10n 鳴笛與 3D 照片，main 8ddc0193）。做中：session_013AAhuBSsBFF5MAzis3q8UC（決策 406：山岳隧道底拉直、股道不跳線）、session_01WBiArcxxo6UcPuchugpydK（10i：實景地圖讀底圖的路，400 續篇，不升存檔）。10i-2（公車接駁，存檔 73）等後者合併再派。main 的 full lane 要等下一次 nightly 驗 missing-button 那一步。
- **10i-2 公車接駁**（session_0131GGjejMKbVP3fkorpsVNa，分支 `claude/bus-feeder-core`，**存檔 73**，決策 400 續篇「公車接駁」；10-25 壓縮 2 次，交接）：GameCore 的 `BusRoute` 與六個命令、接駁規則、`acquisitions` 的 `kind`、存檔解碼的格數上限都做完，本機 Swift 6.4 的 `-warnings-as-errors` build 與相關測試綠；PR 是完整 tier。剩下的（接手的 session 或規劃派）：
  - CI 綠 → 轉 ready → #1041 寫「可合併」與 40 字 head sha → 告訴規劃；規劃開獨立審查。CI 紅就照 CLAUDE.md 修。
  - 平衡是 CONCERNS：空白地圖接駁只多 0.04% 的票收旅次、公車一天虧約 $5,880；實景地圖一條路線讓車站旅次多 19–51%（目標 5–25%）。數字在 400.md「量到的」；票價、車的成本、回程乘客、自己畫的路線能不能走國道寫在 400.md「下一步」。
  - 畫面（畫路線、站牌、車數與損益）還沒做，App 沒動。
- **10i-5 自己畫公車路線**（session_013NAE9FMP5UoYatwP4b4DrJ，分支 `claude/bus-route-editor`，存檔不動，決策 400 續篇「自己畫公車路線」）：建造工具的「公車」、預覽、確認、車站面板的路線卡、2D 地圖的路線與站牌都做了。沒做的寫在 400.md「下一步」的「畫面」那一點：10i-6 的 3D 公車、審查 I 的 I8、full lane 的 UI 測試、全公司的路線清單。
- **新任接手後的現況**（session_019yHzrc1rgGJgdXSSwRNqgM，10-24 22:50 UTC，本任已壓縮 2 次，換手；見上面第十一次換手）：
  - 合併了（10-24 15:07 起）：#1191、#1189（決策 404）、#1192、#1196、#1197、#1195、#1194（10m）、#1193（教學卡片留在原位）、#1199（H1，買下的地塊有路，存檔不升）、#1198（**決策 405**：完整 tier **21 個 job**，警告線 17 分）、#1204（H4–H6）、#1205（交接）；作者 22:23 自己合了 Codex 的 #1203（N700S/N700ST），main **e105e889**。`ci.yml` 在 main 綠。
  - 審查 H：H1–H6 都已合；H7、H8 照 `docs/archive/PR1137_1188_REVIEW_HANDOFF.md` 第四節延後。下一輪審查從 #1189 起數（程式 PR：#1192、#1193、#1194、#1195、#1199〔GameCore〕、#1204）。
  - **full lane 紅，發版前要先綠**：
    - nightly 40131283541（921c62f1）所有 UI 測試都過，只有每晚的「Prove a missing toolbar button fails the smoke test」一秒就停：決策 382 把「完成」改成 `BuildDoneButton`（在 `BuildToolRail.swift`、`ContentView.swift` 各叫一次），腳本還找舊的 `doneButton`。
    - 修正是 **#1206**（本任開的，只改 `.github/scripts/ui-smoke-missing-button.sh`，PR 會跑完整 tier）。本任在分支上手動跑了 `ios-build.yml`（`verify_missing_button=true`、`only_testing=ToolbarSmokeTests/testEnglishToolbar`），綠了才算證明拿掉「完成」會讓 smoke test 失敗。
    - #1206 的 gate 和那次手動 run 都綠了，就照 §1.2 合，等下一次 full lane。
    - 更早的 40109459200（7ca9d6d1）是 lessons job 紅，在 #1193（教學卡片）合併之前，921c62f1 的 lessons 已經綠，不另外追。
  - **做中的派工 session**（都是本任 22:27 UTC 派的，派工留言 #1041 6390317632）：
    - session_01P5gjwSg3taxPLmdNHrMbLb：10n，決策 403 第 3 個 PR（照車種的鳴笛、3D 快照），分支 `claude/map3d-horn-snapshot`，不升存檔。
    - session_013AAhuBSsBFF5MAzis3q8UC：401 第 2 件（`Map3DRealTrains` 的真實列車軌道：照真實單複線、高度、不斷軌），**決策 406**，分支 `claude/real-train-tracks-406`。
    - 它們說「可合併」時，新任查過 gate 與 iOS 都綠就照 §1.2 合，在 #1041 記下，再封存 session。
  - Codex 的 PR（#1201 還開著；#1203 作者已自己合）是作者自己叫 Codex 做的，規劃不合、不管。
  - 還沒派（照 §22.2，派之前在 #1041 寫分數）：10i 的公車與底圖道路（作者選 B，規則見下面「公車」）、10f、10d、10k、11。
  - 號碼：下一個決策 **407**，存檔 **73**；golden 不動。
  - 週額度：seven_day 是 allowed_warning，10-27 14:00 UTC 重置。作者問「怎麼不做了」，意思是照做，所以同時最多 2 個派工 session。
  - `tools/golden-checks/doc_numbers.py --check` 在 main 上本來就不過（OVERVIEW 的存檔版本與 ARCHITECTURE 舊順序），不是哪個 PR 弄壞的，沒有人接。
- **合併了**（10-24，第九次換手之後）：#1177（交接）、#1166（398）、#1175（401 第 1 件）、#1176（391 續篇三）、#1180、#1185、#1187（87 的 What to Test）、#1181、#1188（full lane 的 UI 測試）、#1179（391 續篇二）、#1182（決策 402）、#1183（決策 403 第 1 個 PR）、#1184、#1186（CI 第 18 片 `campaigns-17`）、#1178（10i-1 道路格子，**存檔 72**，合前有獨立審查 session_013mpDRYLdRh5jv8tqnwg7hx），main **947c23ad**。main 的 `ci.yml` 在 947c23ad 綠（run 40093112308）。
- **第 87 版**（作者：「好 綠了就幫我發」「等全部綠了再合沒關係我可以等」；作者去看演唱會，不在）：候選 947c23ad，What to Test 已在 main（`.github/testflight-whats-new.md`，0.5.0 (87.1)）。full lane 40093122899 第 1 次只有 Xcode build job 紅，在 `TutorialUITests.testATouchHeldOnTheFoldedCardAsTheStepMovesOnOpensIt`（`TutorialUITests.swift:359`，卡片在步驟換掉時移了位置）。這支測試在 30e34922 也紅過一次，在 b7793b97 綠，這版沒有改到教學，所以只重跑那個 job 一次（第 2 次）。**作者 14:02 UTC 自己按了 `testflight.yml`（run 40100730344，947c23ad，成功：帶 iCloud entitlement 的匯出與上傳都過了），說好「你過了再給玩家」。重跑的 UI 測試綠了（13:47–14:44），剩翻譯檢查；最後結果、有沒有告訴作者「可以給玩家」，看 #1041 本任最後的留言。** 原本的做法：
  - 綠了，本任就照 §1.2 寫健康報告，按 `testflight.yml` 一次（`archive_signing=adhoc`、`testing_scope=external`）。87 是第一個帶 iCloud entitlement 的匯出：匯出失敗時先看錯誤說的是哪個 capability，是 iCloud 就 `git revert d9b9cc6`；
  - 又紅了就算真的，不發，交給新任派修（和 HANDOFF §5「第 5 課卡片跳動」同一類：教學卡片在步驟換掉時跳位置）；
  - 發完：記進 PLAYER_FEEDBACK「0.5.0 (87.1)」，在 #1041 留「發版凍結解除」。本任來不及做的，新任接著做。
- **開著的 PR**：#1189（決策 404：分片快到上限時先警告、每片 `swift test --parallel`，session_016VsuVC61edGEaS3rfsHJkS，draft）。它在本任叫它等 87 之前自己開了 `full-ci`，本任取消了那次 run（40093277697）。87 發完之後，新任叫 016Vsu 把 main 合進去、重跑一次 `full-ci`，綠了照 §1.2 合。main 的 `swift-shards.sh` 已經用「decision 404」指 #1186 加第 18 片的決定，所以 `docs/decisions/404.md` 合併時要一起記下第 18 片（`campaigns-17`，#1186，full tier 20 個 job）；#1189 不合的話，另開一個只有 404.md 的 PR 記這件。
- **做完、可封存的 session**：01XztRUE（403 第 1 個 PR，已合）、018gwb44（10i-1，已合）、013mpDR（10i-1 獨立審查）、01CWPnhw（402，已合）、01T3bLv（391 續篇二、三，已合）、01AdP4eU（10j-1）、019Yxc（401 第 1 件）、01E26h8（398）。01Vtrfi（full lane 修測試，#1188）已封存。
- **還沒派**（照 §22.2 的分數，每件派之前在 #1041 寫分數）：
  - 決策 403 方案 E 第 2 個 PR（「旁邊」「從車站看」兩個視角）、第 3 個 PR（鳴笛與 3D 快照），細節在決策 403「下一步」與 §4.13；
  - 401 第 2 件（示範模式鋪軌的三種問題，§2.0 第九次換手那段與決策 401「下一步」）；
  - 10i 的下一步：底圖的路接進 `RoadGrid.setRoads`（這次沒做），以及公車；
  - 10f、10d、10k、11（10l 已合，10m、10n 就是上面 403 的第 2、3 個 PR，10o 只研究）；
  - 第 5 課卡片跳動的 App bug（§5），沒有人接。
- **公車（作者選 B，10-24：「好 照B」「好 照這樣做 但其實台灣有些公車是會到國道高速公路上的怎麼辦」）**，五方在 #1041。10i 下一個 PR 照這樣做，並寫進決策 400「下一步」：
  - 2D 用道路格子判斷路通不通；高架或平面只在 3D 照決策 391 的道路分層畫，不進規則；
  - 國道與快速道路（OSM `motorway`、`trunk`、`motorway_link`）不算公車的路，另存成 `highwayCells`，之後加客運時用；
  - 買下的真實路線照真實走法，國道那段也照走；
  - 玩家自己畫的路線，之後每條路線加一個「可走國道／快速道路」的開關，只能從匝道上下，國道上不能設站。
- **審查**：從 #1137 數到 #1188，合併的程式 PR 共 **32 點**（GameCore：#1166、#1175、#1178），已經滿 30。新任先開審查 H（#1137–#1188），再派新功能。
- **號碼**：決策 402、403 已合；404 是 #1189；下一個 **405**。存檔版本 72 已合，下一個 73；golden 不動。
- **排程**：每日 Threads 開發日誌 `trig_01M2rwYPRRjTwQTC5g6QaW9v`（綁 013dJ7，暫停）：新任用同一份 prompt 建綁自己的（暫停），刪掉它。舊的 `trig_01ABYQAarHbVxBbEShiVWDr3`（綁 01Axcy）也還在，一起刪。本任的 87 提醒 `trig_01Kcpwka48kaPDBU1a8HccCU`（14:44 UTC）是本任自己用的；新任自己用 `send_later` 排巡查。
- **CI**：runner 的速度差到約 2 倍，慢的 runner 上 Swift 分片還是會接近 20 分鐘的上限。所以要合 #1189，以及每週量一次（§1 的 CI 線）。full lane 每次紅的都是不同的 UI 測試：b7793b97 綠；12c12354、82fffc7f、30e34922、584bdddb、947c23ad 各紅一兩支，原因多半是慢 runner 和教學卡片移位。同一支在 7 天內紅了 2 次就照 diagnosing-bugs 查；`testATouchHeldOnTheFoldedCard…` 已經 2 次。

**第九次換手（2026-10-24 08:00 UTC，session_017HD7Krh51WqqzXjy6949Pq 壓縮 2 次 → 作者從 claude.ai 開的新規劃）**。和下面不同時以這段為準。新任開工：讀第 1 節、這一段、第 3 節最上面幾列；#1041 只讀「session_017HD7Krh51WqqzXjy6949Pq 壓縮第 2 次」那則之後的留言。

- **合併了**（10-24，第八次換手之後）：#1170（交接）、#1160（397 iCloud 存檔）、#1172（決策 400 研究，main 684caacb）、#1171（391 續一，圖磚帶 `layer`，cf1ccdb6）、#1173（iCloud entitlement，81bd234d，合前有獨立審查）、#1174（10j-1 收購單一真實車站，30e34922）。私庫 #69（privacy.html：iCloud 那句改成「登入 iCloud 時」）。main 的 `ci.yml` 到 81bd234d 都綠；30e34922 的還沒看。這一批 4 個合完，**新任先等 30e34922 的 `ci.yml` 綠了再合下一批**。
- **官網**：`website-deploy.yml` 按了兩次（第二次在私庫 #69 之後），`curl https://www.alongthelinegame.com/privacy` 看得到 Game Center 與 iCloud 那兩段（VERIFIED）。Game Center 的 privacy.html 那件做完了。
- **第 87 版**（作者：「好 等兩個合完一起發87」「期間如果有新功能剛好也好了就順便一起發」）：範圍 #1160 iCloud 存檔、#1171 公路高架分層、#1173 entitlement、#1174 收購單一車站、Game Center（ASC 已建好），#1166 若合也算。還沒做：
  1. #1166 有結果後寫 What to Test 87.1（`.github/testflight-whats-new.md`），開 PR、合併；
  2. 那個 HEAD 的 full lane 與 `ci.yml` 都綠；
  3. 健康報告（§1.2）；
  4. 作者已說要發，照 CLAUDE.md 由規劃按 `testflight.yml` 一次。87 是第一個同時有 Game Center 與 iCloud entitlement 的匯出：匯出失敗先看錯誤說的是哪一個 capability，是 iCloud 就 `git revert d9b9cc6`（#1173 的 entitlement commit）再發；
  5. 記進 PLAYER_FEEDBACK，留「發版凍結解除」。
- **開著的 PR 與做中的 session**（都會 send_message 規劃「可合併」；新任接手後 send_message 每個 session 改通知新任）：
  - #1166（398 自有建築套件，session_01E26h8gQVHa51w79DJRAyv2，ready）：手動跑的 `LessonUITests.testDoubleTrackIsAbsentInTheFourthLessonAndReachableInTheFifth` 在舊 head 990cdcb9 兩次都在 `dismissGuide`（`LessonUITests.swift:413`）紅。對照：main 684caac 同一個測試綠（run 40074319020）。原因是分支沒有 #1163 改過的 `showGuide`／`pause`（先等卡片最多 10 秒、Pause 點不到再點）。01E26h8 把 main 合進去（只有 merge commit），**head 70fae6c7c19ef89f1483c24fbc94336a88148999**，正在用 `only_testing` 跑整個 `LessonUITests`（run 40076267074）。它會 send_message「可合併」，連同 40 字 sha 與 run 號碼；綠了且 PR 的 CI 綠就照 §1.2 合。合了之後封存 01E26h8；RecreationKit（自有建築第 2 批）照分數再排。
  - #1175（決策 401 第 1 件：收購支線時一起買下線底下的地塊，session_019YxcVGrDSUjGBqxpWQ5Mnc，draft）：GameCore 完整 tier。上一輪 `rest` shard 在 20 分鐘上限被取消，不是這個 PR 的問題（main 的 `rest` 也要 18.5 分鐘，PR 上有說明），正在重跑。動 GameCore 指令，不動存檔，不用獨立審查；綠了 019Yxc 會改 ready、留「可合併」，就照 §1.2 合。019Yxc 壓縮了 1 次，**第 2 件交回，要另派**。它查完沒修，寫進 #1175 的 `docs/decisions/401.md`「下一步」與 HANDOFF §5：
    - 地圖底下畫的真實鐵路，走向是對的（和 OSM、官方測量的中位偏差 2.2 m）。看起來不對的是資料簡化後的長直段，最長約 4.8 km。
    - 示範模式（`DemoRealLines`）鋪的軌道有三種問題：
      - 真實雙線鋪成單線：`layDemoRun` 鋪雙線失敗時默默退回單線。縱貫線臺北–板橋、捷運環狀線是 trackTooClose；崎頂–竹南、新左營–高雄、海線竹南–談文是 trackTooSteep；高捷紅線美麗島–左營是 trackOverWater。
      - 斷軌：最小半徑 40 m，文湖線斷 2 處、環狀輕軌斷 4 處。
      - 跳站：R 象山–台北車站、KR 前鎮高中–中央公園、O 永安市場–東門，中間沒鋪。
    - **作者問的是另一件，還沒有人做**：實景地圖 3D 畫的真實鐵路（決策 339，`Map3DRealTrains.swift`）。作者 10-24 問「要不要改成真實複線或單線 還有高度也是」，再補「不是示範鋪的是實景地圖裡面鋪的」，規劃答要做，作者「好」。要做的：
      - 照真實資料畫單線或複線（現在只畫一條）；
      - 高度照參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/physical/level-profiles.json`、`metro-display-profiles.json`，交會時誰在上照 `data/rail_crossing_levels.json`（OSM 的 layer），參考 `docs/rail-levels-0909.md`；
      - 補上玩家軌道旁 `playerClearance` 留下的缺口。
    - 新任開一個實作 session 做 3D 這件（只動 GamePresentation，決策號另登記）；示範模式的三種問題照分數排在後面。
  - #1176（391 續篇三：並排的橋只留外緣護欄，session_01T3bLvXC3Wm9dpcDF5WMjCj）：只動 GamePresentation，綠了就合。接著的「斷路接起來」（391 續篇二，`claude/road-joins-391`）做了實景底圖的部分，在 #1176 之後合；剩下的地面月台與種子道路在 §4.12 第 6 點。
  - session_018gwb44aL5MFmY8312pE3hD：10i-1（道路格子、路自己長、站前路，決策 400，**存檔 72**）。PR 綠了先開一個獨立審查 session（只給 PR 號碼與 CLAUDE.md），審過才合。它和 #1175 是同時跑完整 tier 的上限 2 個。
- **號碼**：決策 400 已合；401（#1175）登記了；下一個 **402**。存檔版本 72 由 10i-1 預約；golden 不動。
- **審查**：從 #1137 起算，還沒精算；新任先數一次，滿 30 點開一輪。
- **排程**：每日 Threads 開發日誌 `trig_01MuomHH45uKxbneGtK4xaLr`（綁 017HD7，暫停）：新任用同一份 prompt 建綁自己的（暫停），刪掉它。本任的巡查提醒已刪；新任自己用 `send_later` 排。
- **還沒派**（照 §22.2 的分數）：10f、10d、10k、11。作者 10-24 問「怎麼感覺好多實作都被擋了」之後，「先優化再加新功能」不再擋新功能：照五方分數排，每件派之前在 #1041 寫分數。
- **本任漏記**：第 1 次壓縮（06:58 UTC）沒有在 #1041 留「壓縮第 1 次」，第 2 次時一起補。

**第八次換手（2026-10-24 06:30 UTC，session_01AxcyajwHdF6j4ryDMghASM 壓縮 2 次 → 作者從 claude.ai 開的新規劃）**。和下面不同時以這段為準。新任開工：讀第 1 節（含 §1.1 新加的「作者提新事時，先排序再動手」）、這一段、第 3 節最上面幾列；#1041 只讀「01AxcyajwHdF6j4ryDMghASM（遊戲規劃）壓縮第 2 次」那則之後的留言。

- **合併了**（10-24，第七次換手之後）：#1150、#1159（391 公路橋）、#1156（396 Game Center 第一個 PR）、#1162（Game Center setup 工具）、#1158（成就圖 38 張與 entitlement）、#1165（本交接）、#1167、#1168（Game Center 排行榜格式）、#1164（399 Codex 列車，main 1c9dda03）、#1163（Lesson UI 測試，main e1bda5bd）。main 的 `ci.yml` 到 da7a9fb6 都綠；#1164 之後的還沒看，新任先看 main 最新的 run 再合下一批。
- **開著的 PR**（實作 session 都會 send_message 規劃「可合併」；新任接手後 send_message 每個 session 改通知新任；01MTVUo、01NDDS 已封存）：
  - #1166（決策 398，自有建築用 EstateKit／CoastalKit，session_01E26h8gQVHa51w79DJRAyv2）：draft、CI 跑中；第 9 課選飯店時建造選單多一排外觀選擇器，要看 iPhone UI 測試。改 GameCore 的 `looks`，算 2 點。
  - #1160（決策 397 iCloud 存檔，session_01MsxSwi6ituX5dsw6ZQNmEx，head d4216e6（又併過 main 解 project.pbxproj 衝突），draft）：獨立審查已過；和 main 合併後（e296a40）程式 diff 和審過的 bf5b522 一樣，只差文件。CI 綠了先改 ready、再用 merge commit 合；合後封存 01MsxSw，再派 **iCloud entitlement 的 PR**（container `iCloud.io.github.a91453.RailwayGame`；作者的 Apple 步驟已做完）。
- **做中的 session**：
  - session_01AhfV8HVyDQfkoqCY2FNbmY：決策 391 第二個 PR（圖磚照 `layer` 重切、§4.12 第 1、6 點「斷路接起來」），決策號沿用 391。
- **Game Center**：`game-center-setup.yml` 的 `apply` 在第 5 次成功（run 40070031235，06:30）：1 個排行榜、38 個成就與圖都建好了。前幾次失敗是格式：Apple 的 `recurrenceDuration` 只收只有時間部分的寫法（`PT168H`），`recurrenceRule` 只收 MINUTELY、HOURLY、DAILY（每週寫成 `FREQ=DAILY;INTERVAL=7`），修在 #1165、#1167、#1168。新任把決策 396 裡「Apple 收不收……仍是 UNVERIFIED」那句改成 VERIFIED（run 40070031235）。還沒做：第 5 步（送審時勾 Game Center，作者的事）、privacy.html。
- **號碼**：決策 396、399 已合，397（#1160）、398（#1166）開著；下一個 400。存檔版本 72 沒用；golden 不動。
- **審查**：從 #1137 起算，還沒精算；新任先數一次，滿 30 點開一輪。
- **排程**：每日 Threads 開發日誌 `trig_01ABYQAarHbVxBbEShiVWDr3`（綁 01Axcy，暫停）：新任用同一份 prompt 建綁自己的（暫停），刪掉它。本任的巡查提醒已刪；新任自己用 `send_later` 排。
- **還沒派**（照 §22.2）：RecreationKit 要新的建築種類（自有建築第 2 批，等 398 合併）；10/31 之後研究「2D 改用 3D 渲染器的俯視圖、不再用 MapLibre」。
- **MapLibre**（作者 10-24 問「需要不依賴 maplibre 用自製 map 了嗎」，規劃答「現在不用」，作者「好 那就照你說的」）：2D 的效能問題（決策 371、377、379）都在遊戲自己的程式，不在 MapLibre。等到這三件之一才重新評估：2D 與 3D 要做兩次的工作變常見；當機紀錄或幀數讀數指向 MapLibre；2D 要 MapLibre 做不到的功能。

**第七次換手（2026-10-24 05:00 UTC，session_01XsVqbA1A5wGtJbuAa881oT 壓縮 2 次 → 作者從 claude.ai 開的新規劃）**。和下面不同時以這段為準。新任開工：讀第 1 節、這一段、第 3 節最上面幾列；#1041 只讀「壓縮第 2 次」那則之後的留言。

- **86.1 已發**（TestFlight run 40051143234，commit 584bddd，作者已發給測試者；凍結解除）。紀錄在 PLAYER_FEEDBACK「0.5.0 (86.1)」。
- **合併了**（10-24）：#1146、#1145（86.1）、#1151（392）、#1153（86.1 full lane）、#1154（10k）、#1155（395）、#1152（394）、#1157（393 農地，main 85660009）。main 的 `ci.yml`：edaa7f00 綠，87b1c48d（40061101609）跑中，85660009 排隊。這一批 edaa7f00 綠了之後合了 #1152、#1157；再合 1–3 個就等最新的綠。
- **開著的 PR 與 session**（全部由規劃開的，都會 send_message 規劃「可合併」；新任接手後 send_message 每個做中的 session 改通知新任）：
  - #1150（full lane 重新分配，session_01VZJVMsPVmSxC3WeNiv9Yuw）：只改 CI 與 UI 測試，綠了隨時可合，之後封存 01VZJV。
  - #1159（決策 391，公路橋照 `layer` 架高，session_01MZ2KiwLCyJErN9jbfH6p78）：CI 跑中。#1157 已合，它要照 §4.12 用 `layer` 重切圖磚（若和農地圖磚衝突就併 main）。
  - #1156（決策 396 Game Center 第一個 PR，不含 entitlement，session_01V99archiZKLqZkwqTnsajc）：綠了可合。
  - #1158（396 成就圖 38 張）：美術審查 session_01T1XUaZrPxBZmiPFch6oLWZ 審完，13 張要改、全套要 1024 px，總覽在 `claude/art-review-1158:docs/game-center/review/overview.png`；01V99 改完再合，總覽圖用 SendUserFile 給作者看（作者：「那你記得請美術重新看過一次成就圖片」）。01T1XU 可封存。
  - session_01UNbeShXpVCYqZfpuchUPVe：Game Center 用 App Store Connect API 自動建排行榜與成就的工具（作者「用 B」；`game-center-setup.yml`，先 dry run 再 apply）。碰 secrets，**合併前要獨立審查**（§1.2）。
  - #1160（決策 397 iCloud 存檔，session_01MsxSwi6ituX5dsw6ZQNmEx）：在補兩項（新版存檔在舊 App 打開時顯示「請更新 App」、只同步玩家存檔與最新自動存檔）。碰存檔，**合併前要獨立審查**。存檔格式現在不改（規劃 10-24 判斷）。
  - session_01NDDS2s5myyGvhD26ZW26zB（`claude/lesson-pause-retry`）：86.1 分支 full lane 的 lessons 紅（`LessonUITests.pause()` 只給 Pause 鈕 2 秒，慢 runner 要約 4 秒，`testFreightYardsStartInTheEighthLesson`），修好推了、等 run 40063446628。只改 UI 測試，綠了可合，之後封存。
  - session_01QnjGxTmCx1sAYpH4wacqhH：#1151、#1157 都合了（「我就停在這裡」），可封存。session_01AdAQTbXs639m7Yd3ZoxLE7：394、395 合了，可封存。
- **作者的 Apple 步驟**（作者保留）：Game Center 的 ASC 頁面已開好（作者「我好了」）；iCloud：在 Identifiers 建 container `iCloud.io.github.a91453.RailwayGame`、App ID 勾 iCloud（iCloud Documents，不用 CloudKit schema），**還在等作者的截圖**。之後在 #1158 與工具合併後跑 `game-center-setup.yml`（dry run → apply），並確認 API key 的角色是 Admin 或 App Manager。entitlement 的 PR 在作者做完 Apple 步驟之後才開（可 revert）。TestFlight 也能用 Game Center 與 iCloud。
- **健康報告**：§1.2 的規則在本次的文件 PR。86.1 的第一份：規則與存檔綠（`ci.yml` 40051132292）；畫面與操作黃（full lane 4 個測試問題 #1153 修了；分支 lane 40060038516 second、iPad 綠，lessons 紅是測試等太短，01NDDS 在修）；發版綠（已上 TestFlight）；手機上要看的：隧道不畫地面是否省電、隧道裡的架空線、月台不撞、農地顏色。
- **號碼**：決策 391–397 已登記（391 #1159、392–395 已合、396 #1156／#1158、397 #1160）；下一個 398。存檔版本：397 若要改格式才用 72（現在不改）；golden 不動。
- **審查**：從 #1137 起算，估計還沒到 30 點（沒有逐個精算，新任開下一輪前數一次）。
- **排程**：每日 Threads 開發日誌 `trig_01AFVLnSeazUGc5ve1SprEqV`（綁 01XsVq，暫停）：新任用同一份 prompt 建綁自己的（暫停），刪掉它。01XsVq 沒有留巡查提醒；實作 session 自己的檢查提醒照舊。
- **之後**：照 NEXT_PRIORITIES §22 下一件；10k（玩家分享路網，不用伺服器，3.10）排在 Game Center、iCloud 之後。

**作者 2026-10-22 晚上的問題、規劃的決定**（五方都在 #1041）：地下透視做，開關預設關，排在隧道內部與地下月台之後（§22.2 10c）；只玩 2D、省電檔不做多重取樣、3D 不搬網頁（10g，在 10e 之前派）；五項效能排進 §22.2（10h 2D 大世界掉幀，要作者在大存檔與宜蘭線 6000× 的幀數截圖；25a、25b、41、42）。

**玩家回報的當機與卡頓（2026-10-22 23:30 UTC，遊戲規劃整理；細節在 PLAYER_FEEDBACK 77.1–82.1）**。和下面不同時以這段為準。
- 五位玩家、六則：77.1 #2（iPad（A16），列車多時跨 24:00、06:00 切速度卡頓後結束）、78.1 #11（iPhone 17 Pro 發熱後結束）、79.1 #5（iPhone 17 Pro，6000× 卡住）、80.1 #1（iPad Air M3，按「升級為複線」後卡住）、82.1 #1（iPad（A16），站多、切速度、點建設、買地卡頓）、82.1 #2（環狀線旅客沒被載到）。另有 81.1 #1 的建議（慢車自動待避，§22.2 第 20a 名，2.75，未派）。
- **升級複線卡住**：修在 #1059（session_01NQonNFtpUhUm4Vbo9krCKK；複線預覽的快取以 worldRevision 記，每個 tick 整份重算），放進第 83 版；決策 362 沒用。同樣以 worldRevision 記住的建造草稿寫在 §5。
- **卡頓、發熱、6000×**：session_011kVCxFJEULkYyGGU7emgsx，決策 363，分三個 PR：(a) 三個動作與跨 24:00、06:00 切速度；(b) §22.2 第 25a 名（決策 330 第 3 步，高倍速每次換世界整個畫面重算）；(c) 第 10h 名 2D 每幀，含不操作時降 2D 幀率上限。它壓縮 1 次就停，剩下的寫在 §7.1，下一個規劃再派人接。
- **環狀線沒載到人**：#1065（決策 364，session_01Efb7Sr7mZC2SiNXUtd1ZAa，`claude/loop-line-boarding`）可合併：環線列車停在第一站以外時每一圈都從那站起算，和旅客排的一圈對不上，改成繞過第一站再跑一整圈、之後從第一站起算；一列車的環線只排內環。`ReplayFixtures/long-leg-traffic.json` 重錄 checksum 1–5（作者同意）。還沒做的：作者轉來玩家的路線卡與車站卡截圖時，對照玩家的路線是不是環線、幾列車；兩種都不是就再查（決策 364「下一步」）；實機確認放進下一版的 What to Test。
- 第 83 版：#1057、#1059 合併後，What to Test 在 `claude/testflight-83-notes`；其他修好的進 84。TestFlight 的「當機意見反應」只有文字、沒有當機紀錄（作者 2026-10-23 截圖）。

**第六次換手（2026-10-24 00:45 UTC，暫代 session_01PGibJmGNcvu2d7dJWWhWVb → 作者從 claude.ai 開的新規劃）**。作者：「權限全部交接 記得看清楚」。01PGib 是換手鏈第 8 層（§1.1「換手」），`create_session`、`send_later`、建排程都被擋，只做合併與留言；新任是第 0 層，**全部權限交給新任**，01PGib 在新任接手後由新任封存。和下面不同時以這段為準。

- **已接手**（2026-10-24 01:30 UTC，session_01XsVqbA1A5wGtJbuAa881oT）：Threads 排程重建為 `trig_01AFVLnSeazUGc5ve1SprEqV`（暫停），舊的刪了；01PGib 已封存；§22.2 10e 剩下的部分（公路橋照 `brunnel`／`layer` 架高、國道高橋照 data.gov.tw/dataset/30616）派給 session_01MZ2KiwLCyJErN9jbfH6p78，決策 391。86.1 照下面的順序：#1146 → #1145。
- **交給新任的權限與職責**（全部照原文，不多不少）：
  - **合併**（作者 2026-10-21 授權，§1.2）：綠了的 PR 用 merge commit、帶 `expectedHeadSha` 合；一批 3–5 個，兩批之間等 main 的 `ci.yml` 綠；只改文件、只改 UI 測試或 CI 腳本的隨時可合。不開 auto-merge、不 force-push、不推 main、不取消 main 的 push run。
  - **派工**（§1.3）：用 `create_session` 開實作 session，照 NEXT_PRIORITIES §22 一條線一次一個 PR；實作 session 同時最多 3–4 個；同時跑全套 Swift CI 的 GameCore PR 最多 2 個；派工單寫好決策號、存檔版本。
  - **封存**（作者 2026-10-23）：PR 開了、CI 綠、#1041 有「可合併」、後續寫進本檔的實作 session 就封存，不用等合併。**新任確定在動後，封存 01PGib**（標題改成「【舊・已換手】…→ 改用 <新任 id>」）。
  - **巡查**：自己用 `send_later` 排（01PGib 排不了，沒有留下任何提醒）。
  - **TestFlight**（作者 2026-10-23「改成我說可以發你才能替我發」）：只在作者在**遊戲規劃 session 裡**說「發」之後，`main` HEAD 的完整 `ci.yml` 與 full lane 都綠、What to Test 已合進 main，才用 `workflow_dispatch` 跑一次 `testflight.yml`；否則告訴作者哪裡紅。自動模式可能擋下，就照 §1.2 請作者自己按。
  - **審查**：滿 30 點開一輪（§1）；下一輪從 #1137 起算，目前約 1 點（#1137 GamePresentation、#1140 只改 UI 測試 0 點）。
  - **五方**寫進 PR 與派工單；頭像與美術先照 art-style 審過再給作者看；What to Test 每版都要寫。
  - 作者保留、新任也不能做的：Apple 帳號與 App Store Connect、secrets、加依賴、copyleft 或沒授權的程式碼、在作者沒說「發」時發版。
- **排程**：每日 Threads 開發日誌現在是 `trig_01Hre19DLcYMRt2yiktxHWFY`（綁 01PGib，暫停）。新任用同一份 prompt（`get_trigger` 讀得到）建一個綁到自己的新排程（作者沒說要開就維持暫停），再刪掉這個。
- **開著的 PR（00:45 UTC）**：
  - #1119（Codex 雙聯蒸汽，head 1f1ebbe4）、#1121（Codex EstateKit，head 31ef7ef0）：CI 跑中，綠了轉 ready 合併（Codex 沒有 session 可通知）。
  - #1128（決策 379（續），session_01MhQXufQK6jhjrKXY6iUTDB）：在併 main、解衝突，要跑全套 GameCore CI；它會通知規劃。
- **做中**：session_01GaPJUuAAMyqKsvxJjpnhEf（SettingsUITests 兩支）。它和 01MhQX 都被告知「通知規劃」；新任接手後在 #1041 留言，並用 `send_message` 告訴這兩個改通知新任。
- **main**：6426b9c9（#1141）。`ci.yml`：08fe5ab6 綠，73753863 跑中，6426b9c9 排隊。
- **號碼**：下一個決策 391；存檔版本 72（main 是 71）；golden 不動。
- **等作者**：同第五次換手的「等作者」三項。
- **稽核 01H5RH**（2026-10-24，作者：「檢查一下10/23那個session有沒有因為太長而做錯我給的劇本或是設定」）：讀了它全部 2,829 筆紀錄、147 則作者訊息、12 次壓縮。四份劇本（平溪、劉銘傳、集集、三鎮／造鎮／大亨）逐句照作者原文進了 repo，只改 4 句，理由都寫在決策 387。錯的：(1) 壓縮 12 次沒換手、沒留「壓縮第 N 次」（作者提醒才換，已由 #1141、#1143 補規則）；(2) 換手時把次數寫成 2 次（已改）；(3) 第 84 版沒寫 What to Test（#1088 已補成規則，85.1 照做）；(4) 本檔挑戰劇情那一列過時（已改）。只確認到「已派工」、沒查結果的：taste-skill 網站部署、機場不住人與斑馬線等 PR 是否都合併。

**第五次換手（2026-10-24 00:35 UTC，session_01H5RHAwnA69n8EfAUSUrH52 壓縮 12 次（2026-10-24 讀紀錄數的；換手時寫成 2 次是錯的）→ session_01PGibJmGNcvu2d7dJWWhWVb）**。作者：「你要不要換新session 壓縮已經超過2次以上了吧」。和下面不同時以這段為準。

- **量到的**：前任做了約 24.5 小時、壓縮 2 次以上，約 $116（`get_session` 的 `usage`），換手時 28 萬。
- **合併了**（10-23 這一天）：#1110、#1108（379）、#1127、#1129、#1133（審查 F）、#1130、#1134、#1135、#1136、#1124、#1132、#1126、#1113、#1115、#1138、#1122、#1139（審查 G）、#1125、#1137（390）、#1140；作者另合了 #1131。作者睡前「綠了就合併 滿30點記得pr review 現在這批都過了才加新功能」：那一批已合完，可以照 NEXT_PRIORITIES §22 再派新功能。
- **main**：73753863。`ci.yml` 8ebefabd 綠，08fe5ab6 跑中，73753863 排隊；最新的綠了才合下一批。
- **開著的 PR**：
  - #1128（決策 379（續），GameCore tick 加速，session_01MhQXufQK6jhjrKXY6iUTDB）：#1108 先用了 379，它把自己那段改成「379（續）」，正在併 main、跑 golden／存檔／重播測試；綠了轉 ready、通知規劃。全套 GameCore CI。
  - #1119（Codex 雙聯蒸汽機車）：前任把 main 併進去（1f1ebbe4，`Map3DModelTests` 的模型數兩組都算、§7.3 兩段都留），本機建置與模型測試過，CI 跑中。綠了轉 ready 合併。
  - #1121（Codex 住宅街廓 24 棟＋4 景）：沒有衝突，CI 跑中。綠了轉 ready 合併。美術：屋頂與牆全是米色、灰色，接上地圖時要加顏色變化。
- **做中**：session_01GaPJUuAAMyqKsvxJjpnhEf（`claude/settings-tests-landscape`）：ff8e4dda nightly full lane（run 40026341039）兩個 SettingsUITests 紅。
- **號碼**：下一個決策 391；存檔版本 72（main 是 71）；golden 不動。
- **審查**：審查 G 到 #1136；下一輪從 #1137 起算，約 1 點。
- **等作者**：railway-reference-private PR #67（頭像預覽）合併（規劃被自動權限擋下）；#1125 的三個對齊取捨要實機看；下一版 What to Test 放高鐵 6000× 的實機重量。
- **排程**：前任的巡查提醒已刪；每日 Threads 開發日誌改成 `trig_01Hre19DLcYMRt2yiktxHWFY`（綁新任，暫停），舊的 `trig_014ibKY35K534uorD2a3L5us` 已刪。

**第四次換手（2026-10-23 00:10 UTC，session_014nUBHbE9mSK4qXHHgm8xCQ 壓縮 2 次 → session_01H5RHAwnA69n8EfAUSUrH52）**。和下面不同時以這段為準。

- **合併了**（43b5b011 起這一批）：#1058（玩家回報 77.1–82.1）、#1057（決策 360 第一步，3D 跟車最高 10×）、#1059（升級複線卡住，80.1）→ main 4e18ee8b。之前還有 #1056、#1052（決策 359）、#1048（358）。main 的 `ci.yml` 在 719d3d09 綠，4e18ee8b 那次交接時還在跑。
- **第 83 版**：程式到齊。What to Test 在文件 PR #1062（head 4150e4c9，gate 綠）；4e18ee8b 綠了就合，合併後的 commit 就是 83 的 commit，等它的 `ci.yml` 與 full lane 都綠再告訴作者「可以發（commit X）」。
- **做中**（合併後收工，「可合併」留在 #1041 並 send_message 給規劃）：
  - session_014NB8yWZmutMBX3jDsXC3Sm：#1061 隧道本體（決策 359 續一，壓縮 1 次，只做完這個）。地下月台與地下透視開關寫在 359.md「續一之後還沒做」，要再派。
  - session_01KAjPfBFs9fKJcLV9JsgRC4：#1060 自有建築公園與廟（10d，存檔 71、決策 361，GameCore）。
  - session_01Q3q6JL8VvzYZShXTQRTsoz：仲夏寶島號。
  - session_011kVCxFJEULkYyGGU7emgsx：卡頓、發熱、6000×（決策 363，三個 PR，見上一段）。
  - session_01Efb7Sr7mZC2SiNXUtd1ZAa：環狀線旅客沒被載到 → #1065 可合併（決策 364，動 GameCore；見上面「環狀線沒載到人」）。
- **號碼**：決策 362 釋出，下一個 365；存檔下一個 72。
- **排隊**：360 第二步（沿線預載、霧）、10g、10e、10f、20a（慢車自動待避）。§5 的同類預覽（`NetworkSession` 草稿、`PassingLoop`、`DepotYard`、`LevelPlatformTrack`）在 #1129 改以 commandRevision 記。
- **審查**：從 #1031 起約 21 點（#1057、#1059 各 1），滿 30 開一輪。
- **排程**：每日 Threads 開發日誌 `trig_016U9uyaff5jSPvx4fZNbAp1`（暫停）綁在前任；新任建一個綁到自己的、刪掉舊的，新 id 寫在 #1041 接手的留言。
- **等作者**：環狀線玩家的路線卡與車站卡截圖；大存檔的幀數截圖。

**第三次換手（2026-10-22 22:30 UTC，session_01UsF4QYCGrzSeNSFq11i8Wu 壓縮 2 次 → session_014nUBHbE9mSK4qXHHgm8xCQ）**。和下面不同時以這段為準。

- **合併了**：#1037、#1039、#1040、#1043（決策 356）、#1044（決策 357）、#1045（鳴日號）、#1046（iPad 委託案旗子）、#1047（環島之星，main 24bd3875）、文件 #1049、#1050、#1051。這一批從 b136e84b 起只合了 #1047；等 24bd3875（或之後最新的 push）的 `ci.yml` 綠再合下一批。
- **開著的 PR**：#1048（決策 358，3D 邊開邊載入，session_01DQGby5PQyfvKAmzTey1zVE，壓縮 1 次）、#1052（決策 359，隧道第一步：隧道裡的列車不畫、跟車鏡頭留在地面，session_0134bAxAfAEENYWu1NaK1RWW，壓縮 1 次）。都是 draft，綠了轉 ready 就合併；兩個 session 合併後收工。
- **做中**：session_01KAjPfBFs9fKJcLV9JsgRC4，§22.2 第 10d 名自有建築（公園、廟），存檔 71、決策 361，`claude/owned-building-kits`。
- **號碼**：決策 358、359、361 已登記未合併，360 預約；下一個空的決策號 362，存檔版本 72。
- **排隊派工**：
  1. #1048 合併後：決策 360（3D 駕駛艙速度上限）。兩個 PR：先在 3D 跟車時速度最高 10×（用 600× 開 3D 就改用 10×，離開 3D 回到 2D 原本的速度，2D 不變）；再做沿路線的走廊載入（往前 6 km、軌道兩側各一格，岔路兩邊各蓋一小段）加駕駛艙的霧（1.2 km 起、2 km 全白、天空色，俯瞰不加），停下、10× 以下或看側面時補蓋周圍 3 km；實機量過再調高上限（估 30–40×），跟不上自動降一檔，用現有的「跟不上」提示。作者原話：「邊開邊載入的上限是多少速度 例如最高600x 你在駕駛艙速度那欄就改600x 防止載不出來 但是原本2d的速度不變」「所以調窄 調霧有用摟」。細節在 #1041 22:09–22:14 的三則規劃留言。
  2. #1052 合併後：隧道的下一步派新 session（0134 壓縮過，不接新工作）：隧道口接地形與路塹、隧道內部與隧道燈、地下月台，用現有的 3D 套件組（作者：「那要不要畫隧道燈的地下 跟隧道月台 用現有codex素材組的出來嗎」→ 要；「記得改成遊戲風格而不是照搬」：照 art-style §7 任意組合、成品跟原本不同）。見決策 359「下一步」。
  3. 之後依序：§22.2 10e（3D 道路照真實高度）、10f（不同的高架橋），兩個都改 `Map3DScene.swift`，排在 359 之後；然後仲夏寶島號（第 11 名）、第 7 名其餘、第 14 名……
- **TDX 查過沒有道路高度**（作者：「精確高度如果要抓的話Tdx抓的到嗎」→「好，去跑 TDX 查一下」；2026-10-22 `tdx-check.yml` run 39865308650、39865353614）：`/api/basic/v2/Road/Traffic/SectionShape/Freeway` 只有平面的 LINESTRING；`Section/Freeway` 有路名、里程、速限、LinkID，沒有高度、高架或橋梁欄位；TDX 的道路路網線型只有國道與省道。所以 10e 照圖磚的 `brunnel`／`layer`（每層約 6 m）做，不用 TDX。
- **E1**：作者說還沒要上 App Store，不派、巡查不提（第 5 節）。
- **排程**：Threads 每日排程由新規劃重建（暫停）、刪掉綁在 01UsF4 的 `trig_01YPQ4fTJtzar7o3upbBQBE9`；01UsF4 的巡查提醒換手時已刪，新規劃自己排。

**第二次換手（2026-10-22 18:30 UTC，session_01Ddr2wiXx1Xhn2m9qNBDnDh 壓縮 2 次）**。這一段以下是上午換手時寫的，和這段不同時以這段為準。

- **合併了**：#1034（8c7b8e6d）、#1035、#1036（4095e8f6，`ci.yml` 綠）、#1038（f3c0d717，決策 355）。4095e8f6 綠了之後這一批只合了 #1038，還能再合 2–4 個。
- **main 已有的決策**：352、353、355。**354**（月台卡片，session_01Bajcx7SuZfZPAaLTq8DWM5）與 **356**（Fresnel，session_0136FXagwq4pwPNs3d9vWUHN，已壓縮 1 次）已登記、還沒合併。**下一個空的決策號是 357**；存檔版本 70。
- **開著的 PR**：#1037、#1039（session_01Hmkv6wxPNTX4HFyKxMeBcC，main full lane 的第 5 課與 3D 拉近測試，只改 UI 測試）、#1040（session_01XZM7WBK1v1RdHJdynRfngs，iPad 三個 UI 測試，其中地圖鎖的點擊範圍是 App 的修正）。都是 draft，綠了各自轉 ready；只改 UI 測試的隨時可合。
- **main 的 full lane**：29ebf5ed 與 8c7b8e6d 的紅都已有人修（上面三個 PR）；合併後看下一次 full lane。
- **還沒派**：§22.10 第 6 項（太陽的陰影貼圖）；§22.2 #10a（3D 預先載入）與 §22.2 其餘照順序；E1（演示模式的編譯旗標，App Store 送審前一定要做，見第 5 節；作者 2026-10-22：「還沒有要上 app store 先幫我記著 我要上再跟我說」，先不派、巡查報告不再提，作者說要上 App Store 時再提出來）。
- **排程**：Threads 每日排程 `trig_01MBWsHEjEzt6VzQ6BskFpku` 暫停中、綁在本 session；新規劃重建一個綁自己的（暫停）後刪掉它。本 session 的巡查提醒換手時刪除，新規劃自己排。

作者 2026-10-22：「要不要全部所有換個session了 都一直在壓縮了」→「好，照表換」；「壓縮到一定次數後幫我更換新session 指派的也一樣」。各 session 在手上的 PR 合併、#231 的登記結束之後才換，不在做到一半時換；要接手的事寫在這裡。

**開著的 PR**（2026-10-22 12:00 UTC）：
- #1020（決策 350，地圖的範圍、3D、縮放鈕，session_013fMmahDsHF9xHba1mJyASm）：ready，head d9fdb2bd。iPad 那個紅的 job 是手動的診斷 run，不是 PR 自己的；PR 自己的 iOS run 39761671036 綠。013f 在 d9fdb2b 跑一次只有 iPhone 的 `only_testing`，綠了就照第 1.2 節合併。`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 在 main 71a3807 也紅（run 39765719731），不是 #1020 造成的。
- #1025（決策 349，3D 色調，session_01H2iSUj5f1cCXAwjvuFvbsp）：draft，綠了它會轉 ready。

**main 的批次**：上一個綠的 `ci.yml` push 是 82ce09e9（#1021）。之後合了 4 個：#1019（決策 344，GameCore）、#1023（公園修正）、#1027（CI 優化的頻率）、#1026（演示模式 1/2，決策 351），main f565326f。這一批還能再合 1 個（#1020）；其他的等 f565326f（或之後最新的 push）的 `ci.yml` 綠了才合下一批。

**下一個空的決策號是 352**（351 已用；有人在 #231 登記了更大的號就用那個加一）。

| 線 | session | 做到哪 | 下一步 |
| --- | --- | --- | --- |
| 遊戲規劃 | 新 session（接 session_01CHQg7B6JqzbScGSjyDwHos，id 寫在 #231） | 舊的壓縮 2 次換手；#1012–#1019、#1021–#1024、#1026、#1027 已合併 | 第 1.1 節；開工先讀第 1 節、這一節、第 3 節開頭 |
| 地圖按鈕（決策 350） | session_013fMmahDsHF9xHba1mJyASm | #1020 ready | 合併後收工 |
| 3D 城市（§22.10） | session_01H2iSUj5f1cCXAwjvuFvbsp | 第 2 項色調 #1025 | 已壓縮 1 次：#1025 合併後收工，第 3–6 項寫回第 4 節 |
| 演示模式（決策 351） | session_01Q6ucfu4uY1YiX1buRCZzFr | PR 1 #1026 已合併；PR 2「鋪好這一帶的真實路線」在 `claude/demo-mode-real-lines` | PR 2 綠了轉 ready 合併 |
| 發版前小審查（#1019 起的程式 PR） | session_012YaVnnbN5pq9pjh53FF4RC | 進行中，範圍含 #1026 | 報告寫成 `docs/archive/PR1019_<N>_REVIEW_HANDOFF.md`；回報「可以發」或 P1、P2 修正 |
| Threads 貼文草稿 | session_01QAC77cR5wi8UFqoLxMDVH6 | 照作者給的前幾天貼文排今天的發文 | 只寫草稿、用 SendUserFile 給作者，不 commit、不發文 |

**發版前**（作者 2026-10-22：「演示模式做完 我就差不多要發文了 所以做完這項看需不需要pr review 我就發那版 跟發文」）：
- 這次是 TestFlight 第 82 版（上一版 81 是 #1003，7fc0d373），新的是 #1004 起。
- 演示模式兩個 PR 都合併；發版前小審查（上表）的 P1、P2 修正全部合併。
- 選定的那個 commit 在 main 上的 `ci.yml` 與 full lane 都綠了，才告訴作者「可以發（commit X）」，並告訴 Threads 草稿 session。`testflight.yml` 由作者自己按。
- Threads 每日排程（`trig_01FZhfBNQCdDW8iDpowANLZS`）維持暫停；它綁在舊規劃 session 上，新規劃照第 1 節那一列重建一個綁自己的（暫停），再刪舊的。發文由作者自己發。
- 舊規劃的巡查提醒 `trig_0195QqR2dnriwyNw5SrQT7Jr` 換手時已刪，新規劃自己排巡查。

**下一個空位依序派**（第 1 項演示模式已在做，見上表）：
1. **演示模式**（作者 2026-10-22：「要不要設置一個開發者模式 解鎖所有東西跟路線 不然我要演示都只能自己拉」）。設定裡一個開關，預設關。**藏起來**（作者：「要藏隱密一點只有我按得到嗎」）：只在測試版出現（Xcode 與 TestFlight，用決策 338 的 `TestBuild.isTest`），App Store 版完全沒有，因為 Apple 審查不准有隱藏功能；測試版裡也要在設定的「版本」那一列連點 5 下才出現，別的測試者不會誤開。打開時：課程、挑戰全開；新局自動無限資金、地圖擴張全開；實景地圖多一顆「鋪好這一帶的真實路線」，照現有示範（`RealWorldDemo`、`HighSpeedDemo`、`TRADemo`）的建法，把畫面範圍內的台鐵、高鐵、捷運鋪好並排車；成就與紀念章不算（和示範一樣）。前三項一個 PR，一鍵鋪路線另一個 PR。不升存檔、不動 GameCore。五方：玩家（演示一開就有車跑，一般玩家看不到也碰不到）、鐵道迷（鋪的是真實走向）、開發（用現有指令與示範建法）、美術（一個開關一顆鈕）、音樂（無）。
2. 網頁 `Web/CityView` 看得到的「技術試作」標示（NEXT_PRIORITIES 隨時可派的小修第一項）。
3. 之後照 NEXT_PRIORITIES §22.2 的順序。

已做完、2026-10-22 封存的：session_018gQPWzopcCfuR9gTAApKTj（#1019，決策 344）、session_01TCwdHtJTq9REwDrCSHzR11（#1024，審查 D）、session_014APxWZsoEbwngV3qd6QZtr（#1016，車站紀念章）、session_01T8UdZRFmxs93DFtUKX5V73（#1012，雨聲雷聲）、session_01MsTCquc1D1FqFiEdn6j3fz（#998）、session_01RU6kM49KUK5VFvU5osr8eP（決策 333、334、337：3D 跟車視角、下一班飛到月台、前面展望）、session_01QiPq4nZdq5bVS9MZ4rkr4L（#966、#970、#984；A6 與 A11／B7 還開著，§7.1）、session_01VVzExSvZcTej5eCqxdUEpY（審查 C #945–#961）、session_014SH8oLiB8EPtSm4afuuxNn（決策 335）。

**作者 2026-10-22 回報、已修**：廟、公園、站前店畫成全黑（#1008，套件模型放進場景時法線是零）；1× 時跟車與駕駛室一頓一頓（#1010，1× 一個遊戲秒要 10 個 tick，列車只滑 0.1 秒就停 0.9 秒，改成整秒滑完）。兩個都待實機確認。

**新任第一件事**：核對 NEXT_PRIORITIES §22.1 與 §22.2，把已合併的搬到 §22.3：第 1、4、5 名（決策 333、337、334）、第 7 名的第一項（決策 343）、第 15 名的前兩項（決策 342、345）；第 2 名（找不到的四個入口，session_01MsTCquc1D1FqFiEdn6j3fz）與第 3 名（素材包）做到哪要查 main 與 #231 再寫，§22.1 改成上表。


作者 2026-10-17 讓各線開工，合併交給遊戲規劃（「交給你綠了就合 紅了解衝突」、「由你四方思考後決定」）。分工照 `AGENTS.md`：Claude 做核心與整合，Codex 做 UI 測試、工具與獨立審查，Antigravity 做網頁試看與畫面。

| 線 | 誰 | 狀態 | 下一步 | 動 GameCore |
| --- | --- | --- | --- | :-: |
| 核心玩法：規則、配車、關卡、回饋第二批 | session_01Q48iRY9H6EmeUL8NPyfiDW | 第 1–5 個 PR 與決策 264 的後續已合併（決策 258、264、266、271）；收尾 #779（決策 273）；回饋第二批全部做完：#780（決策 274）、#792 每趟蓋章與 #795 長按路線看旅程（決策 276）；#785 延後的三項 #789（決策 275）、#790 | 高鐵示範（NEXT_PRIORITIES §16 第 4 項）：快轉 #801 已合併；#669 的長進路死結與台南—左營交會是決策 278（#804，已合併）：號誌開＋閉塞時白天不再死結、取消 60 → 45 班。北端夜裡的死結是決策 280（`claude/hsr-north-depot-room`：機廠有空股才入庫，機廠的股道算終點站的盡頭；取消 45 → 32 班）；計算時間是 `claude/hsr-traffic-speed`（結果逐位元不變，`docs/research/APP_TICK_COST_2026-10-18.md` §6）。左營出入線是決策 281；南港咽喉與照地形建是決策 283（`claude/hsr-nangang-throat`）。左營咽喉白天的死結是決策 287（`claude/hsr-zuoying-throat`）：看了第一個死結，是調度不是軌道。閉塞分界設在上行線匯入的斜線旁（決策 281 為出入線加的節點），進站的車停在那裡擋住出站的路，和要讓出股道的閒置車互等；分界改成只設在列車停下來不會妨礙別條軌道的地方，取消 86 → 44 班（平地 129 → 46）。照地形建時夜裡出庫的死結是決策 290（`claude/hsr-zuoying-depot-exit`）：有班次的路線，終點站有一股沒有車停、也沒有車正開往才從機廠出庫，並開往那一股；照地形一天取消 44 → 30、每小時結束時都沒有死結（平地 46 → 33）。「剛入庫 16 分鐘又出庫」是另一個機制（班次晚了、在等的車拿不到路時，出庫的判斷把它們當成趕不上），試過讓兩邊一致，量了變差（照地形 30 → 40），不採用。決策 290 之後剩下的取消逐班分類寫在 `docs/research/HSR_SIGNAL_BASELINE_2026-10-15.md` §13：最多的是接班的車晚到（晚點四成多來自快車跟在慢車後面，排定待避一次都沒排出來），其次是左營咽喉被一百多 km 外的進站車整段占著。決策 294（`claude/hsr-overtake-approach`）兩條一起改：時刻表裡的待避照排（慢車停側線等快車，最多多等 5 分），長區間的列車離站 14 km 內才排進站的路；照地形取消 30 → 13、平地 33 → 22。只做其中一條時某一種建法會變差，數字在決策 294 的「試過、不採用」。機廠與終點站之間的來回（作者這輪的第 3 步）由 session_01KFRB53UNrJR1yVGu2fGJog 接手做成決策 296（`claude/hsr-depot-shuttle`）；作者提的車輛運用（原車接下一班、閒得久的才入庫）試過、不採用（照地形取消 13 → 24，數字在決策 296「下一步」第 1 點的「之後」）。平地白天短暫的死結（第 4 步）是決策 297（`claude/hsr-flat-deadlocks`，session_01KFRB53UNrJR1yVGu2fGJog 開工、session_011GLH8sEjxxMsy2VEXa8szu 接手）：台中、左營月台上等下一班的閒置車擋到進站的車，那站沒有一班要開時就入庫；照地形取消 13 → 4、平地 18 → 2，每小時結束時都沒有死結，代價是機廠進出多了 2.5 倍。往前看 30／60 分、換月台不算後面的車、只在中間站生效，四種都量了、不採用（決策 297「試過、不採用」）。決策 297 的「下一步」第 1–3 點是決策 302（`claude/hsr-depot-churn`，session_011GLH8sEjxxMsy2VEXa8szu）：一組正在路上的車預估比出庫的車先到時，算成接得了那站的班，不再從一個半小時外的烏日機廠派車；台中 08:04 不再取消，照地形取消 4 → 2、平地 2 → 1。「擋路的車入庫前先看來回趕不趕得上」量了、逐位元相同；「在路上的車都算接得了」讓沒有閉塞的組合 21 時起卡死，都不採用。晚點的車追回時間是決策 306（`claude/hsr-catch-up`，session_011GLH8sEjxxMsy2VEXa8szu）：號誌與閉塞打開時，晚點的列車照到表定到站剩下的時間跑，最快照車的性能與彎道限速，不超過設計時速；照地形 取消 2 → 1、晚點中位數 7／11／9 → 3／3／9 分、平地取消 1 → 1、晚點中位數 4／10／11 → 2／4／9 分。沒有閉塞時也追回會在夜裡互等（台南的進路宣告、左營咽喉與要入庫的閒置車），量了、不採用。**交接：決策 302 的「下一步」第 1–3 點**（晚到的車停下那一兩分鐘的出庫、南港咽喉的取消、左營月台的互等）**與決策 306 的「下一步」**（沒有閉塞時的兩個互等與追回時間、平地五站停晚 93 分的那一班）。決策 306 之後還能做的五項、估計與順序在 §5；第 1 項（沒有閉塞時的互等）是決策 308（`claude/hsr-no-block-catch-up`，session_0125dMtwyMdz7mzoBCRNa1pn）：跟車的宣告放開擋住前車的車（台南）、不往終點那股要結束班次的車靠近並早一點換股（左營），條件放寬到沒有閉塞；號誌開、沒有閉塞時照地形取消 85 → 77、晚點中位數 69／74／144 → 46／43／62 分，平地 85 → 79、29／38／59 分，夜裡不再有車等到天亮；閉塞與號誌關的組合逐位元不變。剩下的在決策 308「下一步」。決策 294「下一步」其餘四點還沒人做：出站的路上停著的車不能跟（決策 212 的 (C)）、咽喉的容量與南港往台北共用上行線（軌道，§10）、計算時間（一天照地形 1,657 秒）、要不要讓示範的號誌與閉塞一起打開。第 6 個 PR（GameCore 的新目標）先不做。UI 測試交給 Codex（決策 266、271、273、274、276 列了要補的） | 是（決策 280、283、287、288、294、297、302、306、308） |
| 3D 生活感 | Claude session_01EPkWLr5a25LyJvCuvh1U3R | 四步完成：#734（259）、#745（263）、#765（267）、#768（268）、#769（269）、#771（270）；#770 收尾 #752；#772 修 71.1「3D 一放大就跳回 2D」；#776 配色亮度（決策 272）；#788 場景快取；#793 Meshy 試做模型規格與讀檔；#794 雨天的光線與霧（決策 277） | 決策 277 的後兩步：(a) 雨絲：2026-10-21 由 3D session_01Y25x9NJSKmAuP1M1K3Sf3C 做完（決策 320，`claude/map3d-rain-streaks`；實機的樣子與幀數還沒看）；(b) 站前商店街（條紋雨遮、屋頂立牌、下照燈）。**已解鎖**：作者 2026-10-21 的實機幀數（iPhone 17 Pro，台北近景 CPU 2.4–3.1 ms、GPU 2.2–2.7 ms，PLAYER_FEEDBACK 72.1 節）只用了一幀的兩成；交給 3D session_01Y25x9NJSKmAuP1M1K3Sf3C（派工的第 3 項）。店名、站名、招牌配色要換成本專案自己的，不沿用參考原作那五家店與「晴川站」（art-style §7） | 否 |
| 關卡的 UI 測試、full lane、GLB 轉換器 | Codex | 三張卡都已合併（2026-10-18）：#784 關卡 UI 測試（`LessonUITests` 12 個，決策 271 列的五項都有）；#802 full lane 拆工作（`LessonUITests` 自己一個 iPhone job `FULL_LANE_LESSONS_JOB`、`-lesson-stars` 檔名常數改 public、`FlexDispatchPropertyTests` 搬到較短的 shard）；#803 GLB → `.m3dmodel` 轉換器（`tools/glb-to-m3dmodel/`，Meshy 公車 1,543 面、8 色）。之後 #821 Peakline 圖資研究（§4.5） | (1) 公車模型接進 App：3D session 做（`Resources/Models/`、XcodeGen 重新產生 `.xcodeproj`、取決策號；模型在 `docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel`，轉換器已把車頭轉成 +x）；(2) meshopt／量化與 `.gltf` 橋接已實作於 `codex/glb-meshopt-bridge`，使用／接手點見第 7.3 節；App 接入仍由 3D session 做 | 否 |
| 開發工具 | Claude session_011Z9h1X1GcZZ3i1EKEEjDZj | `GameSim` #740（決策 260）、`Policy` #748（決策 261）、文件數字檢查 #760 都已合併 | 第 7.4 節剩下的項目 | 否 |
| 示範地圖照真實的高架與隧道（決策 279、281） | Claude session_01KeynzCwtDyLHTUYBfKxy1c（作者直接交辦） | #805、#807、#808、#809 已合併（瑞芳／平溪示範、宜蘭線示範、沿真實鐵路描線、參考庫新版）；`claude/hsr-real-structures`：左營機廠的出入線；高鐵示範照真實高架與隧道的建法做好，開關先關（決策 281） | Claude platform 做完（`claude/hsr-nangang-throat`，決策 283）：南港咽喉的卡死修好（遲到的車還在終點站的股道上，進站的車改去空的一條；沿路看對向車 20 km；兩列都還沒上共用軌道時遠的等近的），開關打開，號誌關的一天 `HighSpeedDemoDayTests` 全過。號誌開＋閉塞重量的結果：左營咽喉白天就卡住（平地 09 時、照地形 16 時起），下一步見決策 283。決策 287 看了第一個死結：是閉塞分界的位置（調度），不是出入線和進站的車共用咽喉，**軌道這邊不用改**。決策 290 做完夜裡出庫的死結（調度：終點站有空股才出庫），重量一天：照地形每小時結束時都沒有死結，所以**軌道仍不用為了死結改**。軌道這邊之後可以評估的（都不急，是示範的真實度與咽喉容量，不是死結）：出入線分成入庫、出庫兩條；左營咽喉照真實改成雙線加交叉渡線（現在八股只靠下行線上一串轉轍器） | 否（決策 283、287 動 GameCore） |

**main 的 full lane 紅燈（遊戲規劃 2026-10-20 派工）**：main 的 `ios-build.yml` full lane 從 784bb3a（#833，10-19 16:41）起連續 7 次紅，最後一次綠是 ae77ab4（#827，run 39254620337）。每次都紅的是 `LineDraftSummaryUITests` 兩個（#835 新加）、`NextStepChipUITests.testANewGamesNextStepOpensTheGoals`（#842 新加）、`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`。時紅時好的是 `LessonUITests` 第 8、9 課（清單捲不到按鈕）。已派 session_01MV9BgbHcs7XFafNDk76DyD：先分清楚是 App 的 bug 還是測試過時，再修，用 `only_testing` 驗證。修好以前不發版。
  - **修了**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-red-1020`，原因與證據在那個 PR 的說明）：`NextStepChip` 不是按鈕（App）；路線面板加第一站後停在原處、表單在畫面外（App，決策 299）；月台測試點到 #839 的涵蓋捷徑、第二個月台的偏移超過 80 m 月台（測試）；第 8 課的拖曳落在面板的捲軸上（測試）。
  - **還沒查**（修完後的 full lane 再紅才查）：第 9 課 `testTheNinthLessonsSightOpensItsTourismPanel` 只在 784bb3a 紅過一次，那時 #840 還沒合併，和它無關；`CoverageShortcutUITests:16`、`LineDraftSummaryUITests:75` 的 `Failed to get background assertion`（Simulator 逾時）；`StartSaveFlowSmokeTests:499` 的 `menu.backToStart` 沒停穩。各只紅過一次。
  - **2026-10-21，run 39526204987（5040730）兩個紅**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-coverage-ipad`）：兩個都是那個 job 的第一個測試、App 的第一次啟動。
    - **iPad 的 `TutorialJourneyUITests.testTheWholeTutorialOnAnIPad`（測試，已修）**：第一次啟動花了 35 秒（綠的時候 14–22 秒），接著點 Lessons，點在 (270, 688)，不在按鈕上（478–898, 499–580），課程清單沒開。App 的紀錄只有那一下觸控，看起來是畫面還在轉向時就算好了位置。改成等按鈕停穩再點，5 秒內清單沒開就再點一次。和 #870（決策 303）無關：#870 沒改課程清單，這一步在它之前。
    - **`CoverageShortcutUITests`（Simulator，沒改）**：第二次在 `app.launch()` 就失敗（`Failed to get background assertion … Timed out`，啟動後 19.6 秒）。App 那時已經開始畫面了（01:24:37 起每秒 120 幀），是 XCTest 和 Simulator 的交接逾時，測試的步驟一個都還沒跑。上一次是 `LineDraftSummaryUITests:75`（run 39415463138），也是那個 job 的第一次啟動。最近 15 次 full lane 的 iPhone job 中，第一次啟動從按下到 XCTest 接上要 6–32 秒，有時超過這次失敗時的 19.6 秒也沒事，所以不是單純太慢。「暖機」那一步用 `simctl launch`，不經過 XCTest，所以擋不住這個。測試沒辦法重試 `launch()`。**可能的下一步**（沒做，要多跑幾次才看得出效果）：暖機改用 `xcodebuild test-without-building` 跑一個很短的 UI 測試，讓 XCTest 的第一次交接發生在暖機裡。
  - **2026-10-21，run 39546432319（01e3c9a）兩個紅，都是測試**（session_01MV9BgbHcs7XFafNDk76DyD，`claude/full-lane-held-card-lesson`）：
    - **`TutorialUITests.testATouchHeldOnTheFoldedCardAsTheStepMovesOnOpensIt`**：測試讓下一步在 4 秒後到，要在那之前按住小卡。這次按下去時已經是點 Zoom out 之後 4.4 秒（XCTest 中間的等待與尋找就花了這麼久），小卡已經換到下一步的位置，按在地圖上（App 的紀錄：`map.hold at (506, 280)`）。改成 8 秒後才換下一步，按住 12 秒。
    - **`LessonUITests.testKeepPlayingClosesTheResultAndKeepsTheRailwayRunning`**：第二次打開路線面板時，面板還在滑進來就量了清單的位置，找「加入選取的車站」的拖曳全落在 x 815.7（面板舊的右緣），清單沒動，和決策 299「後來」裡 `LineDraftSummaryUITests` 的第一個原因一樣。`reveal` 改成先等清單不動。

**決策 284–286 的 iPhone UI 測試（Codex，`codex/feature-ui-284-286`）**：`Feature284To286UITests` 共 5 個測試，檢查新路線草稿的兩種警告、複線月台卡片與確認後的兩個月台項目、兩款觀光列車的型錄說明與選擇按鈕、景點的觀光列車加星文字。只放 full lane 的 `FULL_LANE_LESSONS_JOB`，PR gate 不加測試。Debug 參數 `-ui-testing -ui-test-world <name>` 可開 `separate-tracks`、`missing-platform`、`double-platform`、`catalog`、`sightseeing`；全部先存入每次清空的測試暫存 library，再經一般讀檔入口載入。VERIFIED：Linux Swift 6.4 的 warnings-as-errors build、5 種世界的建立與存讀一致、XcodeGen 2.46.0 產生專案；GitHub Actions／macOS 26.6.2、Xcode 26.6、iOS 26.5、iPhone 17 Pro 的 [only_testing run 39341335419](https://github.com/a91453/railway-game-ios/actions/runs/39341335419)（head `3fd877f0`）5/5 通過、0 failures，測試 298.160 秒，整個 UI 測試步驟 7:36，專案 drift check 與 build-for-testing 也通過。以最近成功的 lessons job 42:56 加上完整 7:36 保守估算是 50:32／75 分鐘；UI 步驟 36:44＋7:36＝44:20／55 分鐘，兩者都留十分鐘以上。UNVERIFIED：加入新類別後的整條 full lane、實體裝置與 Release archive。下一步：審查者從本卡 PR 的 Checks 接，合併後看正常的 full lane；本卡不另手動開整條 full lane。重現只用 `ios-build.yml` 的 `only_testing=RailwayGameUITests/Feature284To286UITests`。2026-10-20 依作者回報續解 PR #840：merge main `c46f5d2d`，唯一衝突是產生的 `project.pbxproj`，已用 XcodeGen 2.46.0 重建（重複產生結果相同），保留 main 新增的 `LineDraftSummaryUITests`、`CoverageShortcutUITests` 與其 App 元件。本卡的 5 個測試、Debug world、App 測試入口與 full lane 分配皆未改，`LinesPanel` 相對 main 仍只有新增 identifier；main 的新 UI 與其他 session 交接完整保留。merge 後 VERIFIED（Linux／官方 Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors -j 3` 乾淨通過（221.86 秒），5 種 Debug 世界重新建立並經 `SaveLibrary` 存讀一致；沒有跑本機全套測試。上述 5/5 Simulator 證據屬 merge 前 head；merge 後未另手動重跑，專案 drift、Xcode build 與 PR gate 看 PR #840 的新 Checks。存檔版本、決策編號、golden schema 不動。

**Kenney 素材（遊戲規劃 2026-10-17 決定）**：Antigravity 的試看 #773（`docs/art/town-scene-preview-2026-10-17/`）證實 Kenney 包是 CC0，可以用；但人物是大頭比例、每人 690–756、每台車 2,000 以上三角形，原生 3D 已有程式做的人、機車、汽車（決策 259），所以**不放進遊戲、不做 GLB 轉檔**。素材留在 `Web/CityView/public/models/town/`（`SOURCES.json`），遇到程式做不好、Kenney 剛好有的東西再改色組合後取用。

**引擎與素材線（遊戲規劃 2026-10-17 決定；作者問「unity + blender + tripo + claude + codex」要不要跟，說「你四方決定後 幫我做決定」）**：
- **不換 Unity，留在 Swift／SwiftUI／Metal。** 玩家：換引擎要停好幾個月的新功能。開發：GameCore（Swift，270 多條決策、golden、存檔與確定性測試）要改寫成 C# 或接原生外掛，CI 與 TestFlight 流程要重建；雲端的 Claude、Codex 跑在 Linux，打不開 Unity 編輯器。美術：別人跨過的坎是做素材的速度，這和引擎無關。音樂：無。
- **素材線照別人那套，但接進現在的架構**：作者已有付費的 Meshy（`tools/meshy/`，商用輸出歸作者，條款見那裡的 README），不另加 Tripo；Blender 是作者電腦上的選項，不是必要步驟（Meshy 的 smart topology 直接給低面數）。缺的只有「GLB 進原生 3D」這一段。
- **順序**：72.1 在實機量到 3D 幀時間之後，先試一個模型（台灣速克達特寫版或市區公車，#773 指出的缺口）：Meshy 生成、遊戲規劃先報點數等作者同意並由作者在 session 裡登入；Codex 寫 `tools/` 的 GLB 轉成遊戲模型的工具；3D session 接進 Metal。好看、幀數夠，才把這條線用到更多模型。
- **試做模型的規格**（3D 生活感，遊戲規劃 2026-10-17 同意）：`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`。先做市區公車（1,500 面以內），機車排第二。不帶貼圖，每個三角形烤成一個顏色、8 色以內，車身用實例的顏色。格式是二進位的 `.m3dmodel`，GamePresentation 讀檔的 `Map3DModelFile` 已經做好（Linux 測試）。GLB 轉換器已由 Codex 做完（#803，`tools/glb-to-m3dmodel/`）。接進 App 與公車上街 2026-10-21 由 3D session_01Y25x9NJSKmAuP1M1K3Sf3C 做完（決策 317，`claude/map3d-city-bus`：`Resources/Models/city-bus.m3dmodel`、`Map3DCityBus`、主要道路車流的 5%）；還沒做的是實機上同一畫面有沒有公車的 fps 比較（規格「怎麼判斷成功」的第三條）、機車（排第二），與把 glTF-Validator 加進轉換器（新依賴，只在本機跑過，等作者同意再照 GAME_AI_TOOLS §6.3 加）。點數由作者決定，遊戲規劃建議先做一次（約 35 點）；作者登入前不呼叫 Meshy。

**#785 審查延後的項目，派給誰（遊戲規劃 2026-10-17）**（詳見 `docs/archive/PR755_784_REVIEW_HANDOFF.md` 第四節）：
- 核心玩法 session，排在回饋第二批（二）之前，因為是玩家會碰到的錯：
  - 整平月台時，轉乘中的乘客會被放棄（要動 GameCore，取決策號）；
  - `AutoService.passingLoopsNeeded` 的第二處以後的規劃帶上高度與水域；
  - 兩端需求燈改用路線列車定員的最小值。
- 3D session：做完（#788，決策 269 的「之後的修正」）。3D 場景快取在回到開始畫面、收到記憶體警告時放掉；2D 拉近到門檻 ¾ 到門檻之間停 0.4 秒，才開始預先蓋 3D。
- Codex（作者轉交；**已由 #802 做完**）：`LessonUITests` 讓 full lane 第一個 job 跑到 1 小時，拆到兩個 job 或第三個 iPhone job（第二個 job 已 35–40 分，整個搬過去會超過 45 分上限）；`-lesson-stars` 用的檔名常數改成 public 給 App 讀；`ci.yml` push 超過 30 分的兩次（#759、#770）看 shard 時間。
- 時好時壞的 `MapInteractionTests/testHoldingAStationTracesItsBusiestTrips`：下次紅時讀 #785 加的 trace（refused／station none／什麼都沒有，各指一個原因），再派。

**作者 2026-10-18 暫停（「現在的做完 收工 就不要做了 沒有額度了」）**：遊戲規劃 session 讓各線停在這裡，每日 Threads 日誌的排程也暫停（`trig_01342WWauXtTPc87kNedEhb9`，重新開工時再打開）。沒有開著的 PR。下次開工從這裡接：
- 核心玩法：高鐵示範的快轉在停工前已推上 `claude/hsr-demo-speed`，之後由 #801 合併（一週 `.fast` 97 s → 36 s）。2026-10-18 作者重新派工後做了決策 278（見第 2 節表格）。
- 3D：72.1 的 fps 回報 2026-10-21 到了（近景只用一幀的兩成，遠景 CPU 16.6 ms），決策 277 的雨絲與站前商店街**已解鎖**；Meshy 公車（`docs/art/meshy-city-bus-2026-10-18/`）已由 Codex 的轉換器轉好（#803，`city-bus.m3dmodel`，車頭轉成 +x），等 3D session 接進 App。那兩個 PR 順便照 GAME_AI_TOOLS §6.3 加工具：改 3D 畫面的加 pixelmatch 差異圖，接 Meshy 公車的加 glTF-Validator。
- Codex：三張卡都已合併（#802 full lane 拆工作、#784 關卡 UI 測試、#803 GLB 轉換器），見第 2 節表格。

**App 效能（#791 查到，遊戲規劃 2026-10-18 派給核心玩法 session）**：main 98d1f15 的 full lane 兩個 UI 測試紅，根因都是 App 忙到無障礙查詢要 5–46 秒（#791 改了測試的等待；證據在 #791 的說明，run 39070554849、39077241788 的 xcresult）。App 這邊還沒解：
- 新遊戲買 15 列車、600 倍時，錄影裡 9 秒只走了 14 分鐘（應該 90 分）；6000 倍時一次查詢 14.5 秒。
- 時鐘停著時，主執行緒也會有 6 秒沒回應（App 剛啟動、畫面靜止）。
- 做法：先用 `GameSim` 在 Linux 量每個 tick 的 GameCore 與 GamePresentation 時間，分清楚是模擬慢還是 App 每 tick 重算畫面；結果要逐位元不變。都是 CI Simulator 上看到的，實機要對照 72.1 的回報。
- **量完了（#798，`docs/research/APP_TICK_COST_2026-10-18.md`）**：主因是 XCTest 的無障礙快照，玩家不受影響。
  - 模擬很便宜：UI 測試那一局每 tick 0.2 ms。
  - 不打擾 App 時，600 倍跟得上：10.1 s 走了 102 遊戲分鐘，應該 100；畫面 50–60 fps。
  - 卡頓只出在測試查詢時。App 沒有改。
  - **VoiceOver 未量**（未驗證的缺口）：VoiceOver 也讀無障礙樹，時鐘跑時可能一樣卡。下一版的 What to Test 請實機開 VoiceOver 試 600 倍。
- **高鐵示範的快轉（分支 `claude/hsr-demo-speed`，作者暫停時已提交、推上分支，沒開 PR、沒跑 CI）**：模擬本身慢，熱點是每個 tick 重算每條路線的行程，和出庫時每站重算空車。改成跨 tick 記住（`RouteMemo.ServiceKey`），結果逐位元不變，不動存檔、golden、決策號。一週 `.fast` 從 97 s 到 36 s（預算 100.8 s），超過 100 ms 的 tick 從 563 個到 16 個（`docs/research/APP_TICK_COST_2026-10-18.md` §5）。開工時：開 PR（會跑 GameCore 的整套 CI）。之後才做 #669 的長進路死結與台南—左營交會（號誌開），要改規則才取決策號。

已收工（2026-10-17／18）：#787 文件、#791 full lane 的兩個 UI 測試；玩家回報的修正 #759（建造確認卡換行）、#761（有月台的軌道也能整平）；自動待避線放不回路線的列車 #763；N700 審查修正 #764（Antigravity）與 #770；實景開局 UI 測試的同步 #775（Codex）。2026-10-16 以前：單線死結 #736、#750（決策 255）；語言選單 #727（決策 257）；實景城市 #746、#753（決策 262）；審查清理 #728–#743；PR #712–#754 審查 #757；CI 優化 #756、#758（決策 265）；高鐵 N700 #752；貨運開關說明 #754。

**預覽圖放哪裡（2026-10-22，session_011DWN98Fo4KePt7PLmgsV9e，遊戲規劃派工）**：遊戲不讀的預覽圖、截圖放私有庫 `a91453/railway-reference-private` 的 `Railway/game-art-previews/`，路徑和這裡一樣（`docs/art/<資料夾>/`、`tools/cityview-benchmark/examples/`）。這次從 main 01956db 搬了 138 個檔、約 31.7 MB（逐檔 SHA-256 核對，清單是私有庫的 `Railway/game-art-previews/MOVED_2026-10-22.sha256.txt`）；每個資料夾留 README（開頭一行寫其他圖在哪）、一張總覽圖、文字紀錄（`.md`、`.json`、`.html`、`.svg`）和測試讀的 `meshy-city-bus-2026-10-18/city-bus.glb`、`city-bus.m3dmodel`。**以後的規則**：PR 只把 README、一張總覽圖和小的紀錄放進 `docs/art/`，其他圖先在私有庫開 PR；各 kit 的 `rebuild.sh` 本來就拒絕寫進公開 checkout，`Web/CityView/tools/town-preview/preview.cjs` 改成一定要給輸出資料夾。git 歷史裡的舊檔沒有改寫，`.git` 不會變小。

**素材放哪裡（2026-10-28，派工單 AZ，作者：「建好了 railway-assets-private」）**：私庫 `a91453/railway-reference-private` 約 3.6 GB（GitHub 建議 1 GB 以下），作者另開了私有的 `a91453/railway-assets-private` 放大的二進位素材。
- 放新庫：遊戲不讀的預覽圖與完整素材包（原 `Railway/game-art-previews/`，路徑改成新庫的 `game-art-previews/docs/art/`）、Meshy 批次（`meshy-batch-2026-10/`）、產出的模型包。搬完後作者點頭刪了舊庫的那些檔案（私庫 #113，留下 `Railway/ASSETS_MOVED_2026-10-28.md` 寫新位置），舊文件寫的 `Railway/game-art-previews/...` 要改到新庫的同名路徑讀；新的一律放新庫。
- 留舊庫：參考網站原始碼與資料快照（CLAUDE.md 列的那些）。
- 新庫規則：每個外部素材資料夾附自己的授權與來源檔；Quaternius、Polyfork 的檔案不得公開轉載；Meshy 照它的條款；單檔不超過 100 MB；沒有授權檔。細節見新庫的 README。
- 新庫的防護（新庫 #7、#9）：`AGENTS.md` 的 8 條規則（Codex 與 Claude 都讀）、`tools/asset_guard.py` 與 `.github/workflows/asset-guard.yml`（PR 時檢查單檔大小、`history/`、整包 ZIP、被取代輪次留下的模型；只用標準函式庫、不 checkout，一次約 1 分鐘的私庫 Actions 額度）。新庫 #8、#10 刪了 `history/` 與重複的 ZIP（含 TEMU1000、TEMU2000 的 `asset-package.zip`）；內容還在 git 歷史裡，歷史先不清（作者 10-28）。
- 發佈板（Releases）的 vehicle-source-pack-2nd、vehicle-source-pack-3rd、Tai 不動（作者：「發佈板那邊的都不動」）；Release 檔不算進 repository 大小。
- 不改寫歷史、不 force-push：刪檔不會縮小舊庫在 GitHub 上的大小，只讓 session 的淺層 clone 變小。

## 3. 作者說過的話、還在等作者的事、遊戲規劃代為決定的事

| 事項 | 狀態 | 在哪裡 |
| --- | --- | --- |
| 只收購的玩法（10j）不另開模式 | 作者 2026-10-24：「有個小問題 其實我已經有示範地圖了 讓不想蓋鐵軌的直接觀看 那只收購路線的玩法還有必要存在嗎」→ 規劃三個選項的五方比較（A 新遊戲多一個只收購模式 2.75、B 不做 2.60、C 可收購的線擴大＋開局提示 3.25）→「五方決定ok就選那條」。**選了 C**：可收購的線擴到輕軌與捷運，放進一般新遊戲；實景開局提示「可以先買一條線」；不加新遊戲選項、不分新存檔種類；10i 的公車收購沿用決策 315、336，不等 10j。同日作者再加「如果直接收購那一個車站 然後玩家不就能省去蓋站 直接從那一站延伸嗎 感覺也不錯」→「五方決定ok就執行」：**收購單一真實車站**（一小段軌道加月台，價格和自己蓋一樣，不升存檔），排在 10j 的第一個 PR。還在等作者：TDX 的帳號與 API 金鑰（公車班次要用；金鑰不進 repository） | [決策 400](decisions/400.md)、NEXT_PRIORITIES §22.2 第 10i、10j 名 |
| Game Center（每週排行榜與成就，決策 396） | 作者 2026-10-24：「那先合併 然後做 Game Center」。**第一個 PR**（#1156，已合併，session_01V99archiZKLqZkwqTnsajc）：GamePresentation 的對照（成就 ID、點數、百分比、本週的分數與哪一週的榜）與 App 的 GameKit 呼叫、成就畫面的入口。作者已做完 `docs/GAME_CENTER_SETUP.md` 第 1、2 步（App ID 與 App Store Connect 都開了 Game Center，2026-10-24 截圖）。**設定工具**（#1162，已合併，決策 396 續篇，session_01UNbe）：`docs/game-center/game-center.json` 是排行榜與成就的唯一資料來源，`game-center-setup.yml` 在 GitHub 按一次就建好。**第二個 PR**（#1158，`claude/game-center-art-396`）放三樣東西：(1) Game Center 的 entitlement：`project.yml` 的 `entitlements` 產生 `RailwayGameApp/App/RailwayGame.entitlements`（`com.apple.developer.game-center` = true）；(2) 38 張 1024×1024 成就圖，在 `docs/game-center/achievements/<ID>.png`，已照三輪美術審查改過（第一輪 session_01T1XU，第三輪的 9 張由 session_01EL7e 重畫；各輪改了什麼在 `docs/game-center/README.md`），作者看過 2efc2d9 的總覽說「可以了」，設定工具上傳到 App Store Connect 用，App 不讀；(3) 這一列。**已做**：(a) 第 3、4 步：第 5 次 apply 成功（run 40070031235，2026-10-24 06:30 UTC），1 個排行榜、38 個成就與圖都建好，`PT168H` 與 `FREQ=DAILY;INTERVAL=7` Apple 收了（VERIFIED）。(c) 官網隱私權政策 `Website/site/privacy.html`（參考庫）加了 Game Center 一節，和 iCloud entitlement 同一輪改（決策 397 續，參考庫 PR #68 已合併；要按 Deploy website 才上線）。**還沒做**：(b) 第 5 步，送審的版本勾 Game Center；(d) 排行榜與成就建好之後才發下一版（獨立審查的建議，免得玩家看到空的排行榜）；那一版若匯出或上傳失敗（profile 沒有 Game Center），revert #1158 的 entitlement commit `431a69f` 就回到第一個 PR 的狀態，發版後在實機看一眼 Game Center。iCloud 的 entitlement 不跟 Game Center 一起，等 #1160（決策 397）合併後另外加，同樣可 revert。成就清單或挑戰目標（`ChallengeRecords.rulesVersion`）改了，`GameCenterMapping` 與 `docs/game-center/game-center.json` 一起改（再用 `tools/game-center-setup/game_center_setup.py --write-doc` 更新設定文件），`GameCenterMappingTests` 與 `game-center-setup-checks.yml` 會擋，作者再按一次 Game Center setup | `docs/decisions/396.md`；`docs/GAME_CENTER_SETUP.md` |
| 10/31 正式對外：公開 TestFlight，App Store 之後 | 作者 2026-10-23（內測 47 人）：「我10/31想要正式上testflight 還是直接上app store」。**規劃的建議：10/31 開公開 TestFlight 連結**（外部測試最多 10,000 人，不必過 App Store 審查的上架項目），App Store 等公開測試約兩週、一週內沒有新的閃退與卡死再送審。時程：10/24 發 85.1（2D 6000×、3D 地面、課程引導），作者實機量過再開第二批內測；10/27 前後 86.1（第二批回報、3D 畫風 (e)）；10/29–30 只修 bug、不加新東西；10/31 用最後一個 `ci.yml` 與 full lane 都綠的版本開公開連結。**可以提早**（作者 2026-10-23：「好 照這三個條件」）：三條都達到，就在 86.1 那天（約 10/28）開，10/31 是最晚：(1) 85.1 作者實機量過，高鐵 6000× 不卡、3D 跟車不閃退；(2) 第二批內測進來後連續兩天沒有新的閃退或卡死回報（PLAYER_FEEDBACK）；(3) 那一版的 `ci.yml` 與 full lane 都綠。每一版發出後，遊戲規劃照這三條檢查，達到就告訴作者「可以開公開連結」；開連結是作者在 App Store Connect 的步驟。App Store 之前還要（作者的 Apple 帳號步驟加程式）：列車包的 StoreKit 2 與拿掉測試開關（決策 338，或第一版先不賣列車包）、隱私標籤、年齡分級、商店截圖與說明、送審說明（決策 335 的定位）。五方：玩家 30（公開測試讓更多人玩到，壞了還能每天修，不會留下一星評價）；鐵道迷 15（無）；開發 25（App Store 的審查與付費項目來不及在 8 天內做好又驗證）；美術 15（商店截圖與圖示可以趁公開測試期間準備）；音樂 15（無） | 這一列；#1041。公開頁介紹、What to Test、回報方式與 Threads 貼文的中英文定稿：`docs/research/PUBLIC_BETA_TEXT_2026-10-31.md` |
| 這個 repository 維持公開，著作權所有 | 作者 2026-10-23：「我沒寫mit…怎樣能防止被拿走」→「授權」→「因為我要省action 費用所以只能公開」。**repository 不改私有**（公開的 Actions 不計費；改私有後 macOS 分鐘以 10 倍計，一次 full lane 就用完免費額度；遊戲「資料來源」頁也連到這裡提供 ODbL 資料與授權全文）。保護靠根目錄的 `LICENSE.md`（#1104）：著作權所有，未經書面授權不得重製、改作、散布或用來上架；自帶授權的檔案與第三方資料照各自的授權，從 OpenStreetMap、Overture Maps 整理出的資料檔依 ODbL 1.0。**以後的規則**：不要提議或替作者改成私有；不要加 MIT 或其他開放授權到整個 repository；新進的第三方程式或素材把它的授權檔放在自己的資料夾（`LICENSE.md` 的例外第 1 條才涵蓋得到）；還沒要公開的預覽與大型素材照舊放私有的參考庫。五方：玩家 30（有人照抄上架時好檢舉，玩家不會裝到假冒的）；鐵道迷 15（資料出處與 ODbL 照舊公開）；開發 25（CI 免費、不動建置）；美術 15（美術、模型明確屬作者）；音樂 15（音效、配樂同上） | `LICENSE.md`；#1104；#1041 |
| 現階段先優化，再加新功能 | 作者 2026-10-23：「現階段先優化遊戲再加新功能比較好對不對」→ 遊戲規劃的分法 →「好 就照這個順序」。**第 85 版是穩定版**：(1) 馬上做：卡頓、發熱、當機（2D 高鐵 6000× 只有 3 fps，決策 375）、3D 地面與道路插進山丘（§22.2 10e）、課程第 3–10 關的一步一步引導（決策 376，另一個帳號的 session_01QTjYzbHDE2QFpRux5BQSsW）；(2) 可以穿插：只加顯示、不動規則的小改動（像 #1089）；(3) 先不派：動 GameCore、存檔或新系統的大功能，等第 85 版發出、作者在實機重量過（6000× 的幀數、發熱）再從 NEXT_PRIORITIES 挑。五方：玩家 30（卡頓與看不懂比少一個功能更容易讓人放棄）；鐵道迷 15（示範要跑得順，真實路網才看得下去）；開發 25（先把量測與快取做好，之後加功能才有底）；美術 15（3D 畫風 (e) 屬於優化，可以一起做）；音樂 15（無） | 這一列；#1041 |
| 3D 地標怎麼做（101、台北車站與之後每一棟） | **固定規則**（作者 2026-10-23：「記得以後都用website的那種模型做法來調整地標」）。每一棟地標照三步做，PR 寫出每一步用了什麼：**(1)** 先用作者參考庫 `a91453/railway-reference-private` 裡的粗略模型（例如 `scripts/landmarks.py` 重組的形狀）當起點；**(2)** 再用官網 3D 試作（決策 152、239）的 Overture 資料核對足跡、高度、樓層。101 與台北車站在 Overture 裡的資料是從 OSM 搬過去的，兩邊完全一樣，所以規格直接讀 OSM（`height`、`building:levels`、`building:part`）；**(3)** 最後照真實照片調外觀細節（分段、出簷、屋頂、窗）。照片和 Mapbox 等地圖的畫面只拿來看，不放進 repository、不上傳到外部服務，也不描它們的模型或幾何（Mapbox 只能看外觀）。三角形數量照決策 238、267 的近中遠細節分級；顏色照決策 370 的 (e) 調色盤。 | 決策 370；#1107 |
| 遊戲的資料來源改了，官網也要改 | **固定規則**（遊戲規劃 2026-10-23，作者要求重寫資料來源頁時定的）：`Sources/GamePresentation/DataSourceCredits.swift` 的來源加、刪或改寫時，同一輪也改官網的資料來源頁 `a91453/railway-reference-private` 的 `Website/site/credits.html`（中英兩邊說法一致）。官網保留自己的截圖底圖說明與網站字型那一節，不放原始碼儲存庫的連結（`Website/README.md` 的「注意」），遊戲裡寫「可從原始碼儲存庫取得」的地方，官網寫「取得方式見遊戲內的「資料來源」頁」。新的中文字要重新產生網站字型（`Website/README.md`）。隱私權政策 `Website/site/privacy.html` 也一樣：遊戲加了網路連線、權限或會送出資料的功能，同一輪改它 | `DataSourceCredits.swift` 開頭的註解；`Website/README.md` |
| 高鐵開到台北時 3D 能不能邊開邊載入前方 | **第一個 PR 做了（決策 358，`claude/map3d-streaming-window`，session_01DQGby5PQyfvKAmzTey1zVE）**：實景地圖的 3D 以 512 m 一格的滑動視窗跟著鏡頭，前方 6 km 的格子在背景一塊 3 × 3 先蓋，遠在後方的丟掉；十倍速以內跟得上，超過 1,000 m/s 停止載入。還沒做的（高倍速的粗遠景是第二個 PR、非實景地圖、真實列車與街景跟著走、實機量測）寫在決策 358「下一步」。作者 2026-10-22：「那如果像高鐵開視窗到台北是不是沒辦法 還是可以移動的時候邊載入前方視野邊使用gpu 繪圖」。**規劃的回答：做得到，還沒做**。現在 3D 場景以焦點為中心一次蓋好（`Map3DScene.reach` 每邊 6,000 m、`margin` 1,500、`chunkSize` 512，`Map3DSceneCache` 在背景蓋），開出範圍就要重蓋。提議的做法：以 512 m 的格子做滑動視窗，前方的格子在背景執行緒先蓋、後方的丟掉；300 km/h（83 m/s）時前方 6 km 約有 70 秒的餘裕，10× 時只剩約 7 秒，所以高倍速用粗的遠景或限制速度。提議排在 §22.2 第 4 名（前面展望，已做完）之後、派給 3D 鏡頭那條線。作者 2026-10-22「你五方決定 排序」→ **規劃決定做**，排在 NEXT_PRIORITIES §22.2 第 10a 名（第 10 名紀念章之後、第 11 名觀光列車之前），給 3D 那條線；五方與分數寫在那一列 | NEXT_PRIORITIES §22.2 第 10a 名 |
| 網頁 3D 試作（高雄、台中）要不要標「技術試作」 | 作者 2026-10-22：「那我想問網頁3d試做的高雄/台中 能搬一點想法進遊戲嗎 怕大家看到後對遊戲太失望」。搬什麼、什麼順序已排進 NEXT_PRIORITIES §22.10（#1011），由 3D 城市線照做。作者 2026-10-22「你五方決定 排序」→ **規劃決定標**：網頁頁面上加一個看得見的「技術試作」小標，中英兩種，說明遊戲裡的 3D 正在逐步加入這些效果（頁面標題本來就寫「3D 城市試作」，但畫面上看不到）。五方：玩家：從網頁來的人期待和遊戲一致，比較不會失望；鐵道迷：無；開發：只改 `Web/CityView/` 的頁面與 `boot.js`，很小；美術：小標照網頁現有的 credits 樣式，不擋畫面；音樂：無。排在 NEXT_PRIORITIES §22.2「隨時可派的小修」第一項，有空位就派 | NEXT_PRIORITIES §22.2 |
| Codex 生成的 3D 素材包怎麼用 | 作者 2026-10-21：「現在多了一堆codex素材包你怎麼處理」→「全部都可以用是他自己生成的」。可用的包：#900 場景套件（`SceneKitBuilder`）、#913 車站套件（`StationKitBuilder`、`Map3DStationKit`）、#921 細節套件（`Map3DDetailKit`）、#925 工程套件（合併後）。**3D session 的接入順序**，一次一個 PR：(1) 車站（#922，決策 321）；(2) 站前商店街（決策 322）；(3) ~~#900 的透天厝放到城市地塊~~ 量過不做：一塊 64 m、約 22 戶的地塊近看從約 1,550 變約 12,000 個三角形（約 8 倍），會失去決策 231／242 的牆面貼圖，獨棟四面開窗排不成街屋（決策 326 的「沒有選的做法」）；(4) 細節零件放到車站與軌道旁，第一個是架空線與電桿（決策 326），接著號誌機、轉轍器；(5) 會動的零件最後做，照 `.claude/skills/motion/SKILL.md`。原則：包當函式庫用，不改包裡的檔案；近看才用模型，遠看是方塊；每步量三角形與畫面成本；GameCore、存檔、golden 不動。列車的車頭維持 #900 的弧形、顏色用新版（作者 2026-10-21，決策 318 的 #923）。**第二波素材**（遊戲規劃 2026-10-22 派工，3D session_01ShaLWGSyEn9fYcNjS8j5Gz，決策 331）：(1) 車輛：輕型捷運（`C`）已畫成綠色三節電車（`claude/map3d-kit-vehicles`；派工寫的 `L` 是線性馬達捷運，不改）；兩節綠色通勤車已接上，兩節的通勤電聯車畫成它（決策 331 續二）；中巴 #960 自己已加進車流；(2) civic／park／commercial／works kit 照真實資料放地標，近看才放：寺廟已用公共建築套件畫在真實位置（`claude/map3d-kit-temples`，決策 331 續），公園套件已放進實景地圖的公園（決策 331 續三）；商業套件已放在城市與高鐵大車站的站前（決策 331 續五）；機廠的工程套件與學校醫院還沒做；B7（非實景地圖的街道穿過站房）由 #976 修；(3) 車站附近少量住宅模型：量過不做（決策 331 續六：農地格都在 700 m 外，換城市地塊會在近景與遠景之間留下空洞或貴 8 倍）。還沒做的寫在決策 331「還沒做的」 | 決策 321、322、326、331；這一列 |
| 列車包（付費內容） | 作者 2026-10-22：「我現在更新的套件組要做成付費內容嗎」「開發版不能先鎖東西嗎 然後我輸碼解鎖」→ 五方建議後「好 照你的做」。**決策 338**：列車包現在只有三節都市電聯車，沒解鎖時照舊畫一般通勤車；設定的「測試」區有解鎖開關，只在 Xcode 與 TestFlight 的版本出現。**上架前要做**：作者在 App Store Connect 簽付費 App 合約、填稅務與銀行、建一次性購買的「列車包」商品並訂價；之後開 PR 接 StoreKit 2、加「購買」與「恢復購買」、拿掉測試開關，送審前確認 App Store 版本沒有「測試」區。之後的新車要不要放進包，加進 `TrainPack.sets`。338（續）：#992 的五節、七節輕軌也進了包，解鎖後兩節的輕型捷運畫五節輕軌、三節畫七節輕軌，其他節數照舊綠色電車 | 決策 338（`docs/decisions/338.md`） |
| 列車包的分法與收費方向（分法已定；收費還沒做） | 作者 2026-10-25 先說「Claude 做的舊版給一般人用，Codex 做的新版放入列車包」，重新考慮後定案「己＋買之前看得到」（作者：「選分數最高的」，六項加權 8.16）。比較與理由在決策 338（續二）。**免費**：現有的台灣車，包括 Codex 的新版（700T、E200 新車頭、全部台鐵的車、兩台蒸汽機車、綠色電車），以及下一版合併的 #1229（EMU3000）、#1230（太魯閣號），它們合併時照常免費，不用進包。一般玩家用固定的基本塗裝；捷運照路線顏色上色照舊免費。**列車包**：main 上原本的 5 款（`threeCarUrban`、`fiveSectionLRT`、`sevenSectionLRT`、`fourCarMetro`、`blueSeven`）；外國車 N700S-G（`n700sG`，#1234；沒解鎖時所有高鐵都是 700T，遠景是 `highSpeedFar`）；之後的新車，包括 N700ST；原創的另一套塗裝；之後的玩家塗裝編輯器（只能用遊戲色票、只存在自己的裝置、不能分享，因為一分享就要照 App Store 準則 1.2 審核玩家上傳的內容；塗裝要不要存進 GameCore，做的時候再決定）。原版 N700S（藍線，#1202 的素材）不另外放：想要藍線的玩家，等塗裝編輯器用遊戲色票自己塗。**買之前看得到**：列車包的購買頁有 3D 預覽，可以轉著看包裡的每台車和每套塗裝；和購買流程一起做（不是試用），排在 10/31 之後。**列車包只改外觀**：沒買的人照樣能用每一種列車（GameCore 的種類），只是畫成基本款。測試版（TestFlight、Debug）的列車包開關預設關，和 App Store 版看到的一樣，測試者要看包裡的車自己打開；App Store 版看不到開關、也不解鎖（決策 338（續二））。演示模式要不要自動打開，88.1 之後再看。**舊版**：#1233 留下的 `highSpeedClassic`、`emu3000Classic`、`tarokoClassic`、`E200CKClassic` 在「己」裡用不到，#1234 刪了。改版前的寫法留在 git 歷史，要用時照那裡拿回來：700T 和 E200 是 b3e5fd1 之前的 `multipleUnit("highSpeed", asset: "02_HSR_MRT_3x2-01", …)` 和 `hauled("E200CK", locomotive: .e200, …)`；EMU3000 和太魯閣號是 #1233 的 merge 7a49276。`Map3DTrainLocomotive.e200` 照決策 408 留著。**收費方向（App Store 第一版）**：F＋＝免費下載、遊戲完整免費，賣付一次就永久擁有的列車包和支持者包（分兩三個價位，送紀念塗裝與原聲帶），加一個比分開買便宜的全部包，上架第一週限時降價。之後再出建築外觀包；劇本包和官方授權等有數字後再看。不做訂閱、廣告、付費下載。五方加權（玩家 30、開發 25、鐵道迷 15、美術 15、音樂 15）：F＋ 約 7.9、F 7.7、外觀包 7.55、劇本包 6.95、付費下載 6.0、試玩解鎖 5.35、訂閱 3.2、廣告 2.5。**規則**：建築包只賣同一種建築的另一款外觀，新的建築種類一律免費，因為它們會影響地價與人口。**收錢前要查**：每份資料與素材能不能商用；真實車名與塗裝的商標（付費包不寫真實車名、不放公司標誌，正式賣之前問律師或台鐵、高鐵公司）；審查 E 的 E1（測試開關改用只在 TestFlight 加的編譯旗標）；N700ST 的模型是 Meshy 產生再加工的（本文件「網站的素材」），依 Meshy 條款要能看出是 AI 產生，賣之前要確認遊戲裡怎麼標示。 | 這一列；決策 338（續二）；#1041 |
| 實景開局的「用我的位置」 | **已做，決策 335（#963，2026-10-22 合併）；實機待確認**。實景選點的地圖右上角「用我的位置」：只要求使用 App 期間的定位權限、取一次位置、四捨五入到約 1 公里後把框移過去；不在背景追蹤，位置不存、不傳出裝置；App Store Connect 的隱私標籤不用加「位置」（出處與給作者的送審說明在決策 335）。**CI 驗不到、要作者在 TestFlight 實機看**：(1) 第一次按時的權限對話框只有「使用 App 期間」，用途文字中英文都對；(2) 允許後框移到所在地附近，在本島或澎湖時沒有說明小卡；(3) 拒絕、或到「設定」關掉定位後再按，小卡說「這個 App 的定位已關閉……」，搜尋與點地圖照常；(4) 按下後的轉圈不會卡住（30 秒內有結果）。有問題就開一個 PR 改 `OneShotLocation`／`RealWorldPicker`。同一個決策 312 也沒做「已下載的地點」：存檔摘要沒有錨點，要做得先在 `SaveSummary` 記錨點 | 決策 335（`docs/decisions/335.md`）、ARCHITECTURE 決策 312 |
| 競爭對手與收購公司 | 作者 2026-10-21：「收購整條線 或公司會讓玩法變有趣嗎」→「好 排進去……然後競爭對手與收購公司再考慮一下」；2026-10-22 交給遊戲規劃五方決定。**規劃 2026-10-22 決定做 A「汽機車分走旅客」，不做 B「對手鐵路公司」、C「收購公司」**（決策 332 的「沒選的做法」）。A 由 session_018gQPWzopcCfuR9gTAApKTj 做，一步一個 PR：(1) 一頁設計 `docs/decisions/332.md`（#967，已合併）；(2) GameCore 的運具分配，存檔 70，`claude/mode-shift-core`（規則、`setModeShift`、玩家的新遊戲打開；挑戰、示範、教學不開），已合併（#986）；(3a) 車站卡、路線卡那一行與原因，`claude/mode-shift-cards`，已合併（#995）；(3b) 縣市上限、鄉鎮加縣市的工具、`DataSourceCredits`、實景地圖的量測，`claude/mode-shift-county`，已合併（#1001）；(3c) 點路線卡那一行跳到車站、站長只說一次的提示，`claude/mode-shift-hint`。之後的（高鐵城際、觀光客、每站的縣市上限、尖峰塞車）沒有人做，見決策 332「下一步」第 5 項。收購支線另排在 §19 第 9 名 | 決策 332；NEXT_PRIORITIES §20.2 |
| 69.1 之後先不開新工作 | 作者 2026-10-16（69.1 發版後）：「不用凍結了 但也先不要開工我要做pr review 跟ci優化」。發版凍結解除，PR 照一般規則合；但核心玩法第 4 個 PR（關卡）、3D 2b、文件數字檢查等都先不開，等作者說開工。現在只跑：PR #712–#754 審查（session_01QVLVMib2sHjahi6BdYdK48）、CI 優化（session_01LQE9Rif1ggbZsT3iYQiN7G）。各線都已通知 | #231 |
| 69.1 的發版 | 作者 2026-10-16：「交給你綠了就合 紅了解衝突 最後是試著發一版TestFlight 但前提是要所有pr都綠 無失敗」「記得要adhoc external」，之後「隨便 我來發69.1了」，作者自己跑了 run 69（e68f237）。#747 的 What to Test 晚兩分鐘合併，沒被帶上（`docs/research/PLAYER_FEEDBACK.md` 69.1）。教訓：What to Test 的 PR 要最先合，不要排在最後 | PLAYER_FEEDBACK |
| 航空遊戲手感借到鐵道 | **遊戲規劃 2026-10-16 決定**：③ 到站收入飄字併進核心玩法的回饋（#724 的「+$12」）；①座位圖、②每趟蓋章、④車型「剛好／太大／不夠」、⑤兩端站需求燈，排在核心玩法第 5 個 PR 之後，當「回饋第二批」，由遊戲規劃開 session。理由——玩家：先讓核心玩法好上手，再加細節；開發：和回饋共用同一套 GamePresentation 事件，晚做不重工；美術：照《沿線》的畫風重畫，不用影片的霓虹；音樂：蓋章可沿用目標旋律的音色 | session_01NoAXS67jevFRE5XRz37tcF（研究） |
| 高鐵示範的誤點 | 作者 2026-10-15：「沒差先誤點再看怎麼調整」。#660 之後誤點中位數約 7 分、最多 27 分，作者接受；調整方向記在 #660 的留言 | #660 |
| iPhone 左欄縮回 56 點後，iPad 建造欄還是 72 點 | 「作者決定的」沒有原話可查。**遊戲規劃 2026-10-16 決定維持 72 點**。理由——玩家：iPad 畫面大，72 點比較好點，也沒擠到地圖；開發：#721 已經合併，不用再動；美術：iPad 的工具欄留在左下，和 iPhone 本來就是不同排版（決策 226）；音樂：無。作者實機看了覺得要縮，再開一個小 PR | #721（已合併） |
| 加依賴：ACE-Step 1.5 當離線配樂工具 | **遊戲規劃 2026-10-16 決定：現在不加**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」）。玩家：現在缺的是好上手，不是配樂的種類；開發：要 Python 與 GPU，雲端 session 沒有 GPU，只能在作者電腦上跑，而且要改決策 219 §2.2；美術：無；音樂：MML Studio 的流程（決策 219）讓配樂和到站鈴同一種音色，生成的配樂音色不一致。配樂需要更多變化（聲音第 3、4 階段）時再評估 | 已決定 |
| 加依賴：`tools/` 用 glTF-Transform 與 meshoptimizer（npm），讓 3D 的 GLB 在電腦上轉檔 | **遊戲規劃 2026-10-16 決定：同意，只在 `tools/` 用**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」；加依賴是作者保留的決定，合併協調 session 再問作者本人，作者回「四方 思考 最後做決定」，#729 才合併）。條件：兩個都是 MIT；寫進 `tools/` 底下一個工具自己的 `package.json`，版本釘死，加上 lockfile；App 與 Swift 套件不讀它們，也不打包進 App；授權寫進該工具的 README。轉出來的模型照 art-style §7 拆零件、重組、換成調色盤顏色；原始 GLB 與對照留在 scratchpad 或私有參考庫。玩家：3D 的人、車、地標可以更快做到目標畫面；開發：Linux 沒有能讀 GLB 的 Swift 套件（第 4.1 節），用現成工具比自己寫解碼器小；美術：只是取零件的手段，成品還是遊戲自己的風格；音樂：無 | 已決定，3D 生活感 session 可以用 |
| CI 優化（決策 265，session_01LQE9Rif1ggbZsT3iYQiN7G） | 作者 2026-10-16：「我要做pr review 跟ci優化」。四項由遊戲規劃以四方決定：把 iOS 列為必要檢查、關掉 auto-merge 都先不改，#756 跑一陣子再評估；PR gate 的 UI 測試名單不動（`docs/research/CI_MEASURE_2026-10-16.md` 第 3 節 E）；分片逾時上限 20 分不改，下次重新分配分片時再看。之後若 macOS 又常排隊，先看研究文件的方案 | 已決定 |
| CI 流程優化（決策 329，session_01E8oiGWPQZ2a8wAE8tNvFKk） | 作者 2026-10-21：「還需要一個session優化ci流程」。三個 PR：新決策一個檔一個（`docs/decisions/`）；被取代的 PR run 不判紅、swift-build 崩潰重試一次；main 的 full lane 紅了在 #231 自動留言。量測在 `docs/research/CI_MEASURE_2026-10-21.md`。**之後可以做的**（量過，沒做）：`ios-build.yml` 的 Simulator 開機（約 2.0 分）和建置（約 2.6 分）並行，以及翻譯匯出（約 2.9 分）不排在 UI 測試後面——這兩項只能在 macOS 上驗；HANDOFF 這份本身三天衝突 8 次，可以照同樣做法把 §2 的各列拆成檔；`superseded` 讓 gate 變灰，要等某個 PR 真的有一輪被新 push 取消，才看得到效果 | 做完；之後的兩項沒人接 |
| CI 4C：自架 runner、Xcode Cloud、第三方 macOS runner | **遊戲規劃 2026-10-16 決定：現在不做**（作者 2026-10-16：「尚未決定的都四方考慮後做決定」）。開發：#693 把 full lane 拆成兩個 job 之後，5 台 macOS runner 夠用；這個 repo 是公開的，自架 runner 會讓 PR 的程式跑在作者的機器上，有安全風險；Xcode Cloud 要作者做 Apple 帳號的設定（`docs/XCODE_CLOUD_ONBOARDING.md`）；第三方 runner 要另外付費。玩家：無；美術：無；音樂：無。macOS 的工作經常排隊超過 30 分鐘時再評估 | 已決定 |
| 複線的最短相隔距離要不要再縮 | 作者 2026-10-14 在手機上問，那個 session 停在權限確認，沒有回答。**遊戲規劃 2026-10-16 回答：不縮**。遊戲的軌道中心間距是 `RailwayNetwork.trackSpacing` 256 單位＝4 m，台鐵一般路段的線間距就是 4 m 左右（高鐵更寬）。畫面上看起來太寬或太窄，是 2D 線的畫法（決策 249），不是間距 | session_01Mtv1QDk434KcMtFHWw67SM |

## 4. 3D 地圖

接手的是「3D 生活感」session（第 2 節）。下面三份交接是 2026-10-16 從做過 3D 的三個 session 收來的，數字對照 main `d542952`。標「估」或「未驗證」的，都沒有量過。

**先讀的決策**：
- 229：3D 地圖
- 230：實例化的列車
- 231：軌道抬高
- 232：陰影
- 234：pmtiles 實景地面
- 235：程序化建物
- 238：遠近分級
- 239：真實建物
- 241：地圖配色
- 242：材質
- 244：街道設施

預覽圖在 `docs/art/map3d-*-2026-10-1*/`。畫風在 `docs/art/3d-style-2026-10-13/`（README 與總覽 `ftwplus-top.jpg`；其他圖在 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/`，同一相對路徑），最接近作者要的是 `ftwplus-street.jpg`。

**作者 2026-10-16 的目標畫面**：明亮的 low-poly 台灣街景，白天，斜上方約 35° 俯看。
- 左邊是紅牆橘瓦、雙層屋簷的廟，屋脊兩端翹起、綠色屋脊。廟前是淺色鋪面的廟埕，三四十個方塊小人，衣服顏色各異。廟埕前有一座紅色牌樓（兩根柱子加一道橫楣）。
- 中間一條雙向馬路，白色虛線分隔，路上有紅、白轎車與幾台機車（有一台載兩個人），人行道有路燈與行人。
- 右邊是 4–5 層的米白、黃色公寓：每層窗上有藍、綠、紅的遮雨棚，陽台曬著彩色衣服，頂樓有藍色水塔；一樓店面是彩色雨遮，門口堆著貨物與攤架。
- 遠處是高低錯落的公寓群，頂樓有水塔與彩色屋頂；左上是綠地、圓球狀的行道樹與一條藍色的河。
- 整體很亮、陰影柔和，活的東西多。

這就是 F 台灣版＋（`docs/art/3d-style-2026-10-13/`）的「＋」。作者回報 67.1／68.1 的 3D 地圖在 iPhone 17 Pro 上 60 fps，加人車之後同等級機型要維持 60 fps，舊機型降級。

### 4.1 架構、預算、坑、素材（3D 任務素材庫 session_01DDMNH81xijBkgM2wVnHEyR）

**讀 GameWorld**
- `Map3DScene(world:snapshot:skyline:focus:baseMap:cityTiles:heights:)`（`Sources/GamePresentation/Map3DScene.swift`）是唯讀的衍生資料，不存世界的第二份。
- 由 `RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift` 在 `Task.detached` 裡整個重蓋。路網或城市一變就全部重蓋，沒有增量更新。
- 範圍是已建的部分加 `margin` 1,500 m，每邊最多 `reach` 6,000 m（決策 89 的記憶體理由）。
- 座標單位是公尺：x 東、y 上、z 南。
- 列車不在 scene 裡。`Map3DTrains.frame(...)` 每幀讀 `TrainMotion`，接法是 `view.trains = { eye in feed.frame(in: scene, models:, eye:) }`。

**Chunk**
- 每塊 `chunkSize` 512 m。`Map3DScene.Chunk` 有：
  - `mesh`：前 `baseIndexCount` 個 index 是地面、軌道、道路、玩家建物，任何距離都畫；後面是城市建物。
  - `far`：簡化版的城市。
  - `shadows`：接地陰影，最後畫。
  - `props: [Map3DInstance]`：決策 244 的街道設施。
  - `minimum`、`maximum`：包圍盒。

**遠近分級**（決策 238，`Map3DCamera.wantsDetail`）
- 完整畫要同時符合兩個條件：相機距離 ≤ `detailDistance` 1,600 m；chunk 離目標點或眼睛正下方在 `max(detailReach 700, distance×1.2)` 以內。不符合就畫 base 加 `far`。
- 有遲滯，避免來回切換：已完整的放寬到 1.14 倍才退出，未完整的要進到 0.86 倍才進入（照參考庫 street_scene 的 `updateDetail`）。人和車用同一套，才不會閃。
- 列車：離眼睛 `Map3DTrains.modelReach` 900 m 內畫車廂模型，更遠畫方盒。
- 相機：`nearest` 60 m 到 `farthest` 12 km，依距離傾斜（遠處正上方往下看，近處斜看）。主地圖拉近變傾斜的 3D，可以直接用這台相機。

**實例化繪製**（決策 230、244，可以直接畫人和車）
- `Map3DInstance`：`model` index、4×4 `transform`、`stripe` RGB，每個實例 20 個 float。
- 著色器 `map3dInstancedVertex`：頂點 alpha < 1 的地方換成 `stripe` 的顏色。樹冠就是 alpha 0，所以每棵樹的綠不一樣。人的衣服、車的車身可以照這招，一個模型配多種顏色。
- 模型放在 `Map3DModelPack.standard`（`Map3DModels.swift`）：先列車，再 `Map3DProp.allCases`（`Map3DProps.swift`）。新模型往後加；`Map3DModelTests` 釘了模型總數，要跟著改。
- 建模：用 `Map3DMesh` 的 `addBox`、`addCylinder`、`addFacet`（scene 軸），再用 `Map3DModelPack.Model.flat(named:from:)` 轉成模型空間（+x 前、+y 左、+z 上，每個三角形用自己的法線）。
- 擺放：`Map3DInstance.prop(_:at:forward:scale:tint:)`。
- **不動的東西**（店面貨物、水塔、雨遮、牌樓）：放進 `Builder.props`，進 `Chunk.props`。Metal 端每塊、每種模型一次 draw call，只在 chunk 完整畫時才畫（`Map3DMetalView.swift` 約 372 行）。
- **會動的東西**（人、車）：照列車的做法，每幀由一個 closure 回傳 instances，加在 `Map3DMetalView` 列車 instanced 那段旁邊。
  - 列車現在每幀 `makeBuffer` 一個新的 buffer。上千個人或車時，改成 ring buffer（三份輪流）。
  - 移動狀態放在 GamePresentation，是暫時的表現狀態，不進 GameCore。
  - 亂數用 `map3DRandom(_:_:salt:)`，依位置或 id 取，不用 random。

**量過的數字**（#679，Linux 除錯版，空白的實景新局）

| 地圖 | 行道樹 | 路燈 | 電線桿 | 最多的一塊（三角形） |
| --- | --: | --: | --: | --: |
| 台北 | 6,101 | 2,255 | 1,675 | 34,580 |
| 高雄 | 3,229 | 1,615 | 2,742 | 32,712 |

- 近處通常有 4–9 塊完整畫，街道設施約 13–30 萬個三角形、12–27 次 draw call。
- 每件的面數：樹冠是三團各 20 面；路燈、電線桿都是幾十面。

**draw call 怎麼算**
- 靜態：每塊可見的 chunk 1 次（完整）或 2 次（base 加 far）。
- 陰影：每塊 1 次。
- 列車：方盒合成 1 次，加上每種車廂模型 1 次。
- 街道設施：完整的 chunk，每塊每種模型 1 次。

**沒量過的**
- 整幀的總三角形與總 draw call：`Map3DMetalView` 裡的 `drawCalls`、`triangles` 計數可以印出來。
- 作者在 iPhone 17 Pro 上看到 60 fps，但沒有記下當時的三角形數。

**建議預算**（估）
- 一幀 100 萬個三角形、150 次 draw call 以內。
- 人和車每種模型 200 面以下，只在完整畫的 chunk 或眼睛 300–500 m 內出現。
- 舊機（A15 等）要留餘裕。

**坑：深度閃爍**
- `depthRange`：near = max(1, 0.02×距離)，far = 6×距離 + 4,000。
- 地面的各層靠很小的高度差分開，由低到高：
  - cover：0.04×(rawValue+1)
  - 人行道 `sidewalkLift`：0.26
  - 道路：服務道路與小路 0.28，三級到主要道路 0.32，幹道與高速公路 0.36
  - 中線 `centreLineLift`：0.38
  - 陰影 `Map3DShadow.lift`：0.4
  - 軌道 `railLift`：0.85（道床原本會被地面和廣場蓋掉，決策 231）
- 廟埕鋪面、斑馬線等新的地面層，要插進這個順序裡，不要跟既有的層同高。
- 深度是反轉的（決策 342）：近處 1、遠處 0，清成 0，比較用 `.greater`。2 cm 的層在所有鏡頭至少隔 18 個深度刻度（`Map3DDepthTests`）；改投影或加更薄的層時跑 `MAP3D_FRAME_REPORT=1` 的 `testTheDepthReport`。
- 陰影 pass 不寫深度、用 greaterEqual（決策 342 前是 lessEqual），最後才疊上去。
- cull mode 是 `.none`，但法線和 winding 有測試檢查（`Map3DRealBuildingsTests`）。

**坑：道具穿模**
- 決策 244 的樹、燈、桿只避開軌道經過的格（`removeProps(on: cleared)`）和路口 9 m。
- **沒有**檢查建物輪廓，人行道窄的地方，樹冠可能插進真實建物。加人、車、貨物時一起處理。

**坑：列車被遮住**
- 真實建物和程序化城市都會避開軌道經過的格（`addRealBuildings(..., clearOf:)`）。
- 道床抬高 0.85 m，是為了不被地面蓋掉。
- 高架下的車和人要注意橋墩：`pierSpacing` 32 m，墩的大小是 1.6×2.2 m。

**坑：Metal 在 CI 上驗不到**
- Linux 驗不到 `Map3DShaders.metal` 和 `Map3DMetalView`。只有 `ios-build.yml` 的 Xcode build（PR 的 gate）會編譯；幀數只能在實機看。
- 預覽工具 `tools/map3d-preview/`：
  - `Map3DPreviewDump.swift.txt` 要暫時複製進 Tests，用 `MAP3D_WORLD=kaohsiung|taichung`、`MAP3D_CITY=1` 等環境變數跑，跑完刪掉。
  - `render.sh` 用 headless Chromium 的 WebGL 照 Metal 的算式重畫，著色器是手抄的。改 shader 時兩邊要一起改。
  - 材質常數（第一層 18、`detailRepeat`）由 `Map3DSurfaceTests` 釘住。
  - 預覽圖是軟體算的圖，不是 iPhone 的畫面。

**其他**
- 頂點的 layer 編碼是 surface + 64×(detail+1)（決策 242）。`Map3DSurfaces.png` 有 22 層，每層 512 px。
- scene 每次整個重蓋，加很多靜態實例會拉長重蓋的時間。
- 美術規則見 art-style §7：素材都能用，但要混合、改成遊戲的配色與低多邊形再產出，不照搬。公開 repo 只放改過的成品；加工腳本與原檔對照留在 scratchpad 或私有庫。素材庫的圖與模型不上傳到會保留或拿去訓練的外部服務。

**看過、還沒搬的素材**
- 本 repo 的 `Web/CityView/src/world/`（MIT，Yong Su 與本專案的修改）：
  - `traffic.js`：車在道路圖上跑，有紅綠燈、跟車間距、路口讓行，台灣靠右。
  - `props.js`：號誌 `signalGeometry`、公車站 `busStopGeometry`、停放的腳踏車 `bikesGeometry`、販賣機 `vendingGeometry`、雕像 `statueGeometry`、遊樂設施 `playGeometry`。目前只用過 `poleGeometry`、`lightGeometry`、`blobTreeGeometry` 的尺寸。
  - 還有 `signs.js`、`ads.js`、`decals.js`、`lamplight.js`（夜間燈）、`landmarks.js`（地標清單）。
- App 裡的城市 tile（`RailwayGameApp/Resources/BaseMap/city/{kaohsiung,taichung}`，來源是 Overture／OSM，授權 ODbL 與 CC BY，`DataSourceCredits` 已列）：
  - TKY1 v7 的每個 tile 除了建物，還有路面、設施、電線、牆、招牌五段，也就是高雄、台中真實的設施、招牌、電線位置。
  - `CityTile.swift` 現在只讀建物，其他五段跳過（header 的 `skip(5*4)`）。
  - 格式見 `Web/CityView/src/shared/tileformat.js` 的 `decodeTile`。
- 私有參考庫 `a91453/railway-reference-private`（作者授權）：
  - `Railway/street_scene_reference_clean/`（銅鑼灣街景）：
    - `source/models/street-agents.glb`：行人、遠距行人、車輛、街頭道具的範本，共 213 個 mesh，用 EXT_meshopt_compression 壓縮，沒有骨架，動作由 JS 做。
    - `source/assets/scene.js`：行人與車的移動、事件、日夜、遠近分級。
    - `causeway-bay-buildings.gltf`：店面。
    - OSM 的部分是 ODbL，要保留署名。
  - `Railway/procedural_assets_reference_clean/`：**購買的素材包**，條款在 `ASSET_LICENSE.txt`。
    - 可以用在遊戲、可以修改、不必署名。
    - 不能原樣轉散布 pack 檔、元件或調色盤；不能放進競爭的素材庫；不能拿去訓練或評估生成模型。
    - 程序化建模的 JS 在 `source/preview/<pack>/assets/createModel-*.js`，可以照決策 235 的方式翻成 Swift 再改風格。
    - 跟這條線有關的：
      - japan：Temple Gate、Temple Main Hall、Stacked Shop House、Kishi Corner Shop、Shop Building、Storefront Display Rack、Produce Carton Pallet、Rooftop Water Tank、Chochin Lantern、Kei Taxi、Kei Truck、Sedan Taxi、Bus Stop Sign Board
      - suburban：Car suv、Classic car、Pickup truck、Gable Roof Bus Shelter
      - tiny-cubes：Market Stall、City Shop、City Car
      - city：Voxel Corner Store、Illuminated Advertising Kiosk
      - blocky-characters：100 個角色
      - rooms：Laundry Basket、Paint Cloth Drying Rack（可以參考曬衣）
    - 日式山門不是台灣的牌樓，要改成紅柱、燕尾脊。廟的紅脊色已有 `Map3DPalette.templeRidge`；真實建物裡用途 454 是廟（決策 239）。
  - `Railway/commuter_journey_reference_clean/`（香港地鐵）：人潮、排隊、車門、店舖。它用了 `Math.random`，只能搬進表現層。
  - `Railway/island_city_reference_clean/`：居民、工作、程序化模型。它用了 `Math.random`，只搬規則與數值。
  - `Railway/city_world_reference/`：街屋的地塊規則，已經用在決策 235，第三方聲明在 `THIRD_PARTY_NOTICES.md`。
  - `OpenWorld/reference_snapshot/play/src/world/tamkang-bridge.js`、`bridge-blender-visual.js`：淡江大橋的零件。它是 200 m 的斜張**公路**橋，不能當鐵路高架，可以當地標。
  - 台鐵三款 GLB 每個 16–20 萬面，太重。
  - `Railway/night_district_reference_clean/`、`location_modeler_reference_clean/`：只看過目錄，沒細讀。
- 網站的素材：
  - 貼圖是 Poly Haven（CC0），在參考庫 `Website/site/city/textures/`。決策 242 只取了灰階當底紋。
  - N700ST 列車是 Meshy 產生後再加工的。依 Meshy 條款，要能看出是 AI 產生。

**它原本想做的下一步**
1. 讀 tile 的其他五段：用高雄、台中真實的路面、設施、招牌、電線，取代決策 244 依道路等級推估的擺放；也補上電線（決策 244 的缺口）和路口號誌。
2. GLB 在電腦上轉檔，不在 App 裡讀。
   - Linux 上沒有能用的純 Swift 讀取器：SwiftGLTF 在 Linux 失敗，GLTFKit2 只支援 Apple。
   - 做法：在 scratchpad 寫腳本，解 meshopt（meshoptimizer 是 MIT）、減面、換成遊戲的配色，輸出成 `Map3DModelPack` 能讀的頂點資料。不加 runtime 依賴，要加是作者的決定。
   - 對象：street-agents.glb 的人和車，以及地標（淡江大橋、日月潭）。
3. 3D 列車讀 `TrainLivery`（決策 243，#677）的 `body`、`stripe`、`cab`、`nose`，不另外定顏色。
4. 全台的建物圖層：等作者決定 App 容量。目前兩區的 tile 約 2.6 MB，全台沒量過。

### 4.2 夜晚與地形（session_01RuxRaNwRfKKNijYAe4ReU6，#690）

細節在決策 229、234 的「續（2026-10-16）」和 `docs/art/map3d-night-terrain-2026-10-16/`。

**夜晚怎麼做**
- 開燈的程度：`Map3DLighting.lights` = night×1.4，上限 1，黃昏就開始亮。Metal 從 uniform `shade.y` 讀，白天是 0。
- 會發光的頂點：layer 設成 `Map3DVertex.glowing`（−2），用 `Map3DMesh.makeGlowing(from:)` 標。著色器在霧之後加上 `顏色×1.3×lights`。
  - 實例化模型（`Model.flat`）會保留 glowing，instanced vertex shader 也會把 −2 傳下去。
  - 路燈的燈頭就是這樣做的，顏色 `Map3DProp.lampLight` 0xFFE3B0。
- 地上的光圈：`Map3DMesh.addPool` 放在 shadows mesh。陰影頂點是黑色，有顏色的就當成光，alpha 乘上 `shade.y`。
  - 光圈在 `Builder.addLampPools()` 裡加，要在 `removeProps` 之後，照 chunk key 排序（為了決定論）。
- 亮窗：貼圖不動，全在著色器裡算。
  - 玻璃的判定：有窗的圖層裡，mask 為 0（不染色）而且亮度 ≤ 門檻；店面整面都算玻璃。
  - 亮不亮：用 hash12(格子 floor(surfaceAt) ＋ 牆面平面 `[[flat]] plane`)，每晚亮同一批窗，不會閃。
  - 各圖層亮窗的比例在 `Map3DNightWindows.rule`（GamePresentation），經 `Map3DLighting.nightWindowRows`（12 列）傳進 uniform `nightWindows`。新增 `Map3DSurface` 時要加 rule，總層數不能超過 24。
- 改著色器時，`tools/map3d-preview/index.html`（WebGL 版的同一套算式）要一起改。dump 的陰影格式是 7 個 float：xyz、rgb、a。
- 夜晚的環境光是 0.75 加月光。`Map3DNightAndGroundTests` 釘了地面、道路、牆的亮度下限，以及「夜晚仍是藍色」。

**新的人、車、店面怎麼接上夜晚**（建議）
- 車：頭燈、尾燈做成小方塊並標 glowing，頭燈暖白、尾燈紅（0xFF3B30 一類）。
  - 要讓車燈照在路面上，可以沿用 `addPool`。但 pool 是靜態的、放在 shadows mesh 裡，會動的車要每幀另做一份 instanced 的光圈，或乾脆不做地面光。
- 店面招牌的招牌面用 glowing，整面發光，晚上最顯眼。廟埕、牌樓的燈籠與燈串也用 glowing，顏色用紅與暖黃。
- 列車的車窗和頭燈還沒做（#690 列為缺口）：可以把 `Map3DModels` 的車窗頂點標成 glowing。
- 人：晚上少一點，`lights` 越高人越少，例如乘上 (1−0.5×lights)。夜市、廟埕、車站例外，晚上反而多。只用 `lights` 或 `night` 決定，不另外接時鐘，這樣才有決定論。

**地形與地面的坑**
- 世界的地面只在軌道經過的 1,024 m 區塊讀進來（決策 124），沒讀的區塊 `world.groundHeight` 回 nil。
  - 3D 一律用 `Builder.ground(x:y:)` 或 `drawnGround(x:z:)` 取高度：它們會改讀高度檔（`FileGround`），世界邊緣以外取邊上的值。
  - 不要直接用 `groundHeight ?? 0`，那就是原本斷崖的 bug。
- 東西要貼地就用 `drawnGround`（跟 64 m 的三角形一致），不要自己內插。抬升的順序照 `Map3DRealGround`：水 < 人行道 < 道路 < 中心線 < 陰影 0.4 < 軌道底。
- 平坦的實景地圖（決策 198）`groundHeight` 永遠是 0，3D 不套高度檔，這是對的。
- 道具會被 `removeProps(on: cleared)` 從軌道經過的格清掉，任何依附道具的東西（例如光圈）都要在這之後才加。
- 加進 shadows mesh 的東西會影響 `Map3DRealGroundTests` 的地塊計數，那個計數現在只算黑色的三角形。
- `Map3DRealGround.swift` 沒有 import Foundation，要用 sin、cos 就把表放在 Map3DProps（例如 `poolRing`）。
- 預覽工具的大場景會讓瀏覽器記憶體不夠（OOM），`MAP3D_CROP` 半徑約 1,400 以內比較安全。

### 4.3 F 台灣版＋ 的人車與街景（畫風示意 session_018sTU6EMMCProJhAkswMiuo，#520）

示意場景是 2026-10-13 用 three.js 在 scratchpad 做的，沒有進 repo，下面的數字就是它的全部參數。

**參考庫只當量尺**，模型沒有載入或複製。決策 230：作者看過縮面、重上色的白模，說「根本一模一樣」。
- 來源：`Railway/street_scene_reference_clean/source/models/street-agents.glb`，組裝在 `source/assets/scene.js`。
- 量到的尺寸：

| 物件 | 尺寸（m） | 三角形 |
| --- | --- | --: |
| 汽車、計程車 | 4.56×2.08×1.38 | 約 2,076 |
| 小巴 | 7.2×2.5×2.98 | 2,224 |
| 行人近版（27 件） | — | 約 1,616 |
| 行人遠版 `personfar_`（7 件） | — | 378 |

- 它的店招有仿真實品牌的（mcdonolds、watsens、uniqla），不要搬。

**行人**（自己畫，面向 +z，腳底是原點）
- 腿兩支：漸縮的盒子，寬 0.15→0.17、高 0.82、深 0.16，中心 (±0.09, 0.45)。
- 軀幹：漸縮的盒子，寬 0.32→0.38、高 0.6、深 0.24，中心高 1.13。
- 手臂：0.10→0.11×0.54，x ±0.235，中心高 1.12。
- 頸：圓柱 r0.055，高 1.47。頭：icosahedron r0.16 細分一次，高 1.64。
- 頭髮：球冠 r0.175，三種（短髮、鮑伯、棕髮）。
- 手：球 r0.05，高 0.80。鞋：0.11×0.08×0.25。
- 雨傘：cone r0.55、高 0.28，放在 2.1；傘柄 0.9。
- 一種人分三個 InstancedMesh：褲子、上衣（白色幾何，用 instanceColor 每人換色），加上固定部件（2 種膚色 × 3 種髮型 = 6 個模板）。
- 配色：

| 部位 | 顏色 |
| --- | --- |
| 上衣 | E8E4DA 4E78A8 C65A4E 3B3F45 8A9BB0 D9B48A 5E9A78 B04E6A F2F0EA |
| 褲子 | 3B3F45 4E5A6E 6B5A4A 2B2B2B 8A8F96 C9C2B4 |
| 膚色 | E8C9A8、C48E6A |
| 髮色 | 2B2B2B、5A4232 |
| 傘 | 2B2B2B 4E78A8 C65A4E 5E9A78 F2F0EA B04E6A |

- 雷雨時八成的人撐傘。
- 一人約 500–700 個三角形，偏多（球的分段沒有省）。
- 擺放的人數：北月台（列車要進的那一側）70、南月台 22、路兩側人行道 90、廟埕 26、夜市白天 30 晚上 90。

**汽車**
- 用側面輪廓擠出，輪廓點 (z,y)：(-2.28,.32) (2.28,.32) (2.28,.72) (1.35,.86) (.65,1.36) (-1.15,1.38) (-1.95,.95) (-2.28,.9)，寬 2.0。
- 玻璃帶是一個暗色的盒子 2B3440。四個輪子 r0.33、十邊。頭燈 F4F1E0，尾燈 B0302A。

**小巴與公車**
- 小巴 7.2×2.4×2.7。
- 台灣的單層公車 11×2.5×3.2：前方 LED 牌 F0A93C，車頂淺灰。

**車的畫法**
- 一種車分兩個 InstancedMesh：車身（白色幾何，用 instanceColor 換色），加上固定件。夜裡多一個自發光的頭燈。
- 車身色：
  - 汽車：F2F2F0 C9CCCF 3B3F45 9C3B36 5B6E86 E8E4DA 7C8288
  - 公車：3E8C8C 4E78A8 F2F2F0 5E9A78

**機車**
- 車身 0.5×0.45×1.3，加前擋。兩個輪子 r0.26，加座墊、把手。
- 騎士：軀幹、腿、頭，戴白色安全帽。

**機車與汽車的擺放**
- 站前道路靠右 34 台。車道 z：西行 27.6、29.4，東行 30.6、32.4。
- 平交道柵欄放下時兩側排隊 4＋3 台，**機車 10 台停在最前面**（待轉區的感覺）。
- 路上 18 台機車有騎士；透天厝門口停 0–3 台。

**透天厝的街面**

尺寸：寬 4.2–5.6 m、深 13 m、3–5 層，每層 3.3 m。外牆 9 色磁磚：E9E2D3 D9D6CF E2C9B8 CFDCD8 EDEDEA D6CBB8 C9D3DE B9B2A8 E6D9C9。

一樓：
- 騎樓：3 m 高的暗色退縮（5E5852），兩側柱子 0.4×0.4。店面是亮的玻璃或鐵捲門（BFC3C8）。
- 店面陳列擺到騎樓：
  - 櫃台：寬×0.55、高 0.9、深 0.6，顏色 D8D0C2、8E6E52、C9CCCF；
  - 櫃台上放 3 箱貨，每箱 0.5×0.35×0.35，顏色 E86A7A F2D24B 5E9A78 4E78A8 F2F0EA D98A4A；
  - 低遮雨棚：深 1.1 m、往外斜 0.25 rad、高 2.95 m，顏色 3E8C8C C65A4E 4E78A8 F2F0EA。

樓上每層：
- 窗：寬×0.62、高 1.5。鐵窗是 3 根 0.07 的直桿加一根上橫桿。
- 陽台板深 0.7，樓層飾帶 0.12。
- 鐵皮雨遮：寬是窗寬＋0.6、深 0.9、斜 0.35 rad，在窗上 1.05 m，顏色 7A93A6 6F8E7C D5D1C6 9AA3A8。
- 曬衣：45% 的樓層有，4 片 0.45×0.6，掛在陽台外 0.62 m，顏色 F2F0EA 4E78A8 E86A7A 8A9BB0 D9B48A。
- 花台：35% 有，0.9×0.35×0.35，顏色 6A8F4E。
- 冷氣：30% 有。

其他：
- 直立招牌：50% 的店有，0.25×(3–7)×1.0，夜裡自發光。
- 屋頂：
  - 頂樓加蓋：60% 有，寬減 0.4、高 2.6、深×0.6，上面是鐵皮山牆屋頂高 0.7 m，顏色 7A93A6 6F8E7C 9C6B52 8E9AA3。
  - 水塔：75% 有，r0.62、高 1.1，藍色 3F6FA0 或不鏽鋼 C9CCCF。

**廟埕與牌樓**
- 廟埕：石鋪 34×16（D8D0C2）。台基 24×22×0.8。
- 三川殿 18×8×4.6，屋頂高 2.8。正殿 16×9×5.6，屋頂高 3.4。
- 顏色：牆 A8342C、瓦 C2603C、脊飾帶 3E8C8C、脊中央的綠飾 4F9A6A。燕尾是兩端各斜 0.5 rad 的盒子。
- 前簷 4 盞紅燈籠 E0392C，夜裡自發光。香爐 r1。
- 牌樓：柱 0.9×6，在 ±6 m；橫樑 14×0.9，在 5.4 m 高；上面一個小屋頂。
- 廟面向站前道路，牌樓就在路邊。

**光**

| 天氣 | 設定 |
| --- | --- |
| 晴天 | sun FFF6E6×2.5；hemi D4E8FF／B9C99F×1.35；天空漸層 3D8BE0→9CCDF3→EAF5FB；霧 E2EFF8，320–1100 m；Neutral tone mapping，曝光 1.08；AO；建物下貼一張模糊方塊當接地影（黑 32%） |
| 雷雨 | sun C9D3E0×0.55；霧 8F989F，90–520 m；路面粗糙度 0.18，濕亮；窗戶提早亮 |
| 夜 | 窗 FFC98A，輕微泛光 |

**三角形與遠近分級**
- F 台灣版＋一個畫面 72–78 萬個三角形、79–98 次 draw call（人車都用 instanced）；沒有人車的 F 台灣版是 33 萬。
- 示意場景沒有做遠近門檻（全部畫近版），所以這是上限。
- 建議的門檻（未驗證）：
  - 鏡頭距離 ≲150–200 m：完整的人、車、騎樓陳列、曬衣、雨遮。
  - 150–400 m：人換成 7 件的遠版（目標每人 20–40 個三角形）或不畫；車換成兩個盒子。
  - 400 m 以外：人車都不畫，透天厝只剩盒子、屋頂、水塔。決策 238 的 700 m／距離×1.2 分塊遠版可以沿用。

**當時「定案前要補」的三件事，現況**
1. 真的台灣車與站房：列車已經做了（決策 230、243、252）。main 上找不到專屬的台灣站房。
2. 擋住列車的建物變透明：決策 342 做了。玩家列車前面圓錐裡的城市畫成 25%（alpha to coverage），只有圓錐經過的 chunk 改畫。
3. 建造時地面調淡：3D 還是從設定或 ContentView 打開的獨立預覽（`Map3DPreviewScreen`），沒有接到主地圖的建造模式，所以「建造時正上方、地面調淡」還沒有對象。

**main 和 F 台灣版＋ 的差距**
- 沒有人，路上也沒有車（Map3DProps 只有樹、路燈、電線桿；列車以外沒有會動的東西）。這是和作者那張圖最大的差別。
- 透天厝的立面細節是貼圖（`Map3DSurface` 的 homeWindows、homeBalcony、shopfront、shopEatery 等），畫在平的牆上。示意圖裡的雨遮、曬衣、店面貨物、騎樓柱是凸出牆面的幾何，斜看時有影子和厚度，這才是生活感。陽台、冷氣、直立招牌已經是幾何（決策 238），方向是對的。
- 騎樓沒有退縮的空間：一樓是貼圖，沒有陰影深處和柱子，貨物也擺不進去。
- 有廟（決策 235），但沒有廟埕、牌樓、人潮、燈籠。廟固定面向南，不一定面向街。
- 配色：決策 241 改用遊戲 2D 地圖的色系，比示意圖的晴天飽和度低。作者看的是明亮的晴天，要不要調亮，拿 `ftwplus-street.jpg` 並排給作者看再定。
- 拉近就傾斜：相機已經有（`Map3DCamera`，300 m 內傾到 55°），但只在預覽畫面，主地圖還沒有。

**建議先補的三件**
1. 先上人和機車（不是汽車）：
   - 照上面的零件比例做一種行人和一種機車騎士，用 InstancedMesh、每人換色。
   - 一開始就做好遠版與距離門檻。
   - 擺在月台（照遊戲裡真的候車人數）、廟埕、站前人行道、平交道前。
   - 台灣街景的辨識度有一半在機車。
2. 透天厝的一樓做成真的騎樓：
   - 一樓退縮 2–2.5 m 留出陰影，加柱子，店面貨物和低遮雨棚擺進去。
   - 樓上加凸出牆面的鐵皮雨遮和曬衣，只在近版。
   - 貼圖留給遠版。
3. 廟埕、牌樓、人潮做成一個「地標組」：
   - 廟改成面向最近的街，前面留廟埕，街邊放牌樓，燈籠夜裡亮，廟埕擺人。
   - 一個城鎮一兩個就夠，當畫面的焦點。

之後再做：汽車與公車、雷雨撐傘、擋住列車的建物淡出、接到主地圖。

示意圖相關檔案（2026-10-22 起在 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/3d-style-2026-10-13/`）：
- `ftwplus-street.jpg`：最接近作者要的畫面；
- `ftwplus-street-storm.jpg`：撐傘；
- `ftwplus-close.jpg`：列車、月台的人、平交道排隊；
- `ftwplus-phone.jpg`：手機上的實際大小；
- `ftwplus-street-night.jpg`：夜晚；
- `compare-ftw-ftwplus.jpg`：有人車和沒人車的對照。

### 4.4 3D 生活感這條線做到哪（session_01EPkWLr5a25LyJvCuvh1U3R，2026-10-17 更新）

遊戲規劃 session 派的四步，對照作者的目標畫面（本節開頭）。69.1 發版前收工。

**做完的**：
- **第 1 步：行人與車輛**（決策 259，#734）。
  - 方塊人、機車（一人或兩人）、轎車、廂型車，用 instancing 畫，只在拉近時出現。
  - 月台人數照候車，站前照一天的旅次，街上照城鎮人口；晚上店面與人行道的人少一半。
  - 依 GPU 決定份量，掉幀時再降一級；右上角細節顯示人數、車數、份量。
- **第 2a 步：空白地圖的種子道路**（決策 263，#745）。
  - 主要道路、街、巷照種子分配，和實景地圖共用 `addRoads`。
  - 軌道優先：地面上越過的畫平交道，高架下避開橋墩，路堤、路塹、月台旁邊不畫。只有主要道路與一半的街越過鐵路。
  - 透天厝沿街排、正面朝街。
- **第 2b 步：騎樓與生活細節**（決策 267）。
  - 騎樓柱、櫃台與三箱貨、低遮雨棚；樓上一半的樓層有彩色鐵皮雨遮，有陽台的 45% 曬衣；屋頂 75% 是圓水塔（遠處仍是方塊）。
  - 種子道路旁的透天厝，面向主要道路 70%、面向街 40% 一樓開店。
  - 這些小東西在第 4 層 LOD `Chunk.close`：鏡頭 450 m 內、分塊 350 m 內才畫（`Map3DCamera.wantsClose`），每塊多一次 draw call。之後的小細節（廟埕的燈籠、攤架）也放這一層：`Builder` 的 `target = .close`。
  - 斜交平交道的柵欄沿軌道法線離開道床、平台照 1/sinθ 加長；複線 8 m 內的交點合成一個平交道。
- **第 3 步：廟埕與牌樓**（決策 268）。
  - 廟面向格子四邊最熱鬧的種子道路（`templeFront`），台基後退，前面是最深 16 m 的石鋪廟埕，人行道邊立牌樓，簷下 4 盞夜裡發光的燈籠，兩角各一棵榕樹，廟埕 36 人。
  - 兩面臨街的透天厝後院，70% 鋪草地、1–3 棵樹。
  - 沒做：空地仍是素色（決策 241）、三級道路沒有行道樹（`addRoads` 和實景地圖共用，要另外看實景的效能）、實景地圖的廟沒有廟埕。
- **第 4 步的前半：拉近就傾斜**（決策 269）。
  - 2D 雙指拉近到 3D 站在 800 m 的比例時交給 3D，3D 拉遠超過 960 m 交回；縮放按鈕、建造工具、教學不交接（核心玩法 session 同意：引導的點擊在 2D 上）。
  - 3D 傾斜曲線：800 m 以外平視、150–200 m 約 34–40°、最多 42°。
  - 3D 場景放在 `Map3DSceneCache`（App），同一個世界只蓋一次，2D 拉到門檻一半就先蓋。
- **第 4 步的後半：2D 拉近畫種子道路**（決策 270）。
  - `Map3DScene.seededStreets(world:)` 只鋪軌道與月台、照決策 263 的規則選路（不蓋城市），和 3D 場景的 `seededStreets` 一模一樣（測試釘住）。
  - 2D 照實景道路的配色畫，64 m 格子 16–24 點時淡入。沒做：2D 的平交道記號、道路名稱。
- **#752（N700）的收尾**：#764（Antigravity）還原了其他車頭，#770 補 EMU3000 鼻頂，`Map3DModelTests` 釘住四款車頭的鼻頂顏色（決策 230 之後的修正）。

**下一步，照順序，一次一個 PR**：
1. 第 4 步的後半（決策 270）做完後，四步都完成；之後由遊戲規劃排序。決策 269 的缺口仍在：交接後要放開手指再雙指；3D 的方向交回時不保留；3D 裡沒有建造。
- **配色**（決策 272）：白天的光強一成二、公園與樹更綠；地面與道路照決策 241。目標畫面的大片草地沒有做，要做是另一個決策（連 2D 一起）。

**留下的缺口**（決策 259、263 的缺口一節有完整清單）：
- 車流：沒有跟車、紅綠燈、路口轉彎，車到道路端點就縮小消失；底圖沒有 oneway，所以單行道也畫成雙向。
- 人車沒有影子，車燈不照在路面。
- 平交道的柵欄不會隨列車放下，警示燈不閃，也沒有噹噹聲。
- 路在路堤、路塹處斷開，沒有地下道或陸橋；主要道路的路口沒有號誌。
- 第 2b 步沒做的：陳列只有櫃台與貨箱（沒有攤架、騎樓下的機車、花台），雨遮與曬衣沒有影子，實景地圖的建物沒有這些細節。
- 實機都還沒驗證：人車的幀數、舊機型降級、場景建構時間。兩鎮地圖除錯版的近版三角形 26 萬 → 45 萬（決策 263）→ 57 萬（決策 267），一個 170 m 的近景約 8 萬＋最近一層 2 萬 3 千。掉幀時先把 `Map3DCamera.closeReach` 調小，再把圓水塔換回方塊。

**預覽工具**（`tools/map3d-preview/README.md`）：
- `MAP3D_LIFE=x:z:距離` 畫人車；`MAP3D_BUSY=1` 把每站當作很忙；`MAP3D_LIFE_DETAIL=reduced` 畫舊機型的份量。
- 要知道平交道在哪：暫時在 dump 測試裡印 `scene.levelCrossings`，用完刪掉。
- 預覽預設連最近一層一起畫；`MAP3D_DETAIL=near` 不畫它。鏡頭的傾斜跟著距離，40 m 時幾乎往下看，所以騎樓的近照要選順著街的方向。

### 4.5 Peakline 圖資與離線模型研究（Codex，2026-10-19）

研究基準 main `43f6abc95bd4235a07f91480e401231cbf4cfe5f`；報告：[PEAKLINE_MAP_ENGINE_STUDY.md](research/PEAKLINE_MAP_ENGINE_STUDY.md)，附錄保留141筆套件、26個來源與E01解碼器（D26/E01同一上游），含官方查核、GLB與WorldCover小樣本。普通GLB轉換器已完成，本研究沒有重做或改App。

只推薦一個後續工具任務：報告§8的「無貼圖、無skin的靜態meshopt GLB → `.m3dmodel`橋接」，含節點選取與非AI來源紀錄；沿用§3已同意的tools-only glTF-Transform／meshoptimizer、固定版本／lockfile／README授權，不再列成未批准。正式工具尚未實作。WorldCover僅列視覺補漏候選；現有`addArea(.wood)`會影響程序城市展示地塊，不能直接灌分類。本環境香港下載403，但#820補充已有香港實際樣本、材質誤判與參考庫現成WorldCover，見主報告§3／§5；skin整體轉換與iOS／實機仍未驗證，無手機效能數字。初版functions間接LGPL漏查已更正；後續只用core／extensions4.5.1＋meshoptimizer1.3.0的五個MIT包，bridge lock／逐包授權與無functions重跑證據見附件，不把歷史offline lock視為已批准工具。原始參考GLB、加工腳本及原檔對照留scratch／私有交付，不放公開repo。排程仍由NEXT_PRIORITIES與遊戲規劃處理。

### 4.6 3D 地圖的淡色模型樣子（決策 370，session_014cbL5XNksWgQgYNkhMDNxV，#1075）

作者 2026-10-23 要 3D 像 Mapbox Standard。預覽、選定、「玩得清楚嗎」的對照與數字在 `docs/art/map3d-mapbox-look-2026-10-23/README.md`；原圖與腳本在參考庫同名資料夾（參考庫 #53 已合併，#54 是之後的重捏地標與 `play/`）。規劃選 (b)，做進遊戲的是 README 裡的 **(b'')**。

做到哪：第 1 步（全城換色、柔光、路燈光）已做，見本節最後的「第 1 步做了」與 `docs/decisions/370.md`；下面的清單是當初的派工，留著對照。

接手的人要做的（#1070，決策 368 合併後）：

1. 先在 #1041 更新登記。
2. 寫 `docs/decisions/370.md`，寫清楚改了決策 241 的哪些部分、242 的哪些部分：
   - 241：路面的藏青四階改成白（#FFFFFF–#F8F8F8），人行道改成路緣 #8F949E，黃色中線留。
   - 242：牆面細節留，但淡（預覽裡細節對比乘 0.35，牆腳較暗，影子較深）。
3. 先做 101 與台北車站。形狀照參考庫 `scripts/landmarks.py`，那是重新組的，不是原網格；顏色照 README 的表，101 玻璃天藍 #C0DDEE。
4. 再做全城淡色：
   - `Map3DPalette` 換色，照 `compose_play.py` 的 `REMAP`／`KEEP`／`pale()` 和 `roads` 選項；
   - `map3dShade` 加上柔光，強度跟著時間（預覽頁 `index.html` 的 `look`）。
5. 實機看夜晚的路：(b'') 的路面與地面夜晚只差 ΔL* 4.5。
6. 跑 `Map3DSceneMemoryTests.testThe3DMapRoundBanqiaoFitsAPhone`，記憶體不能增加。淡色只換頂點色；留招牌就不省貼圖（約 30 MB 的數字在 README）。

(d) 融合版（session_015wf4dPgATxoWNLz6ef2PW7，2026-10-23）：(b'') 的淡色加中灰路面（L* 62，#949598–#A6A7AA）、白路緣，天黑後路面加路燈光（黃昏不開）。顏色與對比（含白色、有色公車）在 README「(d) 融合版」。作者看圖後，由遊戲規劃把 (a)、(b'')、(d) 一起評分。選了 (d) 的話，上面第 2、4 點的路面改用 (d) 的顏色；`map3dShade` 給路面一個新 layer，天空夠暗時加路燈光（預覽頁 `ROAD_LAMP` 與天空亮度 0.30–0.42 的 smoothstep）。(e) 圖示色的 (d)（同一 session，同日）：明度同 (d)，路改帶藏青色相的灰（C* 6，#9595A0–#A8A7B2），地面 #ECEEF6，中線、燈頭、窗燈 #FFC86B（路燈照在路面的光仍是暖白）；`play-e.jpg` 與 README「(e) 圖示色的 (d)」，五方加權 7.43。選了 (e) 的話，除了 (d) 那些，再改地面色與中線色，窗燈顏色改 #FFC86B；月台邊線和中線同一個顏色，要不要一起換再決定。

**作者選了 (e)，月台邊線保留 #F2C94C**（2026-10-23：「用分數最高的7.6那個」）。這一段取代上面的「規劃選 (b)」：做進遊戲的是 (e)，路是帶藏青色相的灰 #9595A0–#A8A7B2，地面 #ECEEF6，中線、燈頭、窗燈 #FFC86B，路燈照在路面的光照 (d)，月台邊線維持 #F2C94C。上面第 2 點的路面與第 4 點的換色改照 (e)，第 5 點改看黃昏：路燈比 (d) 早一點開，有色公車與白牆在灰路上才看得清（差距 4–11）。排序：等 §22.2 10e（3D 地面與道路插進山丘，session_01AEq1bFjyAS1nyPmCs6wW7p）合併後才派，避免兩邊改同一批 `Map3D*` 檔。順序：先換全城顏色、作者用 iPhone 看；再做 101 與台北車站；最後跑板橋的記憶體測試。五方用同一把尺（(a) 6.90、(d) 7.45、(e) 7.45、(e)＋月台邊黃 7.60）：玩家 30 是 8.5（軌道、列車、公車都清楚，夜晚路對地面差一點仍看得清）；鐵道迷 15 是 8（柏油路是灰的，月台邊維持安全黃）；開發 25 是 7（只換頂點色，窗燈多一個 uniform，記憶體與 (d) 相同）；美術 15 是 9（和 App 圖示同一套顏色，作者在意的風格保住）；音樂 15 是 5（無關）。

**第 1 步做了**（session_01BnZ6aE54dfdknXcyjYqUvQ，`docs/decisions/370.md`）：全城換成 (e) 的顏色（`Map3DPalette`、新檔 `Map3DLook.swift`）、柔光、路面 layer −11 與路燈光（天空亮度 0.70 起開，0.50 全亮，比 (d) 早）。夜晚路面對地面 ΔL* 14.1；黃昏列車、白牆、公車對路面最小 7.8。板橋記憶體測試綠，頂點數不變。對照圖 `docs/art/map3d-mapbox-look-2026-10-23/game-e.jpg`。還沒做的：

1. ~~第 2 步~~ 已做（同一 session，決策 370「第 2 步」）：101 與台北車站做進遊戲（`Map3DTaipeiLandmarks.swift`，線條 layer −5、−8、−9）。作者要照網頁版高雄車站的方法先抓規格，所以大小、高度、101 的塔位（在購物中心的角上，不在中間）照 OSM 的 building part，台北車站頂 30 m；細節照 `landmarks.py`。玩家地面上的軌道穿過時地標讓路，台北車站畫出來時套件的台北站房不畫。板橋記憶體測試綠，網格 +0.03%（車站遠看的模型）。對照圖 `game-landmarks.jpg`。之後作者要 101 上半部更好看：加了白色平台與四個玻璃小箱、倒梯形頂層、三階退台、細尖塔（508 m），每節白腰帶與四角白直條，八節照真的外斜 7°，夜裡每節一圈光帶、白簷與頂冠打燈、尖塔頂一點白光（新的 layer −10、−12；`taipei101-crown.jpg`）。台北車站照三步（參考庫起點、OSM 規格與 entrance 節點、照片只看）加了四面騎樓、十二個門、南北中門的門廳與小瓦頂、方窗帶、屋角起翹、脊飾、雙坡天窗（`station-detail.jpg`）。作者看過預覽，2026-10-23 說兩棟都可以合併（PR #1107）。
2. 實機（TestFlight）看黃昏與夜晚的路、白天白牆對路面（只差 ΔL* 3–9.5，靠路緣與陰影分）。
3. 天空與霧沒有改；要不要照預覽調淡，看實機再決定。
4. 地標還沒做的：
   - 實機看 101 的夜景（光帶、角落燈條、尖塔頂）與台北車站的窗帶，看亮度要不要調（`Map3DShaders.metal` 的 −10、−12 分支）；
   - 台北一帶沒有真實建物圖塊（決策 239 只有高雄、台中），101 周圍是城市的建物；要不要加是另一件事；
   - 之後的地標照 §3 的三步做（參考庫起點、OSM 規格、照片只看），夜裡要特別的燈就用 `towerGlass`／`floodlit`。

預覽工具：參考庫 `scripts/Map3DPreviewDump.patch`（`MAP3D_PLAY` 放列車與標籤位置），用法在那裡的 README。

**台北市中心的地標與城門**（決策 457，session_01YGNNupg9BaQswnXKhfrkdv）：中正紀念堂、自由廣場牌樓、兩廳院、總統府、西門紅樓、國父紀念館、圓山大飯店、四座城門做進 `Map3DTaipeiLandmark`；中式屋頂（廡殿、歇山、重簷、起翹）是獨立的零件 `chineseRoof`（`Map3DChineseRoof.swift`）。還沒做的：
- ~~台北車站、101、高雄車站照第三輪的流程逐件更新~~：session_01YGNNumg2QcGW9DMPVNbA8L 做了（決策 457「後來」）；作者選了台北車站、101 的第四欄；高雄車站的兩棟共構大樓已加（OSM ways 1298938833、1298938834），高度是照新聞樓層估的（35 m、38.5 m），有官方數字後再校正，見決策 457「後來」；
- 讓 civic-kit（廟宇、古蹟）與 residential-kit（三合院、傳統街屋）的配方共用 `chineseRoof`（遊戲規劃在這張合併後派）；
- 101 夜裡照星期換色（§22.12 第 3 項的另一半）；
- 其他大廟改用 `chineseRoof`（§22.12 第 15 名「廟放到真實廟址」）；
- 實機看台北開局多出的約 1.6 萬個近看三角形的幀數；
- 城門只有十幾公尺，卻清掉整格 64 m 的城市；要縮小就改 `addTaipeiLandmarks` 的清場，照 `clearing` 的矩形清，不清整格。

### 4.7 鐵路低於地面的路塹（決策 375，session_01AEq1bFjyAS1nyPmCs6wW7p）

作者 84.1 的回報（駕駛室前面只有路、白色平面切進山）：道床低於 64 m 的地面的地方，現在挖一條溝（`Map3DTrench.swift`），地面、底圖、道路、標線、街上的車都讓開，深溝上的跨路留成橋。還沒做的：

1. 10e 其餘：照圖磚 `brunnel`／`layer` 把公路橋架高（每層約 6 m、兩端坡道、墩和 10f 共用）。跨溝的路現在只在溝深 6.5 m 以上、夾角大於 30° 時留在地面高度當橋；淺溝上的路是讓開的。
2. 真實路線（`Map3DRealTrains`）的路塹沒有挖。
3. 小瑕疵：兩段溝接在一起的地方可能有細縫；溝坡上的電桿腳埋在坡裡；溝的端面只在隧道口封。
4. 實機：TestFlight 上從高鐵示範的駕駛室看苗栗南的路塹（最深約 20 m），看坡的顏色、跨路的橋和 fps。

### 4.8 全地圖用真實建物足跡（決策 386、389，session_0111G2MZyPt5YSXpsF6azF2e）

第 1 到 4 步做完：

- 第 1 步，決策 386：`tools/overture-footprint-tiles/` 把 Overture 的台灣建物（196 萬棟）做成 z16 精簡圖塊。報告 `docs/research/OVERTURE_FOOTPRINT_TILES_2026-10-23.md`。
- 第 2 步，決策 389：工具填上樓層。3D 地圖有足跡的 64 m 格畫真實足跡，沒有的才放程序房子。
- 第 3 步：打包成 `BaseMap/taiwan_buildings.pmtiles`，29.6 MB。
- 第 4 步：`DataSourceCredits` 的 `overtureBuildings` 與 `buildingStoreys`。

照工具的 README 重建約 3 分鐘。還沒做的：

1. ~~和決策 385 對接~~：做完（#1127 先合併，#1132 合併 main 時接上；有足跡時機場的建物由足跡畫，決策 389 第 5 點）。
2. **官網 `credits.html`**（參考庫）加：
   - Overture 建物：3D 地圖也用。
   - 臺中市建物圖 111、113、114 年，臺北市建築執照套繪圖（政府資料開放授權條款第 1 版）。
   - GHS-BUILT-H（CC BY 4.0）。

   文字照 `DataSourceCredits` 的 `buildingStoreys`。
3. **實機**（**UNVERIFIED**）：
   - TestFlight 的 App 大小；
   - 讀檔與建 chunk 的時間；
   - 足跡房子在 Metal 上好不好看。
4. **美術的後續**：
   - 足跡房子沒有招牌與一樓店面：可以依用途（商業）與臨街加。
   - 沒有放進 close（決策 267 的騎樓等）。
   - 樓層 0 的不會出現：工具給每棟都填了。
   - 高雄車站的大屋頂（Overture，665 × 334 m、10 個天窗洞）照決策 239 畫成柱子撐的薄棚，斜看像一張有圓洞的平面（遊戲規劃 2026-10-23 的美術意見）。main 上讀城市圖塊時也是這樣。要更像新高雄車站的屋頂（圓錐採光口、起伏）是決策 239 的後續。
5. **樓高來源還沒做的**：
   - 國土測繪中心的授權：作者還在考慮，要問的事在報告 §8.5。格式已留位置，接上只要改工具的順序重跑。
   - 內政部 20 m DSM 減 DTM，能不能抓出 40 m 以上的高樓：TGOS 對這個環境 403，從 GitHub Actions 下載要另寫 workflow。報告 §12.4。
   - 其他直轄市的建物圖：報告 §8.3。
6. Overture 每月出新版；換版本時重跑 `extract`、`storeys` 與 `build`，在 PR 寫新舊棟數與大小。

### 4.9 機場等地不蓋房子、程序房子沿真實的街（決策 385，session_01AgFLCW9xSb9fyLr8k57iZ1）

作者 85.1：「機場不要有住宅看起來好怪」「而且也太整齊了吧」。做完的：實景 3D 地圖在機場、軍事用地、墓地、高爾夫球場、鐵路用地與港區不畫城市的房子，機場畫 OSM 的航廈與機棚（`tools/no-build-land/`、`RealNoBuildLand`）；程序房子沿底圖的真實道路排、面向馬路，寬窄、退縮、樓高、種類有變化，沒有路碰到的格子不放（`Map3DFrontage.swift`）。三角形與記憶體不高於 main（決策 385 第 3 點）。#1127、#1130 都已合併。剩下的：

1. **人口**：做完（決策 385 第 4 點，`claude/no-build-population`）：新開的實景地圖在這些地上不住人，人搬到同一個 WorldPop 格的其他格，總數守恆；存檔版本與 golden 不動，舊存檔已讀的地照舊、之後新讀的地塊用新規則。資料檔搬到 `Resources/RealWorld/`。
2. **和決策 389 對齊**（決策 386 第 2 步，§4.8；session_0111G2MZyPt5YSXpsF6azF2e 的 #1132，`claude/footprint-tiles-3d`）：已和 0111G2 約好，由 #1132 合 main 時做：
   - 在兩個 pass 都把 `addAirportBuildings` 包進 `if footprints == nil`：Overture 足跡已有 OSM 的航廈與機棚，385 的機場建物只在沒有足跡檔時當後備。
   - 不蓋區裡照畫 Overture 的建物，只有程序房子不放。
   - `addFootprints` 放在公園之後、`addCity` 之前，回傳的格併進 `standing`，所以排房與沿街的房子都避開它。
   - 用途對齊：Overture `transportation` → `.transport`，`industrial`／`outbuilding`／`agricultural` → `.industry`。
   - #1132 合併後，確認 `Map3DScene.init` 裡有這個條件；沒有就補一個小 PR。
   - 動 `addCity` 的人先 `send_message` 給這兩個 session。
3. **實機**：只在 Linux 的 WebGL 預覽看過（`docs/art/map3d-no-build-2026-10-23/`）；下一次 TestFlight 看 600 倍俯看小港與板橋，房子是不是太稀或太密（`Map3DScene.Builder.openShare` 與 `layFrontage` 的公寓比例）。
4. **決策 516**（HOUSEROAD，作者 99.1 宜蘭平原的點陣）：辦公、公共、休閒的低密度地塊也沿路排了。還沒做：密度 3 以上的樓與工廠在實景地圖上仍在格子中間（決策 516 下一步第 1 點）；實機看宜蘭平原 600× 俯看的疏密（第 2 點）。

### 4.10 3D 月台只畫在放得下的地方（決策 392，session_01QnjGxTmCx1sAYpH4wacqhH）

作者 86.1：「過站的時候會撞到月台」。原因是月台配對把高鐵示範錯開 10 m、只隔 5 m 的正線與側線月台當成島式月台，月台蓋到另一條軌道上；已改成只認橫向距離、放不下就不畫（`Map3DScene.Builder.addPlatforms`）。剩下的：台北、板橋真實是島式月台、快車停正線，遊戲的 5 m 股道間放不下，3D 裡這兩站的快車停在沒有月台的正線；要畫就得在高鐵示範把這兩站的股道拉開（動示範的軌道，沒有人接，決策 392 下一步）。

### 4.11 隧道裡的駕駛視角不畫地面（決策 394，session_01AdAQTbXs639m7Yd3ZoxLE7）

作者 2026-10-24：「如果在隧道或是地下能不能不要算地面上的建築物等切換視角的時候再計算會省gpu嗎」。做完的：駕駛視角在隧道深處、300 m 內沒有洞口、視野裡也看不到洞口時，只畫每個 chunk 的地面、軌道與道路（bore 與洞口在這裡）和列車，其他（城市、遠近細節、街具、招牌、人車、日影 pass、地面陰影、雨、天空）都不畫，mesh 留在記憶體（`Map3DUnderground`）。剩下的：**實機 GPU 數字還沒量**，下一次 TestFlight 照 [決策 394](decisions/394.md)「怎麼在實機上看」量；看到洞口前城市晚出現，就把 `Map3DUnderground.near` 調大。

### 4.12 公路橋照真實高度架高（決策 391，session_01MZ2KiwLCyJErN9jbfH6p78）

作者 2026-10-22：「目前道路要不要改照真實高度而不是全部在地面」。做完的：跨過軌道、地面道路或較低的橋的公路橋，在交點抬到一層 6 m，兩端照 5%／6%／8% 的坡度下到地面；高架鐵路下的路留 4.6 m 淨空。國道最高的 5 座橋照 data.gov.tw/dataset/30616。梁、墩、坡道擋牆在 `Map3DElevatedLook.roadBridge`，`Map3DRoadBridge.swift`。main 上 29 個交點不夠高，這裡是 0。這個 session 壓縮到第 2 次後在這裡停。還沒做的：

1. ~~**圖磚沒有 `layer`**~~：做完了（[決策 391 續篇一](decisions/391.md)，session_01AhfV8HVyDQfkoqCY2FNbmY）。`build_basemap.py` 在 2 層以上的橋寫 `layer`，`taiwan.pmtiles` 從 main 重切；板橋場景 +0.8%。
2. **10f**：換墩的款式（改 `Map3DElevatedLook.roadBridge` 或加一組），以及橋下的陰影。
3. 決策 375 留下的真實路線（`Map3DRealTrains`）路塹（§4.7 第 2 點）。
4. **實機**（UNVERIFIED）：TestFlight 上看板橋、苗栗南的跨線橋、坡道與 fps。板橋周圍的場景大了 9%。
5. 苗栗南 16 塊的位元組在分支上量過一次 20,259,996、之後三次 20,266,884（頂點 md5 相同），沒有再重現。分塊與整片一樣由 `Map3DStreamingTests` 守著；若再看到不同的數字，先懷疑 `VectorTile.layers`（Dictionary）的順序。
6. **斷路接起來**（遊戲規劃 2026-10-24 補派，作者：「路面橋在照高度的時候要不要順便補道路鋪設 感覺能一起做」）：**實景底圖的部分做了**，[決策 391 續篇二](decisions/391.md)（session_01T3bLvXC3Wm9dpcDF5WMjCj，分支 `claude/road-joins-391`）。地面的路在淺路塹與矮路堤處架陸橋越過（軌面 + 6.5 m），在高路堤處留在地面、路堤開口架一段梁；示範地圖原本斷的 100 處接上了（`Map3DSceneMemoryTests.testTheDemosRoadsOnTheGroundGoOverItsEmbankmentsAndCuttings`）。路堤處沒有採用「路面下挖」。還沒做的，照順序：
   - **地面月台**（示範 19 處）：月台不在 `trackCover`，`addPlatforms` 在底圖之後才畫，路照舊在月台處斷開。做法：把地面月台的範圍（`Map3DScene` 建月台時的長方形）也當成交點，路越過，高度同路塹（軌面 + `overTrack`）。
   - **空白地圖的種子道路**：`Map3DStreets.trackMeeting` 對路堤、路塹與任何月台回 `.blocked`（`Map3DStreetsTests.testTheTrackComesFirst` 守著），要改成新的 `.joined`（斜交 > 0.5、兩側都有街），2D 地圖用同一個 `SeededStreetPlan`，要一起看；再把 `Map3DRoadBridges.addJoins` 用在種子道路上。先寫測試：兩鎮種子地圖被丟掉的交叉段數（main 上不是 0）。
   - **實機**（UNVERIFIED）：TestFlight 上看高鐵示範板橋、苗栗南附近跨過路塹與路堤的路、路堤的開口。
7. PR 收尾若這個 session 沒做完：CI 綠 → 標 ready → #1041 留「可合併」→ 告訴遊戲規劃。

### 4.13 3D 跟車的駕駛資訊（決策 403，session_01XztRUELu6E7BzspLuGpk9w）

作者 2026-10-24 看了韓國高鐵駕駛遊戲的錄影，說「都可以五方評估決定」；規劃選了方案 E，分三個 PR。第 1 個做完了：3D 跟車時上方一條（線、方向、下一站、距離、誤點）、車速卡（現速、現在的彎道限速、前方下一個限速與距離）、進站提示（`Map3DDriverHUD`）。還沒做、由遊戲規劃另派的（細節在決策 403「下一步」）：
- 第 2 個 PR：「旁邊」「從車站看」兩個視角（NEXT_PRIORITIES §22.2 第 10m 名）：做了（session_01ECniun7ySv3N8EbHxvmefb，`claude/follow-views-403`）。實機要看的與剩下的在決策 403「續：旁邊與從車站看」的下一步。
- 第 3 個 PR：鳴笛與 3D 快照（第 10n 名）：做了（session_01P5gjwSg3taxPLmdNHrMbLb，`claude/map3d-horn-snapshot`）。實機要聽、要看的與剩下的（真實汽笛錄音、平交道前鳴笛、照片的署名只寫畫到的來源）在決策 403「續二：鳴笛與 3D 照片」的下一步。
- 實機看 iPhone 橫拿時三張卡會不會擋到前方；真實列車能跟車之後，也接上這三張卡。

### 4.14 3D 效能：遠景城市的實例、太陽陰影、小細節、東京狂飆研究（決策 455，session_01YGNNunmjyoeMSdTvYbyZJm，2026-10-28）

作者交代四項（P0–P3），這個 session 壓縮過一次，做到這裡停。

- **P0 遠景城市的方塊用實例**（[決策 455](decisions/455.md)）有兩個 draft PR：
  - 第一步 #1408（`claude/far-box-instances`，展示層與 App 留著的場景）；
  - 第二步 #1410（`claude/far-box-instances-metal`，Metal 用實例畫，疊在 #1408 上，要先合 #1408）；
  - 全尺寸預覽在 a91453/railway-assets-private#14。
- **P0 還沒做的**，照順序：
  1. **實機**（UNVERIFIED）：TestFlight 上看板橋、台北的遠景白天與夜裡，記憶體（Xcode 的 Memory Report 或 Jetsam 紀錄），GPU 與 CPU 的幀時間。第二步讓遠景每個 chunk 多一個 draw：5,000 m 從 64 到 96，太陽陰影圖從 172 到 255。
  2. 若 CPU 變慢，把一個鏡頭看到的方塊併進每幀一個實例緩衝、一個 draw 畫完（決策 455 寫了）。
  3. `.metal` 沒有在 Linux 編過，第一次編譯是 #1410 的 iOS 建置。
- **P1 太陽陰影用簡化版城市：量過、不做**，決策 456 沒有用（已在 #1041 釋出）。數字來自 `Map3DCityMemoryReportTests.testTheCitysMemory` 的「sun map at」幾行，`MAP3D_FRAME_REPORT=1`。
  - 太陽陰影圖只對畫完整版的 chunk 畫完整城市。月台、車站、高架橋、軌道都在 base，本來就投影；列車不畫進太陽陰影圖（用決策 232 的團狀影子）。
  - App 的資料下，把那些 chunk 的城市換成簡化版只少 30k–63k 三角形（陰影圖的 10% 以下），每個 chunk 卻從 1 個 draw 變 3 個。近看時陰影圖一格只有 0.21–0.36 m，換成方塊看得出來。
  - **陰影圖最大的一層是街道設施**：台北 1,000 m 時 496k 三角形、210 個 draw，城市只有 210k。用「模型最寬的一邊 ≥ 兩格」挑也挑不掉：電桿的包圍盒 10.2 m、路燈 8.6 m，算進了電線與燈臂。要省得用模型本身的粗細（例如樹冠以外的細桿不投影），或在陰影圖裡把同一個模型的實例併成一個 draw。這是街道設施的事，作者這次說不要動，留給之後。
- **P2 小細節的實例池：量過、不做**。冷氣、遮雨棚、陽台、晾衣都在近距細節（`.close`，決策 267）。整層連車站套件、地標、月台小物、架空線也只有 17–20 MB（板橋、台北 App 的場景 367–517 MB 裡），而且只在最近時畫。全部改成實例也省不到 5%。
  - 遠景屋頂的水塔與加蓋在 P0 已經是實例。
  - 場景裡最大的剩下底圖（地面、軌道、道路：板橋 216 MB、台北 280 MB）與決策 232 的團狀影子（35–48 MB），下一個省記憶體的地方在那裡。
- **P3 東京狂飆研究**：在 [docs/research/TOKYO_RUSH_STUDY_2026-10-28.md](research/TOKYO_RUSH_STUDY_2026-10-28.md)。鏡像沒有授權檔，只讀不取。§4 有三個提案，都沒做，可以各派一個小 PR：
  1. 站前三樓以上街屋的逐層招牌牆，字用我們自己的 `Map3DSignAtlas`；
  2. 轉角街屋臨路的側面也畫店面與窗；
  3. 依行業換店門口的擺設，部分店拉下鐵捲門。

### 4.15 依機型的記憶體與 CPU 兩軸（決策 460，session_01YGNNunsRnVMGEEAM3pwnzr，派工單 BQ，2026-10-28）

- 做了的在 [決策 460](decisions/460.md)：記憶體 3–4 GB（或系統只讓用 2.5 GB 以下）的機器不先建、不留 3D 場景，自動畫質起點低一格；所有機型剩下記憶體低於 300 MB 就先降；遊戲迴圈跟不上時依晶片與發燙休息（A14 以前最多 60% 的時間在算 tick）。問題回報的每一段多一項「裝置」。GPU 分層補兩點：M 系列晶片升一級；「少像素」在 iPad 上真的少（整個畫面最多 170 萬像素）。
- **等作者在 TestFlight 看**（UNVERIFIED）：4 GB 的 iPhone 開關 3D、在台北拖動時有沒有閃退、回報裡的「記憶體最高／最少剩」與「裝置」；`tight` 每次開 3D 要等多久；6000× 大地圖上 A14 以前的手機畫面順不順、燙不燙、實際倍速；M1 iPad 的 `MTLDevice.name` 是否以「Apple M」開頭、升級後順不順，iPad 降像素後的清晰度。
- **下一步**（沒派）：3D 場景上傳 GPU 後放掉 App 留著的那份（tw3d `gpu-residency.js` 的做法，所有機型省 370–520 MB），見決策 460「下一步」。

### 4.16 跑不到設定倍速時的一次性提示（決策 464，session_01YGNNumnQtaMdPM5echyBfu，派工單 BV，2026-10-28）

- 做了的在 [決策 464](decisions/464.md)：連續 20 秒低於設定的 70% 時，倍速旁的點自動打開一次 popover（「這張地圖在這台裝置上大約只跑得到 ×N」＋改成最近跑得到的一檔＋知道了；發燙時只說「裝置有點燙，遊戲先放慢」）。規則在 `SpeedLagHint.swift`，Linux 測試 `SpeedLagHintTests`。
- **等作者在 TestFlight 看**（UNVERIFIED，Linux 編不了 SwiftUI）：舊 iPhone／iPad (A16) 在大地圖 6000× 時 20 秒後有沒有跳、popover 擋不擋操作、「改成」那一檔順不順；70%／20 秒是不是剛好（太吵就調 `SpeedLagWatch.lowPermille`／`sustained`）。沒有新的 UI 測試。

### 4.17 手機上看板下那一排照寬度收起來（決策 469，session_01YGNNuphFRU9bQ2b4Tq1DwJ，派工單 CD，2026-10-28）

- 做了：UI 健檢 D 的 2-3（那一排的窄排法）與 2-22（建造數字列）；2-20 只做到那一排會跟著細節卡收。
- 實機待看：iPhone SE 與一般 iPhone 橫拿、開細節卡、夜晚或跟車時那一排；收成「圖層」鈕後點得到、會開圖層表。
- 留下的：2-20 其他浮動元件（站長、警示泡泡、小地圖）在橫拿開細節卡時的取捨，見[決策 469](decisions/469.md) 的下一步，等健檢第 5 節的截圖檢查。

### 4.18 描線接上已有軌道、真實路線讓位給玩家（決策 468，session_01YGNNun7niN3kzJtkLN8GL6，派工單 BZ，2026-10-28）

- 做了的在 [決策 468](decisions/468.md)：沿真實路線描線碰到同一條線上已鋪的軌道（自己的、收購的、示範的）就略過、不收錢、兩端自動接上繼續描，仍是一個 `buildTrackChain`；玩家軌道蓋住的那段真實路線不畫，那段上的真實列車不畫；車站過半是玩家同名車站的線整條不跑真實列車。規則在 `TraceOverlap.swift`、`RealRailwayYield.swift`，Linux 測試 `TraceOverlapTests`、`RealRailwayYieldTests`。
- **等作者在 TestFlight 看**（UNVERIFIED，Linux 編不了 SwiftUI）：預覽的虛線＋光暈好不好認；真實路線切掉的地方對不對齊玩家軌道。
- **下一步**（沒派）：3D 地圖還沒讓位；接上時的複線；「可以直接收購」提示。見決策 468「下一步」。

### 4.19 載入畫面的步驟與取消（決策 473，session_01YGNNukvbEqFLMsPED4XHuY，派工單 M，2026-10-29）

- 做了的在 [決策 473](decisions/473.md)：實景新局、示範、讀存檔的載入畫面顯示實際完成的步驟與進度條，並有「回開始畫面」／「回到遊戲」。規則在 `RealWorldLoading.swift`、`GameLauncher.swift`（`LoadingRun`、`cancelLoading()`），Linux 測試 `RealWorldLoadingTests`。
- **等 macOS CI 與 TestFlight 看**（UNVERIFIED，Linux 編不了 SwiftUI）：條與按鈕的位置、按下取消後回到的畫面。
- **下一步**（沒派）：依量到的時間給每步權重；GameCore 建世界加檢查點讓取消能在步驟中間停；第一次開 3D 地圖的等待。見決策 473「下一步」。

### 4.20 地圖標籤不互蓋、「整個臺灣」放第一、缺建材泡泡開在建材（決策 477，session_01YGNNumMhqmw96pGQJnVgtY，派工單 SHOT，2026-10-29）

- 做了的在 [決策 477](decisions/477.md)：警示泡泡、票價避開站名（`MapLabelPlacement`，Linux 測試 `MapLabelPlacementTests`）；擴張地圖的價錢不躲在頂列下、景點星等讓價錢；底圖地名被頂列蓋住時移出；真實地圖選單「整個臺灣」放第一；點「缺建材」泡泡開車站面板並捲到「貨運與拆除」組（`StationPanelGroup.answering`，`StationPanelFocusTests`）。
- 車隊總覽「從卡片拖不動」查過：main 的程式照影片流程拖得動（run 40822516453、40823923438），沒改，測試 `MapInteractionTests/testTheFleetListScrollsFromADragOnACard` 留著防退步。
- **發版前要補（作者 2026-10-29：「截圖先暫停拍攝 明天要發前再做」）**：截圖驗收沒做。到時在分支或 main 跑 `website-screenshots.yml`，看 freight-materials、freight-station（泡泡點開後面板在建材）、map-expansion、liu-mingchuan（臺北市、基隆市要完整）、real-world-demo-day（票價不蓋八堵）、新加的 real-world-picker；照 `docs/research/UI_UX_REVIEW_2026-10-28.md` §5 看七題、寫最嚴重三項、最多三輪。本 session 的截圖 run 40828547711 排隊中被規劃取消，沒有拍到。
- **修之前的截圖**（不要刪）：網站截圖 artifact `website-screenshots`，run 40805756457（VID）；宣傳影片截圖 run 40812436549（WEB）。都在 a91453/railway-game-ios 的 Actions，保留到 GitHub 的期限。
- **等 TestFlight 看**（UNVERIFIED）：iPhone SE 開始畫面不必捲就看得到「新遊戲」是估算，CI 是 iPhone 17 Pro；地名「空位」在各縮放下有沒有把地名推得太遠。

### 4.21 畫面的 ui-review skill、截圖驗收暫緩（決策 482，session_01YGNNuoinesWfV5nQhzCYuV，派工單 UIREV，2026-10-29）

- 做了的在 [決策 482](decisions/482.md)：`.claude/skills/ui-review/`（改畫面前讀；第 3 節截圖驗收、第 10 節列車用圖標還是車型）、UI_THEME「玩家看的文字」第 7 條。
- **截圖驗收暫緩**（作者 2026-10-29：「截圖先暫停拍攝 明天要發前再做而且我自己也可以截圖」）：#1467（決策 472）圖表的驗收沒拍。拍照的測試 `testStatisticsCharts`、`testTrainLooks` 已在 `WebsiteScreenshotTests`，發版前在那個分支跑一次 `website-screenshots.yml`（一次只跑一個），照 skill 第 3 節看，寫成決策 472「472 截圖驗收」；路線清單列的問題給 LP（決策 481）。
- **鐵道味建議**（只列不改）：決策 482 續篇的表，規劃決定要不要派。

### 4.22 路線面板拆兩層（決策 481，session_01YGNNunF7F1xm5bcPAv9pcL，派工單 LP，2026-10-29，#1476）

- 做了的在 [決策 481](decisions/481.md)，包括：
  - 精簡清單與每條線自己的頁
  - 線多時分組、可收合
  - 「需要注意」篩選
  - 從頁面返回時清單捲回那條線
- 規則在 `LinesPanelNavigation.swift`、`LineGroups.swift`，Linux 測試在 `LinesPanelNavigationTests`。
- **留到發版前**：截圖驗收（決策 482）。作者 2026-10-29 暫停截圖：「截圖先暫停拍攝 明天要發前再做而且我自己也可以截圖」。
  - `WebsiteScreenshotTests.testLinesListAndLinePage` 已寫好，還沒跑過。它拍三張：清單（`lines-list`）、一條線的頁（`line-page`）、整個路網的頁（`lines-network`）。
  - 規劃要的「線多一點的局，看得到分組與需要注意」還沒有：貨運場景只有幾條線。發版前跑截圖時，改用實景 demo 或收購後的局。
  - 合併 main（#1472）後，`testLoadCharts` 改成點列進線頁再拍兩張載客圖，回清單再按路網流量。
  - `testStatisticsCharts`、`testTrainLooks` 也會拍到路線列：`line.report.*` 還在清單列上，`lines.networkFlow` 還在工具列。
  - 沒有刪任何截圖：這個 PR 只有 `docs/art/lines-panel-481-2026-10-29/overview.png`（三個做法的示意圖），沒有 Actions 的截圖 artifact。
- **等實機看**：
  - 固定在上方的四段篩選會不會太擠。
  - 組標題按鈕的大小。
  - 見決策 481「下一步」。
- **沒修好、交給下一個 session：`LineRoutePreferenceUITests` 兩支在合併後的 main 是紅的**（只在 full lane 跑，`FULL_LANE_LESSONS_JOB`；PR 的 gate 不跑）。本 session 已壓縮 3 次，照規則停手，沒有修。
  - 證據：手動 `ios-build.yml`（`only_testing: LineRoutePreferenceUITests`，iPhone）run 40844553127 與 40855808395。後者在 9573aea，程式碼與 main aa2fc49 相同。
  - `testTheAdvancedSwitchFoldsTheTracksAndTheServiceDay` 紅在 `ToolbarSmokeTests.swift:284`：「lines.advanced Switch never lay wholly on screen」。
    - 剛開面板時，`setAdvanced` 的 8 次 swipeDown 都沒讓開關出現，但一次短拖（清單 0.9→0.75）就出現了。
    - 從線頁按返回後（約 80 秒處），8 次 swipeDown 加 16 次短拖都沒讓開關出現。
    - 疑點：返回時的 `returningTo` 捲回、或 `safeAreaInset(edge: .top)` 固定的篩選列（橫向 272pt 高的面板裡約佔 130pt）把「進階」那列擋住或捲不到。下一步先在 `setAdvanced` 裡印 `app.debugDescription`，看開關那列在不在樹上、frame 在哪。
  - `testALineLegCanSelectAPhysicalPlatform` 紅在 `ToolbarSmokeTests.swift:106`：選單點「Automatic route」後，`line.route.-1.0.1` 按鈕找不到，等「Automatic route」字樣逾時。
    - 在 68bde52 綠過、40844553127 也綠，只在 40855808395 紅。
    - 疑點：#1472 合進來的 `loadSection`（載客圖）讓線頁變長、選單關掉後頁面重排或捲動；也可能是偶發。先在 main 上用 `only_testing` 單跑一次確認。
  - 修法只動測試（`ToolbarSmokeTests.swift` 的 `setAdvanced` 與這兩支），用 `only_testing` 一次跑一支驗證。
- **已修好（派工單 LPF，session_01YGNNunFRqKWjsexshYKzgD，分支 `claude/lines-route-tests-fix`）**：上面兩支都是測試的問題，App 沒有玩家點不到的東西。
  - **原因（LPF 看 40855808395 的結果包與 App 的 trace）**，兩支都是測試的問題，App 沒有玩家點不到的東西：
    - 進階開關：手機橫放時面板只有 270 點寬、272 點高，上方固定的篩選與排序到 y=213，列只剩約 130 點。`swipeDown()` 從清單正中間（667, 206）開始拖，正好落在排序鈕上，清單一動也不動（失敗時捲軸在 100%，清單停在最底）。之後的短拖與 `bringIntoView` 都是往下捲，開關在上面，永遠到不了。玩家在列上拖可以正常捲回上面。
    - 選路線：第二次開選單、點「Automatic route」時，點的位置正確（選單項中心 593, 94），但 App 的 trace 寫著這次觸控開始後 164 毫秒被取消，選單沒關、選擇沒生效。這和 `setAdvanced` 註解裡 run 39781136910 的「觸控被取消」是同一類：偶發，玩家再點一次就好。#1472 的 `loadSection` 沒讓頁面重排（路段列在兩次失敗前後的位置相同）。
  - **修法（只動 `ToolbarSmokeTests.swift`）**：
    - `setAdvanced`：拖動都從固定控制項下方的列上開始（新的 `XCUIApplication.linesListTop(under:)` 算出列從哪裡開始）；先往上捲到第一列（整個路網）露出來，再用短拖往下找開關；最後把開關本身（不是整列，整列約 115 點，比列的空間高）捲進來。
    - `bringIntoView`：在清單上時，「完整顯示」要避開固定的控制項，不只導覽列。
    - 新的 `chooseMenuAction`：點選單項後讀路段的字；沒變就再點一次（選單還開著）或重開選單，最多 3 次，每次先讀字，已選好就不再點。
  - 驗證：`only_testing: LineRoutePreferenceUITests`（iPhone）run [40860707208](https://github.com/a91453/railway-game-ios/actions/runs/40860707208)（commit 3d3b658）兩支都綠（152 秒、200 秒）。這次觸控沒被取消，`chooseMenuAction` 的重試沒用到。
  - 以後避免同類問題：
    - 面板上方有固定（`safeAreaInset`）的控制項時，不要在清單上用 `swipeUp()`／`swipeDown()`，它們從元素正中間開始，會落在固定的控制項上。拖動要從列上開始。
    - 找不在畫面上的列，要先想它在上面還是下面：`dragUntilWhollyOnScreen` 在元素不存在時只會往下捲。
    - 點選單項後要確認結果（值或字有沒有變）；沒變而選單還開著，就再點一次，不要只等更久。

### 4.23 三張載客圖與資料視覺化盤點（決策 478，session_01YGNNuosyKEgJgsVUGFPhbW，派工單 VIZ，#1472，2026-10-29）

- **做了的**在[決策 478](decisions/478.md)，共三張圖：
  - 路線面板的「各站間載客」。
  - 路線營運段的「每日最擠的一班」。
  - 路網流量區間頁的「各時段」。
- 規則在 `LoadCharts.swift`，Linux 測試是 `LoadChartTests`。
- 盤點表在 `docs/research/DATA_VIZ_AUDIT_2026-10-29.md`。
- **留到發版前：截圖驗收**。作者 2026-10-29 說「截圖先暫停拍攝 明天要發前再做而且我自己也可以截圖」，所以這張沒有拍。
  - 截圖測試 `WebsiteScreenshotTests.testLoadCharts` 已經寫好，拍 `line-peak-load`、`line-load-profile`、`section-hourly` 三張。
  - 發版前在 main 手動跑 `website-screenshots.yml` 就有。它只拍深色，淺色要實機看。
  - 照 `docs/research/UI_UX_REVIEW_2026-10-28.md` §5 看：七個問題，最多三輪。
- **截圖與預覽放在哪**（都不刪）：
  - 沒採用的畫法預覽在 `docs/art/data-viz-2026-10-29/overview.png`。
  - 產生它的腳本沒有進 repo。
  - Actions 沒有留下這張的截圖 artifact：兩次 `website-screenshots.yml`（run 27、29）都在拍之前取消。
- **下一步**（沒派）：
  - 盤點表第一類的下一張是票價距離級距的階梯線。
  - 第二類要 GameCore 記歷史，會動存檔。
  - 規劃提的收支組成甜甜圈與可捲動長趨勢。
  - 以上都見決策 478「下一步」。

### 4.24 宣傳影片素材（決策 475，session_01YGNNukoWqi8apoMDtJNZ3x，派工單 VID，2026-10-29）

- 做了的：`PromoMaterialTests` 與 `website-screenshots.yml` 的 `kind=promo`（[決策 475](decisions/475.md)，#1461 已合併）。一次 iPhone 17 Pro 深色跑（run 40825762656，commit d3cd9db）：230 張 PNG、16 支影片。影片轉橫、裁 20 秒、壓縮後逐格檢查，沒有超過 0.1 秒的卡頓。
- 素材不在這個 repo：在 `a91453/railway-assets-private` 的 `promo-material/2026-10-29/`，三個草稿 PR（#27 影片＋README＋三城市、#28 四城市、#29 各場景），等作者合併。影片也直接傳給作者了。
- 還沒做：iPad、淺色（作者：發佈前再拍，他自己也能截圖，所以不再跑 `website-screenshots.yml`）；實機 3D 影片由作者自錄，放 README 的「實機素材」。
- 沒解決的：「車隊總覽」清單（SwiftUI `List`）在 XCUITest 的拖曳、滑動、邊緣拖曳都不捲動，原因未知，不確定是不是真的 bug（UNVERIFIED，需要在實機試）。`testFreight` 因此在抓不到「跟隨」按鈕時略過「貨運列車」那張截圖。
- 版面問題（截圖照實呈現，沒改）：地圖擴建的星等標籤蓋住鎖頭與價格、吉祥物蓋住價格、教學文字框蓋住「南站」標籤。

### 4.25 營運的普悠瑪改用 TEMU2000 revision-2（決策 484，session_01YGNNuoy1fcM99AJFAieNat，派工單 PUY，2026-10-29）

- **做了的**在[決策 484](decisions/484.md)：營運 `puyuma`／`puyumaFar` 改用 #1456 的 revision-2 近遠景，頭尾車用自己的燈鏡片發光；舊的營運配方刪掉（git 歷史在 main `197f642`）。studies 的 `temu2000-*` 不變。
- **留到發版前：截圖驗收**（作者 2026-10-29：「截圖先暫停拍攝 明天要發前再做而且我自己也可以截圖」）。
  - 看普悠瑪的白天、夜裡（頭燈在前、尾燈在後，燈在燈座上不是浮在車鼻前），以及 500 m 換遠景時有沒有跳。`WebsiteScreenshotTests.testTrainLooks` 或實機都可以。
  - Linux 預覽：`tools/train-models/run.sh OUT --night-lights --ids set-puyuma-head,set-puyuma-tail`，再 `render.mjs OUT --time both`。
- **TestFlight 的幀數**：近景一列從 14,860 三角變 25,040，在預算內。幀數如果變差，照決策 417 加中間版或降面。

### 4.26 高雄紅橘線、台中綠線、鳴日號的車接進營運（決策 483，session_01YGNNumwzbuZGqTqwGDGEzX，派工單 TRN，2026-10-29）

- **做了的**在[決策 483](decisions/483.md)：實景高雄紅橘線改畫 #1454 的西門子三節車，台中綠線改畫 #1437 的兩節車，鳴日號改畫 #1480 的 E200 鳴日號風格，近景與遠景都接；列車展示多兩列。盤點表（最近兩天交付的每一款車、營運用哪個配方、接入要改哪裡、作者接受的紀錄）也在決策 483。
- **沒做、留給別人的**：
  - 普悠瑪紅色塗裝：派工單 PUY 的 #1487（決策 484，§4.25）。
  - 高雄車要不要算不鏽鋼（`Map3DTrainMaterial.stainlessSets`）：作者看過真機再定。
  - 實機：兩款近景的幀數、500 m 換遠景、台中第四版與鳴日號的外觀（作者，TestFlight，UNVERIFIED）。

### 4.27 宣傳影片 30 秒預告與 App Store 預覽（派工單 PV，session_01YGNNuoY1GitTFVsk8mHw6J，2026-10-29）

- **第一版做完了**：`a91453/railway-assets-private` 草稿 PR #30，`promo-material/2026-10-29/trailer/`。橫式預告 1920×1080、App Store 橫式 1920×886、直式 886×1920，各有配樂版與靜音版（共約 181 MB，每支 ≤ 50 MB）。README 寫了來源、官網風格（顏色、Noto Sans TC 全字型、標語、吉祥物、圖示）、卡頓檢查（最大 0.1 秒）、重建指令與五個角度。作者的回饋都改了：「全臺灣都能選」、照 alongthelinegame.com 的風格、用作者實機錄影、配樂改用官網開頭影片的音樂（遊戲自己的音樂，決策 79、219，從第 7 秒起 30 秒）。分支歷史裡有舊版影片，PR 說明請作者 squash 合併。
- **第二版不做了**（遊戲規劃 2026-10-29：作者看了覺得不好看，決定自己用 iPhone 錄）。之後作者錄好，照資產 PR #30 README 的「作者實機錄影後怎麼剪」剪：錄影放 `DEV/`，`tools/fetch_inputs.sh` 抓官網素材、字型與配樂，鏡頭表照 `tools/shots-owner-example.json` 寫，`SHOTS_JSON=… tools/build.py` 一次出預告 16:9、App Store 橫式、直式三種（各有配樂與靜音版），`tools/stutter.py` 檢查停格 ≤ 0.1 秒。
  - 為第二版開的 #1492（`PromoMaterialTests.testTrainShowcaseNewTrains`）與它的錄影 run 40863314600 已用不到：錄影取消了，#1492 由遊戲規劃決定關掉或留著。
- **還要作者確認的**：片尾「10/31 開放測試」；iPad 與淺色版要不要做（作者說過發佈前自己也能截圖）。
- **v4 做完了（2026-10-30）**：railway-assets-private 草稿 PR #36，`promo-material/2026-10-30/`，用作者的實機錄影剪。做法：HDR 轉 SDR（npl=120）、`pre.sh` 統一 60 fps、`build_site.py` 出官網用的版本、`fill_badge.py` 補徽章。配樂取自 ae21d70 的 `Website/site/assets/along-the-line-intro-16x9.mp4`。官網那份已經跟 #118 一起上線。v3 不做了，跟 v4 重工。
  - **沒做的**：App Store 預覽影片、iPad 版、淺色版。要不要做等作者說。

### 4.28 手機橫放時路線清單的控制收成一列（決策 486，session_01YGNNuokuACFK12zJPuZVJc，派工單 LPS，2026-10-29）

- 做了的在 [決策 486](decisions/486.md)：橫放時搜尋（放大鏡按鈕）、篩選（選單）、排序收成一列，跟著清單捲走；路線列放不下時改成多行，不截字。直向與 iPad 不變。
- **留到發版前**：截圖驗收（決策 482 暫緩）。`WebsiteScreenshotTests.testLinesListAndLinePage` 的 `lines-list` 那張就是橫放的清單，看：控制列是一列、往下捲看得到 3 列以上、名稱與「1 列 · 每 60 分」「昨日 … 人次」沒有「…」。前後對照的示意在 `docs/art/lines-panel-486-2026-10-29/overview.png`（示意圖，不是截圖）。
- **等實機看**：iPhone SE 寬的面板控制列是否一列放得下；放大鏡打開搜尋欄時鍵盤是否擋住結果。

### 4.29 3D 跟車 10× 的主執行緒工作（決策 485，session_01YGNNuphxaPGPV7TDzRjjop，派工單 FPS，2026-10-29）

3D 地圖的列車滑行與車身高度改從 tick（主執行緒外）拿，3D 面板多一行 `main X ms · longest Y ms`。留下的：實機（3D、駕駛室、集集線、10×）看 fps 回到 60 沒有；`longest` 若仍常超過 30 ms，照 [決策 485](decisions/485.md) 的下一步用 Instruments 找剩下的。截圖驗收照作者 2026-10-29 的指示延到發版前（看 3D 面板展開的那張）。

### 4.30 淡海、安坑、高雄輕軌的車接進營運（決策 496，派工單 TW，`claude/light-rail-fleets`，#1540，2026-10-30）

- **做了的**在決策 496（`docs/decisions/496.md`，跟 #1540 一起合進來）：
  - 淡海輕軌和安坑輕軌改畫 #1533 的兩節車。
  - 高雄環狀輕軌照現役車輛比例，CAF 和 Citadis 3:5 混跑。
  - `tools/train-models/budgets.json` 多了 `twoCarSets`。
  - App 大 27 MB。
- **還沒做的**：作者說 10/31 之後才合。合之前要看 CI 還綠、沒有跟 main 衝突。合之後在實機看三條輕軌的近景幀數，以及 500 m 換遠景（UNVERIFIED）。

### 4.31 主執行緒卡住的 P2（決策 497，HANG2 session_01YGNNupeXhTZqdvRey1V5Lx，2026-10-30）

- **做了的**在決策 497（`docs/decisions/497.md`）：P2-1 收購報價卡在背景排版（#1545）；P2-2 回開始畫面的存檔與清單移出主執行緒（#1549）；存檔清單的檔頭快取（作者 97.1「存檔越多越卡」，`hang2-p2-2-list`）。
- **還沒做的**（HANG2 壓縮一次後依規則停下，`docs/research/BUGHUNT_HANG_2026-10-30.md` 的順序，一項一個 PR，決策 497 接著寫一節）：
  - ~~P2-3~~：HANG2-P2（session_01YGNNumzMVAszUPgVLu26iP）做了，`hang2-p2-3-command-reads`，決策 497 的 P2-3 一節。
  - ~~P2-4~~：HANG2-P2（session_01YGNNumzMVAszUPgVLu26iP）做了，`hang2-p2-4-night-skip`，決策 497 的 P2-4 一節。
  - ~~P2-5：欠錢轉自由模式就卡住~~：做了 A（確認框說現金會停住，決策 497 P2-5，`hang2-p2-5-free-play-cash`）。B 由 HANG2-P3（session_01YGNNupgWmUe97NHqztN8tb）做了，`hang2-p3-free-cash`，決策 497 的「P2-5 續」：轉自由模式時打開無限資金，舊存檔在開局時也打開，存檔不升版。
  - ~~P2-6~~：HANG2-P2（session_01YGNNumzMVAszUPgVLu26iP）做了，`hang2-p2-6-leave-unsaved`，決策 497 的 P2-6 一節。
  - ~~P2-7~~：HANG2-P2（session_01YGNNumzMVAszUPgVLu26iP）做了提示的部分，`hang2-p2-7-parked-holder`，決策 497 的 P2-7 一節。`.noRoute` 與機廠滿了由 HANG2-P3（session_01YGNNupgWmUe97NHqztN8tb）做了，`hang2-p3-norout`，決策 497 的「P2-7 續」。讓派車員移開停著的車是調度規則，公測後由 BH2 決定。
  - `GameLauncher.init` 仍在主執行緒同步讀一次清單；檔頭快取後只有更新後第一次開 App（快取還沒有）會慢。
  - **nightly 的 NightSkip 不穩**（run 41239862458 的 campaigns-9，`testACommandWhilePausedRunsAheadOffTheMainActor`）：HANG2-P2 查出原因（第二次預先推算可能在測試醒來前就算完），修在 #1632（`hang2-p2-nightskip-flake`，決策 497 的「後來」）。HANG2-P2 壓縮第二次後依規則停下：**#1632 還是 draft**，CI 綠了由遊戲規劃（或另派的人）轉 ready 再合。

### 4.32 短面板先列路線（決策 498 B1，UIB session_01YGNNuqDeWxuzsEPMNtxT4N，`uib-b1-lines-first`，#1560，2026-10-30）

- **做了的**在決策 498 的 B1 一節：
  - 手機橫放（`LinesListControls.inline`）時，路線清單的順序改成控制列、路線、入口、新路線（`LinesListControls.parts`，`LinesPanelNavigationTests`）。
  - 這時不顯示「路線」標題，區塊間距改 compact。
  - UI 測試 `openLinePage` 找不到路線列時先往上拖。
  - ios-build `only_testing` 跑過的都綠（41073016530）：LessonUITests 第 1 課、兩個 LineRoutePreferenceUITests、LineDraftSummaryUITests、HUDAlignment 的路線面板測試。
- **UIB2（session_01YGNNumAzAnMatbWkBqD8yV）接手做完**（2026-10-30）：截圖測試紅是測試自己的拖曳把線的列推到面板導覽列底下，點到導覽列；改成跟 `openLinePage` 一樣在導覽列以下找列（6bff8ef）。截圖驗收 run 41098330367 綠，三張在 `docs/art/ui-audit-2026-10-30/b1-*.png`，驗證寫在決策 498 B1。#1560 轉 ready，沒有剩下的步驟。

### 4.33 BUGHUNT_BUILD 的 P3 還沒修的（派工單 ROADFIX，session_01YGNNupRBmuqtaCPwRs9Hat，2026-10-30）

ROADFIX 修了 [BUGHUNT_BUILD](research/BUGHUNT_BUILD_2026-10-30.md) 的 P2-1（#1544）、P2-2（#1548）、P3-1 與 P3-2（#1554）、P3-6（#1559）、P3-9，查了 P2-3（#1519 已解）與 P3-8（同一局語言不會變，不會發生）。壓縮一次後依規則停下，**還沒修的**，每列的位置、怎麼重現、怎麼修都在那份文件 §4 的表：
- **P3-3**：收購路線時 `junctionStation` 會選到機廠（`RealLineAcquisition.swift`），加 `!$0.isDepot`。
- **P3-4**：三鶯線、淡海綠山線的價目表把機廠站的造價算進「N 列車」那列（合計對）。
- **P3-5**：買了綠山線又刪掉，再買藍海線只賣一段，綠山線也買不回來。
- **P3-7**：離車站遠、地塊還沒讀進來的地方，沿真實的街鋪路照全價收（`RealRoadCells.swift`）。

照文件順序做，每項先寫一個在 main 上會紅的測試。

**ROADFIX-P3（session_01YGNNupKN2twaXYyb91H3Cp，2026-10-31，`roadfix-p3`）修了上面四項**：P3-3、P3-4、P3-7 照建議修；P3-5 只做了刪線時的提醒（買來的線刪掉後不能再買回來）。真的要能買回，得改 GameCore 的 `recordLineAcquisition`（同一條真實路線只能買一次），並處理留下的軌道；目前沒有派。

**BUYBACK（session_01YGNNuqHsWbGjPjrKvrzJsn，2026-10-31，`buyback-real-line`）做了 P3-5 的完整修正**（[決策 528](decisions/528.md)）：刪線時收購紀錄一起拿掉、舊存檔讀檔時丟掉；GameCore 記住每次收購鋪的邊（存檔 79），刪線後留一份，再買時只拆那些邊、任何路線經過的不拆，卡片說要拆幾段。藍海線在刪掉綠山線後可整條買。79 以前存檔裡刪掉的線沒有記軌道，舊軌道擋路時照舊拒絕。實機 UNVERIFIED。BUYBACK-2（session_01YGNNukrq1bjpkYYFjG86yA，2026-11-01）依第二次審查補：自排時刻表的列車用的軌道也不拆、另一條線留下的只拆實際碰到的、切開的邊紀錄跟著走、卡片寫月台數；剩下兩項 P3 在決策 528 的「下一步」。

**接手點（BUYBACK 已壓縮 1 次，做完這個 PR 就停）**：#1636 已按第一次獨立審查（P1 A–D、P2、P3）改完，head 見 PR。還差兩件事：遊戲規劃安排的第二次獨立審查，以及 102.1 發版後合併。第二次審查若要修改，由新的實作 session 接手：從 `buyback-real-line` 繼續，先讀[決策 528](decisions/528.md)。存檔 79 已用掉；golden schema 76 已釋出。

### 4.34 存檔一局一筆（決策 502，SAVE1 session_01YGNNuq65cB35dbSd2SspvL → SAVE2 session_01YGNNuogTGYLuCpzpJbTWYt，PR #1556，2026-10-30）

- **做了的**在決策 502（`docs/decisions/502.md`）與 PR #1556：一局一列、存檔寫回同一列、列內留 3 版、多選與全選刪除（正在玩的不列入）、全有或全無。第一次獨立審查（d0ed375）的必修 1、2、建議 3 由 SAVE1 修（a60d1c2）；第二次獨立審查（a60d1c2）的 4（離開時的進度另放一份，不擠玩家的版本）、5（發現衝突的那台把自己這局搬到新列）、6（只改名不留版本）、7 的前半（卡住的 incoming 不擋存檔）由 SAVE2 修，各有一支在 a60d1c2 上紅的測試。
- 第三次獨立審查（6b9fb12）的 1（自動存檔最後同步）、2（`gameRow` 只換同步前的局）、3（分家失敗收回複本）也修了。複審（d35df1c）的 A（讀檔中算在遊戲中）、B（搬回失敗不刪複本）也修了。
- **還沒做的**：CI 綠、規劃確認後轉 ready，在 #1041 寫「可合併」。規劃決定這個 PR 改到 100.1。截圖驗收照作者 10/29 暫緩，PR 寫了要看的畫面。
- **延後的**（審查列為可等）：`Deleting/` 搬回時原處已有同名檔就一直留著、搬回失敗可能讓刪掉的檔案部分回來；`keepInRow` 判斷同一局時不比新聞紀錄；7 的後半（留了版本後寫入失敗多一份）沒重現。

### 4.35 金額改新台幣 PR-1（決策 499，派工單 NTD1，`ntd1-nt-dollar`，2026-10-30）

第二棒 session_01YGNNuksaQd8BihQwuQ3g6x 壓縮一次後交接（第一棒 session_01YGNNuqEGisgunmnvtfGAEi）。依據 `docs/research/NT_DOLLAR_SWITCH_2026-10-27.md` §5 方案 B（NT$3＝$1）。號碼：存檔 76、決策 499、golden schema 75。

- **做了的**（分支上已推）：
  - `Money.decodingScale`（TaskLocal）；`SavedGame` 讀 75 版以前的存檔金額 ×3、溢位就拒讀；76 版存檔照讀。高鐵票價舊存檔是 NT$10＝$1，讀完再由 `convertHighSpeedFaresToNewTaiwanDollars` 換成 ×10。`SaveSummary` 寫 `newTaiwanDollars: true`，沒有的舊摘要餘額 ×3。
  - GameCore 每個金額常數 ×3（營運、維修、電費、人事、貸款、稅、建造、車種、土地價值、站內商業、子公司、觀光、公車、貨運、擴圖、委託報酬上限）。三個不是機械 ×3 的：高鐵每公里 438 分（照官方票價表，台北—左營 NT$1,489）、預設距離票價改整數新台幣 NT$11/14/17/20/24（`standardBands`）、`standardBands(for:)` 四捨五入到整元。
  - GamePresentation 的開局資金、建造成本、難度、挑戰與成就目標、公司等級門檻 ×3；`HighSpeedFares.centsPerNewTaiwanDollar = 100`。
  - 測試：`TestSupport.newTaiwanDollars(ofSaveText:)`（照 parent/key 表把存檔文字的金額 ×3，高鐵票價 ×10）、`ConstructionCosts.times(_:)`；SavedGameTests、CompanyBuildingsTests（部分）、SightseeingTrainTests 已改；新增 `SaveFixtures/v76-nt-dollar.json`（由 v75 公車存檔以 `NT_DOLLAR_SAVE_NEW=1` 產生）。SaveFixtures 舊檔一個都沒改。
- **第三棒**（session_01YGNNuqShqBANnhS1VWF71K，壓縮一次後交接；分支上已推，**還沒全綠**）：
  - 做了：`FareBandScale` 整數新台幣（項 2）；`WhatsNew.swift` 一則 `2026-10-31-98`、`docs/decisions/499.md`（「golden 的例外」「ReplayFixtures」兩節是空的待補）、`docs/OVERVIEW.md` §2（項 6 大半）；`GoldenScenario.schemaVersion` 75 與 `tools/golden-checks/nt_scale.py`（寫好、**還沒對 fixture 跑**）；單元測試的大半 ×3。
  - 存檔 fixture 的「讀進來＝重新做的」測試：做的那一邊用 `TestSupport.swift` 的 `fixtureEconomy(balance:costs:)`，再包 `NTScale.$factor.withValue(3) { … }`（讀進來的舊存檔金額 ×3，做的那一邊也要 ×3）；存回去的文字比對用 `newTaiwanDollars(ofSaveText:)`。沒包的測試 factor 是 1，不變。
  - `tools/golden-checks/nt_fix_test_literals.py FAILS [--apply]`：讀 `swift test` 的 `XCTAssertEqual failed` 行（`grep -a "error:" log`，不要 `cut`，會切壞 UTF-8），實際＝3×期望的就改那一行的字面值；其餘列在 UNHANDLED。**轉 ready 前刪掉這個檔**。
  - 交接時（`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨）重跑之前失敗的類別，還有 373 個失敗，全是 UNHANDLED（不是單純 ×3）：`TrainTypeCatalogTests` 117（`pinned` 表的價格要 ×3，第 104 行的迴圈）、`RollingStockEconomicsTests` 24、`HighSpeedTests` 23（票價 ×10＝項 5，第 16–27、478–488 行）、`DayPassTests` 19（一日券價格與營收，不是 ×3，要逐個看規則）、`IncomeTaxTests` 16、`CompanyBuildingsTests` 13、`RoadGridTests` 12、`FareAndLoanPreviewTests` 12、`BuildingSessionTests` 12、`CityBusToolTests` 9、`EconomyDisplayTests` 8（`$ 0.45 a kilometre` 之類的字）、`StationCommerceTests`、`MapExpansionTests`、`BuildingSaleTests`、`BuildingSaleSessionTests` 各 6，`LineAcquisitionTests`、`FreightTests`、`FinancialStatementsTests`、`CompanyRankTests`、`CityMapTests`、`BusRouteTests`、`AssetAccountsTests` 各 5，其餘 1–4 個：`TourismTests`、`SubsidiaryTests`、`CompanyBuildingsClearingTests`、`RealCoverageTests`、`DayPassCardTests`、`CityBusTripsTests`、`AreaBuyOutTests`、`ZoningTests`、`TrainTripLogTests`、`TourismHotelTests`、`SchoolsHospitalsNightMarketsTests`、`RunDepotTests`、`ProblemReportFixtureTests`、`DistanceDemandTests`、`CityFootprintsTests`、`BusRouteEditorTests`、`TerrainTests`、`RealisticOperationTests`、`ParksAndTemplesTests`、`DepotTests`、`BuildingMaterialsTests`。很多是世界整個比對（`count differs`），或測試裡從常數算出期望、或土地價值湊整後不是 3 倍。另：`ScheduledOvertakeTrackTests`、`DeadlockTests` 的參考模型（`KernelDifferentialTests.differences`）票價基準要 225；campaign shard 一個都還沒在本機跑；ReplayFixtureTests 9 個要重錄（項 4）。
  - `fix3`（上面的工具）第一輪自動改了 46 個測試檔，**還沒逐行審過**：只改 actual＝3×expected 的字面值，但註解裡的舊金額沒跟著改，下一棒看 `git diff origin/main -- Tests` 時一起改。
- **第四棒**（session_01YGNNuo7Z72i6UaBzbD8hCR，壓縮一次後交接；分支上已推，**還沒全綠**）：
  - 改好 14 個類別（每類一個 commit，訊息寫為什麼是或不是 ×3）：`TrainTypeCatalogTests`、`RollingStockEconomicsTests`、`HighSpeedTests`（含 v69 期望世界＝項 5）、`DayPassTests`、`IncomeTaxTests`、`CompanyBuildingsTests`、`RoadGridTests`、`FareAndLoanPreviewTests`、`BuildingSessionTests`、`CityBusToolTests`、`EconomyDisplayTests`、`StationCommerceTests`、`MapExpansionTests`、`BuildingSaleTests`。
  - `TestSupport.swift`：金額鍵表提到檔案層的 `newTaiwanDollarKeys`；新增 `XCTAssertSameButRounding(loaded, made, cents:)`：兩個世界編成 JSON 逐點比，只有表裡的金額鍵可以差到 `cents` 分，其他（數量、時間、位置、字串）一差就失敗；`capitalDays` 比各欄的合計。舊存檔「讀進來＝重新做的」的測試，差在湊整時用它，**不要**改期望值。
  - 決策 499 新增一節「測試看到的、不是剛好 3 倍的值」：折舊無條件捨去（每件資產最多差 2 分，隔天自己補回）、`capitalDays` 的列數變多（舊的每天 0.67 分折舊捨成 0 不寫列；合計相同，**這是金額湊整造成的非金額改變**）、公司建物維護（進位）與房屋稅（四捨五入）1,229／1,129、站內商店營收捨到整元、建物出售 8/11、每小時營運成本湊整元、`LineAccounts.shareFare` 以整元分攤（v57 兩條線之間挪了 NT$426，合計不變）、所得稅半元、一日券、`standardBands` 的意義（基準 NT$15 的票價帶；遊戲一律經 `standardBands(for:)`）、高鐵。
  - 還在失敗的類別（交接時，`run2.log` 108 個 error 再扣掉最後一個 commit 修的）：`BuildingSaleSessionTests`（×3：土地 7,296、建物 61,440、損失 61,824、餘額 93,817,600，沒改）、`LineAcquisitionTests`（56／87–89 的等級值 60B 對 20B、v66 世界）、`FreightTests`（每噸公里 NT$15 的湊整：3800 對 1300、100 對 0；v38）、`FinancialStatementsTests`（利潤低於 ×3 的免稅額所以「稅前利潤／所得稅」列不見了、結帳年度淨損 15,948 對 5,868，**還有一個 Index out of range 當掉**，在 GamePresentationTests 的 FinancialStatements／Zoning 附近，沒查）、`CompanyRankTests`、`CityMapTests`、`BusRouteTests`、`AssetAccountsTests`、`TourismTests`、`SubsidiaryTests`、`CompanyBuildingsClearingTests`、`RealCoverageTests`、`DayPassCardTests`、`CityBusTripsTests`、`AreaBuyOutTests`、`ZoningTests`、`TrainTripLogTests`、`TourismHotelTests`、`SchoolsHospitalsNightMarketsTests`、`RunDepotTests`、`ProblemReportFixtureTests`、`DistanceDemandTests`、`CityFootprintsTests`、`BusRouteEditorTests`、`TerrainTests`、`RealisticOperationTests`、`ParksAndTemplesTests`、`DepotTests`、`BuildingMaterialsTests`；之後是 kernel 參考模型的票價基準 225（`ScheduledOvertakeTrackTests`、`DeadlockTests`）。
  - 做法：`swift test --skip-build --filter '<類別>' 2>&1 | grep -a "error:"`，看實際與期望；剛好 ×3 的改字面值（`Money(x)` 包成 `ntd`／×3），不是的先找湊整原因寫進決策 499 再改。
- **第五棒**（session_01YGNNuo8yfmRdphYxt63KUr）：
  - 單元測試（`rest` shard 與 GamePresentation 的 150 個失敗）全改好：約 40 類剛好 ×3；不是 ×3 的都查了原因，寫進決策 499「測試看到的、不是剛好 3 倍的值」（每小時湊整、貨運每車湊整、車費一批湊整）。舊存檔「讀進來＝重新做的」一律用 `XCTAssertSameButRounding`，容許值取量到的最大差，非金額欄位 0 差。
  - 修的 bug（不是改期望值）：`CityMap.valueSteps`（每平方公尺元的色階）沒乘 3；`SubsidiaryTests` v46 手寫的帳沒乘 3；問題回報轉換器拿 76 版以前裝置的結束餘額（舊美元）比新台幣。`FinancialStatements` 的 Index out of range 是測試用索引讀列，稅的兩列因免稅額 ×3 消失；測試的票價 ×3 後兩列回來。
  - golden（項 3）：`--rewrite-inputs`、`--apply-log` 一輪就綠；`--verify` 通過：1,138 個剛好 ×3、449 個在各 fixture 寫明的湊整內（腳本的 `ROUNDED`）、高鐵 3 個票價（`EXCEPTIONS`），非金額 0 改。`ReferenceWorldGoldenTests` 綠。`GoldenScenarios/README.md` 加 schema 75 一節。
  - ReplayFixtures（項 4）：照 recipe 重錄會挑到別的 campaign case（產生器變了），所以六個 campaign 檔只重算 checksum，起始世界與指令不動；`long-leg-traffic`、`line-route-preferences` 用自己的測試重錄（起始與指令相同）；問題回報重新轉換。逐檔說明在 `ReplayFixtures/README.md` 最後與決策 499。
  - 合 main（衝突：WhatsNew 改 id `2026-10-31-100`、這一節從 §4.31 改成 §4.32）。
- **第六棒**（session_01YGNNuoGaZmXME6KLT2Sy6T）：full-ci 第一輪（176f40d）7 個 shard 紅（5、6、8、10、11、14、18），都是測試字面值還沒 ×3／×10，或舊存檔對照沒包 `NTScale`；153c018 修好（`XCTAssertSameButRounding` 容許湊整），CI run 41083210792 全綠。參考庫對照表與 golden／Replay 逐項說明寫進 PR；平衡量測寫進決策 499「量到的」：換算本身 HEALTHY，現金滾雪球 CONCERNS 照舊（換算前就是）。刪了 `nt_fix_test_literals.py`，PR 轉 ready；合併由遊戲規劃審查後決定。
- **還沒做的**（下一棒照順序；打勾＝做完）：
  - [x] 1. （第五棒：單元測試做完；campaign shard 交 CI 跑，紅了再修）單元測試 ×3：上面 373 個與 campaign shard（`.github/scripts/swift-shards.sh run <shard>`）。不是 ×3 的逐個查是湊整造成的才改；非金額的值動了就停下來查、告訴遊戲規劃。
  - [x] 2. `FareBandScale.swift` 整數新台幣（第三棒）。
  - [x] 3. golden（第五棒）：`python3 -I tools/golden-checks/nt_scale.py --rewrite-inputs`，`swift test --skip-build --filter GoldenScenarioTests > log`，`--apply-log log`，再跑到綠，`--verify` 列出的例外填進腳本的 `EXCEPTIONS` 與決策 499；`GoldenScenarios/README.md` 加 schema 75 一行。
  - [x] 4. （第五棒，做法見上）重錄 9 個 ReplayFixtures（`REPLAY_RECORD="$PWD/ReplayFixtures" swift test --skip-build --filter ReplayFixtureTests/testRecordingTheFixtures`；問題回報那個用 `ProblemReportFixtureTests/testConvertingAReport`），`ReplayFixtures/README.md` 與 PR 逐檔說明。
  - [x] 5. `HighSpeedTests` 的 v69 期望世界（第四棒）：票價 ×10、其他 ×3。
  - [x] 6. What's New 與決策 499（第五棒補完兩節）。
  - [x] 7. （第六棒）參考庫對照表（`thsr_fare.json` 等）；PR-2 平衡量測照 `.claude/skills/economy-balance/SKILL.md`，「之前」用 `docs/research/BUGHUNT_ECONOMY_SAVES_2026-10-30.md` §6。
  - [x] 8. （第六棒；合併等遊戲規劃審查）綠了刪 `nt_fix_test_literals.py`、轉 ready、#1041 留「可合併」、告訴遊戲規劃。NT$ 前綴（PR-3）不在這張。
  - 第六棒：合 main（#1567 決策 504，凌晨 04:00 還在等的乘客回家）：衝突的 3 個 golden（city-buildings-raise、materials-growth、land-value）照 main 的版本再用 `nt_scale.py` 換算；`economy`、`network-economy` 兩個 replay 只重算 checksum；舊存檔對照測試照 main（只比站、線、時鐘）。
  - 合 main 第二次（#1556 等，99.1 發版後）：衝突的 WhatsNew 把 `2026-10-31-100` 放在 main 的 `2026-10-31-99` 前面；這一節從 §4.32 改成 §4.35。
- **獨立審查後的修正**（遊戲規劃第 36 任派 session_01YGNNuqUDNQvyoQt4V44BrL，2026-10-30）：
  - 高鐵每公里改回參考庫的 3 倍 NT$1.35（審查判 CRITICAL：真實的 NT$4.38 是其他金額的 9.7 倍，改性能就多賺）；官方票價表只給示範地圖與 v69 存檔。`HighSpeedReportTests` 票收 2.997 倍、運量不變。golden `high-speed.json` 第 34、36 步與描述逐值寫在決策 499。
  - `economy`、`network-economy` 兩個 replay 的起始餘額、建造成本、`setFareBaseline`／`setFareRules` 的金額 ×3：對 base `d1df0d7` 逐指令重播，193 個指令的接受或拒絕全部一樣。其他 7 檔 checksum 動是因為預設 `demandBaseline` 75 → 225，README 與決策 499 改正。
  - 決策 499 加「高鐵每公里不照真實票價」（五方）與「已知限制」（審查列為低、不改的五項）。沒有剩下的步驟；合併由遊戲規劃決定。

- **Swift CI 的 selected-4 分片快碰到 20 分鐘上限**（PLATBTN，2026-10-31）：a906ed1 用了 19m14s，0b4d4c3 曾逾時（run 41156023348）。之後可能要在 `.github/scripts/swift-shards.sh` 的 `selected_part` 重新切分。

### 4.36 「分區」自己一顆建設工具（決策 509，派工單 ZONE1，session_01YGNNuo27fcYAGK3J1GdZHo，`zone1-zoning-tool`，2026-10-30）

- **做了的**在決策 509：建設工具「路網、列車、建物、分區、公車」，手機的「完成」改站在「建設」旁邊（決策 382 補記）；站長在成長的車站旁有空地時說「點這裡劃分區」；第一棟蓋在分區上的建物通知一次；成就「都市計畫」（`cityPlanner`，10 分）。
- **等作者的**：App Store Connect 還沒有 `achievement.cityPlanner`。作者要再跑一次 Game Center 的建立步驟（`docs/GAME_CENTER_SETUP.md`；只會新建這一個，其餘照舊），沒建之前遊戲內照常解鎖，只是不回報 Game Center。
- **規劃的合併條件**（小 iPhone 橫拿整排不用捲、每顆觸控 44 pt）：觸控範圍改 44、mini 上工具組玻璃縮成上下 2 pt；截圖用 `website-screenshots.yml` 的 `device` = `iphone-small`、`tests` = `testBuildingToolsColumn`（決策 509 第 2 點）。
- **截圖驗收**（決策 509）：17 Pro 四張、最小可選的 iPhone 17e 兩張（run 41156612390，`docs/art/ui-audit-2026-10-30/zone1-*.png`）。runner 沒有 SE／mini 的模擬器，mini 的窄玻璃只由 Linux 的 `ToolColumnTests` 驗證。
- **還沒驗證**：實機畫面；站長「劃分區」的泡泡沒有截圖；e9178e2 改過的三個 full lane UI 測試（`MapButtonsUITests/testThePhonesBuildingToolsStartAtTheColumnsTop`、`MapButtonsUITests/testThePhonesZoomButtonsStandOnTheColumnsLine`、`ToolbarSmokeTests/testTheToolsColumnsButtonsAreOneSize`）沒有單獨跑過，合併後的 full lane 會跑；紅了照它們的新邊界（觸控框比畫的多上下 2 pt、「完成」在「建設」右邊）修。
- ZONE1 已壓縮 3 次，沒有其他剩下的步驟。

### 4.37 自己拉的軌道加成旁邊車站的月台、缺建材說下一步（決策 519，派工單 FREIGHTPLAT，session_01YGNNum9tS2UtTJPb8hQben，2026-10-31）

- 做了的在 [決策 519](decisions/519.md)：「車站」模式點在某站月台旁 100 m 內的軌道，預設加成那站的月台（尾端外的同一條線照舊是新站）；車站選單照距離排、寫幾公尺；車站卡月台組多一句怎麼讓自己的軌道停這站；缺建材那行接著說下一步（蓋貨運場→別站出建材→設貨運路線＋月台→加開列車）。規則在 `NetworkSession.swift`、`FreightText.swift`，Linux 測試 `PlatformStationJoinTests`、`FreightSessionTests`。
- **等 TestFlight 看**（UNVERIFIED）：作者那局台北旁那條線點下去是不是台北（離月台超過 100 m 就要從選單選，選單台北在前面）。
- **下一步**（沒派）：見決策 519「下一步」。

### 4.38 登山軌道與阿里山林鐵（決策 515，ALISHAN session_01YGNNumbnQtwccikAUfEgt2，`alishan-mountain-grade`，2026-10-30）

- **做了的**在決策 515（`docs/decisions/515.md`）：描 `afr_sched` 時坡度到 70‰（邊的 `mountain`）、林鐵描線半徑 20 m、`ALISHAN` 車種、只有登山車上得去（`trainCannotClimb`）、依坡度限速；存檔版本 77。
- **還沒做的**（決策 515 的「缺口與下一步」，一項一個 PR）：
  - 不在車站的折返（Z 字）：GameCore 只在中途站月台折返（決策 63）；要讓列車在非車站的節點換向，動 `LineJourney` 與交通控制，要升 golden 時照規則逐值說明。
  - ~~`placeTrain`、接續運轉沒有檢查登山；線路改走登山軌道後已在線上的一般車不會被拉下來。~~ ALISHAN2（session_01YGNNupKwkmd2NDUaYLBpRs，`claude/alishan2-climbing-check`，2026-10-31）補了，見決策 515「續」。剩下：不在線上、自己跑時刻表的一般車，服務找路仍可能經過登山軌道（決策 515「續」的缺口 1，和 Z 字折返一起看）。
  - ~~登山車的 3D 模型（DL38＋`alicoach`）。~~ ALISHAN3（session_01YGNNumCWCNTAvXzNR8hewS，`alishan3-dl38`，2026-11-01）做了，作者說醜後由 ALISHAN4（session_01YGNNunuFfySvr1h9RVMKf2）照實車照片重做（修訂 2），見決策 531：`Map3DAlishan` 近景與遠景、`ALISHAN` 列車組、真實林鐵畫成機車加五節。剩下（決策 531 的缺口）：兩款車的長度是估的；上山時機車在下山端推，和 Z 字折返一起看；聯控客車、第七代機車、森里號沒做。
  - 獨立山螺旋 16 m、二萬平到神木 20 m 兩處描線停點（資料畫線的折角）。

### 4.39 停站的車停待避線（決策 518，派工單 PASSLOOP session_01YGNNun8qxU3qeJoE7gLpCk，`passloop-siding-platform`，PR #1601，2026-10-31）

第二次壓縮後停手交接。存檔版本、golden schema、SaveFixtures、ReplayFixtures 都不動。

- **做了的**（分支上已推，PR 是 draft）：`RunSpacing.swift` 的 `freePlatformPath`，停完還要開的車先找正線以外的空月台，再來是自己會準時讓出的月台，最後才照舊；規則、重現數字（舊 123 次 → 0）、參考對照與五方在 `docs/decisions/518.md`。第二個 commit（a4fbed1）修了 CI 抓到的回歸：分在兩段軌道上的月台（`TestLine`）的另一半不算「旁邊」（`across`），`LineAcquisitionTests.testVersionSixtySixKeepsTheLineBought` 因此回綠；`CallingLoopPlatformTests` 第五個測試鎖住它。
- 本機 VERIFIED（a4fbed1）：`-warnings-as-errors` 乾淨；`CallingLoopPlatformTests` 5/5、`LineAcquisitionTests` 10/10、`RealLineAcquisitionTests` 12/12、Golden 24/24、ReplayFixtureTests、SavedGameTests 38/38、LongLegReplayTests 與 spacing、depot 類別。
- **接手（session_01YGNNuowaMN8MBaj6QWbCLn，遊戲規劃第 37 任派，2026-10-31）**：合了 main（7b015d3，只這份檔案衝突，本節由 §4.36 改為 §4.39）。CI run 41193250249 全綠（rest 17.8 分）。rest 逐類和 main 的 run 41187751239 比：共同 595 類測試合計 664.2 秒對 674.6 秒（×1.016），沒有一類慢超過 1 秒；新加的只有 `CallingLoopPlatformTests`。`HighSpeedDemoDayTests`（campaigns-16）160.5 對 162.3 秒。所以之前的逾時是 rest 本來就太滿（main 8c2cc38a 已拆），不是這個 PR。
- 沒有剩下的步驟；合併由遊戲規劃決定（排在 TRACELAG 後）。實機上高鐵示範的停站畫面 UNVERIFIED。

### 4.40 審查剩下的 P3（派工單 REV-P3，session_01YGNNuo4zKUm33FJPAx7M5A，`rev-p3`，2026-10-31）

存檔版本、決策編號、golden schema、GameCore 都不動。代號的原文在 `docs/archive/PR1510_1549_REVIEW_HANDOFF.md`（L1）、`PR1551_1578_REVIEW_HANDOFF.md`（L2）與 #1611 的 `PR1579_1610_REVIEW_HANDOFF.md`（L3）。

- **修了**：
  - L1-2：泡泡的排列與位置（`MapAlertBubbles.arranged`／`placements`）記住上一份，輸入（相機、畫面、泡泡、景點、畫面內車站、地價標籤、語言、工具）沒變就不重算；泡泡圖層、選站標籤、景點標記三處共用。
  - L1-3：按「回到開始畫面」後自動存檔寫完前，畫面上蓋一層收下所有觸控的「儲存中…」（`ContentView` 的 `SavingCover`），沒動 `GameLauncher`。
  - L2-3：站長教學提議的兩顆按鈕在窄卡片上可以換成兩行，不再被切成「跟我做 5 分…」。
  - L2-4：檔頭快取讀回比這版新的存檔版本時不採用，改讀檔，清單照樣標「較新版本」。
  - L2-5：報價算到一半世界變了，若描線還沿著同一條線就重新報價（暫停時提示也會有價格）。
  - L3-5：時刻表格子往前拖過「現在」時，預覽加上「（N 分後）」「（N 小時 M 分後）」。
  - L3-6：運用表的「復原」只在運用表自己做過、還能復原的編輯時能按。
  - L3-7：運用表拖曳放開時，用按下時記住的列車與最後看到的路線，不再照位置重找。
  - L3-8：沒有城市建築的世界，分區用土地格的用途算「第一棟」通知與「都市計畫」成就（`GameWorld.zonedUseBuilt`）。
  - L3-9：泡泡只拿掉「真的畫出來的」景點標記的提醒（蓋到地價的標記不算）。
  - L3-10：分區標記的重建鍵加上城市需求開關。
  - 後來（UIFIX，session_01YGNNunwJCYnpcqxRuffiNA，`uifix-tails`）：
    - L3-4：站長的「跟我做 5 分鐘教學」只在第 1 關真的開了之後才記下回答（`GameLauncher.startLesson` 回傳有沒有開）；自動存檔失敗、留在這局時提議還在。測試 `FirstLineGuideTests.testAFailedAutosaveKeepsTheOffer`。
    - L3-9 的小差：泡泡、景點標記（兩層）、選站標籤算地價標籤時都用 `max(clear.top, topColumnDepth)`（和地圖畫地價的同一個頂端），`MapAlertBubbles`／`MapStationTagView` 多一個 `clearTop`。
  - 再後來（UIFIX，`uifix-l311-wanyi`，2026-11-01）：
    - L3-11（每幀多做的掃描）：先量（Linux debug、`openFrameTimeBench(lines: 20)`，2,251 段軌道）：月台模式的 `networkPlatformBeside` 每次 11–27 ms，地圖的 body 一幀問約 7 次（`networkStationLayout`、排法選單、`fits`），合計 80–220 ms；景點標記判斷「在不在軌道上」（`trackEdgePoint`，24 m）31 個約 155 ms。兩樣都只動 GamePresentation：`networkPlatformBeside` 照 `StationLayoutMemo` 的做法記住（鍵：段、起訖、`commandRevision`）；景點標記改問 `GameSession.sightIsOnTrack(_:within:)`，答案記到觸及距離（縮放）或軌道（指令）變了為止。測試數工作量不數毫秒：`DoubleTrackPlatformTests.testTheTrackBesideIsLookedForOncePerPickAndCommand`、`testTheSightsOnTrackAreLookedForOncePerReachAndCommand`。縮放中每幀觸及距離都變，景點仍會重問（和以前一樣多，不更慢）。
- **沒修、留給之後**：
  - L3-3：歸 ALISHAN2（§23.1 第 9 名）。
- **UNVERIFIED**：L1-2、L1-3、L2-3、L3-6、L3-7、L3-9、L3-10 是 App 的程式，Linux 編不到，靠 PR 的 iOS 建置；實機手感沒看。

### 4.41 車站擴建（決策 506，派工單 STATIONEXP session_01YGNNunzxiVH7aAtqVw8b33，`stationexp-capacity`，2026-10-31）

- **做了的**在決策 506（`docs/decisions/506.md`）：候車容量 4,000 → 8,000 → 16,000，NT$30M／NT$90M，昨天進出 50,000／100,000 人次、而且昨天或今天客滿擋過人才開放；存檔 78。先量了作者 97.1 那局：三鶯線 9 站的「滿」是沒有車載（一天 0 人次），台北、板橋才是站太小。
- **三鶯線一天 0 人次的線索**（DEMOON 派工 SANYING-NOTRAIN、決策 527 在查，原因是機廠出來的回送車經渡線開上反向的 A 線而死結）：作者 97.1 存檔（私庫 `bug-reports/wait-and-stall-97-2026-10-30`）裡，三鶯線 12 列車的 `execution` 全是 `travelling`（停在 stop 1、3 或 4 之前），時刻表最後的發車時間比存檔的 `seconds` 3,221,250 早 47–48 小時；其他 70 列車中位數只早 9 分鐘。列車 1、5、12 的時刻表只剩 2 站（28 → 27 鶯桃福德）。模擬兩天，這 12 列車一次也沒有停站（`StationCapacityReportTests` 的「停在站上」是 –）。看來是卡住，不是車少：先從這幾列車的位置（edge 2388、2390 一帶）與號誌、前車查起。
- **3D 站體隨等級變大**：派工單 STATIONEXP-3D（session_01YGNNuotGg4YicGBR6rf8hX，`stationexp-3d`）做了，見決策 506「續」。
- **開放條件改成最近 7 天有 4 天客滿**：派工單 STATIONEXP-2（session_01YGNNupkGji172gBESV1hnh，`stationexp-busy-days`）做了，見決策 534。
- **還沒做的**在決策 506「下一步」：2D 站名牌旁的等級記號（STATIONEXP-2 留給下一個 PR）；三鶯線一整天 0 人次已由決策 527 修好（main 上作者 97.1 那局三鶯線各站不再客滿，決策 534「量到的」）；

### 4.42 在 3D 直接鋪軌（決策 517 續，派工單 BUILD3D-2，session_01YGNNuoVbtz1ohJBKbA8itq，`build3d-pick`，2026-10-31）

存檔版本、決策編號、golden schema、GameCore 都不動。拆成五個 PR，表在 [決策 517 的「續」](decisions/517.md)。

- **做了的**：PR 1（#1634），`Map3DPick`（射線打地面、螢幕 24 pt 內吸附軌道節點、土地格），只有規則與 Linux 測試。PR 2（`build3d-tap`），3D 裡點車站出 2D 那張名牌（`StationTagCard`），點名牌回平面地圖開詳細資料。
- **BUILD3D-2 停在這裡**（壓縮 1 次，遊戲規劃 39 說 PR 2 做完寫好接手點就停）。PR 2 是 #1637：合之前要看截圖（`website-screenshots.yml` 的 `map3d-station-tag`、`map3d-station-tag-details`）；轉 ready 與否看 #1637 最後的留言。
- **接手的下一步**（每一項各開一個 PR，表與理由在決策 517「續」）：
  - **PR 3 做了**（BUILD3D-3，session_01YGNNuq4tB6xwzS9LqMfuEM，`build3d-pick-3`）：`Map3DScene.drawnGround`、`Map3DPick.isSeen`、`.edge` 目標；列車、建物點了不反應（五方在決策 517「續」的 PR 3）。以下是原本的交接，留作紀錄。
  - ~~PR 3 場景自己的地面、遮擋、邊的吸附~~（不動畫面）。入口：`Map3DPick.ground(of:in:)` 現在只讀 `GameWorld.groundHeight(at:)`，沒讀的區塊回 0 m；實景地圖畫出來的地面在 `Map3DScene` 的 `Builder(…, heights: HeightGrid?)` 裡（`Map3DScene.swift` 約 242–302 行），讓場景留一份 64 m 格的高度給 `Map3DPick.Ground`。被山擋住的節點：`Map3DPick.pick` 找節點前，用 `ground(along:)` 打到的距離比節點的深度，比較近就不吸附。邊的吸附：仿 2D 路網工具的螢幕距離，在 `pick` 加一個 `.edge` 目標。列車、建物點了要不要反應也在這裡定（現在不反應）。
  - **PR 3b 鋪完不等重蓋**：開工先在實機量現在重蓋 3D 場景要幾秒；只重蓋經過的區塊，找 `Map3DSceneCache`（`Map3DPreviewScreen.swift`、`MapView.swift`、`RailwayGameApp.swift` 用它）。
  - **PR 4 3D 裡的平面鋪軌**（改畫面，要截圖）：點的入口已經有了，`Map3DPreviewScreen.swift` 的 `tapped(_:at:)` → `Map3DPick.pick` → `GameSession.tapMap3D`（`Map3DTap.swift`）；路網工具時改交給 `NetworkSession`（加收「節點或地面點」的入口，reach 用 `Map3DTap.reach(at:camera:)`），草稿用 Metal 帶狀網格，✓ ✕ 泡泡放在 `Map3DCamera.screenPoint(of:)`；名牌的跟鏡頭擺法（`Map3DStationTagState.place(seenBy:)`、`Map3DTap.tagOrigin`）可照抄。現在只在選取工具收點（`tapMap3D` 的 guard）。
  - **PR 5**：看實機數據再定建物、分區、公車要不要進 3D。
## 5. 已知、還沒派的待辦

| 事項 | 來源 | 狀態 |
| --- | --- | --- |
| 每天 06:00 第一次算乘客計畫（`passengerRelease` → `makeNetworkPassengerPlan`）的 tick 很慢，約為車站數的三次方：Linux debug 高雄示範 54 站 0.75 s、74 站 2.6 s，其他 tick 約 1 ms；作者回報那局的存檔（78 站，高雄）在 Linux debug 第 2 天、第 3 天 06:00 各約 238 s、236 s，白天 6000× 每個 tick 也要 2–5 s，取樣全在 `PassengerRouteGraph.shortest`，關掉真實轉乘仍超過 600 s，所以倍數不是轉乘、原因未明；計畫的路線記憶（`PassengerRouteMemo`）跟著 `PassengerRouteGraph` 每天換掉。按速度把它拖成時鐘停住的部分已修（決策 143「後來（2026-10-27）」），車站很多的地圖 06:00 仍會停頓（作者那局實機估一分鐘以上）| 玩家回報 91.1「車多 時間軸會卡住不前進」，派工單 AL（session_01YGNNunTGjhacnQNuZoH1FS） | 派工單 AQ（#1385）逐位元相同地加快了約 6 倍，剩下的見下一列；作者的存檔在私庫 branch `bug-reports/clock-stuck-2026-10-27` |
| 每天第一次算乘客計畫仍要幾秒（91.1「車多 時間軸會卡住不前進」的 GameCore 那一半）：作者那局（高雄、78 站、63 列車）06:00 的 tick 在 Linux release 約 5.2 秒（原 32.5 秒），debug 約 55 秒（原 238 秒）；結果逐位元相同 | 派工單 AQ（session_01YGNNun1Kn1yX2orJ1cGjgj，#1385），表現層那一半是 #1376（AL） | **做了一半**：同一起點的搜尋只做一次、接著答下一個終點，禁用邊的搜尋從不禁用的那次分岔（`PassengerRouteSearches`）。一天的計畫仍有約 430 萬次 pop：每個起點約 240 組禁用邊，各自幾乎走完整張圖。下一步（都要逐位元相同，或改規則用新決策）：(1) 圖沒變的部分跨天沿用路線（`PassengerRouteMemo` 每天因 `dailyCapacity`、班距變了就清掉）；(2) 第二層禁用邊也從第一層的搜尋分岔；(3) 標籤的 `order` 陣列改成共用前綴，少配置記憶體；(4) 把計畫移到背景算、算好才換上（表現層）。**(1)、(4) 已由派工單 CF（session_01YGNNuqWY2PSBocJBUDh9eW，`claude/passenger-plan-after-edit`，[決策 470](decisions/470.md)，10/31 後合併）做了**：(1) 依路線圖連通的部分沿用，作者那兩局路線圖都是一整塊，沒變快；(4) 改成 tick 開始前用每個核心先算好這次計畫要重搜的路線再交給 tick（不是算好才換上，決定論不變），92.1 那局載入後、改路線後、隔天 06:00 的 5–17.5 秒在 Linux release 4 核變成 1.4–4.1 秒，整份 command log 重播的結尾世界 SHA-256 和 main 相同。還沒做的寫在決策 470「下一步」：暫停或編輯時就先算、實機時間。**(2)、(3) 已由派工單 PLANDAY 做了**（session_01YGNNuqEZL9bfYRQGsEEG44，`planday-route-search`，[決策 470「續」](decisions/470.md)）：搜尋記下自己的經過，禁兩條邊的搜尋從禁一條邊的搜尋在那條邊的停靠點之前分岔（拿掉檢查點與重播），標籤的順序改成共用前綴的節點；逐位元相同（兩份存檔 2 分鐘與 92 那局兩天的世界 SHA-256 和 main 相同），92 那局載入後第一個 06:00 在 Linux release 單核從約 13 秒變約 7 秒（pop 1,113 萬 → 660 萬），AQ 那局 4.0 → 2.2 秒；標籤上限 40 萬 → 20 萬，記憶體和 main 相當（92 那局 159 → 162 MB，合成 200 站 176 → 148 MB）。剩下最大的是禁兩條邊的搜尋（約 395 萬 pop），下一步是以目的地為界提早停（A*），見決策 470「續」。記憶體（審查 K2-2，派工單 BB，`claude/passenger-route-memory`）：#1385 每個停靠點、每組禁用邊都留一份整個搜尋，合成 200 站尖峰 1,460 MB（舊 137 MB）；改成不禁用搜尋最多 16 份檢查點、禁用搜尋照最近使用最多 512 份且合計 40 萬個標籤，逐位元相同，200 站 194 MB、120 站 170 MB，作者那局 136 MB、4.4 秒不變；200 站的時間從 282 秒變 394 秒（舊 1,061 秒），合成路網量法 `PASSENGER_ROUTE_SYNTHETIC=200 swift test -c release -Xswiftc -enable-testing --filter PassengerRouteMemoryReportTests`。量法：`PASSENGER_ROUTE_SAVE=<存檔> swift test --filter PassengerRouteSaveReportTests`（存檔在私庫 `bug-reports/clock-stuck-2026-10-27`，不進公開 repository） |
| 92.1「CPU 過高」與 6000× 的停頓（實景地圖、81 站、22 線、145 列車、1 條公車；第 10 日 05:59:57）：(1) 每天 06:00 的 tick 在 Linux release 約 14 秒，**每天都重做**；(2) 白天 6000× 每個 tick 平均約 0.24 秒（預算 0.1 秒），290 個 tick 有 215 個在 0.2–1 秒，推進的執行緒一直滿載，遊戲只跑約四成速度；(3) 主執行緒每個遊戲小時（6000× 下不到 1 秒一次）停約 0.4 秒，回報裡的「畫面更新 500 ms」 | 派工單 BK（session_01YGNNun8RfEVUbCYxFcr7kV，`claude/cpu-stall-0600`）；回報、command log 與作者給的存檔在私庫 branch `bug-reports/cpu-stall-0600-92-2026-10-28`（存檔是作者在對話裡直接給的，沒進私庫，要的話請作者再附） | **(1) 修了**：`PassengerRouteMemo` 只記一張圖，夜裡沒有車時算的計畫是空圖，把白天的圖換掉，所以每天 06:00 全部重搜；改成多記前一張圖，逐位元相同（同一個 binary 兩天後的世界 SHA-256 相同），第 11、12 日 06:00 從 14 秒降到 1 秒以下；載入後第一天、改了路線後的那一天仍約 14 秒。和 AQ 那局（78 站、5 線，4.4 秒）比：`shortest` 呼叫數一樣，pop 是 2.6 倍（11.1M 對 4.3M），慢在線多、圖大（44 條路徑），不是車站、列車、公車或道路；拿掉 512 個搜尋的上限、檢查點 16→64 都不變（假說推翻）。重播整份 command log（1,154 個 tick）結尾和裝置相同；修好後仍慢的是載入後第一次、玩家改路線之後那一刻（第 8 日 06:29、18:59、21:59 各 5–14 秒），以及晚上改過路線後的隔天 06:00（晚上與早上的班距不同，圖不同）。重播裡每天 02:30 的「session after」1–2 秒是無頭測試在呼叫端跑夜間快轉，App 是在背景跑（決策 369），不代表實機。剩下的照上一列 (2)–(4)；(4) 由派工單 CF 做成「tick 之前先在背景用每個核心算好路線」，見下一句。**(2) 沒修**：取樣分散在列車模擬（`dropRunsHeldUp`／`routeStretches`／`RailwayNetwork.edgeIndex`、`extendAuthorities` 複製整個 `Train`、`stepDwell` 的上下車），沒有單一熱點，要更多取樣。**(3) 已由 #1415 修**（派工單 BP，[決策 459](decisions/459.md)）：`StationMasterView` 每個遊戲小時在主執行緒重算 `StationMasterAdvice(world:)`（這局 Linux release 350–470 ms）；改成讀新聞已經算好的這一小時的建議（背景 tick 的 `AdviceProbe`），被換掉的世界也改在背景放掉；合成 81 站、144 列車主執行緒每小時 20.8 ms → 0.01 ms（release），實機 UNVERIFIED。量法：`PASSENGER_ROUTE_SAVE=<存檔> PASSENGER_ROUTE_SPEED=fast PASSENGER_ROUTE_UNTIL=174000 swift test -c release -Xswiftc -enable-testing --filter PassengerRouteSaveReportTests`；`COMMAND_LOG_SAVE=<存檔>` 跑 `CommandLogTickReportTests/testWhatTheScreenWorksOutOnTheHour`；`COMMAND_LOG_TICKS=<command-log.json>` 跑 `CommandLogTickReportTests/testTheTicksOfACommandLog`（重播整份紀錄、逐 tick 計時）。實機時間 UNVERIFIED |
| 編輯後的主執行緒停頓：91.1 iPhone 15 Plus 蓋車站、開路線、買列車、改時刻後卡住；92.1 iPad15,7 連接轉乘站時卡住，回報的心跳在 84 站、5 線的局最高 704.9 ms／727.6 ms，幾乎都在「其他」 | 派工單 BP-2，session_01YGNNumsbvdDUbdhhgfgCkW（`claude/edit-stall-465`，#1434，決策 465） | **部分修好，待合併**：量法 `EditStallReportTests`（`EDIT_STALL_SAVE=<存檔>`，release）。站長建議、公司評等、路線提示已改在背景算（每次編輯主執行緒少約 65–120 ms）。剩下的寫在決策 465「下一步」：路線面板開著時每次編輯 70–100 ms（軌道數、路線選擇、人力）、車流開著時 `PassingLoopCards` 的 `trafficOverlay`（沒量到）、連接轉乘／改時段後乘客路線重算讓列車停約 6 秒（GameCore，另派）、其他沒計時的畫面工作。實機改善要 TestFlight 確認 |
| 英文介面在大金額旁加「≈ US$」參考（只顯示，不能輸入）：餘額、建造費這類大的金額旁加一個小小的「≈ US$50」（新台幣 ÷ 30，湊整到整數美元）；玩家輸入與調整的金額（票價、一日券、貸款）照樣只用新台幣，中文介面不加。不做「美元為主、新台幣副選項」：輸入會變成 $0.033 一格、各筆換算後加總對不起來、遊戲是台灣的地圖與真實票價。貨幣跟著地圖所在地（以後台灣以外的地圖用當地貨幣），寫在決策 499 | 作者 2026-10-30（「其他國家也強制用台幣不太好」「可以優先轉美元嗎」），遊戲規劃第 35 任五方決定、作者「好 照你的」 | **在做**：派工單 USD（session_01YGNNuo1q4jxf6TL5HyS4Dz，`usd-reference`，決策 523）；`NT$` 前綴一起改了，繁中萬／億沒做 |
| 繁中介面的大金額改寫成「萬／億」（新台幣 PR-3 的剩餘；`NT$` 前綴已由決策 523 改了） | `docs/research/NT_DOLLAR_SWITCH_2026-10-27.md` 的 PR-3、遊戲規劃第 39 任 2026-10-31 | 已合（#1633）：派工單 WANYI（決策 523「續」）：狀態列、收入浮字、經營面板的餘額、建造費、新局的起始資金。列車與行程的短金額 `TrainRoster.shortMoney` 由 UIFIX（`uifix-l311-wanyi`，決策 523「續二」）改成萬／億（不留空格、負號在前） |
| 97.1 實景地圖（74 站、13 線、83 列車）6000× 主執行緒停 1–3.6 秒，回報幾乎全在「其他」 | 作者 2026-10-30，派工單 STALL97（session_01YGNNun14Q65qQzFK9Ggdcd，`stall97-6000x`）；存檔與回報在私庫 branch `bug-reports/wait-and-stall-97-2026-10-30` | **原因未找到，量法與紀錄做好**（[決策 505](decisions/505.md)）：`STALL_SAVE=<存檔>` 跑 `MainThreadStallReportTests`（release）在 Linux 上照遊戲迴圈跑 60 個遊戲小時，GamePresentation 的主執行緒工作最長 80 ms，畫面的 key 比較與小計算最長 1.3 ms，所以停頓在 App 層（SwiftUI、主執行緒 Task 或 MapKit，Linux 量不到，UNVERIFIED）。2D 節拍的最長停頓改列出「畫面更新」、各畫面與遊戲時刻。**下一步**：99.1 請作者在同一局 6000× 再送問題回報，照決策 505「下一步」判斷是哪個畫面再修 |
| ~~高鐵 demo 第一次開地圖時畫面卡住：CI 的 iPhone 模擬器上主執行緒 28–58 秒沒有回應（app trace 最長 57540 ms）~~ | #1257（session_01ATrwF1t4xfwDoTrLvMvRAY，2026-10-25） | **修了**（`claude/hsr-first-map-stall`，session_01NmGg4SVeqcXXqTpHPxnVP6）：不在畫地圖，在 `begin` 的 `readLandRoundStations`：示範建好時沒拿底圖，它的 2,489 個街區的道路（決策 400 的續，00ecb5f）留到 `begin` 在主執行緒讀，Linux debug 11.5 s。改成和建世界一起在背景讀（`GameLauncher.readingRoads`，高鐵與宜蘭線示範），主執行緒上剩 5 ms；開局在主執行緒上的其他工作合計約 0.25 s（`HSR_FIRST_MAP_REPORT=1` 跑 `HighSpeedFirstMapReportTests`）。回歸：`HighSpeedDemoTests.testTheLauncherBuildsAndOpensIt` 檢查遊戲開始時道路已讀。剩下：資料晚到時 `install` 在主執行緒對開著的遊戲 `readLandRoundStations`（只有道路還沒讀的舊存檔會多讀）→ 改到背景讀（session_01YTRwthhkJVsLn8wkaagJ8p，決策 400「續篇：讀檔的兩件小修」）；`begin` 讀檔也搬到背景（決策 419） |
| 輕軌收購（決策 400 10j-2）剩下的：(1) 安坑輕軌：第二條正線在急彎上離第一條不到 4 m（`trackTooClose`）；`RealLineAcquisition.swift` 裡第二條的偏移改成 8 m 時鋪得下，但從 06:12 起列車停住（307 班 179 班沒發），還沒查是靠左（決策 202）選錯路還是待避線方向保護；查好後把 `ntalrt:K` 加回 `extract_metro_runs.py` 的 `LINES`、重跑、在測試加回。(2) 淡海綠山線：**派工單 DHG 做了**（[決策 489](decisions/489.md)，`claude/danhai-green-depot`）：收購時一起蓋崁頂後面真實的淡海機廠，9 組晚上回廠，單買、先綠山再藍海都開放（`DanhaiDepotTests`，兩天一般與寫實規則全部發出、死結 0）。#1510 已合併。**先藍海線、再綠山線**：派工單 BLG 做了（[決策 493](decisions/493.md)，`claude/danhai-blue-then-green`）：綠山線在藍海線之後照整條（紅樹林起）連同淡海機廠收購，紅樹林到濱海沙崙鋪在藍海線旁 30 m，共用的 9 站月台併進藍海線的站；兩天一般與寫實規則見決策 493 的表。兩條線真的共用軌道（真實的樣子）還沒做，要另一套鋪法。 (3) 轉乘站併站（450 m 內同名車站）程式在、沒有測試。(4) $800 萬的價格目標：10j-3 定了輕軌每位旅客 $70，淡水開局的藍海線 $796 萬 | session_011Aw4FB9UV6Nx5P2kPZUH2E（10j-2，壓縮兩次後停下） | 沒派；數字與原因在 [決策 400](decisions/400.md)「量到的」10j-2 |
| 捷運收購（決策 400 10j-3）剩下的：(1) 三鶯線（`sanying:LB`）：**派工單 BY 做了**（`claude/sanying-line`，10/31 後合）：停住的原因是工具把 4 組車晚上送到中間站時停在反方向的正線上，擋住當晚最後幾班；工具改了（`extract_branch_runs.facing`），開放收購，兩天的真實班次一般、寫實規則都全部發出。還剩**號誌的效能**：白天一個遊戲小時約 10 s（debug，藍海線 0.6 s），51 小時一般規則 365 s、寫實 229–243 s，CI 因此把它拆成兩個測試類別（`SanyingLineSimpleDayTests`、`SanyingLineRealisticDayTests`）。gdb 取樣：約四成在被擋住的車估等多久（`secondsUntilARouteFrees` → `reservingDeparture` → `alternativeRoute` → `networkPath`／`TrainRoute.shortest`），其餘在 `trafficPlan`、`planTrafficOvertakes`、`moveTrains`；把 `runTrip` 記住沒有用（量過）。2026-10-29 派工單 SY（作者 94 實機「收購完會卡住」）：地圖的卡車泡泡改在背景 tick 算（`SanyingLineFreezeTests`），主執行緒不再每個 tick 搜死結；早上 6 點起的死結：國華、長壽山、永吉公園晚上各停 1 列在正線上（那幾站沒有側線），直通車開到就被擋，平日 06:32–06:54 的回送開走才解開（週末沒有這幾班回送）。作者要真實的機廠：[決策 479](decisions/479.md)（`claude/sanying-depot`）收購時一起蓋三峽機廠，這 4 列晚上回廠，死結沒了（`SanyingDepotTests`；實機 UNVERIFIED）。要做是 GameCore、要逐位元不變的另一件，沒派。(2) 其他捷運線的終點站要 6–25 條過夜軌道（數字在 `tools/real-timetables/README.md`），要 GameCore 的停車場或回送機廠，和淡海綠山線同一件；中和新蘆線的共用主線也在它之後。(3) 臺中、高雄的實景開局沒有一條線在 $800 萬以內（地圖框裡沒有可收購的線；臺北、新北、桃園有） | session_012tPPoF95rAooSb1w8yot6q（10j-3） | 沒派；數字與原因在 [決策 400](decisions/400.md)「量到的」10j-3 |
| 路網分析（決策 416）剩下的：GameCore 只記每站開局以來的滿站走掉、等到停駛走掉與被滿車留下，沒有每天、也沒有分到站對，所以「流失」只列汽機車與票價；沒有路線連的站對沒有 GameCore 的需求數字，用分配規則估；沒有車站的聚落沒列進來；等不到車固定 30 分；沒有 UI 測試；路線面板標題列在手機橫放時擠不擠要實機看 | session_01695GDiVgssy47EmyircfE4（§22.2 第 22 名） | 沒派；做法在 [決策 416](decisions/416.md)「下一步」 |
| 分享路網（決策 409）剩下的：車站設計的分享（等 10d）、只看時在遊戲裡直接改成開新局、檔案 App 裡顯示明信片縮圖（Quick Look 縮圖延伸）；LINE、AirDrop、檔案 App 點了用遊戲開與分享面板的預覽都是 UNVERIFIED，要 TestFlight 實機 | session_01RarzebNWdkEundHGJDzTBf（10k） | 沒派；做法在 [決策 409](decisions/409.md)「下一步」與「沒有驗證的」 |
| 實景地圖的道路格子（決策 400，10i-1 剩下的）：GameCore 的 `RoadGrid` 與 `setRoads(_:in:)` 已在，空白地圖會長路、能鋪站前路；實景地圖還沒從底圖的 `transportation` 層算出道路格子，所以實景開局不開道路 | session_018gwb44aL5MFmY8312pE3hD（10i-1） | 沒派；做法在 [決策 400](decisions/400.md)「量到的」10i-1 的最後一點 |
| 實景地圖 3D 的真實列車軌道（決策 339，`Map3DRealTrains.swift`）每條線只畫一條、高度沒照真實（捷運該在地下或高架）、在玩家軌道旁與接縫處斷開（作者指的是這層）；另外示範與收購鋪的軌道：真實雙線鋪成單線（縱貫線臺北–板橋、崎頂–竹南、新左營–高雄，海線竹南–談文，捷運環狀線，高捷紅線美麗島–左營）、文湖線與環狀輕軌因最小半徑 40 m 斷軌、一段停下就跳過到下一站的軌道。地圖底下畫的真實鐵路本身是對的 | 作者 2026-10-24「有些也沒照真實路線有些還是單線 而且有斷軌」「要不要改成真實複線或單線 還有高度也是」「不是示範鋪的是實景地圖裡面鋪的」；session_019YxcVGrDSUjGBqxpWQ5Mnc 量了示範那層、壓縮後依派工不修 | 實景地圖 3D 那層：單複線、高度、玩家軌道旁由[決策 402](decisions/402.md) 做了，山裡的隧道斷一截與列車跳軌由[決策 406](decisions/406.md) 修了（剩下的在 406「下一步」：洞門、照派軌走）。示範鋪軌那層（決策 401 (b) 表）由 [決策 401「續」](decisions/401.md) 修了（單複線、文湖線與環狀輕軌斷軌、跳站）；剩下的：板橋一帶高鐵台北–板橋與縱貫線臺北–萬華被同高度交叉擋下的缺口（main 原本就有），收購那層沒量，都寫在 401「續」的「沒修的」 |
| iCloud 存檔（決策 397）：程式已在 App 裡（`SaveSync`、`ICloudSaveFolder`）。iCloud 的 entitlement 與官網隱私權政策在決策 397 續（`claude/icloud-entitlement-397`，參考庫 PR #68）；之後兩台實機驗證（UNVERIFIED）。挑戰紀錄與成就的同步沒有做 | 作者 2026-10-24「那CloudKit可以當雲端存檔保存這樣就好了嗎」，session_01MsxSwi6ituX5dsw6ZQNmEx | 等 entitlement PR；之後的步驟在 [決策 397](decisions/397.md)「下一步」 |
| 隧道裡的架空線（決策 395）只在 Linux 的幾何測試看過，實機上沒看過；台鐵用的是有主吊線的柔性吊架（監察院糾正案的台北—松山隧道斷線紀錄），高鐵隧道用哪一種沒查到，是假設 | 作者 2026-10-24「隧道裡面要有架空架嗎」，session_01AdAQTbXs639m7Yd3ZoxLE7 | 下一次 TestFlight 照 [決策 395](decisions/395.md)「下一步」看；查到高鐵隧道的型式再改 |
| 遊戲跑著時，以 `worldRevision` 記住的預覽每個 tick 都重算：複線升級（選取工具，不暫停）在 80.1 讓 iPad 卡死，`claude/double-track-upgrade-hang` 改成以 `commandRevision` 記。同樣以 `worldRevision` 記的還有建造工具的 `NetworkSession` 草稿、`PassingLoop`、`DepotYard`、`LevelPlatformTrack`：建造工具會自動暫停，但玩家在草稿開著時按播放就會一樣每個 tick 重算。另外第一次算長的「到兩端道岔」預覽在 Linux debug 要 0.4–1 秒（一次的停頓），實機沒量 | PLAYER_FEEDBACK 80.1 #1 | **做了**（#1129，`claude/preview-command-revision`，session_01HgUU1aeQ39gLnPvqAiWBF2）：四個預覽改以 `commandRevision` 記，現金跨過價格時重算一次（✓ 才打得開），✓ 照舊在當下的世界重新規劃（`BuildPreviewTickTests`）。剩下：第一次算長的「到兩端道岔」預覽的一次停頓，實機沒量 |
| 高鐵示範快轉只有約八成速度（一個 tick 123 ms，間隔 100 ms） | 決策 248、#709 | 排在核心玩法之後 |
| 高鐵的長進路／閉塞區間死結、台南—左營交會 | #669，機廠 session session_01YNBmv76sfS8gJUnyRKEqHV（不再接新工作） | 沒有人接。機廠出庫已由 #678 處理；B 方案（`claude/hsr-depot-exit-priority`）量測失敗、放棄，紀錄在 #685。決策 255（單線提早折返）**沒有**解這一項：高鐵是單向的班次（決策 133），時刻表不會回到同一站，不會用到折返 |
| 決策 306 之後，號誌開著的高鐵示範還能做的五項（作者 2026-10-21 問「是不是已經優化到極限了」；車速這條路已到頂，最快就是車的性能與彎道限速，剩下的晚點與取消多半不是速度造成的）。照這個順序：(1) **沒有閉塞時的兩個互等與追回時間**（決策 306「下一步」第 1 點：台南的進路宣告、左營咽喉與要入庫的閒置車；沒有閉塞時一天還取消 85 班，效果最大），約 1 天，改 `RouteReservation.swift`、`RunDepot.swift`、死結判斷，可能動 replay；(2) **平地五站停晚 93 分的那一班**（決策 306「下一步」第 2 點），1–2 小時，查完多半併進別項；(3) **五站停跟在慢車後面**：五站停的表定本來就快，追不回來，晚點中位數停在 9 分，要從待避的排法下手（決策 294），約 1 天，結果不確定；(4) **南港咽喉**（照地形剩的南港 08:30 取消，決策 302「下一步」第 2 點），半天到 1 天，和下一行的六家基地都改示範的機廠配置，併成一件做；(5) **晚點時壓縮停站**（真實鐵路的做法，沒試過、沒量），約半天。五項都改同一塊 GameCore、量同一個示範，平行做要互相重量，所以一個 session 照順序做，全部約 3–4 天 | 作者 2026-10-21（session_011GLH8sEjxxMsy2VEXa8szu 估計與排序） | **第 1 項做完**：決策 308（session_0125dMtwyMdz7mzoBCRNa1pn），剩下的寫在它的「下一步」。其餘排在它之後，也排在 77.1（自動派車，改同一塊派車，影響每個初學者）之後；示範預設是號誌關，這五項只改善號誌開著的組合。順序由遊戲規劃排 |
| 高鐵示範北端的機廠改成真實的配置：南港站東的 2 條盡頭線（約 8 組）加新竹的六家基地（OSM：新竹站東約 500 m、下行線同側，8 股、每股約 420 m，`tools/hsr-depots/hsr_depots.json`），取代決策 221 的「南港機廠 11 股」（台灣高鐵北端沒有機廠，決策 280） | 作者 2026-10-18（session_01KeynzCwtDyLHTUYBfKxy1c，問「建六家機廠有幫助嗎」後說「寫進HANDOFF排著」） | **排在決策 302（`claude/hsr-depot-churn`）合併之後**：原本等的南港咽喉已由決策 283 修好、真實地形已打開，決策 297 後照地形一天只取消 4 班；決策 302 正在改機廠進出的判斷，六家也動機廠進出，同時做會互相干擾量測，所以等它合併、重量一天再做。它解不了南港咽喉的卡死（白天、終點站的調度）和左營夜裡的排隊（南端），只讓北端更真實；代價是南港與新竹之間每天早晚多約 70 km 的空車，可能有新的互等，要重量一天。動 `HighSpeedDemo.swift` 的機廠配置與決策 221，GameCore 不動 |
| §15.3 的內容：觀光列車（第一步在決策 286，後續見 §7.2）、支線劇本、掛機模式、「這版新增」卡片、台灣節慶、各站到站鈴、3D 拉近傾斜與駕駛艙視角、花錢的地方＋新台幣＋分時電價＋車站容量、股票 | NEXT_PRIORITIES §15 | 排在核心玩法之後；各站到站鈴等測試者回報 |
| 台灣以外的實景地圖沒有人口、地點、分區、水域、陡坡、建物覆蓋率與真實鐵路：新車站一律 10,000 人次、住宅區（決策 262 加了 127 個城市，`Ci/` 的 53 座本來就是這樣）。要補就照 `tools/real-world-population/README.md` 的工具，換成各國的 WorldPop 與 OSM 整包檔，一個國家一份資料 | 決策 262 | 沒有人接 |
| 3D：擋住列車的建物變透明、深度閃爍、道具穿模、真的台灣車與站房 | F 台灣版＋「定案前要補」 | 3D 生活感那條線之後 |
| 參考庫 2026-10-18 新增的兩個資料夾，不是新工作，是讓排好的項目省工的素材（照 NEXT_PRIORITIES §16 的順序用，不插隊）。`Railway/taiwan-rail-reference-clean/` 是 `site_archive_clean` 的新版：(1) 高鐵票價表 `source/data/thsr_fare.json`（TDX ODFare，全部站對、票種與車廂；補上 ARCHITECTURE「沒有真實高鐵的票價表」的缺口），給高鐵示範（§16 第 4 項）或「新台幣」那輪（§16 第 5.7 項）；(2) 台鐵時刻表 10-16 版、`thsr_schedule_dense.json`、國土測繪中心的橋隧改判 `rail_structures_official.json` 與較新的 `rail-3d/physical/`（`network.json`、`level-profiles.json` 都和 `site_archive_clean` 不同），給決策 279 的後續與重跑 `tools/real-railways/`、`tools/real-timetables/`；(3) 62 款車型、附出處的編組 `rail-3d/integration/formations.js`、12 個站區模型 `rail-3d/assets/stations/`，給上一行「真的台灣車與站房」。`Railway/world-rail-reference-clean/`：12 個海外城市的路網與班表、120 款車型，可補上上面「台灣以外的實景地圖沒有真實鐵路」那一行；單城班表 26–55 MB，要像平溪線一樣只抽需要的部分，署名照各檔 `source_notes`；`nyc_schedule_dense.lite.json` 的 `source_notes` 寫成 Entur（挪威），用之前先核對 | 參考庫 `058f833`；session_01B2b7QLdd5dVnXNZLmQbcQX 盤點 | (1) 的高鐵票價表已用在高鐵示範：決策 325（session_01YEY1CSzE5zYPKVPqDAMBAy，`claude/hsr-real-fares`，存檔 69），剩下的寫在決策 325「之後」（商務車廂、新台幣那輪換掉 NT$10＝$1）。其他沒有人接；各自跟著它服務的項目做 |
| 從空地畫的複線兩條之間沒有渡線：玩家在兩站點了不同的一條就不相連（70.1 的回報）。決策 284 只讓開新路線的字說出原因與接法；根本的做法是畫複線時兩端自動加渡線，或「月台」工具在複線上一次設兩條的月台，兩個都改建造規則，預覽寫在決策 284「沒選的」 | 決策 284、285、PLAYER_FEEDBACK 70.1 | **做了**（`claude/double-track-platforms`，決策 285）：選了第二種。「月台」工具點在複線的一條上、而旁邊那條和它不相連時，同一個動作兩條都設月台（同一站），兩站點了不同的一條也相連。兩條已經相連（有渡線）時照舊只設點的那條。剩下：從空地畫複線時兩端自動加渡線（第一種）沒有做，預覽在決策 285「沒選的」；待實機確認 |
| 73.1 的「終點無法折返」只從截圖推斷是列車比月台長（決策 284 改了字）。玩家的實際配置沒有存檔：下一版請測試者用「回報問題」附存檔，確認不是別的原因（例如終點的盡頭線放不下整列車） | 決策 284、PLAYER_FEEDBACK 73.1 | 待實機確認 |
| 提早折返（決策 255）後，列車卡的「本趟」仍從沒去的那一站算（74.1 截圖的「扒子岡 13:52 發」）。決策 288 已讓它照一般停站開走、時刻往前移，但卡片與跟隨列還沒說「在龜山提早折返」（決策 255 的「下一步」）。74.1 的玩家配置沒有存檔，下一版請測試者確認不再卡在那一站 | 決策 255、288，PLAYER_FEEDBACK 74.1 | **做了**（`claude/short-turn-card`，決策 255 的第二則「後來」）：卡片與跟隨列的本趟從折返站算，多一行「在龜山提早折返」。剩下：重複的時刻表認不出折返；74.1 待實機確認 |
| NEXT_PRIORITIES §17 的乙線「現實路網」：~~真實車站當建議站點~~（決策 295，`claude/real-station-suggestions`）→ ~~R1 轉乘站~~（決策 298，`claude/r1-transfer-stations`，存檔 64）→ ~~R2 電腦的車照已打包的時刻表在 2D 地圖上跑（只畫）~~（決策 304，`claude/r2-real-trains`）。甲線（M0 之後的 M1–M3、確認路線卡、空窗快轉）由做 M0 的 session 接著做 | 75.1 玩家建議（PLAYER_FEEDBACK 75.1 #1）、競品研究 #832；排序 2026-10-20 | 建議站點：決策 295 已合併（圖釘的大小與好不好點待實機）。R1：決策 298 做完（session_01TePLuBqSCAQxMhhJBTJ8Cq）；待實機：車站卡那一行、新遊戲的開關；決策 298「下一步」列了 R2 要接的地方。R2：決策 304 做完（session_0193ujbBhjzFo37QWceGdzcX）：捷運與輕軌逐班、高鐵一天的班次、台鐵照班距；車站卡列下一班；設定「真實列車」可關。待實機：膠囊的大小與淡度（`RealTrainTraffic.look`）、畫 157 列的時間、iPad 整張地圖。加減速：決策 304 的「後來」（2026-10-22，`claude/real-train-accel`）站間照網站的 `buildProfile` 加速出站、減速進站，高鐵有惰行，解不出時用 Mini Tokyo 3D 的退路；待實機看樣子。剩下的在決策 304「下一步」：3D 的真實列車、台鐵逐班時刻表（要打包參考庫的 2026-10-16 時刻表）、路線名與站名的英文；R3 照 §19 的順序 |
| 乙線的資料與時段研究（`docs/research/RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md`）：(1) 台中捷運（data.gov.tw 175718，2025 年只有 7 個月、只有出站）與桃園機捷（164957，雲端容器連不上，要作者在台灣下載 2025 年 12 個 CSV）有各站運量，淡海、安坑、三鶯、高雄輕軌、林鐵沒有；(2) 遊戲的一天時段已經接近北捷，差的是潮汐（住宅站早上進站真實 40–46%、遊戲最多 28%），建議三步：量尺報告 → 潮汐開關（GameCore，升一次存檔、量平衡，排在 #851 之後）→ 實景地圖用內政部電信信令的日夜人口（取代 geo-scene 第 4 項）；(3) 北捷路線色維持 App 的值 | 作者問「台中桃園 輕軌 三鶯有網址嗎」「台北捷運有分時段…日間夜間模型」；遊戲規劃派工 2026-10-20 | 研究做完。潮汐第 1 步（量尺）做了（`claude/tide-measure`，研究 §2.5），1.5 步（選資料：電信信令最好，OSM 只當細部）也做了（`claude/tide-data-choice`，研究 §2.6）；第 2 步也做了（決策 319，存檔 67），第 3 步沒有人接，見 §7.2「潮汐第 2 步」那一列。**運量（session_01RdsWZvY7RjZeZbiNvn8XP4，`claude/ridership-tmrt-tymc`，PR #869）**：台中捷運（2025 年 7 個月出站）、新北捷運的淡海與安坑輕軌、環狀線（新北捷運網站的每日各站進出站，2025-10 到 2026-09；`trtc_ridership.json` 的環狀線只有台北捷運閘門記到的部分，改用新北的）都已補。桃園機捷（桃捷公司網站每月「各站旅運量統計」PDF，2025 年 12 個月，（進＋出）÷ 2；開放資料 164957 雲端連不上）也已補。**還剩**：(a) 三鶯線現在是通車後 2026-07 到 09 的 3 個月（`--partial`，作者 2026-10-20 要的），2027-07 以後用 `build_ntmc_ridership.py --first 2026-07` 換成一整年；(b) 台中 2027 年初看 2026 是否 12 個月齊了再換；(c) 高雄環狀輕軌沒有各站運量（高雄捷運公司每月的 PDF 只有全線每天的筆數），它的站已改照輕軌的 1 點；高雄捷運公司若哪天公布分站的，再接進 `RealRidership`；(d) 林鐵沒有各站運量：data.gov.tw 林業及自然保育署阿里山林業鐵路及文化資產管理處的 13 個資料集（車站、路線、時刻表、票價等，2026-10-20 查）都沒有運量，afrch.forest.gov.tw 也沒有統計頁；要的話只能由作者照政府資訊公開法向該處申請，拿到前林鐵的站照後備 |
| 真實運量（決策 298：台鐵、高鐵、台北捷運、高雄捷運，#869 加的台中捷運、桃園機捷、新北捷運的淡海與安坑輕軌、環狀線、三鶯線）每年重跑：每年第一季前一年整年的資料出來後，照 `tools/real-ridership/README.md` 重跑（到時平鎮會有數字，廣慈/奉天宮現在是 2026-09 一個月（`--later`）；它 2026-08-30 才通車，重跑 2026 年時除以 365 天會只剩約三分之一，要先讓工具對年中通車的站只除以營運的天數，或繼續用 `--later` 的整月；台中看 2026 年是否 12 個月齊了；新北捷運用最近 12 個 `.ods` 月份，三鶯線現在只有 3 個月，2027-07 起有一年，到時換掉）。**高雄捷運要作者在台灣下載**：data.kcg.gov.tw 擋國外連線，雲端容器抓不到，請作者從 data.gov.tw [159641](https://data.gov.tw/dataset/159641)（入站）與 [159640](https://data.gov.tw/dataset/159640)（出站）下載兩個 CSV、附在對話裡，工具記下 SHA-256 與下載日期，原始 CSV 不進 repository | 決策 298 的「下一步」2、`tools/real-ridership/README.md` | 下一次是 2027 年第一季；台鐵、高鐵、台北捷運、台中捷運、桃園機捷（公司網站的 PDF）、新北捷運雲端自己抓得到 |
| 參考庫 2026-10-20 新增的 `Railway/geo-scene-reference-clean/`（台灣地理資料包）：遊戲的鐵路、車站、地形、居民人口比它準，不換。要融合的：(1) 新車站命名的地名加內政部的聚落（800 m 內有名字的居民 89.0% → 95.6%）、旗津區用官方外框補（`tools/place-names/`）；(2) 3D 的廟放到真實的廟址（`religion/temples.pmtiles`，19,201 座）；(3) 白天人口的比例，和 R1 一起量（先查出處，原包寫「模擬」）；(4) 21 個 `approx` 景點逐個核對、節慶與景點新種類用它的百大宗教活動與古蹟（§16 第 5.5 項）；(5) R2 移植它的 `RailEngine`／`BusEngine`。Ookla 不能商用，不用。之後不只鐵路的「線」（公車接駁 → 離島渡輪 → 航空）的參考也在研究 §6，排在 §17 甲、乙兩線之後 | `docs/research/GEO_SCENE_REFERENCE_2026-10-20.md`、NEXT_PRIORITIES §18；參考庫 `b3af6d8` | (1) 修正 lane、(2) 3D 那條線，都沒有人接；(3)–(5) 跟著它服務的項目做 |
| 建造時的潛力圖（決策 311）只在 Linux 量過 debug 的時間（台北一個畫面第一次約 0.1–0.16 秒），App 沒在實機看過：iPhone 直拿時圖例（潛力／涵蓋、時段兩列切換）高不高、第一次畫的停頓、台北市中心是否整片同一色 | 決策 311 的「下一步」，session_01XcsvN9dp6TVNhLU2TY4sJD | 下一次 TestFlight 時看；要改門檻或把計算移到背景，是 GamePresentation／App 的小 PR |
| 收購真實支線的後續（決策 315 第 2 步之後）：(1) 六家線、沙崙線（雙線電化，要兩條平行的正線與兩端的渡線，班次已能擷取）；(2) `dr1000` 車種（`PERF_DR1000`，動 `TrainType`、車種表與 3D 車）；(3) 收購時替玩家買下線經過的地塊（地圖擴張開著時，現在是拒絕並寫出擋住的圖塊）；(4) 第二批開放輕軌：淡海、安坑、高雄環狀（各站時刻排成 `LineRun`、輕軌車種；重運量捷運不開放） | 決策 315 的「後來」「之後」「量到的」 | 第 2 步（`claude/acquire-real-branch`，存檔 66）做完四條線。**(1) 做了**（`claude/acquire-double-track`，決策 323，存檔不動；雙線但沒有渡線，竹中與內灣線共用的連接沒試過）；(1) 還剩：兩線的年報（`AcquisitionReportTests`）、渡線（要另一套鋪法）。竹中與內灣線一起收購：[決策 462](decisions/462.md) 修好（兩種順序與舊存檔都能買，竹中六家線月台架高、內灣線在地面，同一個站轉乘，軌道不相連所以不互等）。(2)–(4) 沒有人接，順序由遊戲規劃排 |
| ~~收購的線上，低矮的長橋跨寬河床（內灣線竹東—橫山 499 m）被做成路堤~~，排除車站後的橋與高架比例只有 60%（6/10，`testALineBoughtFollowsTheRealStructures`） | 決策 315 的「量到的」、遊戲規劃 2026-10-21 | 做完（決策 279「後來：低矮的長橋」，`claude/low-bridges`，session_01PK2gs3bPYXPFbbJkwsDuUP）：原因不是 10 m 太高，是橋和引道的地面範圍一起被放掉；改成衝突時先放掉地面的，10／10，示範都不退。沒有剩下的 |
| 收購應該買到看得見的東西：第 1 天的人次收購與自己蓋一樣（兩邊都從轉乘點拿到常客，決策 298），價格裡的「沿線的常客」在遊戲裡沒有對應。可能的做法：買下既有的班次與車站運量、或免施工天數，之後再設計 | 決策 315 的「量到的」（CONCERNS）、遊戲規劃 2026-10-21 | 沒有人接 |
| 車站紀念章的後續：新章在地圖上那一站跳出來、目標面板的成就連結也能開護照、車站卡標這一站的章、依縣市分組 | 決策 348「沒有做」 | 做完（決策 353，`claude/station-stamps`，session_01Mj4uPjTo2pmTRVsXob6Ju9）：車站的標記放在車站面板；還沒做的（點車站時的小卡、縣市點進去）寫在決策 353「沒有做」 |
| 刪掉快車停的站被拒絕時，字沒有說要先刪掉哪個停站模式 | 決策 291 的「下一步」、PLAYER_FEEDBACK 75.1 #2 | **做了**（#1129，`claude/preview-command-revision`）：點名停站模式、停的站與去哪裡刪，進階關著時說先打開（決策 291「後來」）。#1115 合併後「打開進階」那半句可以拿掉 |
| 自動派車時讓玩家調兩列車的發車：兩端對開、或晚前一班幾分鐘（77.1 #1）。現在「加開一列車」把班距設成「來回 ÷ 列車數」，從終點發的車和第一站共用一個派車間隔（`lastDispatch`，決策 23、172、264），所以做不到。要動 GameCore 的派車（每端各自的間隔或發車的錯開分鐘），升存檔 | PLAYER_FEEDBACK 77.1 #1；遊戲規劃 2026-10-20 | **已合併**：決策 309（#890，main `cbc7430`，存檔 65）。還沒做的寫在決策 309 的「下一步」（實機確認路線卡的選單、要不要加 UI 測試、停站模式的每個服務、單線開行車控制時的量測）。原本的排法：五方：玩家，初學者第二列車就卡住，影響大；鐵道迷，單線兩列車兩端對開、在中間站交會，最像真的（平溪、集集）；開發，GameCore＋存檔，和 302 同檔，排在它後面；美術，路線卡多一個選項；音樂，無 |
| ~~沿真實捷運、輕軌描線沒有真實高度~~（決策 279「後來」，`claude/metro-real-heights`）：`tools/real-railways/extract_structures.py` 的 `SYSTEMS` 只有台鐵、高鐵、林鐵，捷運的地下段鋪在地面。做法：把捷運與輕軌加進去（同一份 `level-profiles.json` 的 OSM bridge／tunnel），重產 `rail_structures.json`；描線照舊預設照真實高度（結構「自動」），玩家改「地面」就不套；建造費預覽寫隧道佔多少（地下貴）。五方：玩家要像真的、可手動省錢；鐵道迷：北捷多在地下；開發：只動資料工具；美術：地下段不再壓在街上；音樂：無 | 作者 2026-10-21，PLAYER_FEEDBACK 78.1 #7 | 資料與描線做好了（session_01PK2gs3bPYXPFbbJkwsDuUP）：七個系統，整條描四個門檻都過；一站一站描時端點照真實高度，394 個站剩 14 個在地面。**還剩**（決策 279「後來」第 4 點）：(a) 那 14 個站（六張犁、環北等：地形太粗互相衝突、環北坡度不夠），沒有人接；(b) 同系統上下重疊的兩條線（工具要帶 OSM 的 `ref`），沒有人接；(c) 建造費預覽寫隧道佔多少，沒有人接 |
| ~~量 OSM 軌道離官方多遠~~（`claude/osm-offset-measure`，`docs/research/OSM_OFFSET_2026-10-21.md`）。OSM 軌道和 Apple 地圖的偏移：投影沒有錯（兩邊都是 Web Mercator、WGS-84，台灣沒有 GCJ-02），是兩份資料本身不同。不能拿 Apple 地圖量偏移（授權不准取出它的資料）。做法：先寫工具量 OSM 軌道與國土測繪中心「臺灣鐵路」（data.gov.tw 73220，決策 279 用過）的距離分布；OSM 常偏 10 m 以上就把那些段換成官方幾何，大多在 2–3 m 內就改做「底圖對齊微調」（玩家拖底圖，存在存檔、只是畫面位移）。現在要完全對齊可用「OpenStreetMap」地圖樣式 | 作者 2026-10-21，PLAYER_FEEDBACK 78.1 #8（作者「都可以」） | 量測做好了（session_01PK2gs3bPYXPFbbJkwsDuUP，`tools/real-railways/measure_osm_offset.py`）：1,319 km 中位數 2.2 m、90% 在 6.5 m 內、超過 10 m 的 3.8%，每條線的平均位移都在 3 m 內（板南線東段 6 m，地下兩軌的畫法），所以照這一列的做法改做底圖對齊微調。**還剩**：(a) 底圖對齊微調本身（研究 §6：建議照實景地點各記一個位移，存檔加一個欄位、要取決策號），沒有人接；(b) 超過 10 m 的 72 段、36.7 km 要看衛星影像確認哪一邊對（研究 §4），沒有人接；(c) 高鐵沒量：「高速鐵路」（73221）的 tgos.tw 台灣以外 403，要作者在台灣下載 `HSRAIL_*.zip` 附在對話裡 |
| ~~iPad 的 `RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner` 在 main 上就紅~~ | #897 的 session 2026-10-21 對照出來 | **修了**（測試，`claude/ipad-uitests-red`，session_01XZM7WBK1v1RdHJdynRfngs）：iPad 橫拿時地圖看得到更多台北，月台的站名變成「Taipei」，取真實長度 16 節 320 m（`realPlatformCars`），比 254 m、爬 17‰ 的路段長，App 照規則拒絕。測試改成用月台長度的 stepper 調回 4 節（iPhone 橫拿大字要先捲到它） |
| ~~iPad 的 `MapLockUITests`「The lock opens the tile's card」在 main 上就紅~~ | #897 的 session 2026-10-21 對照出來 | **修了**（App，`claude/ipad-uitests-red`）：iPad 上鎖頭圓形的中間一列（圓心 y ± 0.3 點、整個寬度）點下去落到地圖，離圓心 2 點就開得了卡（only_testing run 39826506139 逐點量的；iPhone 每一點都開）。鎖頭的觸控範圍從 `Circle()` 改成 44 點的方形。其他地圖標記也查了、**修了**（`claude/map-marks-tap-rect`，`MapMarkTapUITests`，full lane）：委託案的旗子（`MapRequestMarks`，`Circle()`）一樣中間點不到，只在 iPad 紅（only_testing run 39841822269），改成 44 點的方形；景點星星（`MapAttractionMarks`）與提醒泡泡（`MapAlertBubbles`）是 `Capsule()`，iPad 點中間都點得到，不改。**還沒查**：3D 地圖的指北針 `map3D.compass`（`Map3DPreviewScreen`，`Circle()`，要先轉動地圖才出現）；工具列與卡片裡的膠囊（擴建地圖鈕、教學的膠囊、路線標籤）不在地圖標記上，擴建地圖鈕在 `MapLockUITests` 的 iPad run 點得到 |
| 簡單規則下，線的第一站有 2 股以上時，後到的列車整天等不到月台。重現：簡單規則（決策 258，沒有閉塞區間）、一條有班次（決策 133）的線，第一站 3 股（三貂嶺：正線＋兩條待避線），3 列車；第 1 天清晨，一列照班次在第一站過夜、停在別的列車路線所指的那股，另一列要開進第一站時，它路線指的那股有車，`alternativeRoute` 找到的空股被 `forbids` 擋下，因為線的計畫（`plannedDirections`）從第一站的每一股出發，每股都算有列車要反方向走；終點站的豁免（決策 278 的 `terminusTraversals`）只在有閉塞區間時才有。結果：那一列與後面的列車一直等，不算死結、沒有警告，第 30 天起 0 人次（平溪、集集、內灣三條收購的線都是）。玩家自己蓋、第一站多股、班次讓兩列同時停在第一站的線也會遇到。決策 315 用站序反過來（分歧站排最後）加每段指定股道繞開，GameCore 沒動 | 收購 session_017RbiiqGJTsLWDSz9q4Dukd 2026-10-21（決策 315 的「後來」）、遊戲規劃 | **修了**：決策 344（`claude/first-stop-platforms`）。往線的第一站的列車，可以逆著「只有那一股出發的列車才走」的那段進站，簡單規則也一樣；`long-leg-traffic.json` 重錄。決策 315 的站序沒有改回來，要改回來另量（決策 344「下一步」） |
| 審查 E 的 E1：App Review 的機器也是沙盒收據，送審的版本在設定的「版本」列連點 5 下，開得出演示模式與列車包的開關（審查準則 2.3.1 的隱藏功能）。**送審 App Store 前要做**：Release 版的開關改用只在 TestFlight workflow 加的編譯旗標，不再靠收據判斷。TestFlight 不受影響 | 審查 E（`archive/PR1019_1030_REVIEW_HANDOFF.md` 第三節），規劃 2026-10-22 決定第 82 版後先不做 | 沒有人接；碰 `testflight.yml` 的旗標要作者同意（CLAUDE.md）。作者 2026-10-22：「還沒有要上 app store 先幫我記著 我要上再跟我說」：作者說要上 App Store 時，規劃先把這一項提給作者 |
| 收購六家線（雙線，要另一套鋪法）不在收購第 2 步 | 決策 315 | **做了**：`claude/acquire-double-track`（六家線、沙崙線，決策 315「後來：雙線的六家線、沙崙線」、決策 323） |
| 沙盒三關（三鎮連線、鐵道造鎮、鐵道大亨）劇本建議、但現在做不到的 7 個事件：(1) 客運公司降價搶客；(2) 記者報導讓某條線的乘客暫時增減；(3) 鎮民反對設站；(4) 站前土地開發分潤；(5) 景氣循環或利率變動；(6) 併購對手公司；(7) 在這三關打開城市委託、節慶、颱風，做成劇情事件。(1)–(6) 要 GameCore 的新規則（多半要升存檔）；(7) 不用新規則，但這三關的目標是在這些關著時量的（決策 145、154、183），打開就要重量目標，要另外評估 | 決策 387 第 13–16 節，遊戲規劃 2026-10-23 | 沒有人接 |
| 演示模式「鋪好這一帶的真實路線」（決策 351 續篇）的後續：(a) 實機量一次鋪設要多久（Linux release 8 km 台北 12 條線：原本 11.8 秒，決策 351「後來」改快到 7.3 秒；196 秒是 debug）、按鈕在 iPhone／iPad 的位置；(b) 決策 351 續篇「缺口」列的：不用真實時刻表、只有 10 個系統有資料、林鐵機廠沒鋪、台北高鐵台鐵並行沒測、文湖線 35 m 彎道略過、中和新蘆共用段鋪兩次 | 決策 351 續篇，session_01Q6ucfu4uY1YiX1buRCZzFr（壓縮兩次後停） | (a) 待實機；(b) 沒有人接，只動 GamePresentation |
| 實景地圖 3D 的真實股道（決策 402）：照參考的派軌（`dispatch.json`）讓每一班走它被排的股道與待避線、實機看兩條並排的高架橋面、遠景太重時鋼軌只放近景 | 決策 402「下一步」 | 沒有人接；決策 402 先用「靠左／靠右走中間那條」 |
| ~~第 5 關第一步的卡片在時間走著時會跳：引導指的那段（`tutorialDoubleTrackStretch`，決策 378）每次都重選「現在沒有列車」的最長一段，600 倍速下在 S0、S1、S2 旁輪流換，字跟著換、卡片每幾秒就移到另一邊，玩家要點「略過」「下一步」時會點到地圖。UI 測試改成先暫停再略過（`LessonUITests`，main 12c1235 的 full lane 40085460126 的錄影）。App 的修法要選：開始這一步時記住那一段、列車在上面就叫玩家等它過去；或卡片只在擋到目標時才換位置~~ | session_01VtrfiLxZ1bP4EPrDe6FKZp 2026-10-24 | **修了**（`claude/tutorial-card-steady`）：和 `TutorialUITests.testATouchHeldOnTheFoldedCardAsTheStepMovesOnOpensIt` 7 天紅 2 次是同一個原因，卡片的位置每次排版都從頭算、對著目標置中，大小或要點的地方一變就整張換位置（947c23a 的 full lane 40093122899：膠囊帶著「略過這一步」量位置，步驟完成時那顆按鈕消失、膠囊變窄又置中，手指落在地圖上）。改成卡片留在原位（`TutorialCardPlacement.previous`，左上角不動），只有原位比別處差（擋到要點的地方或按鈕）才換；打開或收合時才重新放。引導指的那段照樣隨列車換（字也換），卡片不跟著跳。 |
| Kenney（CC0）免費素材接進 3D 地圖：Nature Kit 的針葉樹（`tree_pineTallA` 等 2–3 種）、灌木（`plant_bushLarge` 等 2 種）、City Kit Industrial 的臥式儲槽（`detail-tank`），照 art-style §7 改造形狀後經 `bridge.mjs` 轉檔進 `Map3DModelPack`，放山區、站前與沿線、工業用地 | 派工單 BJ（session_01YGNNumzoGFAQMzumKPx3Ry），`docs/research/FREE_ASSETS_TRIAL_KENNEY_2026-10-28.md` §6；試做的成品與烘焙腳本在私庫 railway-assets-private `game-art-previews/docs/art/free-assets-kenney/revision-1/` | 派工單 BN 做了（決策 458，`claude/kenney-trees-tanks`）：六件改形後進 App，`tools/kenney-props/`。glTF-Validator 由決策 467 加進 CI（規劃 2026-10-28 在 #1041 定）。剩下：闊葉樹、竹林與 `wood` 以外山坡的樹沒做 |
| 公測後再看的三件（審查 #1513 的 P3，[`archive/PR1496_1509_REVIEW_HANDOFF.md`](archive/PR1496_1509_REVIEW_HANDOFF.md)）：(1) REV-3 #1505：跳到車站面板某一組之後約一秒內，玩家自己捲會被拉回（`StationPanel.swift` 的 `settleJump`；玩家開始捲時清掉 `pendingJump`）；(2) REV-4 #1496：手機橫放時路線清單的搜尋欄在清單的一列裡，打字中捲走可能收起鍵盤；(3) REV-5 #1508：新舊版本混跑同一個網路對局會不同步（04:00 後收購那天的旅客放出不同），GameCore 沒有版本握手 | 派工單 REV，session_01YGNNuo6Fi8RzveGo8bcMk6，2026-10-29 | 沒派；有玩家回報或開放跨版本連線前再看。P2 的 REV-1、REV-2 由 `claude/rev-p2-fixes` 修了 |

## 6. 留在遠端、沒有合併的 branch

清理時先看這張表，不要刪掉還有用的。

| branch | 是什麼 | 處理 |
| --- | --- | --- |
| `claude/in-app-language` | 語言選單，#727 已合併 | 可以刪 |
| `claude/hsr-depot-exit-priority` | 機廠出庫優先的 B 方案，量測失敗 | 紀錄在 #685，可以刪 |
| `claude/hud-width-proof`、`claude/claude-key-check`、`claude/basemap-align-repro`、`claude/details-card-repro`、`claude/bughunt3-app-proof` | 只用來證明或重現的暫時 commit（「not for merge」「Repro only」「Proof only」） | 可以刪 |
| `claude/review-u9-u10` | U9、U10，已由 #646 那一輪 cherry-pick 進 main | 可以刪 |
| `claude/hsr-train-rostering` | 車輛運用（原車接下一班、閒得久的才入庫）的實驗，量了變差、沒有合併 | 數字在決策 296「下一步」第 1 點的「之後」，可以刪 |
| `claude/real-station-suggestions`、`claude/hsr-overtake-approach`、`claude/hsr-depot-shuttle`、`claude/hsr-rostering-not-adopted` | 決策 295（#844）、294（#845）、296（#846）與 #849，都已合併 | 可以刪 |
| `claude/perf-3d-rain-gpu` | 3D 的雨改用 GPU 畫（80908c4d），接在 #1538 後面 | 公測後開 PR，要量實機 |
| `claude/perf-3d-cockpit`、`claude/perf-real-map-600x`、`claude/iphone-text-overflow` | #1538、#1537、#1536，已合併 | 可以刪 |
| 2026-10-12 以前的其他 `claude/*` | 這份是用淺層 clone 查的，看不到 10-12 以前的歷史，所以沒有核對這些 branch | 刪之前先用完整 clone 確認內容已在 main |

## 7. 舊交接與文件裡還沒做的（2026-10-16 稽核）

2026-10-16 用三個 agent 對照 main `d542952`，把下面這些文件裡寫了「沒修、延後、下一步、等作者」的項目全部查過一遍：
- `docs/archive/` 的 10 份交接，約 90 項；
- ARCHITECTURE 決策 200–254 的後續，約 80 項；
- `docs/research/` 31 份、`docs/art/` 28 份 README、ROADMAP 的平衡待觀察表、PLAYER_FEEDBACK。

已經做完的、已經記在本檔第 2–5 節或 NEXT_PRIORITIES 的，不列。剩下的列在這一節，每一項都有方向和接手的人。查法是讀程式與文件（`git grep`、`git log --grep`），沒有跑測試；「待查」表示原文說可能是刻意的，或要跑起來才看得出來。

同一次也把文件和程式對不上的四處改好：PLAYER_FEEDBACK 59.1 #1–#6 的狀態、54.1 #1 的「拖動」、`docs/art/depot-icons-2026-10-13/README.md` 的定案、OVERVIEW 研究表的 CI 4C。

### 7.1 小 bug 與效能（舊審查交接留下的）

PR #816／#822／#823 的 Codex 獨立審查與待原作者修正：折返後行程準點判斷、秒級存檔窗、車尾清空及舊檔 invariant 工具缺口，見 [PR816_823_REVIEW_HANDOFF.md](archive/PR816_823_REVIEW_HANDOFF.md)；重現程式與四種開關結果都在報告。**R1、R2 已修**（`claude/short-turn-r1-r2`，決策 288 的「後來」）；R3（#822 的作者評估整列車的契約）、R4（`ReferenceWorld` 的作者）還沒有人接。

審查回報清理 session（session_01FUXNvfnNmoSMf58pgakpsF）已經把這 30 項逐項分好類，每一項的去向寫在 `docs/archive/PR685_711_REVIEW_HANDOFF.md` 第十一節的「第二批」：現在修的（#735、#737、#738、#739）、刻意設計已在原決策補「後來」結案的，以及延後等穩定的（附原因、建議做法、影響範圍）。清單只留那一份。

第一批（PR685_711 交接第四節與前兩輪剩下的）的延後項目也在 `docs/archive/PR685_711_REVIEW_HANDOFF.md` 第十一節：狀態列破產倒數、景點計算量、3D 亮窗與反向 Z、3D 開著時的月底報表、#680 清單拖曳、#657 坡道切軌訊息、hook 的 Swift 6.4.1 等，每項附原因與建議做法。

PR #712–#754 那一輪（69.1 收工那一晚）的審查：修了三項，延後的 11 項（自動待避線抬起的列車放不回去、3D 斜交平交道、#752 模型的可追溯性、PR gate 的 UI 時間等）連同原因與建議做法，寫在 `docs/archive/PR712_754_REVIEW_HANDOFF.md` 第四節。3D 平交道那幾項與測試容差已在第 2b 步（決策 267）做完。

PR #786–#872 那一輪（2026-10-21，作者：「很久沒做pr review了 先優先做」）分三組審查，都已合併：
- **A 組 行車控制**（#878，[PR786_872_A_REVIEW_HANDOFF.md](archive/PR786_872_A_REVIEW_HANDOFF.md)）：0 個新發現。延後的在它第五節：
  - **R3**（P2）：#822 的閉塞分界只看車頭。建議 `isClear` 改看車尾，會動閉塞開時的 golden 與 replay。交行車控制的 session 或 #822 的作者，等 302 的後續做完再排。
  - **R4**（P2，測試工具）：`WorldInvariants.violations` 遇到 v28 的自動結構會 trap（`ReferenceVertical.swift:81`）。交 `ReferenceWorld` 的作者；探針的 fixture 數要改成 68。
  - **B4**（P3）：已經誤點的車被折返，時刻表不動，列車卡認不出折返。B 組建議的修法會讓時刻表非遞增、存檔讀不回，不能用。可行的兩條：GameCore 把之後的停靠移到不早於現在（違反決策 288，要重驗 golden 與 replay），或 GamePresentation 從行程紀錄認出折返（較小，建議走這條）。
- **B 組 建造、真實資料、經濟**（#874，[PR786_872_B_REVIEW_HANDOFF.md](archive/PR786_872_B_REVIEW_HANDOFF.md)）：B1–B3 已修，B4 見上。另兩個小項：整平的提示與成功訊息只說點到的那條軌道的長度；#869 之後轉乘的平衡沒有量（`TRANSFER_REPORT=14`，NOT ASSESSED）。
- **C 組 App、介面、3D、工具**（#873，[PR786_872_C_REVIEW_HANDOFF.md](archive/PR786_872_C_REVIEW_HANDOFF.md)）：6 個發現都修了。它第三節有 6 項只讀程式看到、Linux 測不到的，要在 macOS 或實機確認：
  - 3D 場景快取的 key 只數建築與月台（`Map3DPreviewScreen.swift`）；
  - `Map3DSceneCache.clear()` 不會取消建到一半的場景；
  - 路線面板的 `scrollTo` 沒有照「減少動態效果」；
  - 地圖角落按鈕的觸控區只有 44×28；
  - #870 的預覽用 `targets: nil`，建立路線卻用路線自己的目標班距（轉給空窗快轉 session 後沒有在 #877 修：要一張有真實路線的實景地圖才做得出在 main 上紅的測試，又要改 #873 剛改過的 `LineConfirmation.swift`；留給之後，還沒有人接）；
  - diagnosing-bugs skill 的 TICK_REPORT 指令少了 `--skip-build`。

PR #873–#910 那一輪的 A 組（2026-10-21，session_01SvQ285hMiSeRsER1EXzfT9，[PR873_910_REVIEW_HANDOFF.md](archive/PR873_910_REVIEW_HANDOFF.md)）：11 個發現，修了 6 個。兩個 P1 是存檔讀不回：交錯發車的路線改成環線、買下的線拆站拆到沒了。另外修了 3D 快取重用了不含新焦點的場景、半夜的班距、色帶重疊、一個斷掉的連結。延後的 5 個在它第三節：
- **A6**（P2，GameCore）：**已修**（2026-10-22，#966）。沒修到的一種：班次晚派車時，列車自己時刻表的第一段已經被縮短，分不出是晚點；要讓列車記住班次的時刻（改存檔格式），交給下一個改決策 306 或 133 的 session，寫在決策 306 的「後來」。
- **A7**（P2，App）：**已修**（2026-10-22，#970）：實景地圖開始蓋時「新遊戲」頁一起關。Simulator 與實機還沒確認。
- A8（已修，#966）；A10（暫停中每個指令都重算快轉）已修：試跑移到背景（決策 330 的「後來」，`claude/night-skip-offer-off-main`）；A11（SceneKit 的建築與地點沒有用到）交 3D session。

PR #911–#944 那一輪（2026-10-21，審查 B，session_017M3NJsMXLafGDsSvidGhD6）：[PR911_944_REVIEW_HANDOFF.md](archive/PR911_944_REVIEW_HANDOFF.md)。修了兩個 P2：一日週遊券卡片建議的價格賣不出去（#934）、平交道路面上立著電桿（#938）。沒修的五個 P3 在它第四節，每項寫了交給誰：高鐵票價表沒驗站 ID、潮汐的車站示意圖沒看週末、自由模式關潮汐留著舊 `homeShare`、公車模型縮放沒防 NaN 與 3D 場景白白重建、站房可能壓到種子街道。
- 2026-10-22：B3 已修（#966）；B4、B6 已修，B5 定案為自由模式不動需求（決策 319「後來」）（#970）；B7 交 3D session。

PR #945–#961 那一輪（2026-10-22，審查 C，session_01VVzExSvZcTej5eCqxdUEpY）：[PR945_961_REVIEW_HANDOFF.md](archive/PR945_961_REVIEW_HANDOFF.md)。12 個發現，修了 8 個：#955 之前存下的環線交錯發車、拆站留下的收購資產讀不回（#974）；full lane 重跑轉綠不報、重跑舊的報過時消息；素材交接叫 session 疊在未合併的 PR 上（#942、#949、#957 的根因）。沒修的 4 個 P3 在它第四節：公車可能重疊、公車三角形超預算、商用套件 README 的零件名、還沒用到的通勤車模型；決策 332 被 #963 重用的事已由遊戲規劃改成 335。

PR #962–#1018 那一輪（2026-10-22，審查 D，session_01TCwdHtJTq9REwDrCSHzR11）：[PR962_1018_REVIEW_HANDOFF.md](archive/PR962_1018_REVIEW_HANDOFF.md)。36 個程式 PR、40 點；GameCore 的四個（#966、#974、#986、#995）沒有問題。5 個發現，修了 2 個（#1023）：公園場景上蓋城市地塊、鏡頭一動大公園就換場景。沒修的 3 個 P3 在它第四節，交 3D 城市線：阿里山林鐵在 3D 畫成通勤車、1× 同一秒內的掉頭晚一秒才看到、真實列車 1× 走半秒停半秒。#1005 的「有環就不報待避」查過不是 bug（`parallelTracks` 本來就把環算成 2 股）。

PR #1019–#1030 那一輪（2026-10-22，發版前小審查，TestFlight 第 82 版前）：[PR1019_1030_REVIEW_HANDOFF.md](archive/PR1019_1030_REVIEW_HANDOFF.md)。8 個程式 PR、9 點，沒有 P1、P2。#1019 重錄的 `long-leg-traffic.json` 逐值說明合理；演示模式在 App Store 版完全看不到。兩個 P3 沒修，在它第三節：E1 審查員的機器也是沙盒收據，連點 5 下開得出演示模式與列車包的開關，送審 App Store 前改用編譯旗標；E2 一鍵鋪路線的途中還能按播放與復原，一次復原退不完。

PR #1031–#1078 那一輪（2026-10-23，審查 F，session_01PFerWVHLXvDG7PZGKYqgCu）：[PR1031_1078_REVIEW_HANDOFF.md](archive/PR1031_1078_REVIEW_HANDOFF.md)。29 個程式 PR、35 點；GameCore 的六個（#1045、#1047、#1060、#1064、#1065、#1078）沒有問題。修了兩個 P2：教學、課程與演示的車站卡答應會蓋紀念章（#1034）、夜間快轉中進 3D 跟車後速度停在最快（#1057）。沒修的兩個 P3 在它第四節，交 3D 城市線：太陽陰影圖在跳過的幀被當成畫過（#1044）、省電畫質下跟車前的建物整片消失而非半透明（#1067）。

PR #1079–#1136 那一輪（2026-10-23，審查 G，session_012mpfbnZwWC7RpNFhhNgFKs）：[PR1079_1136_REVIEW_HANDOFF.md](archive/PR1079_1136_REVIEW_HANDOFF.md)。31 個程式 PR、32 點；GameCore 的 #1117 沒有問題。修了兩個 P2：6000× 時背景算好的列車滑行在一圈多個 tick 時白算、主執行緒重算（#1108）；重開 App 接續課程時第 6、7 關「改路線設定」的步驟不會前進（#1093、#1100）。沒修的 P3 在它第四節：G3 串流重建時台北車站地標與站體可能同時出現（#1107，交 3D 城市線）；G4 資料來源「機場與空地」沒說也決定哪裡沒人住、G5 舊全台存檔在新舊規則交界的人口差幾十人、G7 足跡出處的兩處寫法與亮島多邊形（#1130、#1123、#1132，交實景資料線）；G6 在 lesson.addTrain 接續時那一步直接跳過（課程線）。full lane 的 `Feature284To286UITests` 第 176 行是 Simulator 冷啟動慢的偶發，不是退步（第五節）。

PR #1137–#1188 那一輪（2026-10-24，審查 H，session_01G5KnXReBk4W8w69FWWX4LW）：[PR1137_1188_REVIEW_HANDOFF.md](archive/PR1137_1188_REVIEW_HANDOFF.md)。29 個程式 PR、32 點；GameCore 的 #1166、#1175 沒有問題。修了（#1195）：第 2 課先蓋一小段再畫到城鎮時「按 ✓ 蓋好軌道」被跳過（P2，#1137）、重開 App 在第 2 課軌道步驟接續時軌道兩步直接跳過（P3）。沒修、要派的在它第四節：**H1（P2，#1178，要動 GameCore）**分區購買的空白地圖上後來買的地塊永遠沒有路、站前路鋪不了（交規劃，決策 400 線）；**H4（P2，#1159）**橋端旁平行的側車道被坡道抬起（交 3D 城市線）；P3：H5 隧道出口沒有電桿（#1155）、H6 平行高架下的路口標線消失（#1159）、H7 iCloud 衝突版本可能重複留成「來自另一台裝置」（#1160，兩台實機驗證時一起）、H8 底圖工具的 `layer=inf`（#1171）。

PR #1189–#1241 那一輪（2026-10-25，審查 I，session_01Mqs95FA7nGrbhR8dXfefX9）：[PR1189_1241_REVIEW_HANDOFF.md](archive/PR1189_1241_REVIEW_HANDOFF.md)。25 個程式 PR、28 點；GameCore 的 #1199、#1220、#1225 沒有問題。8 個發現都是 P3。修了（#1247）：致謝說一半的高鐵是白色的（列車包才有）、存檔列表匯出還是 JSON、路線改高鐵後高架要等一週才換、高架色帶埋進護欄、站距近時車站視角看不到進站、iPad 轉向後教學卡片不重排。沒修、要派的在它第四節：I7 線上時也說「連上網路後會自動上傳」（#1219，決策 397 作者，兩台實機時一起）；I8 公車路線讀檔不檢查編號 ≥ 1（#1220，決策 400 線）；N700S-G 後半列沒有鏡像（01LARTBY 處理中）。

PR #1229–#1287 那一輪（2026-10-26，審查 J，三段：session_01KA4P39dCU3gKAqH2vLPej8 第 1、2 段，session_01UvQcP14umjdnDYpqc14Ngx 第 3 段）：[PR1242_1287_REVIEW_HANDOFF.md](archive/PR1242_1287_REVIEW_HANDOFF.md)。35 個程式 PR、38 點；GameCore 的 #1232、#1239、#1268 沒有問題。
- 第 1 段（#1229–#1253，11 個、13 點）：J1（P2，#1232 × #1249：成就把夜市、廟算成三種事業之一）一個，已修並附回歸測試（#1290）。
- 第 2 段（#1254–#1268，12 個、13 點）：沒有發現。
- 第 3 段（#1270–#1287，12 個、12 點）：J2（P3，#1277）一個，沒修；另一個疑點（#1278 跑分在鐵路資料讀好前開跑是 0 條線，只在測試版）。
- 沒修、要派的：J2 幀時間計量 `FrameTimeMeter.frame(at:)` 每一幀複製一次 11.6 KB 的區間計數（`FrameTimeRecord.swift:504`，改成直接改 `tally!`，決策 421 線，下一個碰這個檔的 PR 順手帶上）。公車道路與真站牌在主執行緒讀是派工單 E（#1295）的，不在這一輪。

**大世界的效能**（決策 328，`claude/perf-2d-sim-speed`，2026-10-21；玩家回報 78.1、79.1：三十幾站後 2D 約 5 FPS、加速跑不到設定）。已修：夜間快轉試跑移出主執行緒、乘客排隊二分搜尋、上車排序、實景支線可購清單記住。還沒做、還沒人接：
- **2D 5 FPS 的主因**：Linux 量不到 SwiftUI 繪圖。要在實機打開「設定 → 地圖 → 幀數」，點開看哪一層（地面、軌道、列車、站名、天氣、推進後）每秒花最多。候選：`session.world` 每個 tick 都讓讀它的 view 重算；軌道畫布在交通覆蓋變了就整張重畫；站名畫布在候車數變了就重畫；夜色的 `.blendMode(.multiply)` 與站名的 `.colorMultiply`。量到哪層再對症改（拆出不常變的圖層、`drawingGroup`、降低重畫頻率）。
- **1200× 在大世界的 GameCore**：第 730 天的測試存檔一個 tick 改之前約 7～9 ms、改之後約 4.5 ms（Linux release），隨等車人數變慢（放人、上車、`makeNetworkPassengerPlan`）。再快要把乘客佇列照路線分組，會改存檔格式。報告：`LONG_GAME_REPORT=730 swift test -c release -Xswiftc -enable-testing --filter LongGameCostReportTests`。
- **Simulator 上的效能 UI 測試**沒有做：CI 的 Simulator 數字和實機差很多，先靠幀數顯示。

**82.1 的卡頓**（決策 363，`claude/perf-actions-82-1`，session_011kVCxFJEULkYyGGU7emgsx，2026-10-23；分三個 PR 的第一個，它壓縮 1 次後停在這裡）。已修：每次編輯重算整張地的車站涵蓋率、夜裡切速度與離開建設工具在主執行緒上試跑一整晚。報告：`ACTION_COST_REPORT=30 swift test -c release -Xswiftc -enable-testing --filter ActionCostReportTests/testWhatTheThreeActionsCost`（44 站、4 條線；`ACTION_COST_PROFILE=1` 跑給 callgrind 用的 50 次編輯）。還沒做、還沒人接：
- **(b) §22.2 第 25a 名**：高倍速每次換世界整個畫面重算（見下面「高倍速少換幾次世界」），要作者的幀數讀數。
- **(c) §22.2 第 10h 名，2D 每幀**：`MapCanvas` 的 `==` 比較 `traffic` 與閉塞，所以交通覆蓋一變整張軌道畫布重畫；可把閉塞與等候畫進自己的畫布。`MapLabelCanvas` 在候車數變了就重畫站名。夜色的 multiply 混色。不操作時降 2D 幀率上限。先請作者在大存檔開「設定 → 地圖 → 幀數」，記下哪一層最慢。
- **買一格地圖約 55 ms**（Linux release）：讀那一格的土地，`LandImport` 約 23 ms、GameCore `expandLand` 約 22 ms。可在玩家點選地塊時就在背景讀好（照地塊、範圍與資料組記住），按「買」時只套用。
- 編輯後第一次讀 `trafficOverlay`、`situationAlerts` 各約 1.3 ms，沒動。
- **遊戲規劃另外交代、給 (b)(c) 的人**（2026-10-23）：同一類還有 78.1 iPhone 17 Pro「手機發熱當機」、79.1 iPhone 17 Pro「6000 倍卡住」（79.1 還沒有決策 330）。(b) 先在 origin/main 量 6000× 的現況。發熱：看不操作、高倍速時 2D 是否一直以 120 Hz 重畫，可在 GamePresentation 定一個幀率上限規則（例如沒有手勢時 60 或 30），App 只接線，值與五方寫進新決策。TestFlight 沒有當機紀錄，分不出 watchdog 還是記憶體：入門 iPad（A16）記憶體較少，順便量大世界、高倍速時的記憶體峰值（批次推進時是否一次複製多份世界）。

**高倍速的主執行緒**（決策 330，`claude/fast-forward-main-thread`，2026-10-22；作者 iPad 宜蘭線 6000×：最長一幀 114 ms、推進後 max 44.8 ms）。已修：整點的站長建議（約 40 ms，幾乎全在 `firstLineWithoutPlaceToPass()`）移到 `LoopTick.work()`；幀數讀數把「推進後」拆成九段、多一行「清理」（放掉舊世界）、第一行多「其他」。報告：`TICK_REPORT_YILAN=432 swift test -c release -Xswiftc -enable-testing --filter TickCostReportTests/testWhatTheStepAfterATickCostsOnTheYilanLine`。還沒做、還沒人接：
- **請作者量**：宜蘭線 6000×，開「設定 → 地圖 → 幀數」，點開讀數，記下幾秒內的「最長一幀 · 其他」與「推進後」的 max。推進後的 max 應該從約 45 ms 降到幾 ms。
- **高倍速時畫面整個重算**（§22.2 25a，決策 367，`claude/perf-fast-forward-views`，2026-10-23）：作者 83.1 高鐵 600× 的「其他」200 ms 是 SwiftUI 重建畫面。已修：畫面框架（`ContentView`）不再讀 `session.world`（改讀 `session.screenFacts`），推進時不再清空已經空的 Undo／Redo 紀錄。Simulator 修後第一次等不到地圖，是這個示範在 Debug 版本來就慢、UI 查詢快照逾時，重跑一次就過（run 39895315471，細節在決策 367）；Debug Simulator 的「其他」前後看不出明確的差。還沒做：**84.1 已重量**（作者實機，高鐵示範 6000×：3 fps、軌道 329 ms/s ×2、其他 360 ms），接續是決策 377（下一條）；那時的下一步是讓 `MapView` 的子 view 只讀自己要的值（`MapAlertBubbles`、`MapAttractionMarks`、`HUDView` 的 `ViewThatFits` 四份、站長角落的 `stationMasterRefreshKey`），再不夠才在 ≥1000× 時每次 `advance(by:)` 多走幾個 tick（守住決策 143、248、195）。量法：`FastForwardFrameUITests`（`ios-build.yml` 的 `only_testing`）、`FAST_FORWARD_READS=50 swift test -c release -Xswiftc -enable-testing --filter FastForwardReadsReportTests`。
- **已修（`claude/no-place-to-pass`，決策 264 的「之後的修正」2026-10-22）：雙線的宜蘭線，站長說「沒有地方交會」**：原因是兩端月台前的轉轍器讓整段算成 1 股。以下是原本的紀錄。重現：宜蘭線示範（`TRADemo.make`，測試裡是 `TRADemoTests.opened`），開局後 6000×（`.fast`）跑 60 個 tick；`StationMasterAdvice(world:)` 回 `.noPlaceToPass(line: LineID(rawValue: 1), name: "TRA Local")`，也就是新聞裡站長說「TRA Local 沒有地方交會」；直接呼叫 `world.firstLineWithoutPlaceToPass()`（`AutoService.swift`，決策 264）回同一條線。宜蘭線是雙線，不該這樣說；可能是兩端的單線（留置線、折返段）被算進去。這個函式每遊戲小時約 38 ms（Linux release），現在在背景（決策 330），修的時候可順便看它要不要用指令版本記住。
- **地圖左半邊沒有地形陰影**（作者同一張截圖，畫面約 55% 處一條垂直分界）：`taiwan_terrain.pmtiles` 在宜蘭附近 z8–z10 的圖磚都在、相鄰邊緣高度連續，z9、z10 的圖磚分界在東經 121.64°，不是缺磚。下一步：請作者下次截圖時附上分界線的經度或地名（或在同一處打開 3D、拉近再截一張）；若正好是 121.64°，查 MapLibre 的 raster-dem 在那一層（`BaseMapStyle.hillshade`、`tileSize` 512）沒畫左邊那張的原因（記憶體、圖磚太大 291 KB、或 hillshade 需要鄰磚才準備）；若不是，看 2D 的地面畫布有沒有蓋住。
- **2D 大世界掉幀**（§22.2 10h，決策 371，`claude/perf-2d-map-frame`，2026-10-23 session_015LxxfmrvhBFnxLie4gd2Bs 從 session_018DNqCBcwA7znTnrzbUpTVF 的 `c075037` 接手完成）：軌道畫布拆成「軌道與路線」和「交通、建物、車站」，站名畫布拆成名字、候車數、標記三張，列車滑行限 30 fps（跟車 60）。Linux release 600×：軌道與站名每秒重畫從 9.6、10 次降到 0。還沒做：**84.1 已重量**（作者實機，高鐵示範 6000×：3 fps、軌道 329 ms/s ×2、其他 360 ms），接續是決策 377（下一條）；交通那張若還重，下一步是 `TrafficOverlay` 帶版本號、只比版本（現在逐項比 1.2 ms／tick）。細節在決策 371。拋棄用的 `claude/perf-2d-map-frame-baseline` 可以刪（proxy 擋刪除）。
- **2D 高鐵 6000× 3 fps**（TestFlight 84.1，決策 377，`claude/map-track-redraw-cost`，2026-10-23 session_01UxzgXQsTohBZKf3mrBWq27）：幀數表的「軌道」拆成「軌道與路線」「交通與車站」兩行；軌道、路線、區間車流的折線照螢幕 0.25 點簡化（整條高鐵 177 萬點 → 5,578 點，Linux 挑點與投影 180 → 76 ms）；地圖泡泡、景點標記、站長、狀態列只在顯示的東西變了才重算。Linux 找不到每秒兩次軌道重畫是誰叫的（世界一次都沒有叫）；Simulator 上是「軌道與路線」那一張、只在開地圖後 15–25 秒，所以幀數表的那一行後面加了重畫的原因（例「畫面移動 ×2」）。**請作者在高鐵示範 6000×（站名、候車數、票價與紀念章打開）開「設定 → 地圖 → 幀數」重量**，記下：fps、最長一幀與其中「其他」、「軌道與路線」與「交通與車站」各幾 ms/s、×幾、最長，以及「軌道與路線」後面寫的原因；下一步在決策 377「還沒做的」。**推進 106.6 ms/s（§22.2 第 41 名）沒有動**，依派工。
- **地圖上浮動控制項的邊距**（TestFlight 85.1 作者截圖，決策 382，`claude/hud-margins-86-1`，2026-10-23 session_013WiLkQHTAxZL85F5PYxJuL）：共用 `HUDMargins`（安全區域內 10 pt），右下角按鈕、小地圖、圖例往外、往下各 14 pt，對齊狀態列右緣與工具欄底線。**請作者在 86.1 手機橫放看**：右緣（狀態列、小地圖、縮放）與底下一排（工具欄最後一格、擴建地圖、站務員、縮放）是否各在一條線上；左緣約 4 pt 的差在程式裡找不到（三者都在 10 pt），若還看得到，多半是圓角不同（決策 382「還沒驗證」）。建設模式時工具欄放不下，× 與鐵鎚固定在底下，上面三個工具與卡片開關那段捲動、切在兩個按鈕之間，放不下時開關排在工具下面；× 與鐵鎚沒合併（理由在決策 382 第 7 點）。**留給遊戲規劃**：手機開著面板時，下面那一排縮放與 3D 的下緣仍在決策 300 的位置（出處條裡），沒有抬到工具欄底線（第 8 點）。
- **全畫面對齊稽核**（決策 388，`claude/hud-alignment-audit`，2026-10-23 session_013WiLkQHTAxZL85F5PYxJuL）：`HUDAlignmentUITests`（full lane，手動 `only_testing` 加 `only_testing_ipad`；iPad 一次跑 11 個會超過那一步的 30 分鐘，分兩次）量每個浮在地圖上的群組離決策 382 的線多遠，`ALIGN|…` 的 log 是量測紀錄；新的浮動控制項加 `.hudFrameMark("…")` 才量得到它的玻璃。修了 3D 控制項（16→10）與課程卡（16→10）。**留給遊戲規劃**：手機開著細節卡時 2D 跟車列沒有 3D 鈕（決策 251 讓位），要不要讓跟車列換到第二排；開始畫面等 #1110 合併後再量。
- **2D 高鐵 6000× 主執行緒**（TestFlight 85.1 作者實機：26–41 fps，最長一幀 173–200 ms 幾乎全是「其他」，推進後 · 音效 max 29 ms、收入 max 22 ms；決策 379，`claude/fast-forward-sound-income-other`，2026-10-23 session_019RS5qZNMdEtyEF7MkVyR4c）：「其他」最大的一塊是地圖每 tick 在主執行緒算列車滑行（Simulator「地圖跟著推進」每次 1.5–2.2 秒，Linux debug 504 ms），改在背景的 tick 裡算、地圖只補時間；音效與收入的時間判斷是 `AVAudioPlayer.play()`，提示音改在 App 自己的佇列播放（聲音、音量、間隔不變），幀數表多「播放音效」一行；幀數表把「其他」拆開：多「畫面更新」（run loop 等待前，SwiftUI 與 Core Animation）與底下的地圖、地圖列車滑行、地圖車流、地圖跟著推進、畫面框架、狀態列、站長，第一行寫「最長一幀 · 其他（畫面更新）」（#1108 已合併；改後的 Simulator 量測與 Linux release 讀數在決策 379「後來」，拆開後那三行在 Simulator 沒量到）。**請作者用同一個高鐵示範 6000× 重量**（步驟在決策 379 第 3 段），照「畫面更新」的分項修；下一步寫在決策 379「還沒做的」。推進（背景）是另一個 session 的；它每 tick 多算了滑行（原本在主執行緒），若推進成了瓶頸，照決策 379 第 4 段的下一步。
- **開新路線的比較抽屜蓋住 ✓**（TestFlight 85.1，決策 384，`claude/line-draft-drawer-checkmark`，2026-10-23 session_013WiLkQHTAxZL85F5PYxJuL）：抽屜讓開細節卡與右下角那一組；手機橫放時抽屜放進 ✓ 膠囊裡、在說明左邊，展開長條也不蓋 ✓。**還沒驗證**：實機上膠囊裡的抽屜好不好看、300 寬的長條讀不讀得清楚（決策 384）。
- **高鐵 6000× 的推進**（TestFlight 85.1 作者實機：推進 500–690 ms/s、×8–12、max 194–305 ms；§22.2 第 41 名，決策 379（續），`claude/tick-advance-hotspots`，2026-10-23 session_01MhQXufQK6jhjrKXY6iUTDB）：每列車的判斷不再整份複製世界（`trains[index]` 先放進區域常數），午夜的城市成長沿用前一天的乘客計畫，不再多算一份。Linux release 每 tick 平均 29.0 → 21.0 ms（−27 %）、最長 321 → 202 ms（−35 %，都在午夜）。報告：`TICK_REPORT_HSR=432 swift test -c release -Xswiftc -enable-testing --filter TickCostReportTests/testWhatATickCostsOnTheHighSpeedRail`。**請作者在 86.1 以後的高鐵示範 6000× 開「設定 → 地圖 → 幀數」**，記下「推進」的 ms/s、×幾、max（白天與深夜各幾秒）。還沒做的（`assessSpacing` 的邊集合每次 tick 先算一次、`routeStretches` 記住 `pathAhead`、乘客找路 memo 依班次等級各留一份）在決策 379「沒有做的，與下一步」，還沒人接。

PR #755–#784 那一輪（72.1 那一天）的審查：修了 6 項（路線卡需求燈只數這條線、座位圖換行、關卡「繼續玩」會繼續、3D 場景快取分局、長按的診斷 trace、決策 266 的文字），延後的 10 項（`main` 在 abb306a 的 full lane 紅、`testHoldingAStationTracesItsBusiestTrips` 的根因、整平時的轉乘乘客、72.1 沒有自己的綠 full lane 等）連同原因與建議做法，寫在 `docs/archive/PR755_784_REVIEW_HANDOFF.md` 第四節。

第 5 關的複線（決策 378，session_01USKsgntpPbW3M49z6oSHen，目標 86.1）：**已修**。最長那段被拒絕是第二條軌道的控制點平移在急彎中間只離 3.81 公尺，改成分段鋪；修好後那段要的錢比第 5 關的現金多，引導改指 S1 旁沒有列車的那段，一次蓋好。預覽慢在找渡線時白切長軌道，GameCore 加一個不改世界的切開查詢先問，Linux release 從 175–744 ms 降到 40–95 ms。剩下：實機 Release 讀數；要再快得改 GameCore 的 fouling 增量或把預覽移出主執行緒（決策 378「下一步」）。

### 7.2 遊戲功能的後續（決策與研究裡寫了「之後」的）

**接手**：遊戲規劃排序後開 session。核心玩法（決策 254）做完以前都不開，除非下表另外寫了。
**方向**：照 NEXT_PRIORITIES §14 的權重排；開工時把這一列搬到第 2 節。

| 項目 | 出處 | 方向 |
| --- | --- | --- |
| 空白地圖「一鍵全開」 | 決策 200 第 6 點 | 併進核心玩法第 4 個 PR 之後的沙盒選項（關卡解鎖後才出現） |
| 颱風一年 1.5 個（氣象署平均 3.6 個），「留給作者決定」 | 決策 208 | **遊戲規劃決定：維持 1.5**。玩家：簡單規則是預設，颱風太頻繁會打斷剛學會的玩家；開發：不用動 golden；美術：無；音樂：無。寫實規則之後可以考慮照 3.6 |
| 劇本節慶（天燈節等）跟著農曆移動（要改存檔） | 決策 211 | 併進 §15.3「台灣節慶」那一項一起做 |
| 票價需求提示、借錢前試算、課程裡未解鎖車型的後續（§22.2 第 18 名做完，session_01QTjYzbHDE2QFpRux5BQSsW，`claude/adoring-fermat-lcewix`） | 決策 374「下一步」 | 都是可做可不做的小事：(1) iPhone 橫拿時票價段落多兩行、貸款段落多三行，TestFlight 看會不會太擠（UNVERIFIED，沒有 UI 測試）；(2) 觀光列車第 9 關才開，若玩家想早點用就把 `Lesson.number(unlocking:)` 的 9 提前；(3) 分期還款要動 GameCore 與存檔（決策 67 的貸款沒有期限），沒有排 |
| 彎道限速沒做的：道岔側向限速、節點折角、坡道影響速度、授權終點前照煞車曲線減速、擺式列車過彎加速、交會停站改用 RunCurve、出發時車尾在彎道內、跨呼叫的快取 | 決策 217 第 10 點 | 寫實規則的加深，排在核心玩法之後；簡單規則不受影響 |
| 長按路線看旅程（用車上與候車的乘客）、鏡頭自動縮放、弧線端點記號 | 決策 220 | 併進「回饋第二批」（第 3 節航空手感那一列） |
| 景點新種類：廟宇、夜市、博物館（新圖示、新季節係數） | 決策 250 | 併進 §15.3「台灣節慶」或觀光列車；廟宇可以和 3D 的廟埕一起做 |
| 放空模式的後續：群車視角（鏡頭在列車最密的路段慢慢漂移）、放空專屬配樂、沒有車的夜晚接上「跳過安靜的夜晚」 | 決策 414「沒做的」 | 都是可做可不做；配樂等有第二首曲子再接 |
| 真正的機客分離：機車掛上、摘下、換端（要改列車模型與存檔） | 決策 252 | 長期；觀光列車（§15.3）之後再評估 |
| 觀光列車的後續：加價、故事（車種圖鑑）、季節、3D 模型（含真正的蒸汽機車）、到站旋律（含汽笛）；具名列車五款已做完 | 決策 286「下一步」 | 第一步（藍皮解憂號、海風號，停靠景點旁加 0.5★）#819 已合併；山嵐號（`SHANLAN`，數字照海風號）#826 已合併；鳴日號（`MINGRI`，E500＋豪華客車，停靠景點旁加 1★，3D 用現成的 E500 與黑色客車）#1045 已合併；環島之星（`STAR`，E500＋6 客車，加 0.75★，價錢在海風號與鳴日號之間，3D 用 E500＋粉紅客車）#1047 已合併；仲夏寶島號（另加一列 `SUMMER`，`STEAM` 不動；CT273＋莒光客車，加 1.25★，買得便宜、營運最貴、起步最慢，2D 黑色圓頭，3D 暫用現成機車外形塗黑金）在 `claude/tourist-train-summer`。具名列車做完；下一步照決策 286「後來（第四次）」最後一點的順序，一個 PR 一項：加價（先決定誰付）、故事、季節（不做開關）、3D 模型（含蒸汽機車）、到站旋律（含汽笛）。**3D 的蒸汽機車**：決策 399 把仲夏寶島號換成 #1103 的蒸汽機車＋煤水車（不稱 CT273），蒸汽列車 `STEAM` 用 #1118 |
| 2D 車頭形狀多一種「機車頭」（`TrainNose`、`MapArt.drawCars`） | 決策 252 | 小 PR；美術線有空就做 |
| 照班距派車的越行：照班次跑的線（決策 133）仍只用決策 59／294；慢車已出發、正開往的那一站不會改進待避股 | 決策 366「沒有做的」、決策 526「缺口」 | 待避股在外側時慢車留正線那一項，已由決策 526（LOOP-SIMPLE，`claude/loop-simple`）修好；剩下這兩項 |
| 台鐵示範延長到七堵或蘇澳 | 決策 240 | 併進 §15.3「支線劇本」 |
| 一日週遊券的後續：限某條線的票（收購的支線各賣自己的，像平溪線）、多日券、票的插圖（卡片現在用 SF Symbol）、多條線與距離制車資的平衡量測；出票聲（決策 373）之後可照授權明確的售票機錄音的頻譜再調 | 決策 324、373 | 小 PR；限線的票等收購支線（決策 315）有人玩再做 |
| 支線情境包：內灣線 → 深澳線 → 六家線、沙崙線（一條一個 PR，只加一筆 `BranchLineChallenge` 的資料、用報告量一次目標；六家、沙崙通到高鐵站，等高鐵示範那條線告一段落） | 決策 289「下一步」 | 第一條集集線在 `claude/branch-line-jiji`；做法、量法照決策 289 |
| 用 `tra_track_sections.json` 每段的 `tracks` 決定描線時預設單線或複線 | 決策 247 | **做了**（`claude/trace-track-count`，決策 247 的「後來」第二則）：整段照多數決一種。剩下：一次描線中途換線（複線段兩條、單線段一條，接頭加渡線），等玩家需要時再做 |
| 坡道上的 X 渡線（四個道岔加中間菱形交叉要同坡度，要動 GameCore 的交叉規則） | 決策 233、247 | GameCore，等玩家回報需要時再做 |
| 拉近才聽得到那一站的鈴聲（`zoomGain()`）＋鈴聲圈 | RAILWAY_SOUND §2.8、§5 | 併進聲音 2b（NEXT_PRIORITIES §14），和各站到站鈴一起做 |
| 跟車行駛聲的後續（決策 343 做了一般電車與高速兩種循環）：過彎的摩擦聲（曲線限速處，研究文件 §7.3 的第三種循環）、柴油車自己的循環（現在柴油車也播電車聲）、隧道裡的回聲；NEXT_PRIORITIES §22.2 第 7 名「聲音」：夜間快轉時配樂收小由決策 372 做了（下一步：實機聽 12 dB 與淡出 3 秒、淡回 1.5 秒是否合適），一日券出票聲是決策 373（雨聲雷聲由決策 346 做了） | 決策 343「下一步」 | 過彎聲要先找到能下載的授權錄音（Freesound 在雲端 session 回 403，維基共享資源原檔回 429；Internet Archive 的 radio aporee 可以） |
| 雨聲雷聲的後續（決策 346 做了雨、颱風風雨與雷三種聲音）：車站與隧道裡雨聲變小、雨天跟車時車窗上的雨、實機聽音量 | 決策 346「下一步」 | 實機聽感要作者在 TestFlight 聽 |
| 玩家建物旋轉；買入城市建物但不拆（P0-D 的另一半） | CITY_BUILDING_STUDY §5、§7 | 城市線，排在核心玩法之後 |
| 拍照模式 | GAP_RESEARCH §3 G | 和 3D 的主地圖整合一起考慮 |
| 平溪線運煤的史實版（O10） | FREIGHT_STUDY §6.4、§8-6 | 缺史料，誰去蒐集還沒定；支線劇本時再看 |
| 空白地圖用種子產生地形、遷葬費、依車種的坡度上限（阿里山要 6%） | TERRAIN_HEIGHT_DESIGN | 阿里山劇本（§15.2 第 7 名）時一起做 |
| 轉乘資料的明確配對沒有匯入（`station_transfers.json` 只在車站資訊裡顯示） | PHASE5、決策 65 | 寫實規則的加深 |
| 收班後車站自動切換營運狀態（`metroComputeStationAutoOperationMode`）沒有移植 | PHASE5 R1 | 寫實規則的加深 |
| 多次調車、無月台倒車、全域最佳解；中途折返的重疊段不拆名義容量 | STAGE_V、決策 63 | gap，維持不做，有玩家需要再說 |
| 預測未來的授權、畫面延遲式的閉塞保持 | STAGE_V、決策 64 | gap，維持不做（手動號誌在 NEXT_PRIORITIES §7 列為不做） |
| 行政區人口；街區與地塊點選、地塊資訊卡 | UI_GAP §7、§8 | 缺資料管線，城市線再評估 |
| 切開「自動」結構的軌道時各段重算（水域晚讀時切不開、明挖段上的建物沒拆） | PR200_290 §4-2，決策 124 | **完成**（決策 282）：兩段沿用原本的區段，只在切點分開。剩下：不是「自動」的結構物（例如地面）切開時照舊依地形與水檢查，之後才讀入的水仍會讓它切不開；沒有玩家回報，沒有改 |
| 滴管（點既有軌道沿用它的構造與高度）等 UX §8 剩下的小項 | UX_REDESIGN_STUDY §8 | 核心玩法的工具欄依解鎖顯示之後再評估 |
| 車站商業沒有逐線帳時，用「需求旅次 × 2」估人次，誤差沒量過 | STATION_COMMERCE §1.2 | 影響小，經濟平衡（economy-balance skill）下次量測時一起看 |
| 平衡待觀察表：飯店回本、觀光景點份量、城市委託份量、加線加站反而少載、車種取捨、公司建物 | ROADMAP 平衡待觀察表 | 核心玩法第 4、5 個 PR 量關卡目標時，用 economy-balance 一起看 |
| City Transport Manager 研究的 M0–M3（只顯示、只動 2D 的 GamePresentation 與 App，不碰 GameCore） | `docs/research/CITY_TRANSPORT_MANAGER_STUDY_2026-10-19.md` 4.0 | **M0、M1 做完**（session_01Vrym4SZSjubXNm9G5XhP3Y，作者 2026-10-20 交辦）：#835 草稿摘要列、#837 財務「今天」卡、#839 一鍵切換涵蓋層（決策 292）。**M2 做完**（決策 293，`claude/m2-next-steps`）：自由遊戲的六個「下一步」（第一條線 → 有一天賺錢 → 第二條線 → 一條線兩列車 → 轉乘站 → 涵蓋一半），地圖上一行、目標面板列全部，做到時打勾與目標旋律，不給錢。待實機確認：地圖上那一行在手機橫拿時擠不擠；TestFlight 問「第一條線花幾分鐘、看不看得懂下一步」（研究 4.0 的 M2 驗收）。**M3 做完**（決策 301，`claude/m3-line-satisfaction`，session_01QC2g3kh7JcDSjwFCDPMfct）：路線卡「乘客感受」三項（候車由班距估算、擁擠＝最擠一班的載客率、準點＝準點率），各 0–100 分與自己畫的三張表情，樣本不夠寫「尚未評分」，最差一項旁放決策 194 的加開列車；車型展示間加一行每營運小時的成本。待實機確認：手機橫拿時路線面板放不放得下分數與按鈕、表情在 20 點看不看得清楚。M3 沒做的（決策 301「沒選的」）：路線清單每列一張臉與照分數排序、乘車時間一項、全公司平均放在頂端。**「確認路線」卡做完**（決策 303，`claude/m4-confirm-line-card`，session_01QC2g3kh7JcDSjwFCDPMfct）：簡單規則下 ✓ 先升起卡片，名稱、顏色、首末班、四個時段各幾列與約每幾分一班、還要買幾列與總價，預設值等於原本的 ✓，開通用決策 264 的一個指令。待實機確認：手機橫拿時 `.medium` 的 sheet 放不放得下四個時段。沒做的（決策 303「沒選的」）：四個時段各自一個數字（要 GameCore 多一個等級）、選來回或環線、一次買超過起訖站停得下的車（要先有「車開出後自動補上」的規則）。**空窗快轉做完**（決策 305，`claude/night-skip`，session_01QC2g3kh7JcDSjwFCDPMfct）：夜裡沒有車時速度下面的「快轉到早上」，跑到第一列車動起來前 10 分，設定可以自動（預設關）。待實機確認：晶片在手機橫拿時和圖層列擠不擠；TestFlight 問自動快轉要不要預設開（研究 4.15）。沒做的（決策 305「沒選的」）：快轉時配樂收小、夜色實驗。M2 的第二階段（點一下領獎金）要 GameCore＋存檔，等 TestFlight 回饋再決定。M1 沒做的：研究 4.1 的潛力熱圖與白天／夜晚 |
| 潮汐第 2 步：住宅站早上進站多、晚上出站多（NEXT_PRIORITIES §19 第 10 名的後半） | 決策 319；研究 `RIDERSHIP_SOURCES_AND_TIME_OF_DAY_2026-10-20.md` §2.4–2.6；量尺 `Tests/GameCoreTests/TideReportTests.swift`（`TIDE_TIDAL=1` 量打開的） | **第 2 步做完**（session_017RbiiqGJTsLWDSz9q4Dukd，`claude/tide-switch`，存檔 67）：世界的開關 `tidalDemand`，新遊戲開，舊存檔、golden、示範、挑戰、入門關卡關；四個目標都達到（住宅站 07–09 進站 39.3%、進出比 6.8 倍、辦公站 6.0 倍、上班日 00–06 放出 0.9%）。強弱是 `StationDemand.homeShare`，由車站附近土地的居民 ÷（居民＋工作）拉開兩端（40%→0、85%→1000）；放出照每小時的中間。路線收班時少放旅客沒有做（深夜已經只剩 0.3%，理由在決策 319）。**還剩第 3 步**：實景地圖用內政部電信信令的鄉鎮日夜比（162907／162908）補上白天的人，寫進土地的工作（GamePresentation 與 App 內附的格網資料），`homeShare` 會自己跟著變，GameCore 不必再動；要解決鄉鎮同名（用代碼與界線）。沒有人接 |
| 自有建築第 2 批：~~學校、醫院（附近人口長得快）、夜市（併 §22.2 第 20 項觀光）~~（#1232，存檔 74，決策 361 的續；session_01B5ozUdytYk9yUcwwXXXUBj 壓縮第 2 次後停在等遊戲規劃審查，審查要再改的交給新的實作 session，照 361「續」的「下一步」與「獨立審查之後改的」；全圖第 200 天居民少 1.1%／0.9% 已由 session_01WBDhnK83mWG9wSxuSHvAtC 查清：一半是建物占的那格與收購拆掉的人，一半是學校附近提早長滿、時間往後移，第 800 天學校 +440、醫院 +175，不改規則，數字在 361 平衡一節）、貨運站（帶貨）、運動中心（接 Codex 的 RecreationKit：場館、健身、泳池，現在沒有對應的種類）；公園與廟的旋轉、夜裡的燈；廟與飯店互相加星；遊樂園的摩天輪與木馬會轉；小住宅、商店、辦公大樓的模型（量過太貴、尺寸不合，決策 398） | 決策 361「下一步」、決策 398「還沒做的」 | 第 1 批（公園、廟、外觀代碼、存檔 71）在 `claude/owned-building-kits`；飯店、百貨、遊樂園、漁人碼頭、遊艇港已接 EstateKit／CoastalKit（決策 398，`claude/owned-building-estate-coastal`，存檔不動）。下一批照決策 361 的做法加 `PlacedBuildingKind`、`looks`，存檔版本再加一 |
| 車站卡下一班分月台的後續：路徑偏好之外，用同一條線上一圈實際停的月台猜下一圈；真實列車有月台資料（TDX 即時看板）時照月台列；環狀線兩向終點相同時照下一站分方向（參考庫 klrt-board-directions） | 決策 354「下一步」 | 第一步（分月台、15 分鐘、沒車列下一班、真實列車照方向）在 `claude/station-departures-by-platform`；後續只動 GamePresentation，記上一圈月台若要存檔才動 GameCore |
| 挑戰劇情的後續：~~其他關的劇本~~（劉銘傳、集集線 #1126，三鎮、造鎮、大亨 #1138，都已合併）；平溪線劇本裡做不到的 6 項（豪雨停駛改公路接駁、天燈節分兩場不同站、疫情延期、菁桐古蹟限制、依年份換台詞、十分單線交會瓶頸） | 決策 387「下一步」 | 機制與平溪線劇本在 `claude/challenge-story`（session_01Wc5kRdeidS2jE66NSZg1n6）。新劇本只加資料；6 項裡前五項要 GameCore 的新事件或存檔，最後一項要打開這關的閉塞並重量目標，沒有人接 |
| 劉銘傳鐵路劇本裡做不到的 7 項：獅球嶺隧道兩頭沒對準、多花錢〔1〕；1888 年試車的圍觀人潮〔4〕；巡撫換人、預算被砍〔7〕〔8〕；坡太陡蒸汽車爬不動、1898 年改經竹仔嶺〔1〕〔4〕；淡水河氾濫沖壞木橋〔5〕；茶季的貨運〔5〕；1892 年外籍工程師回國、人手不足〔3〕 | 決策 387 第 9 節（〔n〕是那裡的出處） | 劇本與機制在 `claude/challenge-story-2`（session_01Wc5kRdeidS2jE66NSZg1n6）。都要 GameCore 的新事件、成本或施工規則（隧道與坡度、橋的損壞、臨時客潮、季節貨運、預算與人手），沒有人接 |
| 集集線劇本裡做不到的 6 項：2021 年邊坡崩坍壓壞隧道、停駛四年多改公路接駁，2026-01-05 回到集集（中文維基寫 2025-12-23 濁水—集集復駛）、6 月底到車埕〔1〕〔7〕；921 全線停駛到 2001-01-21〔1〕〔3〕；1926–1931 日月潭工程停工，工程貨運消失又回來〔5〕；丹大山的木材貨運〔2〕；搬移舊站房的建造功能〔3〕；2014 年和夷隅鐵道締結姊妹鐵道、外國旅客增加〔2〕 | 決策 387 第 10 節（〔n〕是那裡的出處） | 劇本與機制在 `claude/challenge-story-2`（session_01Wc5kRdeidS2jE66NSZg1n6）。停駛與接駁、依年份的工程貨運、木材貨運、搬站房、觀光客增加都要 GameCore 的新事件或規則，沒有人接 |
| 匿名的本機操作計時（附在「回報問題」裡） | CORE_LOOP §1.6 第 6 點 | 核心玩法第 4 個 PR（關卡）時一起做，TestFlight 才問得出「第 1 關花幾分鐘」 |
| 課程第 3、5～10 關要用到該關的工具才過關（session_01WRu24hbsQCqHu4ZnCV2ioW 重走課程時留下） | 決策 390「下一步」第 1 點 | 目標現在只有每日運量，和該關教的工具無關。GameCore 加 `Goal` 種類：一條線幾列車、複線長度、用機廠的路線、貨運噸數、景點遊客、完成委託。各關換上自己那一種，升 golden schema，金銀銅天數用 `LessonTargetReportTests` 重量。不在 GamePresentation 擋（決策 390 寫了為什麼） |
| 第 1 關的軌道與車站要到兩座城鎮才算完成 | 決策 390「下一步」第 2 點 | 現在只改了卡片的說法，沒擋。要擋得先在 Simulator 上把 `TutorialUITests.testBuildingTrackEnablesNextAndSkipEnds`（PR 必跑）與 `TutorialJourneyUITests` 改成點兩座城鎮：它們現在在畫面空地鋪 220–400 點長的一段。改好再把 `GameSession.holdsForPlaces` 放寬到空白地圖 |
| 課程站名 `S0`、`S1`、`S2` | 決策 390「下一步」第 3 點 | `CurvedOpening` 替第 2 關起的世界蓋的站，玩家看得到，名字像代碼（第 5 關的提示還寫「點「S1」旁…」）。要照語言命名得把語言傳進 `GameWorld.newGame(lesson:)`，或改用和玩家自己蓋的站一樣的「車站 N」 |
| 第 11 關起的課程 | 決策 390「下一步」第 4 點 | 建議：**11 列車工具**（第 10 關開放了卻沒教：買車、放到軌道、指派路線，約 5 張，接第 10 關）；**12 票價與報表**（調票價、看月報與年報，約 4 張）；**13 借錢與還款**（約 3 張）；**14 存檔、遊戲速度與 3D**（約 4 張，也可拆進第 1、3 關的最後一張）。每關只教一件，照第 3～10 關一步一個動作 |
| 第 2、7 關新步驟的實機確認 | 決策 390「下一步」第 5 點 | UNVERIFIED：第 2 關「把…加入…」的按鈕在 iPhone 橫拿時捲不捲得進視窗、點不點得到；第 7 關的營運時間按鈕看不看得到。full lane 的 `LessonUITests` 沒有走這兩步，要加的話照決策 199 放 full lane |

### 7.3 3D 的後續

**網格自動簡化與太魯閣、EMU800 的遠景車（決策 420，session_014ZfTTK2BTKfrpKBYMPKmpP，`claude/mesh-lod-qem`）**：簡化器 `Map3DMeshSimplifier` 只在測試與比較裡，沒有接進畫面；太魯閣、EMU800 500–900 m 換程式版遠景車。量到的、建議與沒做的（自動簡化接進畫面要先加誤差上限、修單面板被收掉；裝置快取；照 #1271 的設備級選等級；其他車的遠景版；**700T 與 N700S-G 改用從近景配方產生的遠景版**，遊戲規劃 2026-10-26 補派、這張 PR 沒做）在 [決策 420](decisions/420.md) 的「下一步」。

**Meshy 第一批街道小物、簡化器補三件、glTF-Validator 進 CI（決策 467，session_01YGNNuqASY5sxbk5kKzVByD，`claude/meshy-batch-1`，10/31 後合）**：紅綠郵筒一對與公車站牌接進 3D 地圖（`tools/meshy-props/`）；簡化器加了誤差上限、鎖住單面板的轉角、`Map3DSimplifiedCache`（背景建、裝置快取），但 App 還沒用它畫東西；`tools/gltf-validate/` 與 `gltf-validate.yml` 查 repo 裡的 GLB。這批其他小物、方形郵筒重生成、簡化器接到畫面與小零件保護在 [決策 467](decisions/467.md) 的「下一步」。這個 session 壓縮兩次後停手（2026-10-28），PR #1446 留給下一位接手：草稿，10/31 後轉 ready 再請作者合；本機跑過的只有改到的五個類別與 `DataSourceCredit`（Linux 上 `--filter` 要寫類別名、不加 `GamePresentationTests.` 前綴，否則跑 0 個），其餘 3D 類別、Xcode 建置與 iOS UI 測試看 PR 的 CI；`gltf-validate.yml` 第一次在 GitHub 上跑 15 秒過。

**Codex 蒸汽機車＋煤水車（2026-10-23，issue #1103）**：作者回報前導輪區過空後，新增汽缸外罩／煙箱承座／導輪架共408三角，其餘原模型13,672三角逐頂點不變；真正前版與同相機局部對照在私庫history/front-before及previews/steam-front-side-by-side.png。本輪10張參考的獨立兩單元原生靜態素材，霧綠／石墨／金砂、無紅色。配方`Map3DSteamTender.swift`，入口僅靜態註冊；完整編組14,080三角。公開只配方／工具／必要測試／文件／一張總覽，完整native／GLB／35七向／白模／剪影／同尺度／真前後／viewer／來源與ZIP在私庫`Railway/game-art-previews/docs/art/steam-tender-2026-10-23/`。重建與外觀／技術結論見[本批交接](art/steam-tender-2026-10-23/README.md)與`tools/steam-tender/README.md`，兩庫互鏈draft PR與最新head CI見issue #1103。 作者續報#1106紅字：selected-1在20分鐘job上限取消（無測試失敗），已同步main的#1120五份測試／新權重；模型與素材producer仍為1da739ca，原生／GLB逐bytes核對保持。最新CI狀態與timeout證據見#1103／#1106；不重複改CI分份規則。Linux Swift6.4 warnings-as-errors與20相關測試、實際幾何／支承／故障拒收、GLB／PNG／viewer／ZIP已驗證；真機Metal／效能／動畫及工程尺寸／真實車型仍未驗證。不改GameCore／存檔／golden／replay。**合併只增加靜態素材，不會讓營運列車自動換成這台**；車型映射、煤水車跟隨與連桿動畫是另案，不擅稱CT273。

**第二台霧藍雙走行組蒸汽機車＋煤水車（Codex，#1118，`codex/duplex-steam-2026-10-23`）**：新11圖逐張檢視，靠前駕駛室／前短煙箱後長鍋爐／兩組三個近等大輻條輪／前欄杆平臺／獨立煤水車，獨立`Map3DDuplexSteam.swift`，不依賴未合併第一台。修初版汽缸偏小、前階輪區重疊及前梁／踏階支持；真前版、同相機公尺對照保留。24.830×3.300×4.680m／11128三角為比例推估，型號／工程規格／隱藏鉸接未知。[外觀／技術／私有交付](art/duplex-steam-2026-10-23/README.md)、[重建組裝](../tools/duplex-steam/README.md)。VERIFIED Swift6.4 warnings-as-errors、20測試、封閉／法線／支持射線／輪組淨空／492實體接觸圖、六故障拒收、5native／5GLB／35七向、Blender／PNG／viewer／ZIP。真機Metal／效能／動畫UNVERIFIED；僅靜態註冊，合併不自動出現在營運列車。雙draft PR與最新head CI見#1118；無GameCore／存檔／golden／replay變更，不合併／auto-merge／TestFlight。

**七節暖白霧藍低裙板都市電車（Codex，#1094，`codex/seven-car-blue-2026-10-23`）**：作者新七圖，兩端＋五中節近等長，端每側1／中每側2雙門、九屋頂箱、單端集電弓；獨立`Map3DSevenCarBlue.swift`，不是前批長短交替七節或四節底盤改殼。只新增靜態註冊。最終54.679×2.731×4.120m／13968三角為展示推估；隱藏28軸是補全假設、確切型號／工程尺寸不足。已修下裙露輪過多、車頭下方與接節下緣缺口，全部門窗玻璃逐三角不變。[外觀／技術／私有ZIP與viewer](art/seven-car-blue-2026-10-23/README.md)、[特徵與重建組裝](../tools/seven-car-blue/README.md)。10native／10GLB／70七向、實際白模／剪影／同相機前後在私庫。VERIFIED Linux Swift6.4 warnings-as-errors、19相關測試、原生讀回／精確組裝、封閉邊／真實殼支持／輪頂50mm淨空與遮擋／接節連續、六故障拒收、Blender／PNG／viewer。真機Metal／效能／動畫／工程規格UNVERIFIED；合併不會自動替換營運列車。無GameCore／存檔／golden／replay變更；兩庫draft與最新CI見#1094，未合併／auto-merge／TestFlight。

**Codex 四款列車接進營運（決策 399，session_01MTVUoTThcFpBwCqex6bNyb，`claude/codex-trains-into-service-399`）**：仲夏寶島號＝#1103 機車＋煤水車＋莒光客車；蒸汽列車 `STEAM`＝#1118＋藍皮客車；線性馬達捷運 `L`＝#1081 四節（12.3 m 節距）；輕型捷運四節＝#1094 七節段。四種都照模型的長度畫（`Map3DModelPack.layout`），後兩種在列車包。兩台蒸汽只在 500 m 內畫模型。**還沒做**（之後一個 PR 一項）：
- 連桿、動輪轉動、集電弓升降等動畫：動之前先讀 `.claude/skills/motion/SKILL.md`（決策 253 的 Reduce Motion）；動輪要照列車的速度轉，連桿跟著動輪，車在站裡停住時不動。Codex 的配方把每個輪組做成獨立的零件（`components(_:)` 的 role `wheel`），可以從那裡拆出來做成實例。
- 實機看：蒸汽列車在 500 m 換成方塊時跳不跳、跟車與駕駛室視角時多幾萬個三角形的幀數（決策 399「量到的」）。
- 汽笛（決策 286「到站旋律（含汽笛）」）。
- 七節霧藍只有輕型捷運四節用到；四節金砂的 `middleRear` 沒用到（形狀與 `middleFront` 相同）。磁浮、輕型單軌、單軌照舊是方塊，四款都不合（有輪子、轉向架）；阿里山林鐵的真實列車（決策 339）也照舊是方塊，要等 Shay 式的模型。

**四節暖白金砂都市列車（Codex，#1081，`codex/four-car-metro-2026-10-23`）**：作者新五張圖，四節等長傳統轉向架，與前批五／七節輕軌不同。獨立`Map3DFourCarMetro.swift`；四節每側兩組雙門、16軸、近直立兩端、橫向風擋、雙緩衝塊／中央連結器。每節12m為比例推估，全bounds50.130×2.802×3.694m／7912三角；中心x±18.45、±6.15m，只平移。已修第一版偏長、風擋偏高與輪頂重疊；[外觀／技術、私有成品與限制](art/four-car-metro-2026-10-23/README.md)、[重建與組裝](../tools/four-car-metro/README.md)。7原生／7GLB、49七向、同相機前後、白模／剪影、viewer與ZIP在私庫新目錄。VERIFIED Linux Swift6.4 warnings-as-errors、20測試、原生／組裝／GLB、封閉邊／玻璃支持／20mm輪淨空、缺面／反面／玻璃浮空拒收、PNG和viewer；真機Metal／效能／動畫及工程尺寸UNVERIFIED。**只註冊靜態素材，未綁營運車種，合併不會自動替換路網列車**；後續整合按12.3m節距。無GameCore／存檔／決策／golden／replay變更；兩庫draft PR與CI見#1081，未合併／auto-merge／TestFlight。 作者續報門不好看與無法合併：只修淺暖灰門葉／寬窗／腰帶，門外逐三角不變；門同相機前後與door-verification在私包。原selected-2超過20分鐘已定位，最新main同步後重跑；驗證完成後依作者合併意圖轉ready，不代合併。

**五節改色＋七節輕軌（Codex，#991，公開draft #992／私有draft #40，`codex/five-section-lrt-2026-10-22`）**：作者要求兩台都不要紅，最終五節暖白綠松／七節暖白霧藍。新增獨立七節配方`Map3DSevenSectionLRT.swift`，長—短—長—短—長—短—長，2/0/2/0/2/0/2雙門／側、六鉸接、單端集電弓。五節保留尺寸／門位／輪位／設備／編組，只改色並修trailing側窗沿錯誤對角造成的破口；其餘三角與前producer5a2fd38e逐位元比對。最新[外觀／技術及私有包](art/lrt-pair-2026-10-22/README.md)、[重建／共同軌面／組裝](../tools/lrt-pair/README.md)。12單元＋2編組＋2比較、112七向、白模／剪影／同相機五節改色與七節窗面修訂、viewer／ZIP在私有新目錄lrt-pair-2026-10-22，舊包不覆蓋。VERIFIED Linux Swift6.4 warnings-as-errors、28相關測試、原生組裝／GLB、12單元封閉邊／216主要玻璃承板與車殼支持、六種故障案例。七節45.5m是比例推估，隱藏四架八軸為補全假設；真機Metal／效能／動畫／工程尺寸UNVERIFIED。**兩台均為靜態素材，未綁營運車種，合併不會自動換路網列車**；整合須按各節長度／共同軌面，不能當一般七輛車。不改GameCore／Map3DTrainSets／營運／存檔／決策／golden／replay；最新CI以#992 head為準。未合併／auto-merge或TestFlight。

**高鐵兩款與 E200 接進營運（決策 408，session_01EYjQttfohUR8HPL2aYisHw → session_01Bbe7HnLfcUGdoE2VRgZgoU，`claude/decision-408-hsr-trains`，#1217）**：高鐵單號是 N700S-G（前兩版自己重做外形使用者都說醜；第三版是作者的 mesh 減面＋遊戲色票，`Map3DN700SG.mesh(_:)`，`tools/hsr-trains-408/decimate.py` 從私庫 checkout 讀原檔產生 `Map3DN700SGMesh.swift`：頭 5,965、中間 5,000、集電弓車 4,992 個三角形，一列 61,914，只在 500 m 內；500–900 m 換第一版平塗重建 `n700sGFar`，一列 6,872）、雙號是 #1201 的 700T（照原樣，每節 25.2／25.5 m，500 m 內；500–900 m 換 #900 的舊 700T `highSpeedFar`）；莒光號的 E200 是 #1201 的新車頭。資料來源頁加「白色高速列車」。合併前作者要看過預覽（PR 上「先別合併」）。**還沒做**（之後一個 PR 一項）：
- 玩家每列選高鐵的款式：要在存檔裡記（存檔版本加一），現在照列車號碼單雙分。
- 實景時刻表的列車照自己的長度畫（現在照舊用 `Map3DRealTrains.carPitch` 拉伸）。
- 實機看：700T 一列 74,528、N700S-G 74,202 個三角形在跟車、駕駛室視角的幀數；500 m 換成遠景模型時跳不跳（兩款的遠景決策 422 換成從近景做的，§7.5）；N700S-G 近看窗角與門邊的小白碎片（減面留下的）明不明顯，明顯就把 `decimate.py` 的頭車預算調高或中間車改成不加權。
- N700S-G 的 B、E（門位、E 的鰭）沒有畫，中間車都是 C：要讓 set 有好幾種中間車。
- E200 的遠景模型（現在 900 m 內都是 5,512 個三角形）；舊的 `Map3DTrainLocomotive.e200` 不再被 set 用到，可以一併清掉。
- 作者的 N700ST（橘色，私庫 `Railway/n700s-n700st-2026-10-24/n700st/`）沒有接；要接時同 N700S-G：`decimate.py` 加一組 `UNITS`／`COLOURS`。
- **使用者給的參考照片（2026-10-25，減面版實機檢查時對照用；在 session_01EYjQttfohUR8HPL2aYisHw 的對話裡）**：六張真的台灣高鐵 N700ST，有側面線圖、700T／N700ST 並排的海報、出廠與卸船的照片。照片有著作權（線圖是 CC BY-NC-ND，其他是新聞與官方宣傳照），**不放進任何一個 repo**，只照下面這些特徵檢查減面後的樣子：
  - 鼻：長而低、上下扁的「鴨嘴」，鼻尖寬而圓。兩側從車身肩部往前有一道銳利的稜線，把鼻分成上面的圓背與兩側往下收的「翼」（N700S 的 dual-supreme-wing，700T 沒有這道稜線）。
  - 駕駛室：一個獨立凸起的透明圓罩，在鼻的後段，四周是黑色的玻璃框。
  - 頭燈：細長的「眼」，在兩翼的稜線上、鼻的中段，不是在鼻尖。
  - 下半：鼻下與裙部是一整片淺灰（不是黑），從鼻尖一路接到轉向架。
  - 車窗：小，四角圓，一排間距大；門在頭車駕駛室後面。
  - 真車的塗裝是橘帶加一條深藍細線，在門附近往下斜切到裙部；遊戲的 N700S-G 照作者給的深綠兩條線（決策 408 不叫它 N700ST），要不要另做橘色的 N700ST 由接手的 session 依五方決定。

**列車建模照 700T 升級（使用者 2026-10-25：「寫一份 700T 參考後更新現有 3D 製作模組……寫出更新腳本讓列車產生更好看」；新工作，交給新 session，本 session 已壓縮兩次）**：#1201 的 700T（`Map3DTrainShapeRefresh.refreshHighSpeed`）使用者說「好漂亮」，要把它的做法搬進現有的列車建模，讓用建模產生的列車一起變好看。新 session 先在 #1041 認領（新決策號、存檔／golden 不動）。
- **2026-10-25 做了：決策 410**（session_0184ajQAx9BPLKw475Jw1G5U，`claude/train-modeling-410`）：新的共用車殼 `Map3DTrainShell`，樣式五款、場景套件的電聯車、客車與遠景高鐵都改用它；`SceneKitCab` 的車身與 `CabSurface` 刪掉；`Map3DTrainBuilder` 原封不動，只留給 N700S-G 的遠景。`refreshHighSpeed` 沒有改呼叫共用函式（照下面「會變就先複製一份」，700T 逐位元不變）。斷面一圈 32 段（遠景 16），不是 700T 的 40 段，也沒有搬 `swell`：預算內放不下。留下與刪掉的、量到的、下一步（實機幀數、太重就加 `nearOnly`＋`far`、紅臉特急的紅臉、照車輛建模手冊 #1224 逐款量車頭收窄與肩部包絡、逐款的轉向架資料）在 `docs/decisions/410.md`；手冊的自檢結果也在那裡，自檢圖在私庫 `Railway/game-art-previews/docs/art/train-modeling-410/review/`；重畫前後圖與自檢圖用 `tools/train-modeling-410/`。做這件事的 session 壓縮兩次後停在 #1227 等作者看總覽，下一步由別的 session 接。下面幾條是派工時的說明，留著對照。
- **要改的**：`Map3DTrainBuilder`（`Sources/GamePresentation/Map3DModels.swift`，決策 230；`Map3DTrainStyle.all` 的 commuter、express、highSpeed、metro、peopleMover，與 `Map3DTrainSet.multipleUnit` 每一款場景套件列車的中間車），與 `SceneKitCab`（`Map3DSceneKitCabs.swift`，那些列車的頭車）。
- **700T 好看在哪**（逐項搬，每項一張前後對照）：
  1. 斷面：超橢圓（`surface(x,a)`，側面指數 0.58、上下 0.65）一圈 40 段，車身圓潤；現在 `ring(at:t:)` 段數少、角硬。
  2. 鼻：沿車長一張高、寬的表（`dimensions(x)`），再加肩部隆起（高斯 `swell`）與下方整流罩（`ease`），鼻的輪廓是量出來的曲線，不是 `drop`／`lift`／`tuck` 三個參數。
  3. 塗裝：色帶照多邊形精確切開（`clip`、`hullParts`、`nosePaintParts`），邊緣銳利、順著鼻往下收（`bandHeight`），兩端蓋板同樣切開，不留 T 形接縫；現在是頂點色依高度上色，邊緣會暈開。
  4. 窗：圓角（`refreshRoundedOutline`，十二點）、外框加內嵌玻璃兩層（框比玻璃大 0.07 m），貼著車身的曲面（`flank`）；現在是方塊。
  5. 風擋：照鼻的曲面映射的圓角梯形，玻璃分小格跟著曲率、四周黑框，有車身在後面撐住，不是一片貼片。
  6. 燈：燈罩加兩顆真的燈（`tunnelLamp`），貼在鼻面、沿面的切線擺；頭車白、尾車紅（`Map3DTrainSet.lit(_:front:)`）。
  7. 顏色只用調色盤（`Map3DPalette`），霧面平塗、每個三角形自己的法線（`.flat`）。
- **要守的**：
  - 700T、E200、N700S-G 的 `refresh-*` 模型一個位元組都不變（決策 408 那次用的頂點 FNV checksum 測試，比對完不 commit）。
  - Codex 的列車（列車包、蒸汽機車等）不碰。
  - 三角形預算：建模的列車很多、多數沒有遠景，中間車建議 ≤ 2,000、頭車 ≤ 4,000（現在約 400–1,100；700T 是 5,600–9,100，只在 500 m 內畫）。超過時同決策 408 加 `nearOnly` 與遠景 `far`。
  - 先讀 `.claude/skills/art-style/SKILL.md`。
  - `Map3DTrainSetTests` 的三角形與尺寸範圍、`Map3DModelTests`、`Map3DSceneKit*Tests` 跟著改，並寫明為什麼。
- **怎麼做比較穩**：把 700T 配方裡跟車型無關的部分（超橢圓斷面、多邊形切色帶、圓角窗、曲面風擋、燈）抽成共用的函式。`refreshHighSpeed` 改呼叫它們時，checksum 要不變；不變就改呼叫，會變就先複製一份。`Map3DTrainBuilder` 再用同一組函式，一次換一項、每項出前後對照圖（`tools/hsr-trains-408/` 的 export 與 `render.mjs` 可以照抄），給使用者看過再合併。
- **參考**：私庫的 `Railway/train-shape-refresh-2026-10-24/`（#1200／#1201 的照片與七向圖），`docs/art/train-shape-refresh-2026-10-24/README.md`。

**接手**：3D 生活感 session 做完第 2 節的四步之後，由遊戲規劃排序。

| 項目 | 出處 |
| --- | --- |
| 三台列車統一遊戲配色（Codex，作者追加要求） | [三台配色總覽與前後對照](art/train-colors-2026-10-22/README.md)；暖白綠松電車／暖白霧藍通勤車／暖白柔綠都市車。三配方僅改顏色，8 單元＋3 編組幾何逐頂點相同；最新私有整合包取代舊包的配色版本，既有 ID 不改 |
| 新參考三節都市軌道車（Codex，#987；三節的通勤電聯車用它，決策 331（續四）） | [本批外觀／技術驗收及私有素材連結](art/three-car-urban-2026-10-22/README.md)；[重建、單元組裝與 viewer](../tools/three-car-urban/README.md)。三單元共 12 軸，每側兩組門；兩庫 draft PR，真機 Metal／效能未驗證 |
| 車輛素材跨 session 生成交接（原生配方、七向素材、驗證與兩庫 draft PR；從本批圓弧中巴往後續作） | [可直接複製給新 Codex／Claude 的完整 prompt](art/VEHICLE_ASSET_HANDOFF_PROMPT.md)；依當時 #231 與 PR merged 狀態選 base |
| 移軸（tilt-shift）效果 | 決策 229 |
| 路塹被 64 m 的地面格蓋住，地面沒跟著軌道切開 | 決策 229、231 |
| 隧道與地下月台（作者 2026-10-22「隧道跟地下月台……現在看會破圖」）：決策 359 做了第一步（隧道裡的玩家列車不畫、跟車鏡頭留在地面上），續一（session_014NB8yWZmutMBX3jDsXC3Sm）畫了隧道本體、隧道燈、新的隧道口，隧道裡的車畫回來。還沒做：(1) 隧道口與路塹接上地形（門框在 11–20 m 深的路塹裡被地面格蓋住，平地的門框孤零零；參考 `tunnel-portals.js`、`tunnel-apertures.js`）；(2) 地下月台（同一個 session 的下一個 PR）與地下的車、軌道、月台透視開關（再下一個；參考 `map3d.js` 的 `live-underground-3d`） | 決策 359 的「下一步」與「續一之後還沒做」 |
| 背面剔除先關著，之後要打開（`Map3DMetalView.swift:299` 還是 `setCullMode(.none)`） | 決策 229 |
| 3D 列車的集電弓、車門把手 | 決策 230 |
| 磁浮、懸吊、單軌、蒸汽沒有 3D 樣式，還是方塊（莒光號、藍皮、推拉式自強號、普悠瑪、太魯閣、EMU800、柴油客車已有模型，決策 318）；機車拉長到和客車同長、集電弓畫成降下 | 決策 230、252、318 |
| 影子不跟太陽方向偏移、建物彼此不投影、月台與雨棚底下沒有影子：決策 357 的太陽陰影貼圖做了（省電畫質仍只有決策 232 的團狀影子）；列車、行人、車輛還不投進貼圖 | 決策 232、357 |
| 站前商店街（決策 322）的後續：招牌的字與店一間間關燈已由決策 352 做了；代表站（35 站）沒有店；廣場被路或軌道切開的車站（十分）沒有店；店不放到城市地塊（要動決策 234、235） | 決策 322 |
| 架空線（決策 326）的後續：中間股道沒有門型架或吊架（車站套件有 `catenaryPortal`）；公路橋下的線沒有壓低（`rails.js` 有）；非實景地圖上玩家蓋的柴油支線也有線；接觸線高度與桿距照東京參考、不是臺鐵規範；號誌機、轉轍器還沒放；三貂嶺、十分一帶的軌道在高度檔的地面下約 6 m（原有問題，架空線在那裡不畫） | 決策 326 |
| 車站套件（決策 321）的後續：站房可能壓到實景底圖的道路（基隆）；高架站只有樓梯口、沒有高架下的大廳；站房跨在軌道上的橋上站房；真實站體輪廓（OSM `building=train_station`）沒有用 | 決策 321 |
| 地面的斑馬線、停止線、車道線（新的地面層要插進第 4.1 節的高度順序） | 決策 241 |
| 3D 的「地圖風格」設定（換配色） | 決策 241 |
| `tools/glb-to-m3dmodel` 靜態橋接已實作（`codex/glb-meshopt-bridge`）：`bridge.mjs --manifest` 讀 meshopt／量化 GLB 與 `.gltf`＋外部 `.bin`，用節點白名單、非 AI 來源／SHA 與 `recolorLightPaint: false`；只用固定版本的 core／extensions／meshoptimizer（五包 MIT），不用 functions。拒收貼圖、skin／動畫／morph 等；原 Meshy 入口與 #803 公車成品逐位元相同。接手從工具 README 與自製 `fixtures/static.manifest.json` 開始；App 接入、美術重組／配色、素材授權與實機幀數仍交 3D session，本工具 PR 不代表素材採用。之後另開 WorldCover 只上色圖層（參考庫 `build_worldcover.py` 與圖磚）與香港無貼圖量體任務 | `docs/research/PEAKLINE_MAP_ENGINE_STUDY.md` §8（#821）；補充與修正 `docs/research/PEAKLINE_STUDY_SUPPLEMENT_2026-10-19.md` §1–§4（#820）；轉換器原本是 Codex 的線（第 2 節） |
| 3D 畫面追上網頁試作（NEXT_PRIORITIES §22.10，3D session_01ShaLWGSyEn9fYcNjS8j5Gz 開工、2026-10-22 換手給 session_01H2iSUj5f1cCXAwjvuFvbsp 依序做）：(1) 天空漸層、太陽、星星月亮做完（決策 347，`claude/map3d-sky`；實機還沒看）；(2) 色調映射的肩部、網頁版的調色、貼地的薄霧做完（決策 349，`claude/map3d-grade`；泛光之後放 `Map3DQuality.high`；實機還沒看）；(3) 招牌、LED 看板、霓虹做完（決策 352，`claude/map3d-signs`，session_013jxDFuuw3kiAu4McNsCyBz；併 rank 15；實機的字大小、幀數、iPad、台中的預覽還沒看，見決策 352 的下一步）；(4) 路面標線（斑馬線、停止線、箭頭）與街道小物（號誌、公車亭、自動販賣機）做完（決策 355，`claude/map3d-road-markings`，session_019qs5F2dh6bGZjb9uzCs47j；實機的幀數與清晰度還沒看，號誌不輪替，見決策 355 的下一步）；(5) 玻璃與水面的反光（天空的 Fresnel、日光反射、夜裡玻璃映出城市燈、水面波紋）做完（決策 356，`claude/map3d-fresnel`，session_0136FXagwq4pwPNs3d9vWUHN；實機的強弱與幀數還沒看，波紋還有點規則，見決策 356 的下一步）；(6) 太陽陰影貼圖做完（決策 357，`claude/map3d-sun-shadow`，session_01NbDKX8YtpretK8Bbz6iq5V：太陽方向的深度圖，太陽轉半度、目標移四分之一格或場景換了才重畫；省電畫質不畫；iPad／iPhone 的幀數與 GPU 時間還沒量，見決策 357 的下一步）。§22.10 六項都做完；各一個 PR、各領一個決策號；不搬 AO、SSR、背景、地標、塔；鳥與飛機之後 | 決策 347、349、352、355、356、357 |
| Metal 的色調映射與泛光（作者說留待以後；2026-10-22 作者要網頁試作搬進遊戲，§22.10 把色調映射排成第 2 項，決策 349 做了肩部與調色；泛光仍留待以後） | `docs/art/map3d-night-terrain-2026-10-16/` |
| Fenn 3D 研究的建議，照順序，一次一個 PR，都在現有的 Metal 裡做：(1) 夜晚與黃昏的泛光＋色調映射，就是上一列，作者說留待以後，所以排到作者要時再做；(2) 實景建物依面積與樓層挑台灣的外牆樣式，補屋頂設備與一樓店面（`Map3DRealBuildings.swift`，可寫 Linux 測試）；(3) 假光貼片：車頭燈、廟與店面往上打的光、招牌光暈。不換 MapLibre、Apple Maps 或 wgpu，不搬 Kenney，手機不開 AO 或高解析度陰影 | [FENN_3D_WORLD_STUDY_2026-10-19.md](research/FENN_3D_WORLD_STUDY_2026-10-19.md) §5（#824） |
| 台北市中心 3D 建物很少：決策 345 已補。只有道路經過的格子改在路旁的空地蓋小一點的樓，台北車站一帶 433 個地塊從畫 73 個變 406 個。剩下的：實機看幀數與縮小的樓；台北的真實建物（決策 239 的管線多編一區，App 多約 2 MB）；河道與部分公園仍整格拿掉或不讓開。量法：`MAP3D_FRAME_REPORT=1 swift test --skip-build --filter Map3DFrameCostReportTests/testTaipeiLots` | 決策 345 的「沒有選的做法」與「下一步」 |
| 3D 跟車（決策 333）、看板點車飛到月台（決策 334）與駕駛室視角（決策 337）的後續：駕駛室內裝（眼睛照參考坐進車裡）與遠處路面會不會閃；在 3D 點列車開始跟車；實機看 85° 的「後方」會不會被建物擋住；真實列車（台鐵、高鐵）的看板也飛到月台，等 §22 的 3D 真實列車；月台邊的圈會不會被雨棚擋住 | 決策 333、334、337 的「下一步」 |
| 深度閃爍與擋住列車的建物（決策 342）的後續：實機看遠處路面還會不會閃、淡掉的建物好不好看、改畫的 chunk 多花多少 GPU 時間；台北市中心補建物之後再量的被擋比例已寫進決策 345（看線旁 120 m 6.5%，都看得穿）；圓錐沒有淡入淡出；真實列車前面的建物不透明 | 決策 342 的「下一步」與「沒有選的做法」 |
| 3D 的真實列車（決策 339）的後續：真實車站的月台與站房（真實列車現在停在沒有月台的地方）；車站卡「下一班」的真實列車版（§22.2 第 5 名後半，要替真實列車另開不是 `TrainID` 的頭）；真實軌道上的架空線；照實際車長；列車包（決策 338）合併後確認鎖住的 set 畫成方塊 | 決策 339 的「沒有選的做法」與「下一步」 |
| 3D 駕駛室（決策 380，85.1 實機影片）：架空線放進 coarse 的 chunk、鏡頭的方向用軌道配的拋物線，兩個都在 Linux 修好。還沒做：跟車時列車附近的 chunk 多半是 coarse（城市簡化，影片三角形 100 萬 → 29 萬），決策 368 的視窗來不來得及補成完整的沒量；2D 的列車方向沒改 | 決策 380 的「下一步」 |
| 3D 場景的記憶體（決策 368，83.1 跟車閃退）：真實地圖只在鏡頭 2 km 內蓋完整城市，板橋 1.8 GB → 763 MB。剩下最大的是遠看的簡化城市（板橋 1,050 萬頂點，約 450 MB）；App 上傳 GPU 後還留著 CPU 那份陣列，放掉可再省一半。之後加城市細節前先跑 `Map3DSceneMemoryTests.testThe3DMapRoundBanqiaoFitsAPhone` | 決策 368 的「下一步」 |
| slop-newyork（MIT）的 3D 做法能搬哪些（研究 session_01JxqePZhgA9tQuajjP9gsPm，2026-10-23，只有文件）：建議排序 (1) 城市方塊改實例，先做 `.far`（板橋 763 MB → 約 320 MB，估）；(2) 太陽陰影貼圖用 `.far` 當替身；(3) 小零件放進固定大小的池、依像素大小剔除；假室內與合成聲音列「之後」。等 §22.2 10e 與畫風 (e)（決策 370）都合併後由遊戲規劃派 | [SLOP_NEWYORK_3D_2026-10-23.md](research/SLOP_NEWYORK_3D_2026-10-23.md) §5、§6；排行照 [NEXT_PRIORITIES](research/NEXT_PRIORITIES_2026-10-12.md) §22.15 |
| slop-newyork 補充（session_01UvQcP14umjdnDYpqc14Ngx，2026-10-26，只有文件）：10-23 的三件都還沒做，前提已合併，可由遊戲規劃照原順序派；另加第 4 件「紅綠燈照時鐘變燈」（決策 355 的號誌現在固定一亮綠一亮紅；GamePresentation 純函式、不留狀態，合決策 259；秒數照台灣有來源的時制，含全紅），車子停紅燈是第二步另派。IDM 跟車、行人排隊、新的行人與車輛物理不搬。第 4 件改 `Map3DRoadMarkings.addStreetStops`，和第 1 件的 session 協調 | [SLOP_NEWYORK_UPDATE_2026-10-26.md](research/SLOP_NEWYORK_UPDATE_2026-10-26.md) §3.1、§4 |
| 台灣 3D 參考包 TW3D（參考庫 release `Tai`，session_01UvQcP14umjdnDYpqc14Ngx，2026-10-26，只有文件）：slop-newyork 改的台北真實比例城市。五方排出 10 項；第 1 項「紅綠燈照時鐘變燈、台灣式燈頭」3.10，從 §22.2 第 15 名拆出來先做；第 2 項傍晚垃圾車〈給愛麗絲〉2.95。解開放在參考庫 `Railway/tw3d-reference-clean/`（railway-reference-private#89）。**第 1 項的第一步做完**（派工單 K，決策 429：燈照遊戲時鐘綠黃紅輪流、路口分 4 組錯開、60× 以上不換）；倒數、小綠人、有聲號誌、台北號誌清單、車停紅燈還沒做，見決策 429 的「下一步」 | [NEXT_PRIORITIES_2026-10-12.md](research/NEXT_PRIORITIES_2026-10-12.md) §22.12、決策 429 |
| 兩批生成素材：generated-2026-10-13（43 張）、micro3d（24 張），沒接進 App，也沒有「採用或放棄」的紀錄 | `docs/art/generated-2026-10-13/`、`docs/art/generated-2026-10-14-micro3d/` |

**會動的東西共用預算（決策 417，session_01LPDBFT4sZKR1HK3w7FuKB5，#1271）**：做完了三角形預算、設備三級、從低往上爬並記在裝置上、CPU／GPU 分開降、街景與路線公車的上限、設定每個選項一句。**還沒做**的在 `docs/decisions/417.md` 的「下一步」：用 TestFlight 實機數字校準三級的上限；沒有遠景模型的列車（太魯閣、普悠瑪、EMU800、C381）與公車的遠景版；新的精細 E500／太魯閣照決策 417「新的精細車」的三條規則（一定帶遠景版、一節超過 20,000 三角形才做中間版、量記憶體）；higher 看得更遠；ProMotion 120；強的設備跟車 60×；記憶體警告時放掉遠處的場景塊。

**卡頓量測與顯示層驗證（遊戲規劃 2026-10-26；作者同意 V1＋V2，決策 421；V3 暫不開工）**：`docs/research/FRAME_TIME_AND_ENGINE_SPIKE_PLAN_2026-10-26.md`。作者接受暫時不全面換引擎，要「先修現有問題」（V1 幀時間紀錄進問題回報、V2 固定測試場景）與「長期是否自研」（V3 RealityKit 同場景對照與 Unity／Godot 橋接成本，不進正式 App）分開；先前「卡頓不是引擎造成」「87.1 疑似記憶體」都是 UNVERIFIED，更正在該文件 §0。

### 7.4 開發工具

**接手**：遊戲規劃排序。第 1、3 項對核心玩法的量測有用，可以在第 4 個 PR（關卡）之前開一個 session 先做。

| 項目 | 出處 |
| --- | --- |
| 無頭模擬入口 `GameSim`（指令：new-game、load、apply、advance、dump）——決策 260，#740 已合併 | GAME_AI_TOOLS §3.1、MOTION_3D_TOOLS §4 |
| 3D 截圖時一起輸出每幀時間與 draw call 的 JSON | GAME_AI_TOOLS §3.2 |
| 腳本化玩法框架（`Policy`）＋自動試玩，列出異常——決策 261，#748 已合併 | GAME_AI_TOOLS §3.3、MOTION_3D_TOOLS §5 |
| 文件數字一致性檢查：存檔版本、golden schema、golden 個數——#760 已合併，`python3 -I tools/golden-checks/doc_numbers.py --check` | GAME_AI_TOOLS §3.4 |
| 官網與社群說明短片的 skill | MOTION_3D_TOOLS §2.3 B |
| 在 macOS 上跑一部分套件測試，比對 Apple libm 的浮點值 | GAP_RESEARCH §4.2 |
| 測試用的參照模型擴充到全網選路（`ReferenceWorldGoldenTests.swift:130` 還是 `preconditionFailure`） | GAP_RESEARCH §4.2 |
| 跟著相關的 PR 一起加的工具（作者 2026-10-20 交給 session 判斷時機）：pixelmatch 差異圖 → 下一個改 3D 畫面的 PR；glTF-Validator → Meshy 公車接進 App 的 PR；OR-Tools 車輛運用量尺 → 決策 297 合併後、還有說不出原因的取消時；`performAccessibilityAudit()` → 實機 VoiceOver 有問題時。做那件事的 session 照表加，不必再等作者同意依賴 | GAME_AI_TOOLS §6.3 |
| `ci.yml` 的 rest shard 撞 20 分上限（2026-10-23，session_01KcZCRGFREEAx22ncMXAMwJ，`claude/rest-shard-under-limit`）：main 43852fa 的 rest 有 953 s 測試、469 類，沒有一類特別大（最慢 5 類共 172 s）。6 s 以上的 GamePresentation 類別與 25 s 以上的 4 個 GameCore 類別（共 33 類、約 466 s）搬到 campaigns-16／-6／-15／-12（PR #1087），rest 在 PR 的 run 上 510 s；不加 shard、不改 timeout。campaigns-7 自己的兩個 campaign 一次 354 s、一次 603 s，搖擺很大，不要再往裡面放東西。**之後**：rest 再長，照 `swift-shards.sh` 的時間表註解再搬（run 摘要的「Slowest classes」只列 5 類，要整份 job log 才看得到每類時間）；小的 GameCore 類別不要搬，campaign shard 點名的類別在 `pr_plan` 會被當成「改到的 campaign」，讓改它的 PR 跑全套 | `swift-shards.sh` 2026-10-23 later 的註解 |
| campaign shard 再平衡（2026-10-23，session_01KcZCRGFREEAx22ncMXAMwJ，`claude/campaign-shards-under-limit`）：#1087 合併後 main 4d2c8ce 的 run 39932184002 上 campaigns-10 job 19.0 分（測試 891 s）、-11 812 s、-15 793 s。只搬 GamePresentation 類別（不改任何 PR 的 tier）：TRADemo → -3、RealWorldDemo → -4、Map3DStreetLife／StationCommerceCard／Map3D／LineLossDiagnosis → -6、RealRailwayTracing／Map3DStreaming → -13、NetworkPostcard／NewGameSaveProperty 回 rest；FlexDispatchPropertyTests（GameCore、自我測試用到）不動。不加 shard、不改 timeout。**之後**：同一組類別在不同 runner 上可差到 1.9 倍（campaigns-1 一次 384 s、一次 738 s），看分片空間要用它最長的那次；campaigns-1、-2、-14 最長已 12.3–13.5 分測試，不要再放 | `swift-shards.sh` 2026-10-23 after #1087 的註解 |
| rest 再次撞 20 分上限與分片容量（2026-10-24，session_016VsuVC61edGEaS3rfsHJkS，#1184 與決策 404）：main 82fffc7 的 rest 被取消（15m03s 測試，新的 Map3DPlatformClearanceTests 113 s 沒被點名）；Map3DSceneMemoryTests 實際 274 s，權重卻寫 57。#1184 把 5 個 GamePresentation 類別搬到 -11／-1／-4／-12／-8，rest 剩 9m19s 測試。決策 404 讓分片的 job 用到 15 分時印警告、到 18 分 30 秒印出最慢的類別，權重錯了也會警告。#1186 加了第 18 個分片（全綠，-11 的 job 19m33s）。決策 404 的 PR（#1189）試了每片 `swift test --parallel`：本機 4 核把 839 s 的分片縮到 423 s，但 CI 的 full-ci run 40106343236 裡 -11 逾時、-17 與 rest 變慢（每個測試在自己的 process 裡，類別的 `static let` fixture 每個測試重建一次），所以 `SWIFT_TEST_WORKERS` 退回 1（session_01PGYZVEDnKApav7UJwBzzRT 接手）。**之後**：以類別為單位的平行與分片合併，寫在決策 404「下一步」，沒排 | `docs/decisions/404.md` |
| full lane 的餘裕（2026-10-23，session_01GaPJUuAAMyqKsvxJjpnhEf，PR #1140）：main b6ca9af2 的 full lane（ios-build.yml run 40020950220）紅了三個，判為慢 runner。(1) 「UI tests, second」撞 50 分上限：三次都有跑的 40 個測試合計 09640f5（run 39957090683）28.1 分 → 0149127（run 39992945211）34.6 分 → b6ca9af 46.4 分；測試數沒變，先跑的（20:53–21:16）慢了 2–5 倍，後面的持平，暖機也從 1.5 分變 3.6–5.3 分。正常要 41–44 分，離上限不到 10 分。(2) `ShellLayoutUITests/testTheStatusBarKeepsItsWidthAsTheDaysGoBy`：在 main ff8e4dd 用 only_testing 重跑（run 40032432984）綠，但 6000× 的觀察迴圈用了 65 s（0149127 是 28 s），換日來得晚，餘裕小；#1139 的 G1 會減少 6000× 的 CPU 負擔。(3) 同一晚 ff8e4dd 的 nightly（run 40026341039）紅的兩個 SettingsUITests（音效開關與音量、回報問題附存檔的開關）**不是**慢 runner：在 main 6b28e76 用 only_testing 重跑（run 40044073708）一樣紅在同幾行。原因是決策 381 在設定最上面加了語言區、說明下加了資料來源，手機橫放時音量列和附存檔開關落到更下面，List 還沒捲近就不建那一列；畫面拖動的 24 次也不夠。修法（分支 `claude/settings-tests-landscape`）：附存檔開關多拖幾次（`dragUntilWhollyOnScreen` 新增 `drags:`，這裡給 40），音效開關先切換再往下找音量；拖 List 自己左緣在橫放時捲不動，不用。綠（run 40047802171）。(4) 2026-10-24（session_01VZJVMsPVmSxC3WeNiv9Yuw，PR #1150）：從 09640f5 到 584bddd 六次 full lane 的 log 逐類加總，`RealWorldMapUITests`（13.9 分，慢 runner 11.7）從 second 搬到 build job，second 的 UI 步驟上限 50 → 55（跟 lessons 一樣；job 上限仍 75）。分支上跑一次 full lane（run 40055148286，d0c0376）：second UI 步驟 27.1 分／55、lessons 38.1／55、build 60.0／75（RealWorldMapUITests 在裡面 15.3 分；job 71.8／95），三個都留 10 分以上；build 唯一的紅是 main 上本來就紅的 HUDAlignment `menu.more`，不是逾時。**之後**：加新的 UI 測試類別先看三個 job 誰在 b6ca9af 那種慢 runner 上還留 10 分（數字在 `FULL_LANE_SECOND_JOB` 上方註解），放那裡；都放不下就用 `Class/testMethod` 把大類別（MapInteractionTests、LessonUITests、StartSaveFlowSmokeTests）按方法拆到別的 job，再不夠才問規劃要不要第四個 job；狀態列測試在正常 runner 上再紅，先看 6000× 主執行緒的負擔，不要放寬門檻。(5) 2026-10-28（派工單 BD，session_01YGNNukhJnBuFzBv2ipaCEu）：`4d08067` 的 full lane（run 40616551940）second 撞 55 分，停在 SettingsUITests 拖找 `settings.report.attach` 的中途（那支才跑 43 秒），不是卡住：同一批 49 個測試比 `f70a4cb` 慢 1.67 倍（1914 → 3198 秒），同一 commit 的 lessons、build 都正常，是那台 runner 慢。smoke 的紅是第一支 `CoverageShortcutUITests` 的 App 啟動（Xcode launch）66 秒逾時，App 一行都還沒跑，其他 7 個 job 的第一次啟動都在 25 秒內。second、lessons 的 UI 步驟上限 55 → 75、job 75 → 95（和 build job 一樣）；之後加測試仍照上面「留 10 分」的規則放。(6) 2026-10-28（派工單 BR，PR #1418）：`97badad` 的 full lane（run 40656903835）build 的 UI 步驟 65.5／75（`f70a4cb` nightly 74.4），不到留 10 分。五次 full lane（40559683307、40592891253、40616551940、40634118390、40656903835）逐類加總：build 最多 62.8、平均 54.5（RealWorldMapUITests 13.7–19.0、StartSaveFlowSmokeTests 12.5–16.3），second 53.3／45.6，lessons 51.5／41.6。`StartSaveFlowSmokeTests` 按方法拆：英文與繁中開始存檔流程、兩個蓋了再存的測試（平均 6.2 分）到 lessons，列車與車型選單、刪壞存檔、語言選單（3.1 分）到 second，其餘五個留在 build（`FULL_LANE_SECOND_JOB`、`FULL_LANE_LESSONS_JOB` 可以放 `Class/testMethod`）。分支上跑一次 full lane（run 40668230502，179ea7c）：UI 步驟 build 50.3、lessons 58.0、second 59.2（上限 75，最少餘裕 15.8；那次 second 的 runner 偏慢，MapInteractionTests 28.8 分）。second 重跑兩次才綠，都不是分配造成：`SettingsUITests.testTheCityPreviewLoadsItsPageAndCloses` 網頁 60 秒沒載入（其他五輪都綠）、Simulator 裝置找不到（沒跑測試）。`HUDAlignmentUITests.testAStationsPanelKeepsTheLines` 在 97badad 紅的 `kAXErrorIPCTimeout` 是 Simulator 無障礙查詢逾時，7 天內只紅一次，測試沒改；再有第二次沒有程式原因地紅再照 diagnosing-bugs 查。之後 second 的下一個類別先放 build（平均 45 分，最空），lessons 的 LessonUITests 時間起伏最大（23.6–42.4），別再往 lessons 加 | `ios-build.yml` 的 `FULL_LANE_SECOND_JOB` 註解；PR #1140、#1150、#1418 說明 |
| 86.1 的 full lane（2026-10-24，session_01NDDS2s5myyGvhD26ZW26zB，`claude/full-lane-86-1-fix`）：main 584bddd 的 run 40051175469 紅四個，都不是 App 的退步。`HUDAlignmentUITests` 的說明測試還在點決策 383 拿掉的 `menu.more`（292db69 也紅），改成直接點 `menu.help`；其餘三個是慢 runner 上測試太緊：`StartSaveFlowSmokeTests` 的列車選單選好 Train 5 後收起，2 秒前列出的那一列再讀就失敗（`touchable` 改讀 snapshot），`MapInteractionTests` 改名欄一次查詢要 4 秒、5 秒只看了一次（等 20 秒，仍然不點欄位），`LessonUITests` 第 5 課的「略過」在卡片滑入時按空（還在就再按一次）。**再後來**（同一 session，`claude/lesson-pause-retry`）：#1153 分支的 full lane（run 40060038516）第 8 課的 `pause()` 按了 Pause、5 秒沒看到 Resume（按空），改成時鐘還在走才再按（最多 3 次，每次等 10 秒），`showGuide()` 也不再只給卡片 2 秒。**之後**：同一類「元素在列出與讀取之間消失」的失敗，照 `touchable` 用 `try? snapshot()`，不要加長等待 | 這個 PR 的說明 |
| TDX（運輸資料流通服務）查資料：`.github/workflows/tdx-check.yml`——#850 已合併。Actions → Check TDX API → Run workflow，`path` 填 `/api/basic/` 或 `/api/advanced/` 開頭的 API 路徑與查詢（預設台鐵第一個車站），回答在 run 的 artifact `tdx-response`（保留 7 天）。session 用 GitHub 工具觸發（`actions_run_trigger`，`tdx-check.yml`，ref `main`）再下載 artifact。金鑰是 repository secrets `TDX_CLIENT_ID`、`TDX_CLIENT_SECRET`，只有這個 workflow 讀得到；不要貼在對話、不要存進 repository。TDX 有票價、時刻、站表、路線色，沒有各站運量 | #850、決策 298 |

### 7.5 只等實機確認的

這些不擋任何工作，在 TestFlight 的「請測試者看」裡輪流問：
- 時間軸卡住（玩家回報 91.1，決策 143「後來（2026-10-27）」）：高雄實景、很多列車，第 2 天 06:00 前後換速度，時鐘應在幾秒內走過 06:00，速度選單按下就顯示新速度。還卡就在那一局用「問題回報」送出存檔與卡頓紀錄（決策 418）。
- 高鐵的遠景車（決策 422）：高鐵示範或實景地圖開一列 700T、一列 N700S-G（單號），跟車後把鏡頭往後拉，過 500 m（弱裝置或負荷重時 250 m）換遠景時：顏色與車頭會不會跳（以前 700T 會從綠松帶變橘帶，現在應該看不出來）；N700S-G 在 250–500 m 的風擋是不是太大太黑、車門邊有沒有白點。明顯就照決策 422「下一步」調 `tools/hsr-far-422/n700sg_far.swift`。
- 會動的東西的預算（決策 417）：各機型在 `Map3DPreviewScreen` 除錯數字列（或問題回報的「3D 地圖」那行）爬到哪一格、幾條線開始少街景；跟車時會不會忽多忽少；iPhone 17 是不是還頻繁當機。數字回來調 `Map3DDeviceTier.triangles`。
- PLAYER_FEEDBACK 標「待實機確認」的：54.1 的兩位玩家、56.1 的大多數則、59.1 之後美術線的三件事（選取列車的黃框、建物徽章會不會疊、建造面板好不好捲）。
- 61.1–68.1 各版請測試者看的項目。
- 到站鈴的聽感，以及幾個音軌一起循環時會不會漂移（RAILWAY_SOUND §11）。
- 56.1 #5：教學第 5 步的卡片蓋住 HUD，在 Linux 沒重現。教學之後會併進關卡（決策 254），到時一起看。
- 實景地圖的轉乘站（決策 298，#851）：新遊戲選項的「現實路網：轉乘」開關看不看得到、實景地圖是不是預設開；車站卡第一行「從…轉乘：每天約 N 人」在手機橫拿時會不會被截斷；在台北車站等大站旁蓋站，玩起來覺不覺得旅客變多（量出來第 14 天多 3–12%）。
- 問題回報的卡住紀錄（決策 418）：實機玩到卡一下（或從背景回來被重開），隔天按「回報問題」，訊息最後有沒有「這台裝置記下的卡住與結束」一段；照決策 418「怎麼讀」用那個 build 的 dSYM 換一層 `RailwayGame` 的位址，看換不換得出函式名。沒有那段就查 MetricKit 是否要「與 App 開發者分享」打開。
- 畫面節奏紀錄（決策 421 V1）：TestFlight 新版裝上後，先在 2D 地圖玩一兩分鐘（切幾次速度），再開 3D 環繞、跟車各一分鐘，回 2D 後按「回報問題」，看訊息最後有沒有「這台裝置最近的畫面節奏」一段：要有 3D（「3D 上螢幕間隔」，有沒上螢幕的格數、CPU／GPU、三角形）與 2D（標明「2D 節拍…不是上螢幕的時間」）兩種，各有中位數、p95、p99、三段停頓次數、嚴重停頓與最長停頓。玩到明顯卡一下的話，看最長停頓有沒有對到那一下、2D 那段有沒有寫是哪一部分。記憶體一行在實機要有 MB 數（模擬器沒有「最少剩」）。讀法見決策 421。
- 畫面節奏測試（決策 421 V2）：TestFlight 版的設定裡連點「版本」五下，演示模式下面多一列「畫面節奏測試」，列出台北 1／5／10／20 線 × 2D 平移縮放、3D 環繞、3D 跟車共 12 項。每一項跑三次，每次之前先把 App 從多工畫面滑掉（冷啟動），再進設定按那一項：它開新遊戲、鋪線（20 線要等一兩分鐘）、等 5 秒、自己動一分鐘，期間不要碰螢幕，最後上方的卡片寫 p95 與嚴重停頓次數。三次跑完，清單上那項寫「3／3 次」，p95 差超過 20% 或嚴重停頓次數不同的標「不穩定」（橘字），那項要重跑或注意當時有沒有發燙。全部跑完按「複製結果」貼回來，或直接「回報問題」（結果附在訊息最後）。要確認的：3D 環繞時鏡頭真的繞著台北轉、跟車時真的跟著一列車、2D 時地圖左右上下畫 8 字並縮放；結果一行有沒有寫裝置型號；模擬器跑的要有「只當 CPU 端的參考」。
- 放空模式（決策 414）：選單最後一列「放空模式」找不找得到；放空時 3D 與 2D 切換有沒有閃白或卡頓；碰一下回來時按鈕是不是都回來、暫停狀態和打開前一樣；「減少動態效果」打開時只在 2D；開著 VoiceOver 放空時，左右滑還讀不讀得到收起的按鈕（UI 測試在放空時仍找得到 `hud.menu`，只是碰不到：`ambientHidden` 只設透明與不接觸，若 VoiceOver 也讀得到，要再想不改變 view 身分的隱藏法）。
- 2D／3D 交接（決策 313）：「拉近自動變 3D」預設開，放手才判斷之後是不是還會誤進 3D。常誤觸就把預設改成關（`Map3DHandoff.pinchOpensKey` 的 `@AppStorage` 預設值，在 `MapView.swift` 與 `SettingsView.swift`），不必重做；也看 3D 左上的「2D」「建設」兩顆鈕找不找得到、會不會擋到景。
- 3D 開在 2D 看的地方（2026-10-21，決策 313 的「後來」）：高鐵示範從台北按 3D、實景新遊戲按 3D，是不是都開在 2D 看的地方；2D 移到很遠再按 3D，等候是不是只有第一次。
- 3D 的列車標籤與路線色帶（決策 314）：拉近到 400 m 以內，畫面中間最多三列車頭上的「線號＋載客／定員」標籤大小、位置對不對、跟著車走順不順；軌道旁 0.3 m 的線色細帶看不看得到、會不會閃。標籤太小或太擠就調 `Map3DTrainLabels` 的 `reach`、`most`、`middle`；色帶太細或太粗就調 `Map3DLineBands.width`。
- 3D 駕駛室（決策 380）：高鐵示範 1× 與 10× 的駕駛室，開到平地、水邊時電桿與線是不是一直都在；直線上鏡頭還會不會左右抖。
- 3D 跟車不再閃退（決策 368）：高鐵示範在台北、板橋一帶 600× 跟車切 3D，不再被殺；鏡頭快速移到 2 km 外時，城市先是遠看的樣子，一兩秒內補成完整的，看補的過程明不明顯。
- 3D 的 CPU 與 GPU（2026-10-21，決策 238 的「後來」）：
  - 統計面板多了「wait」一行，CPU 不再把等畫面（drawable）的時間算進去。
  - GPU 連續 1.5 秒超過 10 ms，就降到每點 2×2 像素，面板的 wait 那一行後面寫現在是幾倍。
  - 下一版請作者在同一個台北畫面記下時刻再看一次：
    - CPU 是幾 ms、wait 是幾 ms：CPU 掉到幾 ms、wait 有 10 多 ms，原本量到的就是等螢幕；CPU 還在 16 ms 上下，就用 Instruments 的 Time Profiler 找。
    - 降到 2× 之後 GPU 是幾 ms、畫面會不會跳一下、窗格看起來會不會太軟。太軟就把 `Map3DDrawScale.budget` 調高，或改用 MetalFX。
    - 兩組 GPU（2–4 ms 與 10–12 ms）為什麼差這麼多。
  - 設定的「3D 畫質」（決策 238 的「再後來」）：省電是不是真的少發燙、30 fps 看起來會不會卡；低耗電模式下自動有沒有改成省電（面板的倍數變 2×）；高畫質在 Pro 機上會不會燙到被系統降頻。
- 地圖提示整理（決策 310）：快速圖層多了「車資與章」一格之後，iPhone 直拿時和「快轉到早上」、下一步晶片排在一起放不放得下；地圖上只剩「滿載」章，看起來會不會太少。UI 測試交給 Codex（寫在決策 310）。
- 刪除路線賣掉列車（決策 327，2026-10-21 的玩家回報）：路線面板的「刪除」確認卡寫的列車數與金額對不對；拆月台或軌道被沒有路線的列車擋住時，訊息條的「出售」按鈕在 iPad 與 iPhone 上看不看得到、按不按得到；回報的玩家說地圖上看不到那列車，測試裡它停在第一站月台外約 6 m，要在實機上看它畫出來沒有。
- 藏太深的功能拉上來（決策 383，86.1）：≡ 選單第一層那排「說明／回報問題（／目標或觀光景點或更多）」在手機橫放時三項放不放得下、字會不會被截；路線頁最上面的「整個路網」會不會把線列表擠得太下面；列車卡多了「暫停列車／恢復列車」「折返」之後手機上是不是換成兩排、會不會蓋住地圖太多；建設第一排五顆（「高架、坡度、曲線」「複線」「吸附軌道」「沿真實鐵路」「清除」）手機橫放時排幾排。太擠就照決策 383 的「沒選的」再調。
- 找得到的入口（決策 336，#982 與第 26 名的 PR）：路線面板的「可收購的真實路線」與沒有可買時的那一行、車站面板最上面的「收購○○線…」、資料面板「今天」下面的貸款與票價、地圖左下有字的「擴建地圖」膠囊（手機橫拿時會不會擠到圖層鈕或縮放鈕）、建造時「這塊地還不是你的」旁邊的「擴建地圖」（✕／✓ 小卡變寬後會不會出畫面）、狀態列的景點星、列車卡的「時刻表／車隊總覽」、軌道卡的長按提示。另外 §22.9 沒查證的：選單第一層「明信片／成就」那排在手機上會不會只剩圖示。
- 3D 的公車（決策 400 續篇 10i-6）：空白地圖與實景地圖各開一條有車的公車路線，拉近到 1 km 內，看公車是不是沿街道靠右開、在站牌與車站前停、條紋是不是那座車站的線色；街上的車碰到公車會讓開（變小消失），看起來會不會太突然；統計面板的 CPU 多了多少（Linux debug：20 條路線每幀不到 1 ms，第一次鋪路 0.24 s）。
- 3D 的範圍（作者 2026-10-21 問要不要放大到整張 16 km）：先維持前後左右各 6 km（`Map3DScene.reach`，最多 12 × 12 km；#899 之後移到哪建到哪）。3D 畫質設定（#902）合併後，請作者在台北遠景量降到 2× 之後的 GPU；還有餘裕才只在「高畫質」放大到整張地圖，其他兩個選項不變（遊戲規劃 2026-10-21 代為決定，PLAYER_FEEDBACK 78.1 #10）。

**Codex E200／700T 第三版鼻部（#1200，`codex/train-shape-refresh-2026-10-24`）**：已依使用者指定參考PR#1203與私庫E201四向渲染；E201非已確認Codex來源只作參考，不搬來源mesh。鼻部／風擋／雙燈罩／圓角窗薄門、E200輪架／屋頂／踏階已修，暖白綠松保持。6合法M3DM＋自含單元組裝JSON＋7GLB／49七向／白模剪影／同尺度與真正d476304b前後／viewer／ZIP在私庫原目錄新增revision-2，舊包保留。約7萬三角編組不塞進15,000上限；JS重建與Swift三角payload逐bytes核對，單元仍由原生ModelFile讀回。[外觀、驗證與交接](art/train-shape-refresh-2026-10-24/README.md)。20相關測試與Swift6.4 warnings-as-errors、原生／封閉朝向／缺面反面浮空及組裝偏移拒收、玻璃支承／輪胎淨空抽檢、Blender／PNG／viewer／ZIP已驗；完整碰撞／設備接觸圖／真機Metal／效能／動畫未驗。**仍是靜態素材，合併不自動替換營運E200／高鐵**（2026-10-25：決策 408 已把第十版的 E200 與 700T 接進營運，見 §7.3）；無GameCore／存檔／golden／replay變更。互鏈draft#1201／私有#70、最新producer與CI見#1200；不合併／auto-merge／TestFlight。

#1200第三輪：使用者指出鴨嘴不足，只修頭尾x±9.5以外鼻殼，前緣前伸1.05m並保留寬扁截面；完整bounds長306.5m為造型推估。E200／middle／panto／比較車native和GLB逐bytes不變，頭尾各5768後段三角不變；真正7096130e前版、四向同尺度前後與完整包放revision-3，舊revision-2保留。測試先紅後綠（20測試）；仍靜態素材，不替換營運，不合併／auto-merge／TestFlight。

#1200第四輪：使用者附700T照片明確指橘色前唇／肩帶。上一輪誤加長整鼻已撤回，重建有局部外鼓的肩部與連續包前緣綠松帶；暖白、原風擋／燈／門窗／輪架保持。真前版39b819a3留history及舊revision-3，私庫新包revision-4。E200／中車／集電車／比較車native、GLB逐bytes相同，頭尾各5768後段三角不變。仍靜態素材，合併不替換營運；最新producer／CI見issue1200。

#1200第五輪：回應使用者綠色帶忽上忽下。維持05248513的實際殼面，只把原三角共面切分、以相切三次曲線控制白／綠松邊界，平順接車身；無外掛片或漸層。新測試在真前版8處失敗，修後21相關測試通過；paint-audit逐新增三角檢查原面內／面積一致，輪廓未變；其他單元／5768非殼面後段三角保持bytes。真前版及完整revision-4保留，私庫新revision-5；仍靜態素材、合併不替換營運，最新producer／CI見issue1200。

#1200第六輪：使用者附六圖並指定已合併N700S GLB。已確認公開1203／私有71合併，實際取私庫main的railway-n700s-a.glb在Blender匯入與四向白模研究；只學截面關係，未搬來源頂點／貼圖。六張圖前五為模型、第六實車側面，均實際看；本輪修700T下肩留寬、白鼻罩收窄與隨形包前唇綠松邊界，確實有殼面幾何變化，不沿用第五版車殼不變結論。真前版7c3dbc4a與完整revision-5保留，私庫新revision-6；門窗／風擋／燈／輪架5768後段三角及其他單元native／GLB維持bytes。新增測試真前版三項失敗、修後21測試通過；重建與原生局部白模見工具README。仍靜態素材，合併不替換營運；最新producer／CI見issue1200。

#1200第七輪：依使用者即時更正，白車身／鼻罩／門葉與玻璃保持，綠松主色帶搭55mm黑細輔線；先前黑車身只是未提交本機試稿，未交付。細線在原面內共面切分，paint-audit證明每個新增三角原面內／覆蓋一致，colour-audit鎖定綠松面與燈組bytes、E200／比較車native／GLB不變；實際車殼表面、bounds、編組保持，但三角數因分色增加須看manifest。真262bc3ef前版與完整revision-6保留，新包revision-7。IMG4456立面插畫已看且記署名／CC BY-NC-ND，僅視覺參考不取圖素描摹散布，各中車差異仍未完整重建。配色對比見UI_THEME自有段落，21測試與最終素材重驗，仍靜態不替換營運；最新producer／CI見issue1200。

#1200第八輪：使用者指出黑色風擋方框太高。已重新實看四張700T實車照／前輪附圖，只修頭尾風擋罩上緣位置、高度／寬度／圓角與細緣；沿原鼻面有背板，白車身／綠松主帶＋黑細線、車殼肩部、燈／門窗／輪架及編組保持。原生量測白車頂留邊0.025→0.324m、罩高1.239→0.974m，為展示座標非工程尺寸；真前版測試四項失敗、修後22測試過。windscreen-audit每端只改1296罩緣三角，其餘7012bytes不變，其餘單元native／GLB不變；真2b7eb826及完整revision-7保留，新包revision-8。聚焦正面與四向同尺度前後／來源／重建見工具README；仍靜態不替換營運，最新producer／CI見issue1200。

#1200第九輪：實際查看使用者新附IMG_4456.jpg正面模型圖並重看700t-2實車近照／700t-1斜視。修頭尾x≥3.7m的圓角收窄黑罩、上玻璃／兩支簡化雨刷及實體支點、略內收燈位；白鼻尖尖V改圓底U，下裙板作閉合殼面延伸並收薄深色區，修正中央色界接點。原白車身綠松黑線色票、鼻長／外包bounds、門窗／輪架和編組保留；E200／中車／集電車／比較車native與GLB逐bytes相同。真前版f60f0d92完整留history/f60f0d92，revision-8不動，新包revision-9。Swift6.4 warnings-as-errors及23相關測試，新測試真前版先紅兩項；front-audit核對修改範圍、前輪上緣40點正面包覆（4→40）與白鼻尖變寬，原輪組淨空保留。最終原生四向配色／白模／剪影、真正同相機同尺度前後、全部七向／GLB／viewer／ZIP皆重建；細節與限制見tools/train-shape-refresh/README.md及私包verification。新圖非工程照，原圖不散布；仍為靜態素材，合併不替換營運也不會自動出現遊戲。互鏈draft#1201／私有#70，最新producer與實際CI見issue1200；不合併／auto-merge／TestFlight。

#1200第十輪：再看使用者新附IMG_4456.jpg（與前輪同SHA）及700T實車近照，確認鼻尖綠色過大。僅修改頭尾鼻部分色，白鼻罩向下延伸、綠帶收薄並接回原車側，保留原殼面／鼻長／bounds、風擋燈雨刷、輪架門窗設備和編組；其他四單元native與GLB完全同bytes。真前版0ef6c1c8留history/0ef6c1c8，完整revision-9保持，新私包revision-10。分色交點保留色界值，避免重算非線性場造成T接點／微小退化面；原生封閉朝向及獨立GLB需重驗，livery-audit核對實際殼面雙向共面交疊面積與5mm移面拒收、綠色正面投影範圍縮減及修改只在鼻部白綠黑，並非相似度分數。新增白鼻罩不能停太高的回歸；原有白鼻尖固定寬度／綠色固定高度的歷史塗裝斷言改為仍有窄綠邊及兩側包覆，配合此次擴白收綠目標；其餘幾何／共存／輪軌／組裝維持。最終四向配色白模剪影、真正同尺度前後、全部原生／GLB／七向／viewer／ZIP重新輸出並查看，重建與技術限制見工具README／私包verification。24相關測試與實際producer／最新CI各自記錄issue1200；完整碰撞／真機Metal／效能／動畫仍未驗。仍靜態素材，合併不替換營運也不會自動出現遊戲；互鏈draft#1201／私有#70，不合併／auto-merge／TestFlight。

**Codex 原生車輛製作流程文件化（使用者2026-10-25要求，接續#1200）**：使用者接受第十版後，要求詳細寫出讓不同AI可重複使用的流程。[完整手冊](art/native-vehicle-modeling/README.md)、[可貼製作指令](art/native-vehicle-modeling/PROMPT.md)、[獨立驗收表](art/native-vehicle-modeling/REVIEW_CHECKLIST.md)、[700T實例](art/native-vehicle-modeling/CASE_STUDY_700T.md)已整理；art-style與原素材／工具README加入口。涵蓋真參考判讀、資料缺口、比例／斷面／鼻肩曲面、貼合門窗、色帶面積與穩定切分、輪軌／編組、同相機真前後、匯出／producer／viewer／ZIP、外觀與技術／CI／真機分開記錄。700T數值僅個案，不能套成所有車的車體或預算。素材交付時靜態，後續#1217／決策408已由Claude接入；本輪只文件，不改模型／工具執行碼／遊戲映射，不動決策410的共用建模實作。新文件分支codex/native-vehicle-modeling-guide-2026-10-25從main6a6352b4開；文件鏈結／格式查核與文件PR的實際CI分別記錄，不重跑建模或新增真機驗證。

TEMU1000 原生外形（Codex，初版 issue #1228／公開 #1230／私庫 #78 已合併；本輪 issue #1299）：新附正面、側斜與實車照片均已目視；**本輪真前版** `7efa16f6` 原生端車留私庫 `history/7efa16f6/`，現行同相機／公尺尺度前後圖以它比較。本輪風擋上移並按原殼三角裁切，恢復實車照片可辨的屋頂雙燈，兩側燈改斜深色細紋，補細雨刷；輪盤、側窗、殼頂、車體及八節排列保留。**接手先讀** `docs/art/temu1000-2026-10-25/PRODUCTION_HANDOFF.md`，再讀 README、私包 manifest/source-record/verification；PR checks 看最新 head。此為已接入 `taroko` 營運 3D 顯示的**靜態**造型修訂，新版須公開修訂 PR 合併才生效；GameCore、存檔、fixtures 不變。正面下鼻仍偏方、綠弧中心偏低、側斜風擋偏長；真機 Metal／效能／動畫未驗，外觀尚未經作者認可。
後續使用者指出「黑色跟圓弧要往下移」：Codex 在同分支下移端車風擋與鼻端斷面，讓正面腰線下垂且側線於鼻端漸降；真前版 `3f697206` 另留私庫 history，本版前後對照改用端車相機。外觀仍待作者評價；真機 Metal／效能／動畫仍未驗。
再補的正面／側面裁圖顯示端面還是太平：Codex 在同分支縮短鼻端直面、加密並鼓起圓弧端面，玻璃與腰線跟著真曲面；真前版 `d793874b` 存私庫 history，另出車頭側／斜近景與同尺度對照。最新外觀與重建見上述 README；真機限制不變。
再依使用者明列的輪盤過大、側窗不見及正面灰面偏心：Codex 將輪盤縮至展示半徑 0.33 m 並維持軌面接觸、客窗換成分格可辨玻璃、限制灰屋頂材質在車頭上方且鏡射兩側殼面。真前版 `cea94afc` 留私庫 history，新側窗輪組近景、同尺度前後與各項外觀／驗證仍見上述 README；工程輪徑與真機 Metal 未驗。

**Codex EMU3000第三版（#1226／draft #1229，私有draft #77）**：使用者要求車頭比例及車門破圖修正。真正23a59907／完整revision-2保留，新包revision-3；前裙／白下巴延伸圓收、黑罩改正面U形分色，車寬長／輪組／窗位／設備／編組保留。舊門可重現玻璃被殼面／門葉遮住；白殼作門葉、封閉薄門縫與玻璃按真正截面貼合，新增實際射線回歸先紅後綠及埋入玻璃變異。全量重出原生／GLB／七向／白模剪影／同尺度前後／門部放大／viewer／ZIP。驗證、實際producer、三角及最新同head CI見[自有交接](art/emu3000-refresh-2026-10-25/README.md)與issue交付，外觀自檢不代表作者認可，Linux不代表Metal/FPS。公開PR含營運替換接點，未合併不會出現；靜態幾何無動畫。保留#1227共用builder與#1233的emu3000Classic等舊版，列車包解鎖／回退分派由Claude後續處理，本輪不改其清單。GameCore／存檔／golden／save／replay／玩法不動；不推main／不合併／auto-merge／TestFlight。


**Codex EMU3000第四版（同#1226／draft #1229／私有#77）**：使用者只說側面下巴偏長並補ED側圖。本輪僅微抬／收緊低白鼻與鼻罩縫，保持上部黑罩／風擋／燈／車門／車身／輪組／設備／編組。12件近遠中間車原生payload全同；端車只在x>7.9、z<1.1m位置變更，所有顏色／layer／三角數／總bounds保持，法線依實際最終三角重算。真e25474ff／完整revision-3不動，新包revision-4，同尺度真前後與全部最終素材重出；外觀／技術／最新同head CI及重建見自有交接。仍無作者認可或工程復刻宣稱；不推main／合併／auto-merge／TestFlight，不動GameCore／存檔／fixtures。


**EMU3000第四版最新範圍更正（同#1226／draft#1229／私有#77）**：使用者隨後明確要求「繼續修車頭修到跟圖片一樣」，本版最終改為按新ED側示意校正圓隆艙頂、持續下降斜鼻、鼻下角、三角側窗、乘務／前客室門，風擋燈雨刷重新貼合。f6a010f0只是未完整交付中途小修，不當作最終版本。真第三版e254／完整revision-3保持，revision-4最終producer及最新CI見自有交接與issue。12中間單元payload全同，端車走行／設備／後部保持，全部素材重匯重驗；外觀自檢不是使用者接受。其餘遊戲／存檔／fixtures／classic／列車包分工與禁止合併發版等契約保持。

**EMU3000第五版（#1226／draft#1229／私有#77）**：使用者明確說第四版「側面對了、正面大變形」；撤回前版正面已符合自評。本輪保留實際側面上下包絡，只修前艙橫向截面、圓U黑罩、風擋／燈座、圓燈與雨刷；黑罩直接切殼、風擋依實際朝前殼三角切分，避免遠景大面被凸殼遮住。真4b6352d8／私庫7dfa636a完整revision-4保持，新包revision-5；101真殼切面維持側形、12中間payload全同、走行／總bounds不變。頭尾近8962／遠3834、全列74676／33716，專用上限9200／4000（全列約+0.8%／1.8%），共用預算不改。新圓燈回歸真前版紅4項，正面實際風擋射線／埋風擋變異與門／支持／原生GLBPNGviewerZIP全量重驗；外觀自檢非使用者認可、Linux非Metal/FPS，最新同head CI／實際producer看自有交接及issue。靜態幾何，PR含營運接點，未合併不改已安裝遊戲，列車包／classic分派保持Claude工作。不動GameCore／存檔／fixtures／玩法，不推main／合併／auto-merge／TestFlight。

### 2026-10-26 Codex TEMU2000 native static asset (#1281)

`codex/temu2000-native-2026-10-26` adds a new Swift recipe, static model registration, rebuild tools/tests and one overview. It uses five distinct units in the sourced eight-car TED–TEMA–TEP–TEMB–TEMB–TEP–TEMA–TED order; car 6's TEP is reversed so its pantograph points toward car 8. The final V11 M3DM assembly is 14,740 triangles. Four user images were individually viewed in the conversation; no local originals/SHA exist. V1–V10 genuine models, final M3DM/GLB/49 seven-direction PNGs, clay/silhouette, matched metre-scale comparisons, viewer and ZIP are in the linked private draft PR. See [production record](art/temu2000-2026-10-26/README.md). This is static model registration only: operating `puyuma`, GameCore, saves and fixtures are unchanged. Linux Swift 6.4 warnings-as-errors and 10 relevant tests plus native/GLB/PNG/viewer checks passed locally; ZIP and CI status belong to the latest PR head. Simulator, device Metal, performance, animation and gameplay integration remain unverified. Neither draft PR authorizes merge, auto-merge or TestFlight. 營運的 `puyuma` 已接上（決策 426，PR #1308）。

### 2026-10-26 Codex 莒光自動門客車（issue #1305）

獨立 `Map3DChuKuangPassenger` 標準10400系研究與中央小窗特殊配置研究，近遠原生、七向、GLB、E500＋四客車展示、真第一輪與base通用客車同尺度比較、viewer／ZIP在互鏈公開／私有draft，索引見 [自有交接](art/chukuang-coaches-2026-10-26/README.md)。私庫確有juguang壓縮原mesh，已實際解壓四向查看及追查其10400來源；原左右鏡像／寬門／遠景整窗帶與照片有差異，故不只換色，也不套PP殼。標準左右窗不同；特殊角色不冒稱已確認11400。232份既有實際payload保持，E500第三版與EMU3000第五版比較素材直接讀已接受私包。

**尚未接入營運**：未找到已確認至子系列的專用編組配置，合併後沒有列車自動改用本批；E200CK/E500CK/R100CK/R200CK/SUMMER/PP/MINGRI/STAR現有接點保持。Linux指定Swift6.4／warnings-as-errors、原生／匯出／下載驗證與最新同head CI分開看issue及私包證據；人工Simulator外觀、真機Metal／效能／輪門動畫與動態碰撞未驗，外觀未經使用者接受。不動GameCore／存檔／golden／replay，不合併／auto-merge／TestFlight。下次修訂先保留本批真最終包，再改配方並全量重出。

2026-10-27莒光第二版：使用者指定橘改遊戲藏青#262C57；只改兩角色近遠的橘色及原底面陰色，米色／腰線／幾何／其他色保持，paint-audit逐三角位置／法線／拓樸核對。真5952e905橘色前版完整保持，私庫新revision-2；全量素材與同尺度橘／藏青前後見自有交接及#1305。另將本批兩項Swift Testing改同斷言XCTest，修正第一版shard ID不相容的紅CI。營運仍未接入，GameCore／存檔／fixtures不動，真機／動畫未驗。

### 2026-10-27 Codex EMU800（#1316）

[來源／外觀／靜態範圍／驗證交接](art/emu800-native-2026-10-27/README.md)。獨立藍面黃弧EMU800配方，ED/EMA/EP/EMB近遠正反16單元與八輛M3DAssembly。原先Q比例及通用弧形不當作正確殼；完整私有素材與雙庫draft見issue。原有EMU800 key也涵蓋EMU900性能及一般TRA通勤代表，因此**尚未接入營運**，合併沒有列車自動換用；不替換其他通勤車。241既有完整payload保持，已接受E500v3與EMU3000v5私包直接取作風格比較，PP/E1000／莒光藏青／EMU3000石板藍灰不改。Swift6.4及原生／GLB／PNG／viewer／ZIP的最終證據與同head CI見issue；人工Simulator／真機Metal效能／動畫／完整碰撞未驗。不動GameCore／存檔／fixtures／玩法，不推main、不合併／auto-merge／TestFlight。

### 2026-10-27 Codex EMU3000 石板藍灰（#1309）

使用者要求評估莒光藏青（建議保持，本輪不改）及EMU3000黑色外觀改遊戲風格。新分支codex/emu3000-slate-2026-10-27；原66a515e8第五版幾何／其他色保持，只改罩面、窗框與外觀飾件為既有石板藍灰#6E7487，輪胎／雨刷／底盤／弓機構拆出hardwareColor保持舊炭黑。16單元逐三角paint-audit及真正第五版同尺度前後、全量素材／viewer／ZIP見[交接](art/emu3000-slate-2026-10-27/README.md)。已接受第五版原包及E500／PP／E1000／莒光藏青保持；新色未稱已接受，也不保證換色可免侵權風險。

營運接點／列車包／fallback保持；本PR合併更新後，原專用EMU3000近遠畫面會使用新色。GameCore／存檔／fixtures不動；真機／效能／人工Simulator外觀／動畫未驗。兩庫新互鏈draft與最新同head CI看#1309，不推main、不合併／auto-merge／TestFlight。

### 2026-10-27 Codex EMU900（#1338）

[來源／外觀／角色與重建交接](art/emu900-native-2026-10-27/README.md)。獨立EMU900六設備角色近遠正反24單元，十輛5M5T、3/6/8單弓，合法M3DAssembly展示。既有Q比例與展示簡模已實際四向查看，不套殼；真候選與接入前EMU800顯示比較分別標示。柔灰／綠松腰帶／藏青罩面，已修下鼻方正、肩帶過窄與返回面斷帶；工程站位及左右隱藏設備仍有推估，外觀自檢不稱使用者接受。只靜態註冊，沒有EMU900獨占接點，合併後無營運編組自動改用；現有一般通勤EMU800/EMU500與解鎖／列車包／fallback保持。310份舊完整payload（307註冊＋3直接比較）及私庫已接受E500v3／EMU3000v5與已交付PP/E1000／莒光藏青／石板藍灰／EMU800不動。固定producer、素材下載驗證與最新同head CI見互鏈draft／issue。Linux Swift6.4及取樣幾何不代表人工Simulator、真機Metal/FPS/記憶體、動畫或完整動態碰撞。GameCore／存檔／fixtures／玩法不動；不推main、不合併／auto-merge／TestFlight。


EMU900第二版（#1338／draft#1339↔私庫#102）：使用者要求修圓車頭、下裙／連結器、輪架與遊戲配色。真8ebfd9fd第一版完整包保持；新revision-2，罩面沿實際殼曲線、圓裙凹槽與折面排障器，車身用既有D3D4DA、玻璃shade0.62，綠松／藏青保持；輪胎與屋頂設備原三角保護。另補#1041前版漏做的light介面，頭2188／中868–1092三角，36單元與近59448／遠33800／light12056十輛展示及18全payload pins。最新main b7710cb7 C341整合保持；只靜態註冊，無營運自動換用。全量重出／真前後／驗證與固定producer、下載SHA、最新同head CI見自有README及issue，外觀自檢不等於使用者接受，人工Simulator／真機Metal效能與動畫仍未驗。不改GameCore／存檔／fixtures／玩法，不合併／auto-merge／TestFlight。

### 2026-10-27 Codex C371／C381 原生靜態素材

本次製作各自 DM/T/M/反向端車與原廠六輛 DM1–T–M2＋M2–T–DM1。台灣車輛官網規格及兩張已開啟的 Commons 實車照片、兩張使用者插畫來源與缺口詳見 [製作紀錄](art/c371-c381-2026-10-27/README.md)。真第一版與最終版原生、GLB、預覽及同相機比較保留於互鏈私庫 draft。只在 Map3DModels 註冊單元；`metroC381` 是含其他路線及 C371/C381 性能的共用營運接點，沒有更動，合併後不會自動出現在營運列車。外觀仍待改善 C381 圓鼻、兩款車頂與設備精度；真機 Metal／動畫／效能／完整碰撞未驗。技術、ZIP、producer 和最新 CI 以本次 issue 及私包紀錄為準。不動 GameCore、存檔、Golden／Replay／Save fixtures、玩法，不合併、不啟動 TestFlight。

**C371／C381 外觀修訂（Codex，同 #1341／公開 draft #1342／私有 draft #103）**：使用者明確指出兩款第一交付很醜，撤回任何外觀合格推斷。重新開啟 C371 月台前斜及 C381 近正實車照片，重做兩車頭圓罩、駕駛／逃生窗、燈組與雨刷，C381 另有前下 V 形藍分色、側主藍帶；屋頂補低矮格柵與肋條。原廠尺寸／六輛編組與營運映射不變。真正先前私包 `df3f041a` 將完整保留於新包 `history/true-v4/`；同相機比較和新來源、獨立驗證以私包／issue 最新紀錄為準。黑罩曲率、燈腔、設備站位仍有比例推估，不代表已獲外觀接受。只靜態註冊，合併不會自動出現在營運列車。

**C371 優先修訂（Codex，同 PR／issue）**：使用者又提供三張實車照片，要求先以 C341 的完成度標準修 C371。三張均直接目視，原始檔與授權未取得；銀灰側殼、連續低矮肋條、黑色直立前罩與小型下緣設備的目視依據和限制見[製作紀錄](art/c371-c381-2026-10-27/README.md)。前一次完整交付含 ZIP 原樣保留於私包 `history/true-v5/`；本輪只改 C371 配方與共用 builder 的 C371 分支，C381 10 個原生／GLB 檔案逐 bytes 相同。C371 六車 14,816 三角，低於 15,000 單檔上限；C341 和其他車模型幾何未取用。外觀自檢有進步但設備精確站位、真機 Metal 與使用者接受仍未驗證；仍只靜態素材註冊，合併後不會自動出現在營運列車。

**C371 方框再修（Codex，同 PR／issue）**：使用者仍嫌正面方框，並要求用已合併的 PR #1357。從最新 main 取得 rolling-stock skill 與 `tools/train-models/`，共用工具拍 C371 日夜七向並檢 FNV 鎖；原生編組／GLB／ZIP 仍由自有專用驗收製作。圓角銀色端面有厚度並重疊支承，黑罩與前窗圓角加大，側窗／門框變薄；試作末段漸縮在正面露出藍色方塊，撤回而非出貨。真前版全包在私庫 `history/true-v6/`，目前 C371 六車 14,936 三角；C381 原生／GLB 仍應逐 bytes 核對。新外觀與測試、CI 以自有製作紀錄及 #1341 最新狀態為準，尚無使用者外觀接受或真機驗證。靜態註冊依舊不會自動替換營運列車。

**跨帳戶續作（Codex，同 #1341）**：使用者要由另一個帳戶的 Codex 接手 C371 查實車圖、修原生幾何並更新既有兩個 draft PR。接手起點、可跨帳戶開啟的原圖、現存可見缺陷、真前版與完整 ZIP、分支權限及重建驗證步驟見 [C371 跨帳戶交接](art/c371-c381-2026-10-27/CROSS_ACCOUNT_HANDOFF.md)。本對話的內嵌照片不會自動出現在另一帳戶，不能寫成接手者已查看。C371 方框感仍待修；C381 本輪未修形、未獲外觀接受。
### 2026-10-27 Codex 台北捷運610（#1359）

[專用來源／角色／重建與驗收](art/taipei610-2026-10-27/README.md)。使用者命名台北捷運610，環狀線第一階段正常白黃塗裝，獨立A-C-D-B四動車，三級12單元與合法assembly；沒有同車型獨立原生前版，私庫Q比例y100不套殼，接入前顯示只取真wenhu並明標。最新373註冊＋3直接比較完整payload保持（包含最新月台整合新增項）；已接受E500v3／EMU3000v5及EMU900第二版、其他既有包不動。私庫E1000#88合在PP分支而非main祖先，不能只因merged宣稱main已有素材。沒有610獨占營運接點（BR/Y共用wenhu），本批尚未接入營運，合併不會有營運車自動換用；解鎖／列車包／fallback保持。外觀自檢與使用者接受分開，未經使用者接受；Linux幾何／WebGL／Swift6.4與ZIP證據及互鏈draft見#1359。人工Simulator／真機Metal效能／動畫與完整動態碰撞未驗。只追加自有配方與必要通用匯出適配，不改GameCore／存檔／fixtures；不合併、不推main／auto-merge／TestFlight。

台北捷運610第二版（#1362↔私有#109，#1359）：使用者指出浮空。新增全實體1mm接觸圖在真第一版找到內背襯／端部拉桿／連結器無車體路徑，已加內框固定件與吊座；撤回前版泛稱支承合格。每端僅增60三角，其餘原三角全保持、C/D原生GLB相同，真第一版完整包不動。#1357共用工具原已使用，新增它的真前後離線頁；不加AO／金屬反光／營運玩法。來源與本輪producer／完整素材看本型README與兩張draft；未接受，人工Simulator／真機仍未驗。

台北捷運610 CI收尾：3310bba6的selected-2唯一失敗是總模型計數373漏了本型12份（實際385），gate連帶紅；補本型角色×3計數，Linux Swift6.4嚴格build及Map3DModelTests／Map3DTaipei610Tests共10項通過。模型／producer／ZIP保持，新head CI看公開#1362。私有#109已於2026-10-27T18:01:15Z實際合main49506c7a，非使用者接受；公開仍draft、未接營運。

### 2026-10-28 Codex 列車共用製作模組與三鶯線接手入口

依作者要求更新列車技能／新對話指令與共用編組、GLB、幾何／故障驗收、自含互動檢視頁及限量交付。新任從[三鶯線指令](art/native-vehicle-modeling/SANYING_PROMPT.md)開始，先查工具PR是否已合併，再讀最新main及素材庫AGENTS；[工具說明](../tools/train-models/README.md)列操作與驗證限制。本輪沒有製作三鶯線或更動任何車款配方／營運映射；不合併、不啟動TestFlight。歷史專用工具保留供舊成果重建，新輪次不交ZIP／history副本。

### 2026-10-28 Codex 台中捷運綠線 studies

[獨立配方／官方來源／重建與狀態](art/taichung-green/README.md)。從main04f81f7a新建DM1/DM2近遠四單元及資料描述兩車編組；工具#1416/#1357已合、三鶯#1422未合，不套舊殼。只追加studies；既有tmrt→metroGeneric兩車營運映射保護。外觀未經使用者接受，隱藏底箱／輪徑／設備站位是推估；Simulator／真機Metal／效能／動畫與營運接入UNVERIFIED。實跑producer、完整私庫revision-1、下載SHA與最新CI見自有交付紀錄；不合併／auto-merge／TestFlight，不動GameCore／存檔／fixtures／玩法。

台中綠線交付補記：公開draft[#1430](https://github.com/a91453/railway-game-ios/pull/1430)↔素材draft[railway-assets-private#21](https://github.com/a91453/railway-assets-private/pull/21)，固定producer ebf978be；[完整證據](art/taichung-green/verification.json)。680舊原生逐bytes不變、14成品獨立重建一致、20私庫PNG＋1公開總覽、最終viewer真下載已驗。額外相容性測試發現Map3DModelTests的studies計數漏四件，已只補本型×2。最新head CI與記憶體報告見自有README及PR，不把測試通過當外觀接受。

台中綠線第二版收尾：最後實看發現風琴間隙，僅延伸實際風琴至共同連結面並新增縮回100mm反例；最終producer `e525a29a`／素材`61084334` revision-2。真正前版公開`ebf978be`／素材`d90867d7`可重建，第一輪重檔已在同PR移除、保留PNG／README／來源。最終12項Swift通過，另啟用記憶體報告的13項通過、standard仍583模型／133.3MB；技術／來源／viewer下載SHA及兩庫draft仍見自有README。外觀接受／營運／裝置仍UNVERIFIED。

### 2026-10-28 Codex 三鶯線原生靜態模型

三鶯線兩節車靜態模型的重建入口與來源在 [SANYING_MODEL.md](art/native-vehicle-modeling/SANYING_MODEL.md)。使用者否定第一版外觀，又指出第二版與實車照片不夠像；第三版修白色側板／門柱、獨立深色窗、藍色車頭與銀色橫飾帶。使用者於 2026-10-28 回覆「可以」，僅第三版 producer `495468fe0bef6bf9e56b4543e1db5642bf0328c1` 記外觀接受。前版由 git producer 恢復；營運映射、真機仍未驗，公開／私有 draft PR 見本輪 #1041 登記。

台中收尾合main b4fff5ed後13項相關測試綠、本批14成品與producer逐bytes相同。全包重算另抓到最新main鎖檔28項既有EMU3000／莒光等set值不符；[名單／證據](art/taichung-green/verification.json)，本PR不改任何舊鎖、台中四項正確，680原實際模型仍不變。共用鎖全包驗收不能稱綠，留共用工具／原車作者處理；本型專用素材驗收保持。最新CI看公開#1430 head checks。

### 台中綠線第三版（Codex，使用者重貼四張實車照重新核對）

前#1430已合，因此從最新main12e4590a開codex/taichung-green-shape-2026-10-28。撤回前版將車頭／綠帶／裙部偏差只列為細節簡化的寬鬆自評；已重修圓罩／風擋、連續遊戲綠帶、弧形下裙／凹孔及實體枕座／吊座。producer0b6d26df，真前版e525a29a／素材61084334；私draft#21新revision-3，同PR刪第二輪重檔、留PNG／README／來源。近3828／遠1848各單元，兩車7656／3696。684其他原生逐bytes與main相同，本型14成品獨立producer重建一致；新開口／凹孔／刪支承probe與真前版反例均已跑。本型[交接／來源／重建與證據](art/taichung-green/README.md)為入口；公開新draft及最新head CI看#1041。只studies、tmrt映射不變，外觀接受／營運接入／Simulator及真機仍UNVERIFIED；不合併／auto-merge／TestFlight。最新main繼承的28舊鎖差異不擅改，仍明列全包驗收限制。

### 台中綠線第四版（Codex，正面塗裝回饋）

使用者指出第三版正面塗裝奇怪，重看官方與Blair原圖確認少了接肩部／燈座的深色兩頰；第四版只補正面分色、上肩綠色與相接肩帶，保留車殼／玻璃／燈／設備。producer `498d85ef`，真前版`0b6d26df`／素材`1adbab9f`；新素材`e9c8de91`的revision-4與原公開draft[#1437](https://github.com/a91453/railway-game-ios/pull/1437)↔素材draft[#21](https://github.com/a91453/railway-assets-private/pull/21)互鏈。第三輪重檔同PR刪除，保留PNG／README／來源／授權。近4804／遠2208、兩車9608／4416；20私庫PNG＋1公開小總覽，asset_guard通過，PR新增13.3MB。

本機Swift6.4 warnings-as-errors與最終12測試通過；前臉第一可見材質／實際塗白故障反例拒收、真第三版四單元拒收，逐三角驗分色包絡外幾何與車頭後方頂點色保持（相鄰車頭烘焙遮蔽可變）。既有六模型幾何／玻璃／八輪／支承反例、Blender、Swift42072頂點編組、170PNG與六下載PNG完整解碼、最終七向配色白模剪影目視、viewer18下載SHA通過；14檔獨立producer重建bytes相同，684其他原生與FNV保持。本型四鎖正確，分支繼承28他車舊鎖差異不擅改。詳見[交接／來源／重建／驗證](art/taichung-green/README.md)；最終CI見本輪PR checks及#1041。真實綠藍柔和過渡簡化成乾淨色塊，第四版外觀接受／營運接入／Simulator與真機Metal效能動畫仍UNVERIFIED。仍studies、tmrt映射不動，不合併／auto-merge／TestFlight。

### 2026-10-29 Codex 高雄紅／橘線現役西門子 studies

[來源／交接／重建／狀態](art/kaohsiung/README.md)：producer `62c2da42`，獨立DM1/T/DM2近遠六單元與三車assembly，只有studies，krtc→metroGeneric三車保持。原始高捷PDF、市府實車圖、Siemens SF3000原圖錄及可靠實拍已下載開啟；兩線共用一般銀／綠松塗裝，不另造紅橘車。近9924／遠4788三角，18成品獨立producer逐bytes相同；688他車實際payload/FNV保持，28既有鎖差異不改。四狀態、簡化與資料缺口、最終驗證及互鏈draft見自有README。使用者外觀接受、營運接入、Simulator／真機Metal效能動畫UNVERIFIED；不合併／auto-merge／TestFlight，不動GameCore／存檔／fixtures／玩法。

高雄交付互鏈：公開draft[#1454](https://github.com/a91453/railway-game-ios/pull/1454) ↔ 素材draft[#22](https://github.com/a91453/railway-assets-private/pull/22)，素材revision-1 `10f8abc`；兩庫base main。15項最終Swift＋啟用記憶體報告1項通過（standard585／133.3MB），最終交付viewer24實際下載SHA及20PNG／完整SHA清單通過；asset_guard11.6MB綠。最新CI看兩PR同head checks，不宣稱外觀／真機接受。

### 2026-10-29 高雄第二版續修（Codex）

使用者要求「依實車對照繼續修」。同公開draft#1454 ↔ 素材draft#22，producer `3874b425`，真前版`62c2da42`／素材`10f8abc`。撤回第一輪顯示幕側別及車頭細節的過寬自評：改觀者左側顯示幕、橫向圓弧與風擋／圓角中央門、雙燈共同座、雨刷、下裙與真凹孔連結器。T近遠完整payload、X≤9m後方硬體幾何／flags及其他688模型實際bytes/FNV保持。近三車12148／遠5476，18成品獨立producer重建相同；15項Swift6.4及八件GLB／故障反例／固定尺度真前後／最終viewer下載檢查見自有README和verification。revision-1重檔同PR刪除，留PNG／README／來源；revision-2為最新完整包，沒有ZIP/history。仍studies，營運映射保持；外觀接受／接入／Simulator與真機UNVERIFIED，不merge／auto-merge／TestFlight。

### 2026-10-29 高雄第三版正面塗裝（Codex）

使用者「側面可以了」僅接受R2 producer `3874b425`側面，正面偏方續修；最新producer `bd57e163391bfdf7492cc408c7697451578ae8e1`，真前版素材`1f73fb1`。本輪只改實體殼上的正面分色：黑罩上緣淺弧／肩部收角與U帶細分，不改中央逃生門等硬體或曲面。逐三角形原生52bytes護住X≤9m直側，T近遠整檔保持；兩producer白殼雙向交集驗車頭覆蓋不變。最新main`fd91b75c`的696他車實際bytes/FNV、所有他車鎖保持；只動本型四DM鎖，28繼承差異不消。近三車13892／遠6356；18成品從producer獨立重建相同，15 Swift6.4 WAE、8 GLB、真故障、224PNG／192同尺度前後、24真下載SHA與最終viewer已驗。沿用draft#1454 ↔ 素材draft#22，revision-3為完整包，revision-2重檔同PR刪除留PNG／README／來源。具體資料、預覽、重建及四狀態見[自有交接](art/kaohsiung/README.md)。後續使用者在第三版收尾建議後明確回覆「就這樣」；已據此把producer `bd57e163`的studies整體外觀接受記為VERIFIED，停止外觀修改。營運接入與裝置視覺／真機Metal效能動畫仍UNVERIFIED。交付程式head `cd92b3c6`之Swift gate／六selected分片及Xcode均SUCCESS；公開#1454與素材#22皆由其他流程合併，接受metadata從最新main另開互鏈draft補記（素材#24），模型／20PNG不變。studies、krtc→metroGeneric三車、其他保護範圍不變，不merge／auto-merge／TestFlight。


### Codex：高雄輕軌兩現役車型（CAF／Citadis，2026-10-29）

兩款各自五角色近遠景與完整靜態組裝，首次交付，沒有真正前版；
[查證、模組、保護範圍與交接](art/kaohsiung-light-rail/README.md)、
[重建／驗收工具](../tools/kaohsiung-light-rail/README.md)。
素材在 assets-private 的 kaohsiung-light-rail-phase1／phase2 revision-1，
明確 producer、互鏈 draft PR 與最終證據見該頁 verification.json。
只註冊 studies；既有解鎖 fiveSectionLRT／鎖定 greenTram 的營運映射未動，
沒有兩款選用／配屬契約，不應宣稱合併即在遊戲出現。高雄紅橘線與全部既有
payload 保護；32 舊鎖差異與 TEMU2000 舊整列預算失敗另記，不改 gate。
兩款使用者外觀接受、營運接入及裝置狀態各為 UNVERIFIED；
Linux 靜態技術驗證不代表 iOS Metal／真機／動態關節。未推 main、未合併或啟動 TestFlight。

同輪補完：兩款far窗柱色界已與近景對齊，新增實際白柱／玻璃帶壞例拒收；
最終producer `cfeed799260b609b6765ab44404d9ab095c48f94`，素材 `1a1adcc0420f8151c0a074ed4c242fa2aa63a648`。
80b58f6e／ca6a8bc1是同PR未接受中間版，真實同相機／公尺／光線比較已合併原PNG，非虛構前輪；仍各20張＋公開共用1張、studies而已。最終CI看#1506／素材#31最新head，未把舊head綠燈當最終通過。

### Codex 新北安坑／淡海輕軌雙車（2026-10-29）

本輪兩款獨立原生 studies，交接、車型對照、幾何共用依據、來源及狀態見 [new-taipei-light-rail](art/new-taipei-light-rail/README.md)。各自五角色近遠與完整靜態組裝；素材位於素材庫各款 revision-1。沒有營運接入，合併不會在遊戲出現；使用者外觀接受與裝置各自 UNVERIFIED。greenTram／fiveSectionLRT、ntdlrt／ntalrt／krtc/C原映射、列車包／回退及高雄紅橘線不動。上一輪高雄輕軌公開#1506與素材#31開工時OPEN、其後已MERGED（已納入最新main），其分支／檔案保持。未新增GameCore、存檔、fixtures、購車／解鎖、班表、控制或動畫。後續整合須另查當班配車與逐模組動態路徑契約；不要用車號奇偶或隨機配兩款。兩車首次交付、沒有已接受前版，所有未驗及重建producer詳各款來源／status／驗證。

收尾producer `0d3b6733f6c76a607c034097f95956f4b38ab958`：兩款素材技術VERIFIED，獨立producer模型／PNG／viewer bytes相同、最終HTTP viewer真下載／旋轉縮放已驗；file://被瀏覽器管理政策擋住，離線直開仍UNVERIFIED。最新未改main的757個原生payload與全頂點欄位雜湊保持。14 Swift6.4 WAE測試、獨立Blender／原生組裝／故障反例通過；全量33項既有失敗已在main重現，未改gate。兩款各20PNG＋公開共用1張，外觀接受／營運／裝置各UNVERIFIED，詳自有verification.json。

> Codex 海風／山嵐 EMU500 雙款改造（producer `f036e7f7`，素材draft [#35](https://github.com/a91453/railway-assets-private/pull/35)）：[查證、逐部件差異、角色、來源與驗證](art/tourism-emu500/README.md)。從既有原生EMU500截面／弧頭與走行設備生成段改造，兩端封門、中央落地窗與兩款一般漸層獨立處理；原EMU500及其他營運模型／配車／列車包／回退保持。兩款僅studies，沒有玩家選用或動態行駛驗證；使用者明確producer外觀接受、營運與裝置UNVERIFIED。完整交付、producer、雙draft PR與最新head CI見自有文件；不推main／合併／auto-merge／TestFlight。

> Codex 海風／山嵐第二輪（producer `0e2f38a244db7ea0301169cdb4b6d81f0c340a78`，公開draft #1539 ↔ 素材draft #35）：依使用者「修」收薄下裙、重建連結器凹區／主管線、上下燈座、中央窗及連續漸層；窗框與玻璃沿原EMU500最終弧頭三角面切分，射線／故障反例驗收。前稿f036e7f7未經接受，撤回過寬外觀自評；素材兩款最新revision-2，上一輪只留PNG／README／來源，重檔同PR移除。本輪Swift6.4 WAE與14項測試、777既有payload／全部頂點欄位保持（main d6c5c899），同33舊全量失敗不改gate。仍studies，不接營運／配車／列車包／回退；兩款外觀接受、營運及裝置UNVERIFIED。獨立producer重建／最終viewer、素材guard與最新head CI以[本型驗證](art/tourism-emu500/verification.json)及兩draft記錄為準。不推main／merge／auto-merge／TestFlight。

### Codex R200／R216 獨立雙端 studies（2026-10-30）

[來源、契約、幾何、四態與接手](art/tra-r200/README.md)。本輪保護既有單駕駛室 R200CK 代用配方／營運，獨立建立雙端 R200 近遠完整單機。僅studies，不會合併後自動選用。正式批次、官方端號、遮蔽側／屋頂BOM與部分原廠尺寸來源仍未核齊，不能稱已完成現役工程復刻；所有技術證據與互鏈draft以自有verification為準。沒有已接受R200前版，製作者自檢不代表使用者接受；營運／裝置UNVERIFIED。不改GameCore／存檔／fixtures／配車／他車，不推main／merge／auto-merge／TestFlight。

> Codex R200 第二輪（公開draft #1589 ↔ 素材draft #37）：依使用者「那你改」加寬／微弧前罩與風擋、弧肩、開放台車框、單一凹鑄件／四對彎管、分層機艙屋頂與格柵；真正未接受前稿65464b23，保留同尺度比較。完整資料及producer／四態見 [R200交接](art/tra-r200/README.md)，最新完整包revision-2，第一輪只留PNG／README／來源。只有studies，其他車／營運／standard不變；正式端號與反側屋頂BOM等來源缺口、裝置／營運／使用者接受UNVERIFIED，不合併／auto-merge／TestFlight。

> R200第二輪收尾：真正producer `9c87ea5c94e23b5810ff4a48a9455bbc6fa03732`，最新main基準`2ebe025a`。近12702／遠5098三角、35核心交付檔與66原始模型／檢查圖檔獨立checkout逐bytes一致。最新10 Swift6.4 WAE測試通過，845既有模型payload及全頂點欄位保持（含2個未入上游鎖的場景模型）；standard663／172.5MB，R200常駐增量0。最新main與本分支同33既有全量失敗／34鎖差異，不改gate／他車鎖。外觀接受／營運／裝置與受管理政策阻擋的file://均UNVERIFIED；兩draft最新head CI及衝突見PR留言。
