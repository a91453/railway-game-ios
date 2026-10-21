---
name: station-kit
description: 產生台灣車站完整遊戲站型、月台站廳與建築小零件，匯出原生模型、GLB 與七方向透明 PNG。Use when extending the station catalog, generating modular station/building assets, or checking roof, wall and floor connections.
---

# 車站與建築組件

先讀 `.claude/skills/art-style/SKILL.md`、`CLAUDE.md` 與工作登記 #231。大型成品放私有庫，不把整批 GLB／PNG 搬回公開遊戲庫。

## 程式入口

- `Map3DStationKit.swift`：按需建模、獨立模型包與同零件組裝的站前範例。
- `Map3DStationKitCatalog.swift`：由專案站點目錄生成，按 `(system, name)` 去重；不是新建一份遊戲權威資料。
- `Map3DStationKitBuildings.swift`：35 個代表站外觀與一般遊戲站型。`isLandmark` 由明確站點對照決定，不能因為同樣是木造屋頂就稱為特製站房。
- `Map3DStationKitParts.swift`／`PartGeometry.swift`：64 車站＋32 建築零件，含安裝面與接點。
- `Map3DStationKitGeometry.swift`：封底基本形狀、曲頂、支架、玻璃與樓梯；不更動原有列車／地圖選型。

內部幾何 **x 前、y 上、z 右**；對外原生模型與接點 **x 前、y 左、z 上**，單位公尺。`Model.flat` 只在輸出邊界轉軸。盒子的 y 是底，不是中心。4 m 地坪／牆片、3.2 m 樓層、8 m 直線月台是本批組裝規格，不是真實車站工程尺寸。

## 重建

```sh
python3 tools/station-kit/catalog.py      # 站點來源或對照有改時
tools/station-kit/rebuild.sh ../railway-reference-private/Railway/game-art-previews/docs/art/station-kit-2026-10-21
```

需要 PATH 上 Swift 6.4、Node、Python 3、既有 Playwright／Chromium；工具不下載套件或瀏覽器。`CHROMIUM_PATH` 可指定既有瀏覽器。輸出不能位於公開遊戲 checkout 裡。

配方改動後，原生檔、GLB、PNG、manifest 一起更新。渲染器只有在「原生檔 SHA、renderer.js SHA、七張 PNG SHA」全部相同時才重用圖片；刪除 `render-cache.json` 即可強制重畫。後續 verify 仍檢查每個模型與每張圖。

## 不讓零件浮空

- 雨棚柱頂依實際曲頂下表面計算；中央弧頂比屋簷高，不能拿屋簷高度當中央柱高。
- 窗片含實牆與窗框。騎樓先退縮牆面，再把窗門裝到真正牆面，不能放在柱列之間的空氣中。
- 陽台含背牆、門、與樓板重疊的板及支架安裝板。壁掛零件必須依 `mount`／`connectors` 貼牆，屋頂零件放到屋面。
- 波浪屋頂的分叉支架對準各自端點的屋面高度；太陽能板與支架用同一斜面。
- 看 `previews/undersides.png`、`parts.png`、`directions.png` 與 `style-checks.png`，再在檢視頁旋轉。檔案雜湊、非空與法線不會判斷美醜。

修錯先留會在舊幾何失敗的測試。現有測試涵蓋完整站點覆蓋、規劃路線標記、各站辨識輪廓、封底／有限／不透明／預算、接點、雨棚接柱、窗片背牆與決定性。匯出器對全部模型逐頂點原生讀回，GLB 與 PNG 都從同一幾何產生。

## 取用與限制

`Map3DStationKit.stations`、`station(id:)`、`model(for:)` 提供 544 站及 96 零件；`Map3DModelPack(stationKit:parts:includeStandard:)` 只選需要的模型。不要因為有完整素材庫就把全部常駐在地圖記憶體。

`catalog-archetype` 表示一般可替換遊戲站型；`remixed-landmark-exterior` 表示代表站的遊戲外觀。`planned` 保留來源中的規劃路線；模型不宣稱營運狀態、測繪尺寸、真實室內／軌面高度或實際列車停靠對齊。來源站點資料更新後重建目錄，不能改權威資料來迎合模型。

交付開公開程式 PR＋私有素材 PR；公開只留本批總覽、入口與必要小型紀錄。標示 VERIFIED／UNVERIFIED，實機 Metal 與實際地圖放置要另行驗證，不自行合併。
