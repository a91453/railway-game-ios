# 3D 地圖的列車：程式自己建模（2026-10-15）

ARCHITECTURE 決策 230。作者看過搬進來的參考庫白模後說「根本一模一樣，從裡面學習怎麼建模就好」，所以這裡的列車全部由程式生成（`Sources/GamePresentation/Map3DModels.swift`），不含參考庫的任何幾何。

`models.jpg`：五種樣式的頭車與中間車。由左上依序是通勤電車、自強號（EMU3000）、高鐵、捷運、中運量。

- 紅色是預覽用的路線色。遊戲裡換成那條路線的顏色；沒有路線的列車用藍色。
- 用 scratchpad 裡的 Python 小程式做軟體算圖：z-buffer、每個頂點的顏色在三角形上內插（和 Metal shader 一樣），從左前上方看。
- 沒有在 iPhone 上看過（UNVERIFIED），要等 TestFlight。
