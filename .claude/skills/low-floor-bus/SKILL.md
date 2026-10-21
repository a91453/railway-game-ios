---
name: low-floor-bus
description: 大型前中雙門低地板公車的原生3D、街景車流與七向圖重建。
---

# 雙門低地板公車

先讀CLAUDE.md、art-style、station-kit、shuttle-bus與#231。這批是作者後來提供的4張大型綠色市區公車，不是上批高頂短鼻小巴。保留長車身、右前／中雙門、後側散熱格柵；暖白＋霧藍、斜肩頂、分件車頭／尾燈與HVAC重新建置，無品牌。不要把原始綠白配色或原模型直接搬入。

Map3DLowFloorBus.model()→life-lowFloorBus，Map3DStreetModel.lowFloorBus由standard自動收錄。沿用5%總公車池，30%小巴、35%新大型公車、35%既有公車；小巴原本的seed選型不變。isBus含三款，17m間距／上限／道路資格／總交通量不變。這是街景車型，不是GameCore購車營運新功能。

內部x前/y上/z右，flat只轉軸一次至native x前/y左/z上。長約12.08、身寬2.46、含鏡3.05、高3.40m，輪底0。輪徑.96、輪拱半徑.57，使用上批shuttleShell耳切凹多邊形；不能triangle fan填掉凹輪拱。側窗／門都有實體背板，風擋依實際前斜面法線偏移，門檻貼地板，鏡架碰車身與鏡殼。HVAC底3.20，支腳底3.14接車頂；封閉斜肩頂與底面，別把屋頂設備或玻璃懸空。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/low-floor-bus/rebuild.sh /private/output/low-floor-bus-2026-10-21
```

交付1新車＋1既有對照，2native／2GLB／14七向RGBA，另前後底立體、總覽、比較、四底色／小尺寸／模糊灰階與viewer。不能把對照算新增。管線驗證native逐頂點position/color/glow及normal容差1e-5、GLB全量重編、PNG SHA／實際RGBA解碼／alpha與像素數、viewer操作和六組指定XCTest。模型改後須重建成品與manifest、重新看實際圖片。

公開留配方、工具、測試、skill、README、總覽、小驗證；完整成品／來源對照／ZIP放私有Railway/game-art-previews/docs/art/low-floor-bus-2026-10-21/。兩庫draft PR互鏈；本批PR暫以尚未合併的#941分支為base，合併後轉main。不要改main／自行合併。標記VERIFIED／UNVERIFIED；Metal真機與效能由後續裝置檢查。
