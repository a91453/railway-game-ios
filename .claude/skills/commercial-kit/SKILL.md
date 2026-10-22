---
name: commercial-kit
description: 台灣商業建築、街邊店鋪、夜市招牌與商用接駁載具 3D 素材的擴充、檢查與重建流程。擴充商業套件或審查新模型時使用。
---

# 商業建築、店鋪夜市與商用載具素材 (Commercial Kit)

36 件原生 3D 素材（商業建築 12、街邊店鋪與餐飲 12、招牌家具與接駁載具 12）與 4 個組景範例（繁華商業大道、台灣夜市商圈、站前商業轉運站、社區街角生活商圈）。

## 1. 規範與要求

- 優先使用專案原生程序化 3D，沿用 `StationKitBuilder`、既有色票、原生 loader、GLB 編碼與 WebGL renderer。
- 坐標系：原生坐標為 +x 朝前、+y 朝左、+z 朝上（公尺）。
- 安裝面（Mounting Planes）：
  - `.ground`：地面件底對齊 z = 0。
  - `.wall`：壁掛件背面貼齊 x = 0，朝 +x 延伸。
- 結構完整性：
  - 窗戶均有不透明背板（距離小於 0.12m），絕不透空浮動。
  - 遮陽棚、雨棚、走廊均有支撐立柱或斜拉桿，不浮空。
  - 桌腳、椅子輪子、樓梯踏階與招牌五金均真實接合。
  - 車輛（市區接駁公車）重構車頭流線弧度、全景擋風玻璃、雙雨刷、低地板乘客門、車頂冷氣與輪拱。
- 三角形上限：每件單獨素材與完整組景均嚴格在 15,000 三角形以內。
- 交付成果：
  - 公開庫放配方（`Sources/GamePresentation/Map3DCommercialKit*.swift`）、測試（`Tests/GamePresentationTests/Map3DCommercialKitTests.swift`）、工具（`tools/commercial-kit/`）、技能文件、單一總覽圖與小型驗證 JSON。
  - 大型模型（40 native、40 GLB）、280 張七向透明 PNG（上／下／左／右／前／後／立體）、各預覽表與 viewer 放私有參考庫。

## 2. 重建指令

```sh
tools/commercial-kit/rebuild.sh /path/to/private/output/commercial-kit-2026-10-21
```

## 3. 驗證清單

- Native 頂點逐一經 `Map3DModelFile` 讀回比對。
- GLB 與原生模型位元組轉換一致。
- 280 張 PNG 尺寸均為 384x384，透明 RGBA，非空且不裁邊（visible bounds 落在 2 到 382 之間）。
- 瀏覽器檢視器（viewer.html）可進行分類篩選、搜尋、旋轉軌道、縮放、下載各格式與 390px 手機排版。
