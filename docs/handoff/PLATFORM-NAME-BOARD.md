# PLATFORM-NAME-BOARD（2026-11-19）

工作串「加上月台站名牌」，分支 `claude/project-thread-8uhmt6`，決策 882。GameCore、存檔版本、golden 不動。

## 做了什麼

- 平面、高架、地下（側式與島式）月台背面立站名牌，寫遊戲裡的站名，面向自己的軌道；所有地圖共用
  `Map3DPlatformProps.nameBoards`，在 `addPlatformProps` 畫，只在最近的細節層。
- 字形：Noto Sans TC Bold 點陣化（`tools/platform-name-board/build_glyphs.py` → `Map3DBoardGlyphsData.swift`）。
  **新地圖或新資料帶來新字時要重跑**（指令在工具開頭）；沒有的字只是略過不畫，不會壞。

## 還留下什麼

- 英文站名與前後站、地下站寫在軌道對面牆上的站名：沒做（評分檔 PLATFORM-FURNITURE.md）。
- 造型照舊版 `45e46be7`／`460efb19` 的站牌（灰框白底綠帶），但舊版吊在雨棚下，這裡立在背面柱上（雨棚太低）。

## UNVERIFIED

- 沒在 App、模擬器或實機看過。下一版 TestFlight 請在一個平面站、一個高架站、一個地下站跟車進站看一眼：
  站名牌的大小與高度、字讀不讀得出來、入夜有沒有亮、有沒有被雨棚柱擋住或和人重疊。
