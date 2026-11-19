# CABLEWAY-NO-RIDERS（2026-11-18）

工作串「讓真實路線纜車有乘客」，分支 `claude/project-thread-88u441`，決策 880。動 GameCore 的規則；存檔版本、golden、replay 不動。

## 做了什麼

- 所有纜車共用的新規則：營運日，載客站 2 公里內每個景點當天遊客的一成來回各搭一次，不用接車站；纜線不到 1,500 m 照比例減少；一個景點只算給最近的一條（`Cableway.sightseerReach`、`sightseerShare`、`sightseerFullMetres`，`GameWorld.cablewaySightseerRides(_:onDay:)`、`sights(ofCableway:)`）。接了車站後和決策 586 相加。
- 香港補天壇大佛（`AttractionCatalog.hongKongSpots`）；舊的香港存檔讀進來時補上（`AttractionCatalog.withSights`，在 `GameSession.init`）。
- 纜車卡片多一列：誰會來搭，或「附近沒有車站，也沒有景點」。
- 量到的（一月，沒接車站）：日月潭平日 1,212 乘次、約 15 天回本；烏來 136、約 61 天；昂坪 428、約 150 天。改之前都是 0。

## 還留下什麼

評分在 `a91453/railway-assets-private-2` `docs/priorities/CABLEWAY-NO-RIDERS.md`，都未派：香港其他景點、建造前預覽寫出景點、重量貓空與昂坪接上鐵路後的收支。

## UNVERIFIED

- 沒在模擬器或實機看過。下一版 TestFlight 請在香港舊存檔開纜車模式拉昂坪纜車，隔一個遊戲日（不是週一）看卡片「昨天：乘客」不是 0，並有「天壇大佛的遊客會來搭」那一列；台灣地圖的日月潭、烏來也一樣看。
- 昂坪接東涌綫、貓空接文湖線之後的乘客沒有重量。
