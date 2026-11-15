# AIR-BALANCE：航線回本天數

- 派工：主規劃（工作串「調整航線回本天數」），作者 11-15 問 A2（#2226）量出的回本「有疑慮」；照「一串一件事」在這串調。
- session：雲端 thread session，分支 `claude/project-thread-ralqzq`。
- 決策 762（`docs/decisions/762.md`）；存檔版本、golden schema、golden、replay 不動。
- 做完：旅客的價錢改成 65 天的票錢、窄體／廣體每公里 NT$600／NT$1,200、十九座每公里 NT$100 與每天 NT$1 萬；55 條的回本目標測試 `AirRouteMarketTests.testEveryRoutePaysBackInItsBand`；實際日結報告 `testTheSettledDays`（`AIR_ROUTE_REPORT=<天>`）。
- 還留下：
  - 長程票價改凹曲線（AIR-FARE-CURVE，NEXT_PRIORITIES §29.8 第 16 名，2.25）。
  - 花蓮—香港 778 天超出目標（決策 762「平衡」）；要修就是「旅客的價錢只算載得到的人」，要先擋住「小飛機買、再換大飛機」的漏洞。
  - 一條大航線一天賺的錢是文湖線的幾十倍（觀察，決策 762）；等有一整局的玩法量測再看要不要縮。
- UNVERIFIED：收購卡上的新價錢與天數沒有在模擬器、實機看過。
