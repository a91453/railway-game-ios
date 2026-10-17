# 台灣高鐵 N700ST（700T）遊戲風格 3D 模型（Issue #231）

本目錄收錄原生 3D 地圖（[`Map3DModels.swift`](../../../Sources/GamePresentation/Map3DModels.swift)、[`Map3DTrains.swift`](../../../Sources/GamePresentation/Map3DTrains.swift)）與 3D 城市檢視（[`trains.js`](../../../Web/CityView/src/world/trains.js)、[`build_train.mjs`](../../../tools/trains/build_train.mjs)、[`build_train.py`](../../../tools/trains/build_train.py)、`n700st-cab.glb`／`n700st-car.glb`）的高鐵 N700 遊戲風格模型對照圖與取捨紀錄。

- `options.png`：原生 3D 地圖頂點色模型（`highSpeed-cab`＋`highSpeed-car`＋`highSpeed-panto`）的 **方案 A（採用）** 與 **方案 B（舊版 main）** 在 3/4 視角、正側面、正前方與夜間自發光四個鏡頭下的對照。
- `cityview-sheet.png`：`rolling-stock/preview.cjs --stock hsr` 產出的 3D 城市檢視檢驗圖（3/4、車頭側面、正前方、中間車側面、12 節全編組、夜間發光、7px 模糊剪影）。

## 方案比較

| 方案 | 作法 | 取捨 |
| --- | --- | --- |
| **A（採用）** | **F 台灣版＋雕塑遊戲風格**：以實車與既有高精度參考網格量測出 9.0 m 鴨嘴鼻頭的「駕駛艙穹頂（`canopy: 0.24`）」與「Dual Supreme Wing 雙翼肩脊（`wing: 0.06, shoulder: 0.64`）」；純白車體（`#F6F6F4`）配向鼻尖下潛的路線色＋藏青（`#2B3356`）雙腰帶；風擋收斂於穹頂前斜面（`0.12...0.42`）並加藏青外框；雙翼肩脊於藏青腰帶上方設置深灰燈座與自發光 LED 頭燈（由 `cab.lamp` 驅動）；車頂設連續高壓電纜護罩，且低矮受電弓整流罩僅配置於實車有的第 4、9 節（0-indexed `3, 8`）；CityView GLB 由 [`build_train.mjs`](../../../tools/trains/build_train.mjs) 輸出程序化乾淨色塊塗裝（`TEXCOORD_0`）搭配解析式環境光遮蔽貼圖（`TEXCOORD_1`），移除 AI 噪點貼圖 | 遠看剪影與近看細節皆一眼辨識出高鐵 N700／700T；完全符合 `art-style` 第 7 節「微縮模型純色塊、不用 AI 髒貼圖」，且三角形數大幅下降 |
| B（舊版 main） | 單純平滑超橢圓縮管：無駕駛艙穹頂與雙翼肩脊；原生 3D 地圖風擋 `screenTo: 0.88` 幾乎蓋滿整個 9 m 鼻頭變成大片黑色面罩；鼻頭側面無下潛色帶與頭燈；車頂放置 6 個通勤電車方塊冷氣機 | 正面與 3/4 視角看像整顆黑頭，側面看不出高鐵標誌性的橘藍流線鼻頭與雙翼肩線 |
| C（AI 烘焙貼圖） | 保留 Meshy AI 減面後烘焙的 `n700st-cab.jpg`／`n700st-car.jpg` 照片貼圖 | 減面重展 UV 後車窗與橘色色帶邊緣呈鋸齒扭曲，白色車身帶灰暗斑駁髒污，與遊戲整體的乾淨色塊美學衝突，且多佔用貼圖檔案體積 |

## 四個角度評估（預設自主決策）

- **玩家**：從鳥瞰與 3/4 追蹤鏡頭一眼就能認出高鐵招牌的 9 m 白底橘藍流線鴨嘴鼻、頂置駕駛艙風擋、兩側雙翼肩線頭燈，以及第 4、9 節車頂的受電弓整流罩，不會再把車頭看成整塊黑面罩或一般通勤電車。
- **開發**：原生 3D 地圖與 CityView 建置腳本（[`build_train.mjs`](../../../tools/trains/build_train.mjs)／[`build_train.py`](../../../tools/trains/build_train.py)）共用同一套參數化截面與 UV 座標系；原生 3D 地圖車頭僅 990 面、一般中間車 382 面、集電弓車 392 面（遠低於 1,800／1,200 上限），CityView 12 節全編組由 76,000 面降至 31,992 面（含第 4、9 節集電弓整流罩，低於 96,000 預算），並移除兩張 AI diffuse JPG。
- **美術**：遵循「F 台灣版＋」微縮模型原則——以明確的幾何稜線（駕駛艙穹頂＋Dual Supreme Wing 肩脊）與乾淨色塊（高鐵白 `#F6F6F4`、高鐵橘 `#EA6A1E`、藏青 `#2B3356`、深綠膠囊窗 `#1D4A44`）加上乾淨的解析式環境光遮蔽呈現立體感，不靠髒污貼圖。
- **音樂**：高鐵列車滑過高架橋與進站時的視覺速度感與流線鼻頭一致，不影響既有音效與節奏觸發。
