---
name: coastal-kit
description: 生成海岸、漁港與露營休憩原生 3D 素材、安裝接點、完整組景及七向透明圖。
---

# 海岸、漁港與露營素材

先讀 CLAUDE.md、AGENTS.md、HANDOFF、art-style、station-kit、civic-kit 與工作登記 #1041（#231 為已滿的舊登記）。查最新 main 與全部 Kit 目錄去重，不能只依交接提示的既有批次。

本批 24 獨立素材（三類各8）與4組景。Map3DCoastalKit.model(for:)、Map3DModelPack(coastalKit:) 按需建模，不加入 standard、不接地圖。只延伸自己的 Map3DCoastalKit*.swift、tools/coastal-kit、對應測試與文件。不要改 GameCore、存檔、Golden、其他 Kit 或地圖整合。

Builder 內部 x前/y上/z右，box 的 y 為底；Model.flat 轉成 native x前/y左/z上，公尺。Connector 與 Placement 的位置用 native 軸；Placement.angle 沿用 StationKitBuilder，為從+z往下看順時針的弧度，x′=cos(a)x+sin(a)y、y′=−sin(a)x+cos(a)y。法線向上必須明寫 (0,0,1)，不能用內部幾何的 Map3DPoint.up（那是 y上）。24件均以底 z=0 岸置；浮台、小艇另有 waterline 接點，入水時原點 z=水面高度−接點.z。範例漁港水面 .30m，motorDinghy 原點 −.02m、pontoon .08m。slipway 高端1.2m、低端.12m；campTable 桌面 .70m、fishSortingTable .90m、trailer keelRest .62m。placements(for:) 是組景同源位置表，匯出 manifest 供後續組裝。

幾何必須改輪廓、比例與組件布局，不只改名換色。先讀私庫 MODEL_CATALOG.json、ASSET_LICENSE.txt 和實際 factory。來源路徑、SHA、尺寸、改造方式寫私庫 remix-provenance.json。禁止原始 factory、原包模型、貼圖或品牌公開；不送私有原始素材到外部生成服務。保留授權實際條件，本批是遊戲資產、不是可再分發的原商品包。

接合要點：船殼內外面、船底、船舷與兩端封閉；槳接船舷、舷外機接艉板。吊床布有厚度，繩端與布端／A架共用接點。輪子落地、軸接架；桌腳與椅腳有落地墊。帳篷前庭有支柱，牆面門窗有背板；棚柱、屋頂、燈塔欄杆與頂帽相交接合。新配方不可用整體抬高掩飾穿插。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/coastal-kit/rebuild.sh /path/to/private/Railway/game-art-previews/docs/art/coastal-kit-2026-10-23
```

重用 StationKitBuilder、CivicKit civicTube/civicLegs、現有色票與 station-kit 的 native→GLB／renderer；不另造引擎。不安裝新依賴：已有 Swift6.4、Node、Python/Pillow、Playwright、Chromium 即可。輸出必須在公開庫外。28 native、28 GLB、196張384px七向透明 PNG；每件與整景皆≤15,000三角形。快取須 native／renderer／每張PNG SHA全相同才重用。

驗證 Swift6.4 warnings-as-errors build、Coastal／Station／ModelFile相關測試與既有4項Node編碼測試。全部native逐頂點loader讀回、完整GLB重編、全部PNG實際RGBA解碼與alpha bounds／SHA、不空不裁邊、viewer全模型／分類中文搜尋／七向／旋轉縮放／四底色／下載SHA／390px。打開 parts、三分類、examples、directions、undersides、style-checks 人工看接點、背面與底面；圖片不能只驗存在。ZIP要解壓比對所有成員。rebuild不會自動更新人工驗收或私有來源對照，配方改後必須重看並更新紀錄。

公開只留配方、工具、測試、skill、README、單一總覽及小型驗證JSON。大型成品、viewer、全部圖片、ZIP、來源對照放私庫同名批次。雙庫draft PR互鏈、commit帶 Agent: Codex，不推main、不自行合併或auto-merge。報告 VERIFIED／UNVERIFIED。Chromium WebGL不是iPhone Metal、效能或遊戲地圖採用；海事／救生／露營安全、碰撞與動畫不在此靜態素材範圍。
