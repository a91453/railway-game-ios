# TW-BRIDGES（2026-11-18）

工作串「做台灣的地標橋」，分支 `claude/project-thread-2rlx4u`（接在 #2468 之後，#2468 已合），決策 873。GameCore、存檔版本、golden 不動。

## 做了什麼

- 淡江大橋：橋塔、80 根斜拉索、兩條車道之間的橋面；索吊著的範圍橋面在河面上 20 m、下面沒有墩；橋塔那棟被當成公寓畫的建物足跡不再畫（`Map3DCableStayedBridge.swift`，`Map3DRoadBridge.swift` 的 `Bound.flat` 與 `bridgeDecks` 一段）。
- 台灣標了結構的橋與舊版模型目錄都查過，候選與分數在素材庫 `a91453/railway-assets-private-2` `docs/priorities/TW-BRIDGES.md`。

## 還留下什麼（都未派，分數在評分檔）

1. **其他斜張橋**：高屏溪斜張橋、新北大橋、大直橋。在 `Map3DSuspensionBridge.all` 加一列（塔位、主跨終點、跨度、`Map3DCableStays`）就會畫；每座先看照片：高屏溪是倒 Y 形塔、新北大橋與大直橋的塔是斜的，`Map3DCableStays` 現在只會畫直立的單柱，要各加一種塔形。
2. **關渡大橋**：三個紅色鋼拱。拱肋是倒過來的主纜（拋物線加吊桿），可以接在同一套上；紅色不在色票裡，要新提。舊版目錄有 200 m 與 110 m 的鋼拱橋可以參考比例。
3. **安坑輕軌安心橋**：鐵路斜張橋，橋面是軌道的高架不是公路橋，`suspendedDeck` 要能把高架當橋面。
4. **所有跨河的橋離開水面**（RIVER-BRIDGE-CLEARANCE）：決策 391 讓只跨河的橋留在地面，所以台北的河橋都貼在水上。這次只抬了淡江大橋；`Bound.flat` 可以直接用，但每張地圖的河橋與引道要重拍。
5. 青馬大橋抬到實物高度（素材庫 `HK-ROADS.md` 的 TSINGMA-CLEARANCE）現在可以用同一個 `Bound.flat`，鐵路高架要跟著抬。

## 重拍

```sh
cp tools/map3d-preview/Map3DPreviewDump.swift.txt Tests/GamePresentationTests/Map3DPreviewDump.swift
swift build --build-tests
MAP3D_WORLD=island MAP3D_AT=25.1754:121.4178 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 \
MAP3D_CROP=-50:150:1300 MAP3D_VIEWS="side:-50:150:1100:285:60:72;game:-30:120:520:300;mast:0:0:330:300:60:68;small:-30:120:1300:300" \
MAP3D_DUMP=<dir>/a swift test --skip-build --filter Map3DPreviewDump
```

改前的圖：把 `Map3DSuspensionBridge.all` 暫時改回 `[tsingMa]` 重建（約一分鐘），不用搬檔。

## UNVERIFIED

- Metal 與實機沒看過。下一版 TestFlight 請在台灣地圖的淡水漁人碼頭旁看淡江大橋：斜看要看得到塔與索、橋下沒有墩、河中央沒有那棟高樓。
- `Bound.flat` 只用在淡江大橋；其他橋的高度沒有變（`Map3DRoadBridgeTests` 全過）。
