---
name: midi-bus
description: 圓弧中型公車原生建模、五款巴士共存與七向素材重建。
---

# 圓弧中型公車

先讀 AGENTS／CLAUDE／HANDOFF、art-style、station-kit 與 shuttle／low-floor／coach skills、最新 #231。作者4張綠白圓頭兩軸車圖；改暖白＋藍綠霧面，重組四段弧面風擋、凸弧前臉、連體抬高車頂、右前雙乘客門、左後緊急／設備門、圓尾燈。無品牌／原始 mesh／貼圖。

完整跨 session 可複製指令：[VEHICLE_ASSET_HANDOFF_PROMPT.md](../../../docs/art/VEHICLE_ASSET_HANDOFF_PROMPT.md)。不要只把 prompt 交回去，作者要實際完成素材與兩庫 draft PR。

Map3DMidiBus.model() → life-midiBus → Map3DStreetModel.midiBus → standard；內部 x前/y上/z右，flat只轉一次至native x前/y左/z上。約9.15m長、2.38m車身寬、2.91m含鏡寬、3.16m高，輪底0，軸x=-2.12/+2.86。兩個耳切真輪拱，四段風擋各有背板；上下封閉車身與車頂沿2.80m相接，不能同面疊兩張頂板；細門縫、同色低部漆面，不用厚灰艙蓋。支架連鏡，淺頂蓋接屋頂。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/midi-bus/rebuild.sh /private/output/midi-bus-2026-10-21
```

1新增＋4既有對照，5native／5GLB／35透明PNG。共用renderer與封裝器、同尺度車隊與viewer。工具檢查全量native/GLB讀回、PNG雙解碼與hash、viewer互動及八組XCTest；人工看真正產出圖。舊對照的幾何與封裝bytes不得變。

原5%公車池：30%小巴／35%低地板／20%遊覽車／10%中巴／5%原大型；前三款seed選型不變。17m間距、數量密度、cap與道路不改。非GameCore營運功能。公開小型配方／工具／測試／總覽，完整成品與ZIP在私有game-art-previews/docs/art/midi-bus-2026-10-21/。以未合併#945為base的stacked draft PR；不推main、不合併。VERIFIED與UNVERIFIED分開，真機Metal／效能與車門輪子動畫待驗。
