# CABLEWAY-REAL（2026-11-18）

工作串「讓纜車照真實路線收購」，分支 `claude/project-thread-a61k22`，決策 870。GameCore、存檔版本、golden 不動。

## 做了什麼

- 纜車模式的「照真實路線拉」從只有貓空，改成地圖上每一條還沒蓋的真實纜車各一顆按鈕（`GameSession.realCablewayOffers`，近的在前）。
- 加烏來空中纜車（`RealCableway.wulai`，OSM way 188552077，381 m）；日月潭的資料原本就有，現在也給按鈕。

## 還留下什麼

- 評分在 `a91453/railway-assets-private-2` `docs/priorities/CABLEWAY-REAL.md`：昂坪 360、卡片用真實名字、烏來往復式車廂、列進出售清單、各條票價。都未派。
- 貓空原本就有按鈕，沒有要做的。

## UNVERIFIED

- App 那一排按鈕沒在模擬器或裝置上看過；整張台灣地圖會同時有三顆，請下一版 TestFlight 在纜車模式看一眼會不會太擠。
