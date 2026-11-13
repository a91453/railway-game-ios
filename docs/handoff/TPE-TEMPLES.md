# TPE-TEMPLES：臺北廟宇照真實外形上 3D 地圖

- 派工單：`docs/research/TW_3D_MODELS_2026-11-13.md` §7 的 TPE-TEMPLES（遊戲規劃第 64 任派工）。
- Session：TPE-TEMPLES（`claude/tpe-temples`，PR 2146）；決策 725。存檔版本、golden schema 不動；GameCore、存檔、golden、fixtures 不動。

## 做了什麼

- `tools/tpe-temples/`：讀臺北市宗教建築 3D 模型庫的 KMZ（`fetch.sh` 下載並核對 SHA-256），只取外形、刷遊戲的顏色、以 meshoptimizer 簡化，寫成 `.m3dmodel`。
- 十座（龍山寺、行天宮、指南宮、臺灣省城隍廟、霞海城隍廟、天后宮、清水巖、濟南教會、慈諴宮、惠濟宮）在 `RailwayGameApp/Resources/Models/tpe-*.m3dmodel`。
- 場景：`Map3DTaipeiTemples.swift`，和決策 457 的地標一起放，取代決策 331 的套件廟。
- 資料來源頁新增「臺北廟宇模型」（中英文）。
- 細節在 `docs/decisions/725.md`。

## 還留下什麼

- **山上的廟**（指南宮、惠濟宮）：地面取模型四角最低的地面，坡上的地形會穿過模型。要嘛把模型的地面照地形切，要嘛把那幾格的地形壓平到模型的台階。還沒做。
- **另外四座**（保安宮、關渡宮、清真寺、青山宮）：資料集裡是 Google 3D Warehouse 的匯出、作者不明，這批不做。要做的話先找有授權的來源。
- **資料集其他的廟**：CSV 裡還有約七十座。做下一批時沿用 `recipes.mjs`：加一行配方，照 model-look 拍三輪。
- **惠濟宮的牌樓**（111003_archway）：在山下，地形接好之後再放。
- **實機（Metal）沒有看**：UNVERIFIED，要 TestFlight。
- **照片**：
  - 清水巖在維基共享資源只找到室內照，外觀照沒找到（找的時候被限流）。
  - 臺灣省城隍廟只有一張照片。

## 這個 session 停在哪裡（壓縮第 2 次，依規則停止）

- PR 2146 仍是**草稿**；head `27dabbc` 的 CI 還沒看，也還沒在 #2118 貼「可合併」。總覽圖要給遊戲規劃看過才能合併（第三級）。
- **顏色還沒定，作者不滿意**：
  - 作者看第八輪說「怎麼感覺灰色更多了」。對：`recipes.mjs` 的 `soften` 是把每個顏色往 #E4E3DF 混 35%，往灰混就是降彩度。
  - 作者又問「到底是誰的問題怎麼著色一直破圖」。是 `tools/tpe-temples/build.mjs` 的問題，不是資料集、也不是遊戲的調色：
    1. 顏色是**一面一面**挑的（每面取它底下照片的平均色，再挑最近的遊戲色），簡化後相鄰的三角形常挑到不同的色，同一片屋頂或牆就變成斑駁的補丁。
    2. 簡化後每面取「大多數原始面」的部位，細的脊、柱、簷邊常被分錯，變成一條條雜色。
    3. SketchUp 的面朝向是用射線猜的，猜錯的面打光變暗，看起來像破洞。
  - 下一步建議：**按部位整塊上色**，不要一面一面挑。先把同一部位、相連的面合成一塊（共用邊），一塊取一個顏色（照片平均或配方固定色）；再看要不要淡化。淡化改成「只提亮、保留彩度」：Lab 的 L* 往鋪面色的 L* 移 35%，a*、b* 乘 0.9（試作在本 session 的暫存區，未進 repository；寫法：`pale = (v, s) => { const [L,a,b] = lab(v), G = lab(0xE4E3DF)[0]; return fromLab([L + (G - L) * s, a * 0.9, b * 0.9]); }`）。
  - 改完照 model-look 再拍三輪給作者看；`Map3DTaipeiTemplesTests.palette` 要跟著換成新的色。

### CI 抓到的破圖原因（head `709b464`，`Map3DBundledModelFilesTests.testEveryBundledModelIsDrawnTheRightWayOut`）

- 十個 `tpe-*.m3dmodel` 都有「和鄰面繞向相反」的三角形：行天宮 700、龍山寺 594、惠濟宮 422、指南宮 335、濟南教會 313、慈諴宮 163、霞海 105、省城隍 68、清水巖 25、天后宮 21。這就是作者說的破圖：遊戲依繞向打光、剔背面，翻錯的面會變暗或消失。
- 原因在 `tools/tpe-temples/orient.mjs`：每一面各自用射線猜朝向，沒有和共邊的鄰面對齊。
- 修法：先依共用邊把相連的面繞向傳成一致（每個相連塊做一次廣度優先），再對整塊用射線多數決或有號體積（要 ≥ 0）決定整塊朝外還是朝內；兩面都要畫的薄片（剪影裝飾）照測試的規則可以留正反兩面。重跑 `fetch.sh` 與 `build.mjs`，這個測試和 `Map3DTaipeiTemplesTests` 要過。
- 資料來源測試（`RealRailwaysTests.testEverySourceIsCredited`）已在 `d9a67d5` 修好。
