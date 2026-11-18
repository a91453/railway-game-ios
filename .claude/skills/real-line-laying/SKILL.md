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
   還撞才抬高（決策 863）；共站的高度一律照原有月台（地面、路塹、地下的都算，高架的不算）。
2. **兩條線要在同一局、兩種順序都買過。** 每條線各開一局的測試抓不到共站的問題（決策 809、848 都是這樣漏的）。
3. **量位置，不只量成不成功。** 每座月台的平面位置與高度印出來看（下面第 3 節的探針）；相距 < 4 m 又差 ≥ 2 m 高就是疊。

## 2. 改完要跑

```sh
swift test --skip-build --filter SharedStationLayoutTests     # 三張地圖，同站月台不疊；羅瓦涅米同一高度
swift test --skip-build --filter RovaniemiRailwaysTests
swift test --skip-build --filter "RealLineAcquisitionTests|RealLineRebuildTests|HongKongEveryLineTests|HongKongSharedTrackBuyOrderTests|LiujiaLineTrainsTests"
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

做完一件收購鋪線的工作，在第 4 節加一列，寫決策號。
