---
name: works-kit
description: 工程車、貨運機廠、動物與自然景物的原生 3D 配方與七向圖。Use for construction machinery, freight yards, rural animals and vegetation assets.
---

# 工程、貨運與田野素材

先讀 CLAUDE.md、art-style、station-kit 與工作登記 #231。只在自己的 `Map3DWorksKit*.swift`／`tools/works-kit/` 範圍延伸；不要順手改地圖、StationKit、列車、321 車站接入或 322 商店街。

## 配方

- `Map3DWorksKit.swift`：48 種素材，四類各12；原生 API、安裝面與接點、按需模型包。
- Geometry：封閉幾何、斜面駕駛室、履帶、油壓桿、實體葉片。內部 x前/y上/z右，輸出與 connector 是 native x前/y左/z上、公尺。
- Vehicles：12工程車；Freight：12貨運機廠；Animals：12動物模型（含兩種貓姿勢）；Nature：12田野景物（含穀倉與棧台）。姿勢不同不冒充不同物種。
- Examples：施工、貨場、農村、溪岸。完整組景仍遵守原生載入器15,000三角形上限。

新增素材需獨立輪廓與結構，不只改名／換色。私有來源只取可用建模方法、尺寸與組件，重新組合形狀與比例，再換成現有霧面色票；不放來源factory、照片、品牌文字或原模型。原始來源／SHA／加工對照留私有素材資料夾。

## 接合

- 輪底／腳底觸地；地面件最多1mm正空隙，細圓桿嵌入地面最多4cm。不得用整體抬高掩蓋輪子／支架碰撞。
- 擋風玻璃沿實際斜面，測試向內投射時排除玻璃本身，確認背後是實體外殼。
- 油壓桿端點接到工作臂節點；門式起重機駕駛室含與斜腿接合的平台；穀倉梯子含貼筒壁的支架。
- 貨櫃角件最高點2.6m，`stack`接點同高；20/40呎是約略遊戲比例，沒有真實貨櫃載重或吊運模擬。
- 錦鯉 `mount`接點 native z=.13 對齊水位；例子以位置水面−.13放置，讓下半身浸入不透明水面。它不是落地物。

## 重建

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/works-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/works-kit-2026-10-21
```

沿用 station-kit 的native匯出／GLB編碼／WebGL renderer；既有 Node、Python、Playwright、Chromium 即可，不新增依賴。52模型產生364張384px七向RGBA，附搜尋、分類、旋轉、下載與四個組景。快取需同時符合原生SHA、rendererSHA與每張PNG的SHA。

原生loader逐頂點讀回、GLB完整轉換、PNG雜湊與非空不裁邊、分類、接點、落地、玻璃背板、預算與決定性都要檢查。看 `parts.png`、四類表、`examples.png`、`undersides.png`、`directions.png`、`style-checks.png`，不能只檢查檔案存在。

## 交付

公開：配方、工具、測試、README、單一總覽、小驗證JSON。私有：native、GLB、全部PNG、離線viewer、原始對照與權利說明。各開draft PR；不推main、不自行合併。這些是靜態素材；機械活動、動物行為、地圖放置與真機Metal需另外接入驗證，不冒稱已完成。拿進App前另做來源模型視覺並排與實機效能檢查。
