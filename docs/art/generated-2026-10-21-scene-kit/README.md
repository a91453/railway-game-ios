# 台灣鐵道與城市場景圖片素材

作者要求先將既有圖片提交 PR，再持續補住宅、商業與場景配件。第一批為 **6 張透明 PNG 素材表、45 個項目**。

[開啟本地檢視頁](index.html) · [素材清單](manifest.json)

| 素材表 | 排列 | 項目 |
| --- | --- | ---: |
| [台鐵現代列車](png/01_TRA_modern_3x2.png) | 3 × 2 | 6 |
| [高鐵與捷運](png/02_HSR_MRT_3x2.png) | 3 × 2 | 6 |
| [車站與月台](png/03_stations_3x3.png) | 3 × 3 | 9 |
| [軌道與配件](png/04_tracks_props_4x3.png) | 4 × 3 | 12 |
| [台鐵經典列車](png/05_TRA_classic_3x2.png) | 3 × 2 | 6 |
| [更多捷運與輕軌](png/06_more_transit_3x2.png) | 3 × 2 | 6 |

## 使用

列車為單一視角靜態圖；素材表從左至右、由上至下排列，裁切後可在 2D 場景組合或面板中使用。圖上的軌道未經連接接縫校準，不當作可無縫拼接圖磚。這些 PNG 不是可旋轉的 3D 模型。

所有原圖保留生成工具輸出的位元組；manifest 記錄尺寸、透明度、檔案大小與 SHA-256。具有 Alpha 通道並不表示邊緣已完成美術去背，半透明光暈與細節需按使用尺寸檢視。真實車型僅為造型原型，生成圖片不作車種工程規格或塗裝考證的依據。

## 畫風與來源

既有列車依本對話要求採略為遊戲化的真實車型；城市增補將依 art-style §7 的 F 台灣版＋、Map3DPalette 的霧面模型與台灣騎樓、水塔等比例。原圖皆為本對話 image_gen 原創生成，未上傳私有參考庫內容至生成服務，也未複製其他遊戲的素材。專案對照：`Sources/GamePresentation/Map3DScene.swift` 的 Map3DPalette、`docs/art/3d-style-2026-10-13/`、`docs/art/generated-2026-10-14-micro3d/`。這批不是新 Stage，也不改 GameCore／App／存檔。

## 驗證與採用狀態

- **VERIFIED — Linux**：6 張 PNG 完整解碼、RGBA 與透明像素、manifest 數量及雜湊、git diff 空白檢查。
- **UNVERIFIED**：App／Asset Catalog、Metal、實機效能與遊戲內顯示。圖片本身已交付；原生 App 的採用另由接入工作依目標畫面驗證。
