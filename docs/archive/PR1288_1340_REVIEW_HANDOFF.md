# 交接：PR #1288–#1340 審查 K1

派工單 AW（遊戲規劃 session_01YGNNupfaTiuQSAJ5tsf5a4，2026-10-28）：審查 main 上已合併、編號 #1288–#1340 的程式 PR。#1343–#1385 是審查 K2（派工單 AX）的範圍，另寫自己的檔；HANDOFF §1「上一輪」由規劃兩段都合併後一起改。

- Session：session_01YGNNupNdEVV42ZCiM39rtb，branch `claude/review-k1`。
- 基準：`main` **cdb5bba**（#1385 合併後）；範圍的最後一個合併是 #1340（**b7710cb**）。
- 點數照 HANDOFF §1「多久審查一次」：GameCore 2 點；GamePresentation、App、CI 腳本、會產生打包資料的 `tools/`、`Web/` 1 點；只改文件、只加模型或素材、只改測試 0 點。
- 上一輪：[PR1242_1287](PR1242_1287_REVIEW_HANDOFF.md)（審查 J）。
- 存檔版本、決策編號、golden schema 都**不動**。
- 發版凍結（TestFlight 92）：這一輪只寫這份檔，不開改 App 的 PR。

## 〇、範圍與點數

`git log --first-parent 57dc35d..b7710cb` 裡編號 #1288–#1340 的合併共 44 個。

| 類別 | PR | 個數 | 點數 |
| --- | --- | --: | --: |
| GameCore | #1319 | 1 | 2 |
| GamePresentation／App／CI | #1290、#1291、#1292、#1295、#1298、#1300、#1301、#1302、#1307、#1308、#1311、#1312、#1314、#1320、#1323、#1324、#1325、#1326、#1330、#1336、#1339、#1340 | 22 | 22 |
| 合計 | | **23** | **24** |

不到 30 點，一段一個 PR。

0 點（不看，21 個）：只改文件 #1288、#1289、#1293、#1297、#1303、#1304、#1313、#1317、#1318、#1321、#1327、#1328、#1329、#1331、#1332、#1333、#1334、#1335、#1337；只改 UI 測試 #1315；只加車輛配方、遊戲還沒用 #1306（`Map3DChuKuangPassenger`，由 #1326 接上，跟 #1326 一起讀了）。#1294、#1296、#1299、#1305、#1309、#1310、#1316、#1322、#1338 沒有合併（#1296 的內容由 #1302 合進來）。

判斷依據（同審查 J）：Codex 的車輛 PR 改了 `Map3DModels.swift`（模型包）或 `Map3DTrainSets.swift`（遊戲畫哪台車），算程式；它們 `tools/` 底下的產生器只渲染、檢查、匯出，App 不打包輸出，不另算。#1290 是審查 J 自己的 J1 修正，照樣算 1 點、看了 diff。

## 一、結論

| 項目 | 數量 |
| --- | --- |
| 程式 PR | 23 個、24 點（GameCore #1319 2 點） |
| 新發現 | **1 個**，P2（K1-1） |
| P1 | 0 個（沒有會當機、壞存檔、讓玩家卡住的） |
| 已修 | 0 個（發版凍結，不開改 App 的 PR） |
| 沒修，交出去 | 1 個：K1-1 |

GameCore 的 #1319 由本 session 自己讀。

## 二、逐 PR

| PR | 看了什麼 | 結論 |
| --- | --- | --- |
| #1290 | 審查 J 的 J1：「多角經營」「企業集團」只數百貨公司、飯店、遊樂園；回歸測試 | 無問題 |
| #1291 | PP 推拉式自強號客車（`Map3DPPPassenger`）：`ppHauled` 換掉舊的 `hauled("pushPull", locomotive: .e1000, …, lastIsLocomotive: true)`，`tail: nil` 所以尾車是頭車轉過來（`isTurned`）；近景、遠景各一組，`pushPull` 加進 `nearOnly`；模型包加四種角色近遠各一 | 無問題。模型包多出的靜態角色見 K1-1 |
| #1292 | TEMU2000 原生單元（`Map3DTEMU2000`）與整列，只進模型包 | 無問題（遊戲由 #1308 接上）。見 K1-1 |
| #1295 | 公車工具預讀（決策 424 續）：`BusRoads.readAhead` 一塊一塊拿鎖，點地圖的同時只等一塊；`keptTiles` 48 → 64（`RealBusLibrary.reach` 6 km 內最多 49 塊）；`readBusesAhead` 只在公車工具、同一站不重開、換站取消前一個；`finishBusReadAhead` 用 serial 判斷，換地圖或換真實公車資料時 `busReadAhead = nil`，舊的結果丟掉；`RealBusLibrary.stops` 有自己的鎖 | 無問題。結果不變，只改什麼時候讀 |
| #1298 | 審查 J 的 J2 與疑點：`FrameTimeMeter.frame(at:)` 直接改 `tally!`，不再每幀複製計數陣列；跑分在鐵路資料讀好前不開，鋪出的線數不對就回開始畫面並說原因 | 無問題 |
| #1300 | 3D 公車在主執行緒外鋪（`Map3DBuses.Layer`）：同一個 `signature`＋場景只鋪一次；鋪的期間同一場景畫舊的、換了場景畫不出來（`nil`）；後來的要求取消前一個、serial 防舊結果蓋新的 | 無問題 |
| #1301 | 「這版新增」卡 2026-10-26 一則；兩種語言、只寫功能 | 無問題 |
| #1302 | E1000 原生模型（`Map3DE1000`）；推拉式自強號兩端改 E500（決策 425：E1000 已退出營運），E1000 留在模型包 | 無問題。見 K1-1 |
| #1307 | 太魯閣號車頭：車窗與燈投影到真的車殼面上（`cabSurface`、`clipScreen`）；`precondition` 只在固定幾何上，測試建得出模型就不會在玩家手上觸發 | 無問題 |
| #1308 | 決策 426：普悠瑪接上 TEMU2000，`centreCars: [3, 4]`（`modelIndex` 多一行，其他列車的 `centreCars` 是空的）、`fixedCars: 8`、兩個 TEP 朝外、頭白尾紅；遠景組 | 無問題 |
| #1311 | EMU3000 車頭飾條換顏色，機構件保留原色（`hardwareColor`），幾何不變 | 無問題 |
| #1312 | EMU500 原生單元與整列，只進模型包 | 無問題（遊戲由 #1336 接上）。見 K1-1 |
| #1314 | 決策 427：列車包的推拉式自強號 E1000 外觀，第二個開關（`pushPullE1000Key`）。`TrainPack.locked` 沒解鎖時鎖全部、解鎖但第二個開關關著時只鎖 `pushPullE1000`；`variant` 在沒鎖時換成 `pushPullE1000`。所有呼叫 `variant` 的地方（`Map3DTrains:187`、`Map3DRealTrains:340`）都傳 `models?.locked`，App 唯一設 `locked` 的地方（`Map3DPreviewScreen:806`）兩個開關都讀；展示間 `locked = []` 是故意的 | 無問題 |
| #1319 | **GameCore**：`turnOnRoads(towns:)` 已有道路丟 `.roadsEnabled`，否則 `enableRoads` 再 `seedBoughtTilesRoads`，失敗時世界不變（兩個都不丟錯）。GamePresentation：`PlayerCommand.Edit.turnOnRoads(towns:)` 記下城鎮，重播不必再算；`startingTowns` 依序試四個種子、取城鎮中心都有土地的那一個，買地圖的舊存檔退回世界中心，再由 `seedBoughtTilesRoads` 補已買的格子（`testABoughtBlankMapsSaveGetsItsTownsRoads`）；教學、課程不給；實景圖只讀得到底圖道路時才給；`ActionButton` 沒有道路時不出現；`tapBusTool` 本來就要求 `world.roads` | 無問題。新的 `Edit` case 只影響舊版讀新紀錄，不影響新版讀舊紀錄 |
| #1320 | EMU800 原生角色（四種、兩個朝向、近遠），只進模型包 | 無問題（遊戲由 #1336 接上）。見 K1-1 |
| #1323 | C341 原生單元，只進模型包 | 無問題（遊戲由 #1340 接上）。見 K1-1 |
| #1324 | 決策 429：3D 路口號誌照遊戲時鐘換燈。`Map3DSignalTiming.light` 的時相（70 s 一輪，主路 0–32 綠、32–35 黃，橫路 36–64 綠、64–67 黃，兩次全紅）；路口四個偏移、位置雜湊決定；超過約 17× 不換燈（`changes(at:)`，暫停時看恢復後的速度）；`Map3DPropRuns` 畫面依模型＋群組分批，陰影只依模型；`Map3DMetalView` 換燈只換模型索引，`drawn` 都是包裡的索引；`signalClock` 跟著 `world` 在 `updateUIView` 更新 | 無問題 |
| #1325 | `tdx-check.yml` 允許 `/api/historical/`；仍只送到同一個主機、擋 `..` | 無問題 |
| #1326 | 決策 430：莒光號四組與 SUMMER 用 #1306 的自動門客車、遠景組；`Coach.chuKuang`；最後一節加兩個紅燈（`chuKuangTail`），模型名字由 `set-…-tail` 重新命名，不會和中間車撞名 | 無問題 |
| #1330 | 決策 431：高雄車站地標（OSM 量的綠色頂棚）；`clearing` 672×340 m、`body` 324×284 m；地下的台鐵與捷運是隧道，`isClearOfTrack` 不算隧道，所以畫得出來；玩家在地面上鋪進範圍時地標讓路 | 無問題 |
| #1336 | 決策 432：台鐵區間車一半 EMU800、一半 EMU500（`variant` 依車次單雙）；`cycle` 接點：中間車循環、後半鏡像（`modelIndex` 的 `nearer` 在 1…count−2 都 ≥ 0）；`layout` 每節照 `modelIndex` 取長度 | 無問題。模型包的成長見 K1-1 |
| #1339 | EMU900 原生角色（近、遠、`light` 三種，兩個朝向），只進模型包 | 無問題（遊戲由 #1343 之後接上，K2 的範圍）。見 K1-1 |
| #1340 | 決策 433：台北捷運一半畫 C341（`variantKey` 只在 `trtc`）；玩家的 `L`（線性馬達捷運）在列車包解鎖時照舊畫四節車，鎖著時才可能換 C341；C341 的 `cycle` 沒有後半的反向模型，`pick` 退回前半的 | 無問題 |

## 三、修了的

無（發版凍結）。

## 四、沒修、交出去的

### K1-1 3D 模型包在這一段大了八成，第一次開 3D 時在主執行緒建，記憶體多約 120 MB，P2

- **在哪裡**：
  - 模型包 `Map3DModelPack.standard`（`Sources/GamePresentation/Map3DModels.swift:45`）在 `init(styles:baked:)` 一次建好全部模型。這一段的 PR 加了兩種東西：
    1. 遊戲真的會畫的列車組（`Map3DTrainSet.all` 裡的 `set-…` 模型）：普悠瑪、推拉式自強號 E500／E1000、莒光號四組與 SUMMER 的遠景組、EMU800、EMU500、C341。
    2. **遊戲不畫的靜態展示模型**，直接加在包裡（`Map3DModels.swift:87`、`:106`、`:108`、`:112`、`:115`、`:117`、`:121–122`）：TEMU2000 單元與整列、PP 四種角色近遠、E1000 近遠、EMU800 四種角色×兩個朝向×近遠、EMU500 單元與整列、C341 單元、EMU900 角色。這些名字沒有任何畫面用 `index(of:)` 取（遊戲與展示間都用 `set-…` 的那一份），只有 `tools/*/export.swift`、`capture*.swift` 與 `tools/train-models` 的雜湊鎖讀它們。
  - App 在 `Map3DView` 的 `static let models`（`RailwayGameApp/Views/Map3D/Map3DPreviewScreen.swift:724`）第一次被讀時建包；`makeUIView`（`:744`）在 3D 畫面一出現就讀它，這時場景還在 `Task.detached` 裡建（`built == nil`，`:89` 顯示 `ProgressView`），所以**主執行緒要等建包做完**：主執行緒先讀就在主執行緒建；背景建場景的工作先讀（`Map3DScene.swift:1504` 的 `propModels` 也來自 `standard`）時，主執行緒在同一個 `static let` 的一次性初始化上等它做完。只有 2D 拉近時預先蓋 3D 場景（HANDOFF「3D 場景快取」那一條）已經在背景建好包的時候不用等。決策 439 已記「pack 在第一次開 3D 時於主執行緒做」，UNVERIFIED。
  - `Map3DMetalView.useModels`（`RailwayGameApp/Views/Map3D/Map3DMetalView.swift:760–761`）替**每一個**模型開一個 `MTLBuffer`，所以 CPU 一份（`static let` 一直留著）、GPU 一份。
- **量的**（Linux，官方 Swift 6.4.0；同一支只讀 `Map3DModelPack.standard` 的小程式，`-c release`，各跑三次；頂點 40 bytes）：

  | commit | 模型數 | 頂點 | 一份的大小 | 建包時間（release） |
  | --- | --: | --: | --: | --: |
  | 57dc35d（這一段之前） | 211 | 1,857,045 | 74.3 MB | 0.57–0.59 s |
  | b7710cb（#1340 合併後） | 315 | 3,334,803 | 133.4 MB | 0.80–1.12 s |
  | cdb5bba（現在的 main，含 K2 的範圍） | 618 | 4,200,744 | 168.0 MB | 沒有量（release 建置超過背景工作的 30 分上限被停掉；K2 的範圍） |

  這一段多 147.8 萬個頂點、59 MB（CPU 與 GPU 各一份，共約 120 MB）。其中**遊戲不畫的靜態展示模型**約 63 萬個頂點、25 MB（EMU800 25.4 萬、PP 13.9 萬、EMU500 8.9 萬、TEMU2000 7.4 萬、C341 4.3 萬、E1000 3.0 萬；同樣兩份共約 50 MB）。決策 426、432、433 都寫了「建包時間與記憶體的上升，沒有量」。
- **怎麼推得到**：玩家每次啟動 App 後第一次開 3D 地圖（例如直接按 3D 按鈕，沒有經過 2D 拉近的預先建）→ `makeUIView` 讀 `Map3DView.models` → 主執行緒建整個包，或等背景建完 → 這段時間畫面不動、轉圈也停住；建好後 GPU 再配一份。Linux 這台機器 release 在這一段從約 0.58 s 變 0.80–1.12 s；手機的 CPU 慢一些，實機時間 **UNVERIFIED**。記憶體：3D 開著時模型包 CPU＋GPU 從約 150 MB 變約 270 MB（現在的 main 約 340 MB），再加上場景的網格（決策 446：板橋 779 MB）。記憶體較小的 iPhone 被系統關掉的機率變高，沒有在實機量，**UNVERIFIED**。
- **玩家看到**：第一次進 3D 時畫面卡住約一秒（比這一段之前久將近一倍）；記憶體較小的手機在 3D 裡比較容易閃退。不會壞存檔。
- **等級**：**P2**。主執行緒卡住、記憶體退步；沒有證據會當機，所以不是 P1。
- **建議怎麼修**（發版後派；只動 GamePresentation 與 App，不動存檔、重播、golden）：
  1. 遊戲不畫的靜態展示模型移出 `standard`，放進只給工具與雜湊用的包（例如 `Map3DModelPack.studies`），`tools/train-models/export.swift` 與各 `tools/*/export.swift` 改讀它；`hashes.lock.json` 的模型名稱與雜湊不變，只是換一個包。要先確認沒有 UI 測試或展示間依名字找這些模型。
  2. `Map3DView.models` 不在 `makeUIView` 裡同步建：跟場景一起在 `Task.detached` 建（場景建好之前本來就只顯示轉圈），或 App 啟動後在背景先讀一次。
  3. 加一個 Linux 測試鎖模型包的總頂點數（像 `Map3DSceneMemoryTests` 鎖場景），之後的車輛 PR 要寫多了多少、為什麼。
  4. 修好後在 TestFlight 實機量第一次開 3D 的時間與記憶體。

## 五、執行過的檢查

| 檢查 | 結果 |
| --- | --- |
| 模型包的模型數、頂點數（57dc35d、b7710cb、cdb5bba；暫時的測試與小程式，不提交） | **VERIFIED**，Linux，官方 Swift 6.4.0 `/opt/swift`，數字在 K1-1 |
| 建包時間（`swift build -c release`，同一台機器各跑三次） | **VERIFIED**，Linux；實機 **UNVERIFIED** |
| 這份檔以外沒有改程式 | `git status` 只有這個檔 |
| 其他 | 只讀 diff、追了呼叫路徑 |
| 完整測試、iOS 建置、UI 測試、實機畫面與記憶體 | 交給 CI 與實機，**UNVERIFIED LOCALLY** |

這一段沒有改程式，所以沒有回歸測試。

## 六、五方

- 玩家：二十三個 PR 沒有會丟存檔、當掉、卡住流程或算錯錢的問題；K1-1 是第一次開 3D 多卡一下、3D 的記憶體變大。
- 鐵道迷：普悠瑪的編組與集電弓朝外、推拉式自強號兩端 E500（E1000 退出營運）、區間車 EMU800／EMU500 各半、C341 只在台北捷運、號誌時相照參考庫，都和真實資料一致。
- 開發：唯一的 GameCore PR（#1319）沒有問題；K1-1 的修法只動 GamePresentation 與 App，加一個模型包大小的測試，以後車輛 PR 不會再「沒有量」。
- 美術：無（模型由各自的 PR 照 art-style 檢查；K1-1 不改任何模型的樣子）。
- 音樂：無。
