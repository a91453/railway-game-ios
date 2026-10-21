---
name: coach-bus
description: 三軸高車身遊覽車原生建模、四款巴士街景共存及七向素材重建。
---

# 三軸遊覽車

先讀CLAUDE.md、art-style、station-kit、shuttle-bus、low-floor-bus及#231。本批作者4張綠白遊覽車圖，保留高車身、連續窗帶、後雙軸與右側前門，改暖白／暖紅、重組車頭尾／頂／行李艙。上批小巴已在#941、低地板在#942改成遊戲風格，不重做也不重複計數。無品牌或原始mesh／貼圖／factory複製。

Map3DCoachBus.model()→life-coachBus，Map3DStreetModel.coachBus追加到standard。原5%公車池內30%小巴／35%低地板／20%遊覽車／15%既有大型；前兩款seed選型不變，isBus統計四款，17m間距、密度、道路資格與上限不變。街景車型，不新增GameCore購車營運規則。

內部x前/y上/z右，flat轉一次至native x前/y左/z上。長約13.19、身寬2.5、含鏡3.16、高3.76m，輪底0。輪軸x=-3.90/-2.60/+3.80，胎半徑.50、拱.57。耳切輪廓不能triangle fan填掉凹輪拱。玻璃都有背板；前風擋分兩個真實斜面，不能用跨折線的一張平面造成浮空。行李艙門沿用車身原色，coachLuggageDoor直接著色的薄封殼、面漆只突出9mm、12mm細接縫與12mm內小把手；面漆與接縫背板至少隔2mm避免深度閃爍；不能再用box陰影側色造成三大塊灰門。右側前門有背板與貼門踏階，兩節鏡架接到鏡殼，HVAC支腳底3.52／頂3.58接封殼，所有頂／底封閉。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/coach-bus/rebuild.sh /private/output/coach-bus-2026-10-21
```

1新車＋3既有對照，4native／4GLB／28七向RGBA。額外前後底、四底色／小尺寸／模糊灰階、四車對照、同尺度車隊圖與viewer。對照車不算新增。管線驗證所有native頂點position/color/glow、normal容差1e-5、全量GLB重編／SHA、PNG雙解碼alpha／像素數／SHA／不裁邊、viewer操作和七組指定XCTest。造型改後一起重建，人工看七向／底部／車隊比較；不得只看雜湊宣稱美術已驗證。

公開配方／工具／測試／skill／README／一張總覽與驗證；完整成品／來源對照／ZIP放私有Railway/game-art-previews/docs/art/coach-bus-2026-10-21/。兩庫draft PR互鏈，本批以未合併#942分支為base，合併後可轉main；不推main、不自行合併。標VERIFIED／UNVERIFIED；真機Metal／效能、車門輪子動畫留裝置驗證。
