# STATION-BUY-STACK：收購車站後真實軌道重複堆疊

- 派工：遊戲規劃第 65 任；工作串「修正收購線不沿用預設線而重複堆疊」；雲端 thread session，branch `claude/project-thread-ddrcsn`。
- 決策 742（修訂 402）；存檔版本、golden、GameCore 不動。
- 做了什麼：3D 地圖的真實軌道與真實列車在玩家軌道同向 16 m 內、玩家月台旁 32 m 內讓開（`Map3DRealTrains.swift`）。舊存檔不用清。
- 還留下（照五方分數排，權重同 §19）：
  1. **收購車站時照真實鋪島式或岸式月台**（作者 11-14「收購的時候自動給正確的島式、岸式月台」）：用決策 741 的月台型式表（`tools/station-platform-types/platform_types.json`，#2191），雙線站鋪兩股，島式隔 11 m、岸式兩側各一座。含了決策 742 的選項 B（收購鋪真實股數）。玩家 4、開發 3、美術 4、鐵道迷 5、音樂 1 → **3.45**。等 #2191 合併；只動 GamePresentation（`RealStationPurchase.swift`），價格會變（多一股軌道與月台）。
  2. 「隨意鋪設跟沿真實的一起設定」：手鋪軌道靠近真實線且同向時吸到中心線。玩家 4、開發 3、美術 3、鐵道迷 4、音樂 1 → **3.15**。
  3. 圖上看到的：收購站兩頭外的真實線斷頭（八堵高處），玩家往外鋪就退開，不另做。
- 截圖：作者 Mac 上 `tools/map3d-preview` 拍了樹林、桃園、八堵的前後（`~/Developer/pr2193-shots/out/`），作者 11-14 看過說可以。
- UNVERIFIED：真實列車讓開沒拍到（預覽不畫真實列車）；手機的 Metal 畫面沒看過。
