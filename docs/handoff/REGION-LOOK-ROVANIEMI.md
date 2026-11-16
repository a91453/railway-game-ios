# REGION-LOOK-ROVANIEMI

- 派工：遊戲規劃，2026-11-16。Session：session_01JMHz9YvGc7LubHHqi3taji（雲端）。分支 `claude/region-look-rovaniemi`。決策 [802](../decisions/802.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。
- 做了：`Map3DRegionLook`（街道、建物、雪、軌距依錨點，規則在一處）；芬蘭的街道（`Map3DStreetRegion.finland`）；北歐的建物（`Map3DNordicBuildings.swift`：木屋斜屋頂、公寓平頂、屋頂積雪、北歐色票，沒有水塔、鐵皮屋、騎樓、鐵窗、招牌）；`Map3DRegionLookTests`。台灣與香港的畫面不變（測試，加一次性的整場景雜湊比對，見決策）。

## 還留下什麼

1. **香港的建物**（REGION-LOOK-HK）：在 `Map3DRegionLook.Buildings` 加 case，`init(anchor:)` 的香港範圍指過去；`addRealBuilding` 與 `addTownHouse` 已依 `look.buildings` 分支。
2. **照片沒有真的並排看**：Commons 的圖檔在這個環境被限流，只讀到說明頁（連結在決策 802）。請看得到照片的 session 或作者判 `docs/art/region-look-rovaniemi-2026-11-16/overview.jpg`。
3. **樹還是夏天的綠**、河湖沒結冰（ROVANIEMI-SNOW）。
4. **車站本體、號誌機、路燈、站牌還是台灣的模型**。
5. **遠景的房子是平頂**（`addFarTownHouse` 的北歐版與真實足跡的遠景網格沒有斜屋頂），拉近會跳；不是矩形的矮房子也是平頂。
6. **森林與水**：預覽看起來市區外的林地與河面夠分辨，這張沒有動 WorldCover / Maastotietokanta；要更細的林地邊界時另開一張。
7. 決策 799 交接的其餘各項（備用車擋夜車、同一局買兩條線、列車輪距、聖誕老人村地標）沒有動。

## UNVERIFIED

- iOS 建置、Metal 畫面、實機（macOS CI、TestFlight）。地圖沒開放，沒有截圖驗收。
- 預覽圖是 WebGL 算的。
- 完整測試留給 CI；本機只跑了建置（warnings as errors）與相關的測試類別。
