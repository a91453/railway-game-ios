# TW-3DMODEL：台灣官方 3D 建物與地標模型的研究

- 派工單：TW-3DMODEL（遊戲規劃第 64 任，2026-11-13；作者：「很有用耶 有很多模型 那台灣沒有嗎」）。
- session：雲端 session_01YGNNumo45JSR7AjTvewXyb；分支 `claude/tw-3dmodel`。
- 只有文件：`docs/research/TW_3D_MODELS_2026-11-13.md`、這個檔。程式、存檔版本、決策、golden、fixtures 不動；沒有 commit 模型。

## 做了什麼

- 查了並實際下載：臺北市宗教建築 3D 模型庫（43 個 KMZ 全部）、國土測繪中心三維建物的 3D Tiles 服務（22 縣市的目錄、11 處 464 塊磚）、data.gov.tw 的搜尋、Sketchfab 的 API。
- 結論與先後在研究文件 §0、§7；第一名的任務單 **TPE-TEMPLES** 在 §7。

## 還留下什麼

1. **作者的事**：寄信問國土測繪中心能不能把三維建物的高度與 LOD3 外形做進 App（五個問題在研究文件 §2.4）；用自然人憑證在平臺上申請一個樣本框（§6）。問到可以之前，測繪中心那一份不進 App。
2. **待派**：TPE-TEMPLES（臺北寺廟第一批 8–10 座），還沒有人做、沒有取決策編號。
3. 臺北寺廟裡 11 個從 Google 3D Warehouse 匯出的檔（保安宮、關渡宮、清真寺等），原作者不明，要先問臺北市民政局再用。
4. 要在作者的 Mac 上再試的清單：研究文件 §6（高雄與桃園的開放資料站、data.taipei 站內搜尋、TGOS、3d.taipei 的圖層說明）。

## UNVERIFIED

- 沒有把任何模型轉檔或畫出來看；樣本在 session 的 scratchpad，session 結束就沒有了，網址與指令都在研究文件裡可以重抓。
- 其餘見研究文件 §8。
