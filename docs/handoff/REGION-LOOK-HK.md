# REGION-LOOK-HK

- 派工：遊戲規劃，2026-11-17（分數 2.85，目標 build 137）。Session：session_01JMHz9ZyBkSeXL3qpPx5JUD（雲端）。分支 `claude/region-look-hk`。決策 [812](../decisions/812.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。沒有碰 NATURE-BASE 的檔案。
- 做了：`Map3DRegionLook.Buildings.hongKong`（`hasArcades` 只有台灣）；`Map3DHongKongBuildings.swift`：住宅塔（淡彩牆、機房加水箱頂冠）、唐樓（舊色牆、馬賽克、地面店面、鐵皮小屋）、村屋、辦公玻璃帷幕、工業、公共建築，屋頂全部灰色（含大平台）；沿路的房子與密度方塊也用香港的。看圖四輪。台灣與羅瓦涅米的場景傾印逐位元組不變（一次性比對，見決策）。
- 總覽圖：`docs/art/region-look-hk-2026-11-17/overview.jpg`（左改前、右改後）。新外觀照 ui-review 要給遊戲規劃看過才合。

## 還留下什麼

1. **住宅塔的平面**：現在是外框直上的盒子；香港公屋的十字、Y 形與凸窗、退台沒有做（外框是資料的，形狀只有外框那麼像）。
2. **村屋（丁屋）**：沒有天台欄杆與樓梯間的典型輪廓；沙田一帶整片灰。
3. **街道**：路牌、人行道的灰磚色、香港路上的機車比例（`hasScooters`）沒有動；街道其餘在決策 732、743。
4. **整體偏淡**：`Map3DLook` 的城市調淡讓淡彩靠在一起；要更鮮明得動城市調淡的參數（影響台灣），沒有做。
5. **照片沒有在相同角度並排**：照片是 Flickr（決策 812 列出），只拿來對色與屋頂內容。

## UNVERIFIED

- iOS 建置、Metal 畫面、實機（macOS CI、TestFlight）；預覽是 WebGL。
- 完整測試留給 CI；本機跑了建置（warnings as errors）與相關的測試類別。
