# STATION-BUY-STACK：收購車站後真實軌道重複堆疊

- 派工：遊戲規劃第 65 任；工作串「修正收購線不沿用預設線而重複堆疊」；雲端 thread session，branch `claude/project-thread-ddrcsn`。
- 決策 742（修訂 402）；存檔版本、golden、GameCore 不動。
- 做了什麼：3D 地圖的真實軌道與真實列車在玩家軌道同向 16 m 內、玩家月台旁 32 m 內讓開（`Map3DRealTrains.swift`）。舊存檔不用清。
- 還留下：
  1. 「隨意鋪設跟沿真實的一起設定」：手鋪軌道靠近真實線且同向時吸到中心線。五方 3.15，未派。
  2. 收購車站改鋪真實的股數（決策 742 選項 B，3.20），未派。
- UNVERIFIED：裝置與模擬器上的 3D 畫面沒看過（雲端沒有 Swift、沒有 Xcode）；Linux 測試交 CI。
