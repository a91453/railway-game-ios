# HK-ISLAND-PLATFORM（決策 748）交接

- 派工：遊戲規劃第 65 任；雲端 thread session，分支 `claude/project-thread-nujxfn`。存檔版本、golden、GameCore 不動。
- 做了：香港在售收購線（`RealLineAcquisition`）真實是島式的站，兩股隔 11 m，3D 畫得出島：東涌綫香港、九龍、東涌；南港島綫金鐘、黃竹坑、利東、海怡半島；東鐵綫落馬洲支落馬洲；將軍澳綫康城支將軍澳、康城。站表與來源見 `docs/decisions/748.md`。
- 還留下：
  - 荃灣綫、觀塘綫、港島綫、屯馬綫開賣時，把決策 748 列好的島式站加進 `RealBranchLine.islandStations`。
  - 跨線同月台轉乘站要兩條線共用一座島，目前各鋪各的做不到。
  - 台灣的收購線（淡海、安坑、桃園機場捷運等）也是 5 m；真實島式站要另外查官方圖再加（同一個欄位就能用）。
- UNVERIFIED：沒在實機或模擬器上看過 3D（截圖見 PR）；只有 Linux 的建置與香港測試。
