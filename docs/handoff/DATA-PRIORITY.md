# DATA-PRIORITY

派工單 DATA-PRIORITY（session_01YGNNukqd655zMp5Q6x8DXF，`claude/data-priority`，2026-11-13；遊戲規劃第 64 任派，#2118；作者：「開一個session排優先順序」）。只研究、只寫文件。不動 GameCore、存檔版本、決策號碼、golden、三套 fixture、`Sources/`、`RailwayGameApp/`、`tools/`。

## 做完的

- `docs/research/DATA_PRIORITY_2026-11-13.md`：作者 11-13 問的全部資料來源（香港政府 24 項、WorldCover、OSM 路面與階梯、VIIRS 夜間燈光、星空、台灣官方統計）的總表、先後、前三名的任務單、五個角度。規劃點名的十項實際下載樣本量過。
- `docs/research/NEXT_PRIORITIES_2026-10-12.md` §28：指向上面那份（只加，沒改別節）。

## 結論（細節在文件第 0、5 節）

1. HK-GROUND（香港地形與水域，地政總署 DTM）→ 2. HK-BUILDINGS-GOV（香港建物改用地政總署）→ 3. TOURISM-OFFICIAL-1（景點卡顯示官方人次）→ 4. HK-NAMES → 5. TOURISM-OFFICIAL-2 → 6. AIRPORT-MONTHS → 7–12 之後。
- 和規劃初步判斷不同的一處：地形排在建物前面（理由在文件第 0 節第 3 點）。
- 條款：DATA.GOV.HK 與 CSDI 都可商用、要標示、都有賠償條款（文件第 2 節）。

## 還留下的（都沒有派工，等規劃決定）

1. 前三名的任務單在文件第 6 節。第 1、2 名要等 #2115（AIR-UNLOCK-4）合併；第 3 名現在可派。
2. 第 1 名趕不趕 130，是規劃與作者的時機判斷（文件 5.1）。
3. 3D Visualisation Map、3D-BIT00：等 HK-3DVIS 的 `docs/research/HK_3D_VISUALISATION_MAP_2026-11-13.md`，之後把它的結論插進這份的 A1、A2 兩列。
4. 給 ROAD-LAYER 的一句：Copernicus 高度在市區把大樓算進地面（香港量到平地相鄰兩格平均差 3.3 m，地政總署的只有 1.2 m）；台灣市區用的也是 Copernicus，開工時先量。
5. 賠償條款沿用 HK_MAP 當時「可以接受」的判斷；作者若不接受，香港每一項的替代寫在文件 2.2。

## UNVERIFIED

見文件第 10 節：沒有任何一項接進遊戲；工作量與地圖包大小是估的；建物多兩倍後的三角形預算沒量；星空那幾項沒有重查；下載的樣本與腳本沒有提交（重抓方法在文件第 8 節）。
