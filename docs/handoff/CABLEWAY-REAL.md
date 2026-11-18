# CABLEWAY-REAL（2026-11-18）

工作串「讓纜車照真實路線收購」，分支 `claude/project-thread-a61k22`，決策 870。GameCore、存檔版本、golden 不動。

## 做了什麼

- 纜車模式的「照真實路線拉」從只有貓空，改成地圖上每一條還沒蓋的真實纜車各一顆按鈕（`GameSession.realCablewayOffers`，近的在前）。
- 加烏來空中纜車（`RealCableway.wulai`，OSM way 188552077，381 m）；日月潭的資料原本就有，現在也給按鈕。

- 2026-11-18 接續（工作串「加入昂坪 360 纜車」，決策 872）：加昂坪纜車（`RealCableway.ngongPing`，OSM way 26351045，東涌、機場島與彌勒山兩個轉向站、昂坪，5,767 m，接東涌綫東涌站）。吊廂沿用現有的。

## 還留下什麼

- 評分在 `a91453/railway-assets-private-2` `docs/priorities/CABLEWAY-REAL.md`：昂坪自己的吊廂、卡片用真實名字、烏來往復式車廂、列進出售清單、各條票價。都未派。
- 貓空原本就有按鈕，沒有要做的。

## UNVERIFIED

- App 那一排按鈕沒在模擬器或裝置上看過；整張台灣地圖會同時有三顆，請下一版 TestFlight 在纜車模式看一眼會不會太擠。
- 昂坪纜車（決策 872）沒在模擬器或裝置上看過：下一版 TestFlight 請在香港地圖開纜車模式，按「照真實路線拉昂坪纜車」，看兩個轉向站與纜線在山上、海邊的樣子，以及買了東涌綫後卡片有沒有寫「接 東涌站」。
