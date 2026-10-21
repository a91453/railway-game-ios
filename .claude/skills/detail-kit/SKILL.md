---
name: detail-kit
description: 製作、擴充及匯出鐵道、台灣建築、站內、道路、生活和可動細節零件。Use for small native 3D assets, mounting connectors, articulated bodies and seven-view exports.
---

# 場景細節零件

先讀 `CLAUDE.md`、art-style 與 station-kit skill，並讀完工作登記 #231 再登記自己的檔案。此套件與地圖接入分工：只新增 `Map3DDetailKit*.swift`，不要順手改 `Map3DStationKit*.swift`、Map3DScene 或 GameCore。

## 新增零件

1. 在 `Map3DDetailKitParts.swift` 加 case、繁體中文名、分類、安裝面。每種零件要有自己的結構，不靠改名或換色充數。
2. 在 RailBuilding／InteriorStreet／LifeMoving 寫對應幾何；StationKitBuilder 的箱子 y 是底。內部 x 前、y 上、z 右；公開 model／接點／關節是 x 前、y 左、z 上，公尺。
3. 壁掛零件的固定板必須接觸 x=0；天花板零件最高點 z=0，幾何向下延伸；地面與屋頂件最低點約 z=0。牆面件只有安裝板，不自帶整面牆，組裝者依 mount 貼牆。
4. 管線端點位置、法向與實體端口相同。2 m 線段接點 ±1 m。不要用接點描述掩蓋幾何的空隙。
5. 可動件寫 `Part.joint`（rotation/radians 或 translation/metres，pivot/axis/limit）與 `detailMoving`，分開建立固定件和活動件。不可在已合併的整個模型上一起旋轉。動作不改遊戲權威狀態。
6. `model(for:pose:)` 生成指定姿態，超界值裁到範圍，非有限值回原姿態。`components(for:)` 供 runtime 只轉活動件。GLB 為靜態 mesh；關節 metadata 與分件可供宿主動畫，沒有假稱內含 glTF 動畫軌。

## 重建與驗證

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/detail-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/detail-kit-2026-10-21
```

需要既有 Node、Python、Playwright、Chromium；不新增依賴、不下載瀏覽器。Swift 只用 6.4 warnings-as-errors。工具依賴 station-kit 的原生基本形狀、GLB 編碼、WebGL renderer，這些是本專案既有程式，不是另外的引擎。

目前 96 種零件、16 個可動姿態、6 個組景，共 118 個檢視模型＋32 個獨立固定／活動 body，826 張七向 RGBA。改幾何時更新原生／GLB／PNG／manifest。快取必須同時符合原生 SHA、renderer SHA 和全部七張 PNG SHA；刪 `render-cache.json` 強制重畫。

匯出器逐頂點經原生載入器讀回；verify 逐位元組重建 GLB、檢查全部圖雜湊與非空不裁邊，以及 16 個瀏覽器關節變換和 Swift 姿態的逐頂點差異。測試檢查固定件不動、活動件保持剛體距離、安裝平面、接點和預算。瀏覽器檢查滑桿確實改變畫面，不只檢查控制項存在。

檢查 `previews/examples.png`、六類零件表、`undersides.png`、`poses.png`、`directions.png`、`style-checks.png`，並旋轉查看。不能只用檔案存在或模型非空當成好看。小尺寸保留輪廓；這些是近景細節，遠處不要全常駐。

## 交付

大型模型與圖放私有參考庫，公開庫只保留程式、工具、測試、README、一張總覽和小型驗證記錄。公開程式與私有素材各開 draft PR、不合併、不推 main。VERIFIED 要寫跑在哪裡；WebGL 與 Linux 測試不代表 Metal／真機效能或遊戲已使用它。
