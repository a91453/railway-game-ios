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
   隔一座島式月台（11 m）、高度照原有月台（決策 848）。
2. **兩條線要在同一局、兩種順序都買過。** 每條線各開一局的測試抓不到共站的問題（決策 809、848 都是這樣漏的）。
3. **量位置，不只量成不成功。** 每座月台的平面位置與高度印出來看（下面第 3 節的探針）；相距 < 4 m 又差 ≥ 2 m 高就是疊。

## 2. 改完要跑

```sh
swift test --skip-build --filter SharedStationLayoutTests     # 三張地圖，同站月台不疊；羅瓦涅米同一高度
swift test --skip-build --filter RovaniemiRailwaysTests
swift test --skip-build --filter "RealLineAcquisitionTests|RealLineRebuildTests|HongKongEveryLineTests|HongKongSharedTrackBuyOrderTests|LiujiaLineTrainsTests"
```

加新地圖（新的 `OverseasMap`）或新的出售路線時，在 `SharedStationLayoutTests` 加一個「全部依序買下、`stacked` 為空」的測試。

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
| 第二條線被拒「並行不到 4 m」，改成抬高共站再試，結果四股月台疊在第一條線正上方 16 m | 共站先鋪在旁邊（`sharedEnds`）、同一高度；抬高只留給真實高架 | 809 → 848 |
| 竹中六家線（真實高架）的月台在內灣線地面月台正上方 | 高架可以，但要在旁邊，不在頭上 | 462 → 848 |
| 拆掉的線重買，旁邊留著自己的舊軌道 | 舊軌道要拆掉重鋪（`RealLineClearing`），不是鋪在旁邊：`sharedEnds` 只看有別條線停靠的站 | 528、848 |
| 香港兩條線沿同一條真實線形（機場快綫、東涌綫） | 整段推成兩條車道（`overseasLanes`） | 753 |

做完一件收購鋪線的工作，在第 4 節加一列，寫決策號。
