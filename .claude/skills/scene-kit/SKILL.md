---
name: scene-kit
description: 建立、修正或增補台灣列車、住宅、商業與街景的原生程序化 3D 素材，匯出原生模型、GLB、上下左右前後 PNG，檢查車頭車尾與建物結構。Use when generating or changing native procedural scene assets and their multi-view previews.
---

# 原生 3D 場景素材

先讀 `.claude/skills/art-style/SKILL.md`、`docs/UI_THEME.md` 與工作登記 #231。這份是可重建的工程入口；不取代畫風、授權與分工規則。

## 唯一來源與入口

- `Sources/GamePresentation/Map3DSceneKit.swift`：題材 ID、分類、配方索引與 `model(for:)`。
- `Map3DSceneKitGeometry.swift`：封閉基本形狀、窗戶、支架與原生模型組合。
- `Map3DSceneKitTransport.swift`／`Map3DSceneKitCabs.swift`：列車配置、各車種的車頭／車尾、車站與軌道。
- `Map3DSceneKitBuildings.swift`／`Map3DSceneKitPlaces.swift`：住宅、商業與街景。
- `tools/scene-kit/`：匯出、渲染、驗證；不需圖片或 3D 生成服務。
- `docs/art/generated-2026-10-21-scene-kit/native3d/`：156 題材的成品、manifest、可旋轉檢視頁。

幾何內部為 **x 前、y 上、z 右**；`Model.flat` 轉成原生 **x 前、y 左、z 上**。尺寸是公尺，盒子的 y 是底面，不是中心。GLB／PNG 由同一個原生模型產生，不能分別手改來掩蓋幾何問題。

## 改模型

1. 認領檔案，讀既有同類配方、原圖片概念與遊戲標準模型。保持既有 ID；依作者指定部分改造，不任意換整套畫風。
2. 以 `Map3DMesh` 和專案調色盤建置，回傳 `Map3DModelPack.Model`。不加入亂數、時間、外部狀態或 App 依賴。
3. 修錯先加入能在舊幾何失敗的回歸測試，再改配方。例：騎樓窗戶沿法線向內 12 cm 內必須碰到牆，兩個外露駕駛端都應有前窗與燈。
4. 不以正面漂亮當作完成：必看六面、立體和下方斜視。住宅窗戶跟隨各樓層真正的牆面；退縮騎樓不在開放區畫窗。陽台樓板嵌入主樓板、門能走到陽台、欄杆站在樓板上、冷氣有接牆支架。
5. 列車先保留原圖的辨識特徵：EMU3000 黑罩、普悠瑪紅罩、太魯閣黑窗／橘帶、700T 長鼻、捷運平前窗。雙端列車尾端用反向駕駛室與紅尾燈，不用中間車平封板。單節柴油車也有雙端。機車牽引編組則保留客車尾門。
6. 修改配方後執行下面整套流程，模型、GLB、圖片及 manifest 一起提交。不能只改生成碼卻留下舊成品。

## 一鍵重建

需要 PATH 上的 **Swift 6.4**、Node、已安裝的 Playwright 和 Chromium。先依 `CLAUDE.md` 的環境指引安裝 Swift；工具不下載套件或瀏覽器。

```sh
tools/scene-kit/rebuild.sh
```

這會更新上述成品目錄。`CHROMIUM_PATH` 可指定 Chromium。各步驟與獨立指令在 `tools/scene-kit/README.md`。

新增題材時，在 `Map3DSceneKit.assets` 加入唯一 ID 與配方；若新增 family，也補 enum 與 `model(for:)` 分派。既有某些 family 用固定 variant 表，不能任意加大索引。新增測試涵蓋新題材；保留原 156 個題材的覆蓋檢查。工具依 manifest 計算成品數，沒有概念圖的新題材也可輸出。若移到新的素材包目錄，還須調整封裝器的概念圖路徑及檢視器伺服器根目錄。

重建完成後實際開啟 PNG：至少查看 `previews/directions.png`、`previews/transport-review.png` 與 `previews/housing-review.png`，並在檢視頁旋轉確認接點。再依 art-style 檢查深淺底、小尺寸、模糊與灰階；非空、雜湊和法線測試不會判斷美醜。

## 使用與交付

```swift
if let asset = Map3DSceneKit.asset(id: "07_residential_low-04") {
    let model = Map3DSceneKit.model(for: asset)
    let pack = Map3DModelPack(sceneKit: [asset])
    let index = pack.index(of: asset.id)
    // model.vertices 是既有原生頂點；pack 可只選場景需要的素材。
}
```

這個素材庫提供建置與選用入口；實際地圖的選型、載入、比例及自動放置是另一條整合工作。未在 Metal／實機跑過就寫 UNVERIFIED，WebGL 預覽不能當成 iOS 畫面或效能證明。

完成後更新 README／驗證紀錄及 draft PR，標示 VERIFIED／UNVERIFIED。規則禁止直接提交 main 或自行合併；這份指南與工具隨 PR 合入 main 後，新 Claude session 就能讀到，不依賴舊對話。
