# TW-3DMODEL：台灣官方 3D 建物與地標模型的研究

- 派工單：TW-3DMODEL（遊戲規劃第 64 任，2026-11-13；作者：「很有用耶 有很多模型 那台灣沒有嗎」）。
- session：雲端 session_01YGNNumo45JSR7AjTvewXyb；分支 `claude/tw-3dmodel`。
- 只有文件：`docs/research/TW_3D_MODELS_2026-11-13.md`、這個檔。程式、存檔版本、決策、golden、fixtures 不動；沒有 commit 模型。

## 做了什麼

- 查了並實際下載：臺北市宗教建築 3D 模型庫（43 個 KMZ 全部）、國土測繪中心三維建物的 3D Tiles 服務（22 縣市的目錄、11 處 464 塊磚）、data.gov.tw 的搜尋、Sketchfab 的 API。
- 結論與先後在研究文件 §0、§7；第一名的任務單 **TPE-TEMPLES** 在 §7。

## 還留下什麼

1. **國土測繪中心三維建物可以接**（作者 2026-11-13：「之前問過 照政府資料開放授權條款第 1 版 就能用」；研究文件 §0 的更正）。不用再寄信。待派：把量測高度接進 `tools/overture-footprint-tiles`（研究文件 §7 第 2 名），LOD3 地標另一張。repo 裡 `docs/HANDOFF.md` 與決策 389 還寫「作者還在考慮」，作者貼的官網原句是「開放資料專區下載使用。(依政府資料開放授權條款第 1 版)」；出處 `https://whgis-nlsc.moi.gov.tw/Support/QA.aspx`；問三維建物有沒有在裡面，作者答「有啊問了」。這個 session 打不開那一頁（雲端連不上），接的那個 PR 在 Mac 上把那一則問答與專區清單抄進決策。自然人憑證的樣本框（§6）變成可做可不做。
2. **待派**：TPE-TEMPLES（臺北寺廟第一批 8–10 座），還沒有人做、沒有取決策編號。
3. 臺北寺廟裡 11 個從 Google 3D Warehouse 匯出的檔（保安宮、關渡宮、清真寺等），原作者不明，要先問臺北市民政局再用。
4. 要在作者的 Mac 上再試的清單：研究文件 §6（高雄與桃園的開放資料站、data.taipei 站內搜尋、TGOS、3d.taipei 的圖層說明）。

## UNVERIFIED

- 沒有把任何模型轉檔或畫出來看；樣本在 session 的 scratchpad，session 結束就沒有了，網址與指令都在研究文件裡可以重抓。
- 其餘見研究文件 §8。
