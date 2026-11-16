# WINTER-LIGHTS：聖誕樹與燈串放進地圖

- 派工單：WINTER-LIGHTS（遊戲規劃 session_01JMHz9aiAQ16u6jrjjW2amC 派，2026-11-16）；session_01JMHz9cErPNET7pdns71qJH；分支 `claude/winter-lights`。
- 決策 794。存檔、golden、GameCore、SaveFixtures、ReplayFixtures：都不動。
- 做了什麼：決策 790 的五個模型進模型包（通勤乘客後、路線公車前）；建場景時記下每座站房正面屋簷的燈串（4 m 一段，一棟最多 8 段）、大站（大站站型或 3 座以上月台）站前廣場的中型樹、板橋市民廣場與尖沙咀海旁的大樹（聖誕老人村的座標已寫好，羅瓦涅米地圖進來就會擺）；每一格畫面只在 `WinterEvent.showsDecorations` 為真時加進去，所以開關切換不重建場景。燈泡晚上才亮（既有的發光頂點）。台灣、香港不下雪。細節在 [`decisions/794.md`](../decisions/794.md)。

## 還留下的

1. 香港的車站大多是地下站（只有出入口），沒有站房就沒有燈串與中型樹；香港只有尖沙咀那棵大樹。要的話另開一張：出入口上方掛燈或站前小樹。
2. 站房前緣不一定是牆（有的站型門廊突出、兩旁縮進），燈串照外框掛，有些站可能看起來懸空：要在 Simulator 或實機看過（UNVERIFIED）。
3. WINTER-FRAME 裡沒有樹或燈的占位模型可換；它的占位只有徽章圖（SF Symbols），那是工作室的另一項。
4. 羅瓦涅米：地圖包（ROVANIEMI-MAP-1）進來後，聖誕老人村的大樹自動擺；站房用的是台灣的站型，北歐站房另做時燈串照同一套掛法。

## UNVERIFIED

- Metal 畫面、光暈、燈串掛的位置與高度、大樹遠景切換會不會跳、iPhone 實機與效能（面數與 draw call 是照模型與上限算的，沒在裝置上量）。
