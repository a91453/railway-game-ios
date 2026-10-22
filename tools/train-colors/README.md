# 三台列車遊戲配色修訂

作者要求三台一起重配色，並授權自行決定最好看的遊戲呈現。只改三個既有配方的頂點色：

| 車輛 | 主色來源 | 呈現 |
| --- | --- | --- |
| 低地板電車 | `tileWhite`／`shopAwnings[0]`／`tankWhite` | 暖白上半身、綠松下裙、中性細窗框 |
| 雙節通勤車 | `tileWhite`／`trimBlue`／`roof` | 暖白窗帶、霧藍下半身、冷淺灰窗框 |
| 三節都市車 | `tileWhite`／`containers[2]`／`tankSteel` | 暖白車身、柔綠肩線／細腰線／端框、淺灰門 |

共同保持霧面平塗、深色玻璃、薄邊、原尺寸與原細節密度。既有 `green-*` asset ID 與型別名稱保留，避免破壞呼叫者；名稱不代表目前仍是綠色。沒有變更營運車種、位置、面數、編組、輪位或動畫。唯一配方仍是 `Map3DGreenTram.swift`、`Map3DGreenCommuter.swift`、`Map3DThreeCarUrban.swift`，本工具只匯出／驗證。

## 重建

Swift 6.4 必須先安裝並在 PATH；本環境位於 `/workspace/swift/usr/bin`。OUT 與 BEFORE 均放在公開庫外。BEFORE 是 producer `2b2bfab2ae6f2a94407c8acd0224516d590a07f5` 的三台全部單元／編組 native，私有 `train-colors-2026-10-22-before/` 有保存；不要使用本輪新模型自己充當比較基準。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DThreeCarUrbanTests|Map3DModelTests|Map3DModelFileTests|Map3DGreenCommuterTests|Map3DGreenTramTests'
tools/train-colors/export.sh OUT
node tools/train-colors/render.mjs OUT
node tools/train-colors/verify.mjs OUT BEFORE
node tools/train-colors/feedback-compare.mjs OUT BEFORE
node tools/train-colors/clay.mjs OUT
node tools/train-colors/geometry-audit.mjs OUT
blender --background --python tools/train-colors/glb-audit.py -- OUT
python3 tools/train-colors/verify-png.py OUT
node tools/train-colors/standalone.mjs OUT
node tools/train-colors/browser-check.mjs OUT
node tools/train-colors/browser-check.mjs OUT --standalone
python3 tools/train-colors/bundle.py OUT ACTUAL_PRODUCER_COMMIT
# ZIP 生成後再測一次資料夾 viewer 的 ZIP 下載，然後重建 bundle 納入結果。
node tools/train-colors/browser-check.mjs OUT
python3 tools/train-colors/bundle.py OUT ACTUAL_PRODUCER_COMMIT
```

12 native／12 GLB＝8 個獨立單元＋3 組完整編組＋1 件未改色的既有比較車；84 張七向透明 PNG。完整編組三角形保持 4,312／4,908／7,548。不是新增三款車的幾何，而是原三款換色。

`verify.mjs` 與真正舊版逐頂點比對位置／法線／順序／alpha／glow，舊比較車顏色也必須不變。每個新色單元重新逐頂點組裝，native 與 GLB 內容比對，七向影像驗證透明、不裁邊及公尺尺度。`geometry-audit.mjs` 針對本輪原新增的三節都市車檢查閉合有向邊／玻璃支持；前兩台以既有測試、七向視檢與幾何完全相同檢查驗證，沒有宣稱重做其幾何。

八個單元共用同一七向 m/pixel；各完整編組的七向各自固定同一尺度。`fleet-same-scale.png` 把三組完整編組放在相同公尺相機，`before-after.png` 及三張 `before-after-{tram,commuter,urban}.png` 使用新舊實際 native 與固定相機／公尺範圍。

組裝：電車單元中心 x=+11.04／0／−11.04；雙節通勤車 +9.86／−9.86；三節都市車 +15.28／0／−15.28，單位公尺，均不旋轉。原生 +x 前、+y 左、+z 上；沿用原軌面基準。精確外廓與三角形統計在 manifest。尺寸仍是原批比例規格，未因配色變更重新宣稱工程尺寸。

`viewer-standalone.html` 內嵌所有模型／圖片，可離線旋轉、縮放、下載 native／GLB／PNG；完整 ZIP 另附，不遞迴內嵌。受管 Chromium 禁止 file://，以斷網內嵌 HTML 執行驗證，作業系統雙擊開檔未直接測。`index.html` 為資料夾版，解壓後以 `python3 -m http.server --directory OUT 8000` 開啟。

完整素材放私有 `Railway/game-art-previews/docs/art/train-colors-2026-10-22/`；原批私有包作歷史保留。公開只保留配方、工具、文件與總覽，不加入原圖／私有來源 mesh／貼圖。producer commit 在 ZIP 前逐一驗證 Git 中三個配方及工具 bytes，並完整解壓逐檔比對。真機 Metal／效能／動畫仍未驗證。
