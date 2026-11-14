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

## 現況（TPE-TEMPLES-2，2026-11-13）

- 第一個 session 壓縮兩次後停下；另一個接手 session 先在 `51b324c` 加了 `wind.mjs`、用 `rewind.mjs` 直接改十個檔的繞向（它下載不到 KMZ）。TPE-TEMPLES-2 從 KMZ 重建（雲端 `fetch.sh` 下載得到，SHA-256 都對），`rewind.mjs` 因此拿掉。
- **繞向**：簡化前 `orient.mjs` 依共用邊對齊、整塊以射線定朝外；簡化後 `wind.mjs` 用確切座標再對齊一次。十座和鄰面相反的邊都是 0、沒有正反兩面的面；`Map3DBundledModelFilesTests` 本機通過。
- **顏色**：同一部位、相連的面合成一塊，一塊一個顏色（`blockColours`），簡化時色界當接縫；淡化改成只提亮、保留彩度（`pale`）。作者的「斑駁」「太灰」兩點都照這個改了；`Map3DTaipeiTemplesTests.palette` 已換成新的 19 色。
- 看圖三輪（第九至十一輪）與「還有哪裡不好」寫在決策 725。
- PR 2146 還是草稿，等 CI 綠、遊戲規劃看總覽圖（第三級）。

## 還沒做

- 山上兩座的地形、3D Warehouse 的四座、資料集其他的廟、惠濟宮的牌樓：見上面「還留下什麼」。
- 慈諴宮、惠濟宮幾段廊道屋頂是石板灰（照片是橘紅瓦）；要改可以在配方加 `tint: { roof: 'default' }`，但那幾座也有真的灰色鐵皮頂，要看照片逐座判。
- 實機（Metal）沒有看：UNVERIFIED，要 TestFlight。
