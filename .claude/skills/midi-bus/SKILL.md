---
name: midi-bus
description: 圓弧中型公車原生建模、五款巴士共存與七向素材重建。
---

# 圓弧中型公車

先讀 AGENTS／CLAUDE／HANDOFF、art-style、station-kit 與 shuttle／low-floor／coach skills、最新 #231。作者4張綠白圓頭兩軸車圖；改暖白＋藍綠霧面，重組多段包覆曲面風擋、凸弧前臉、連體抬高車頂、右前雙乘客門、左後緊急／設備門、圓尾燈。無品牌／原始 mesh／貼圖。

完整跨 session 可複製指令：[VEHICLE_ASSET_HANDOFF_PROMPT.md](../../../docs/art/VEHICLE_ASSET_HANDOFF_PROMPT.md)。不要只把 prompt 交回去，作者要實際完成素材與兩庫 draft PR。

Map3DMidiBus.model() → life-midiBus → Map3DStreetModel.midiBus → standard；內部 x前/y上/z右，flat只轉一次至native x前/y左/z上。約9.15m長、2.38m車身寬、2.91m含鏡寬、3.16m高，輪底0，軸x=-2.12/+2.86。兩個耳切真輪拱，風擋沿高度與前角分段且各有背板；圓肩曲面頂蓋與車身沿2.72m相接，不能同面疊兩張頂板；細門縫、同色低部漆面，不用厚灰艙蓋。支架連鏡，頂蓋本體封底，不加方形外掛頂板。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/midi-bus/rebuild.sh /private/output/midi-bus-2026-10-21
```

1新增＋4既有對照，5native／5GLB／35透明PNG。共用renderer與封裝器、同尺度車隊與viewer。工具檢查全量native/GLB讀回、PNG雙解碼與hash、viewer互動及八組XCTest；人工看真正產出圖。舊對照的幾何與封裝bytes不得變。

原5%公車池：30%小巴／35%低地板／20%遊覽車／10%中巴／5%原大型；前三款seed選型不變。17m間距、數量密度、cap與道路不改。非GameCore營運功能。公開小型配方／工具／測試／總覽，完整成品與ZIP在私有game-art-previews/docs/art/midi-bus-2026-10-21/。PR一律以main為base；依賴的PR還沒合併就等它合併，或把需要的部分一起帶進來（#942、#949、#957曾合進過時分支）；不推main、不合併。VERIFIED與UNVERIFIED分開，真機Metal／效能與車門輪子動畫待驗。

作者流線感回饋後：車頂用縱向loft與橫向圓肩，前窗由直立逐段彎入屋頂，深色窗帶連到前角；塗色面片必須凸分片，不能把有腰線折點的凹多邊形直接fan，否則第一角決定的normal會讓窗帶反向消失。目的地牌從真正的roof三角面裁出並沿法線微移，不能對非共面的quad做bilinear後假定仍在平面上。保留同角度前後對照，舊四車不改。
