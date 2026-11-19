---
name: real-line-laying
description: 收購真實路線怎麼鋪（RealLineLaying、RealLineAcquisition）：車站、站內待避線、第二條正線、高架與隧道、和公司已有的線共站。改鋪線規則、加新地圖的線、或有人回報「兩條線月台分開／疊在一起／一條在橋上一條在橋下」之前先讀。Use before changing how a real line is laid when bought (RealLineAcquisition.swift, RealLineSharedStation.swift, RealLineRing.swift), adding a new map's lines for sale, or when a report says two lines' platforms at one station are split, stacked or on different levels.
---

# 收購鋪線：先量位置，再看買不買得到

收購真實路線的鋪法在 `Sources/GamePresentation/RealLineAcquisition.swift`（`RealLineLaying.offer`）。
「買得到」只代表 GameCore 沒拒絕，**不代表鋪得對**：決策 809 讓羅瓦涅米第二條線買得到，代價是整座月台抬到 16 m
疊在第一條線頭上，測試全綠，直到作者在 iPhone 上看到（決策 848）。

## 1. 三件最常忘的事

1. **同一站的兩條線：並排、同一高度。** 不要用抬高（`viaductsAndShared`）繞過「並行太近」。抬高只給真實在高架上的站
   （決策 462 的 `isRaised`，看真實結構資料）。第二條線的端點站和公司的站共站時，`sharedEnds` 會把它鋪在原有股道旁、
   隔一座島式月台（11 m）、高度照原有月台（決策 848）。線**中間經過**的共站，撞到時先照同樣做法挪到旁邊（兩個方向各自保持），
   還撞才抬高（決策 863）；共站的高度一律照原有月台（地面、路塹、地下的都算）。高架上的月台也照（決策 875）：
   公司在那一站有高架上的月台（離地 4 m 以上）時跟著它們的高度；鋪不上（坡度到不了、同高度相撞）才照各自的真實結構鋪。
2. **兩條線要在同一局、兩種順序都買過。** 每條線各開一局的測試抓不到共站的問題（決策 809、848 都是這樣漏的）。
3. **量位置，不只量成不成功。** 每座月台的平面位置與高度印出來看（下面第 3 節的探針）；相距 < 4 m 又差 ≥ 2 m 高就是疊。

## 2. 改完要跑

```sh
swift test --skip-build --filter SharedStationLayoutTests     # 每張地圖，同站月台不疊、同一高度（`uneven` 為空）
SHARED_STATION_REPORT=/tmp/shared.txt swift test --skip-build --filter SharedStationLayoutTests/testReport   # 每個共站的高度、離地、價格；改前改後各印一份比
swift test --skip-build --filter RovaniemiRailwaysTests
swift test --skip-build --filter "RealLineAcquisitionTests|RealLineRebuildTests|HongKongEveryLineTests|HongKongSharedTrackBuyOrderTests|LiujiaLineTrainsTests|RealLineBoughtAgainTests"
```

加新地圖（新的 `OverseasMap`）或新的出售路線時，在 `SharedStationLayoutTests` 加一個「全部依序買下、`stacked` 為空」的測試（有共站的線兩種順序都買），再把地圖加進 `mapsChecked`；沒加的話 `testEveryOverseasMapHasItsSharedStationsChecked` 會紅。

共用車站的線是**整組一起賣**的（決策 862，`RealLineBundle`）：哪幾條一組從站名自動算，鋪設順序＝遊戲列出路線的順序（`urbanLines`、`overseasLines` 裡誰寫在前面誰先鋪）。
所以新路線在清單裡的位置就是它在線組裡的鋪設順序，放之前先想好；`RealLineBundleTests.testEveryMapSellsItsLinesThatShareAStationTogether` 釘住每張地圖的線組，新地圖加一行。
反過來的順序只會出現在舊存檔（以前單買的），測試仍然兩種順序都買。

## 3. 探針（看每座月台在哪）

在測試裡買好線之後：

```swift
for p in world.network.platforms(of: station) {
    let g = world.trackGeometry(of: p.edge)!
    let mid = g.location(at: (p.start + p.end) / 2).position
    print(p.edge, mid, world.groundHeight(at: mid.plan) as Any)   // 64 單位 = 1 m
}
```

3D 對照圖：`tools/map3d-preview/README.md`，`MAP3D_WORLD=rovaniemi MAP3D_BUY=vr:KJA,vr:MUL`（香港 `hongkong`、`MAP3D_BUY=hkmtr:...`）。

## 4. 歷次的教訓

| 發生過什麼 | 之後照這樣做 | 出處 |
| --- | --- | --- |
| 共站的線一條條賣，後買的要繞著先買的鋪，每種購買順序各出過事（疊月台、漏班、鎖死），每修一次要量每一種順序 | 共站的線整組一起賣、一種鋪法（清單順序＝每晚體檢量的順序）；整組買與照順序一條條買的世界必須相等（`RealLineBundleTests`） | 862 |
| 第二條線被拒「並行不到 4 m」，改成抬高共站再試，結果四股月台疊在第一條線正上方 16 m | 共站先鋪在旁邊（`sharedEnds`）、同一高度；抬高只留給真實高架 | 809 → 848 |
| 竹中六家線（真實高架）的月台在內灣線地面月台正上方 | 高架可以，但要在旁邊，不在頭上 | 462 → 848 |
| 拆掉的線重買，旁邊留著自己的舊軌道 | 舊軌道要拆掉重鋪（`RealLineClearing`），不是鋪在旁邊：`sharedEnds` 只看有別條線停靠的站 | 528、848 |
| 香港兩條線沿同一條真實線形（機場快綫、東涌綫） | 整段推成兩條車道（`overseasLanes`） | 753 |
| 福岡加地圖時漏了本檔第 2 節的共站測試；補了之後發現：先買只到共站的線、最後買穿過它的線（空港線過博多、中洲川端），穿過那條的月台被抬高 16 m（`sharedEnds` 只挪端點） | `SharedStationLayoutTests.mapsChecked` 沒列新地圖就紅 | 854 |
| 上一列：中洲川端的箱崎線股道和空港線線形重合，空港線一撞就被抬高；反過來買，地下幾公尺的月台不算「地面月台」，高度差 3–6 m；香港九龍、欣澳也差 4–6 m | 撞到時先把中間經過的共站也挪到旁邊（`sharedEnds(through:)`，只當後備，原本鋪得上的線不動），還撞才抬高；共站一律對齊原有月台高度。量高度要兩種順序都量、**每張地圖的每個共站**都印出來（測試的 `between`），不只量有沒有疊 | 863 |
| 香港、福岡的真實地下站鋪在地面（香港只有利東在隧道，福岡 0 站）：真實隧道的規則只開給文湖線；站在隧道資料端點上的站靠四捨五入；車道裡的線離隧道資料 25 m 對不到 | `followsRealTunnels` 開給地圖時用 `REAL_UNDERGROUND_REPORT=<檔>`（`RealUndergroundTests/testReport`）印出每座月台的型式與深度，對照真實；新地圖的地下站加進 `RealUndergroundTests`；共站兩種順序照舊量 | 867 |
| 真實隧道的規則開給台灣其他線時，機捷不只環北與淡水河變：體育大學變成地下站後整條線不再需要額外的車站寬限，16 個高架站從 10 m 回到 16 m，舊線改建的重鋪範圍接不回去，擬真規則的體檢數字也動了 | 開規則給一條線前後用 `LINE_HEIGHT_REPORT=1` 逐站對照**整條線**，不只看目標站；跑那條線兩種規則的整天體檢與 `RealLineRebuildTests` | 871 |
| 香港青衣：東涌綫在高架 16 m、機場快綫離地 4.4 m。機場快綫鋪在旁邊 25 m 的車道（`overseasLanes`），找真實的橋只找 20 m 內，青衣的高架與青馬大橋都對不到，過海時比東涌綫低 28 m；另外高架站完全不對齊共站高度 | 寫進 `overseasLanes` 的線，找橋與隧道的範圍都要加上車道偏移；共站跟著已有月台的高度（高架上的也算），鋪不上才退回原來的鋪法。量高度時把整條線逐點印出來（`SHARED_STATION_PROFILE`），和旁邊那條線比，不只看車站。竹中還差（六家線竹中端的路徑和內灣線相交），另一張單 | 875 |
| 竹中兩條一起買之後刪六家線，買不回來：內灣線當初是繞著六家線鋪的（偏南 60 m），重鋪的六家線被挪到它旁邊，鉤狀路徑和自己相交，每種退路都被拒。另外試過「重買一律先照原位鋪」，後鋪的內灣線會鋪回六家線正下方、又疊成兩層 | 刪掉再買回來要鋪回第一次買的位置：平常鋪法全被拒才照原位鋪（`whereItStood`），不能反過來。改鋪法後跑 `RealLineBoughtAgainTests`（每張地圖每個線組逐條刪掉再買，檢查位置）；新地圖的線組要加進去 | 528「後來」 |
| 淡海兩條一起買之後刪綠山線再買回來，9 站偏 25–30 m、掉到地面：`onSale` 只看「另一條買了沒有」就把它當成「鋪在另一條旁邊」，但一起買時藍海線只從濱海沙崙起，旁邊沒有軌道；鋪在旁邊 30 m 的線又找不到 20 m 內的真實高架。舊存檔先藍海再綠山也因此差 10–17 m，而且「跟著已有月台」九站一起鋪不上就整條放棄 | 「在另一條之後」只在那條真的鋪在共用段時才算（`isLaidAlong`）；偏移鋪的線找真實結構的範圍要加上偏移（車道、旁邊都一樣）；跟月台高度鋪不上時能跟幾站就跟幾站。改完比 `SHARED_STATION_REPORT` 改前改後，其他地圖要逐行相同 | 493「後來」 |
| 竹中兩條線一高架一地面（作者 140 實機）：竹中站在內灣線與六家線兩條描線中間（相隔 13 m），站點抓最近的內灣線，六家線的路徑從那裡先往回 15 m、跨到自己的線再往前，平滑後成了鉤，月台轉成和內灣線垂直、在站內相交，內灣線只好留在地面；`sharedEnds` 又把站外兩線會合的那段算進去，把內灣線推到 16 m 外，畫不成一座島 | 端點站在兩條描線之間時，選讓整條路徑最短的那條（`endsWithoutDoublingBack`，只比最近那條遠 30 m 內的），路徑兩頭不准折返；共站端點離公司軌道多遠，只看站內與站外 40 m（`sharedEndPast`），站外會合的一段不算；轉乘端點的一股待避線放朝另一條線那側、離正線 4.5 m（`interchangeLoopOffset`），3D 才畫成側式＋兩線之間一座島（6 m 會被畫成每條線自己的窄島），改月台配置要用 `Map3DScene.Builder.addPlatforms` 看實際畫出哪幾座島。改了以後跑 `SHARED_STATION_REPORT` 看每張地圖逐行的差 | 875「後來」 |

做完一件收購鋪線的工作，在第 4 節加一列，寫決策號。
