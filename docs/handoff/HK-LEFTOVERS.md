# HK-LEFTOVERS：#2115 合併後留下的截圖測試（2026-11-13）

- 作者 2026-11-13「剩下的給你做」「綠了就合併 紅了就修」；專案討論串「修正遊戲目前的 bug」。分支 `claude/project-thread-5hrywn`（#2150 合併後從 main 重開）。登記在 #2118。
- 只改 `RailwayGameApp/UITests/WebsiteScreenshotTests.swift`。`Sources/`、存檔版本、決策號、golden schema、fixtures 都沒動。
- 依據：SHOTS-2115-2145 在作者 Mac 上跑的結果（#2118，2026-11-13 16:04 UTC 那一則）。

## 改了

| 測試 | 原因 | 改法 |
| --- | --- | --- |
| `testHongKongMap` | 等的是卡片上的 `train.stock`；港鐵沒有自己的車組（決策 697 第 4 點：買下後用通用的捷運車），`RealLineStock.setKey(ofRealLine:)` 照設計回 nil，那一列不會出現 | 改等跟隨列的 `train.unfollow`。**沒有改 `boughtStockText`**：給香港的車一個名字要先有車組，是另一張單 |
| `testAirRouteUnlock` | 英文「The whole of Taiwan」那一列超出畫面，香港那一列沒建立，測試卻先等 180 秒才拖 | 先拖、後等（還沒出現時每拖一次等 3 秒，最多 45 次） |
| `testSightVisitors` | 面板先列機場，景點卡在畫面外，`tourism.officialVisitors` 不存在 | 先把清單往上拖到那一列整個在畫面上 |
| 上面兩個與 `openAirports` | iOS 27.2 上遊戲選單的「更多」沒有 `menu.more` 這個識別碼 | 新的 `openSights(in:)`：有 `hud.sights` 就按它，否則走選單，「更多」用識別碼或標籤找 |

其他五處 `menu.more`（`WebsiteScreenshotTests` 三處、`Feature284To286UITests`、`PromoMaterialTests`）沒有動：沒有在 27.2 上看過它們紅。CI 的模擬器若升到 27.2 再一起改。

## 沒修，要在 Mac 上看

1. **香港 3D 近景九龍站旁四塊土黃色方地**：讀程式與 `hong-kong-map-3d-near.png` 的判斷是站房佔到的 64 m 格子被鋪成站前廣場（`Map3DScene.swift` 約 1937 行的 `Map3DPalette.plaza`＋鋪面；`addStations` 回傳的 `cells`）。九龍站的站房跨了四格，四格又都沒有真實建物，所以看起來像四塊空地。這是所有車站共用的畫法，臺灣的站周圍有房子所以不顯眼。可能的做法：真實地圖上只鋪站房實際蓋到的範圍、或顏色靠近地面色。要照 `model-look` 拍圖比較，沒有模擬器不猜。
2. 拉遠看不到港島天際線；從香港開始選地圖時背後還是台北的地圖。都要看圖。

## UNVERIFIED

- 這個雲端環境裝不了 Swift，也沒有 Xcode：測試檔只由 iOS CI 編譯；截圖測試不在 PR 的 gate 清單裡，**要跑 `website-screenshots.yml`（`testHongKongMap`、`testAirRouteUnlock`、`testSightVisitors`）才知道綠不綠**。
