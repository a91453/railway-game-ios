# 原生場景素材工具

以 `Map3DSceneKit` 的 156 個原生程序化配方產出 `.m3dmodel`、相同幾何的 GLB 與七方向透明 PNG，來源與原生使用方式見 [素材 README](../../docs/art/generated-2026-10-21-scene-kit/native3d/README.md)。

- `export.sh`：用 Swift 6.4 建置 GamePresentation，將 `export.swift` 連結到本 checkout 的原生物件檔；支援 Swift 6.4 預設 Swift Build 及傳統 SwiftPM 目錄。匯出時逐檔經 `Map3DModelFile` 讀回，頂點須相同。
- `package.mjs`：把原生模型轉成內含 buffer、霧面頂點色的 GLB，記錄 SHA-256 與原圖片概念的對照。`node --test tools/scene-kit/package.test.mjs` 驗證軸轉換、色彩／glow／provenance、buffer 及格式拒收。
- `renderer.js`、`viewer.html`：無額外套件的 WebGL 2 檢視器，直接讀原生三角形，支援六面與旋轉；`render.mjs` 複製為輸出資料夾的 `renderer.js`／`index.html`。
- `render.mjs`：用本機 Chromium 渲染 156 × 7 張 384 px PNG；逐張檢查非空與四邊留白，記錄雜湊與可見範圍，生成總覽／方向對照。
- `verify.mjs`：核對所有原生／GLB 頂點、檔案雜湊、PNG 與可見範圍。
- `browser-check.mjs`：載入所有模型，驗證搜尋、方向、拖曳、縮放、下載與手機版面，檢查無外部請求／錯誤。

```sh
tools/scene-kit/export.sh "$PWD/docs/art/generated-2026-10-21-scene-kit/native3d"
node tools/scene-kit/render.mjs docs/art/generated-2026-10-21-scene-kit/native3d
node tools/scene-kit/verify.mjs docs/art/generated-2026-10-21-scene-kit/native3d
node tools/scene-kit/browser-check.mjs docs/art/generated-2026-10-21-scene-kit/native3d
```

本機工具只用既有 Node、Swift 與 Playwright，不加 App 依賴。瀏覽器預設 `/usr/bin/chromium`，可用 `CHROMIUM_PATH` 改成已安裝的路徑。軟體 WebGL 作驗收圖片，不代表 iOS Metal 效能。
