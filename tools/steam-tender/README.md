# 蒸汽機車＋獨立煤水車素材重建

配方為 `Sources/GamePresentation/Map3DSteamTender.swift`，入口只在 `Map3DModels.swift` 靜態註冊。獨立車體、底架、圓煙箱、鍋爐、駕駛室、輻條輪與煤水車；沒有呼叫既有車輛配方。沿用專案低階封閉幾何、色票、原生格式與 station-kit exporter/renderer 的做法。**靜態素材；合併不會替換營運列車。**

本輪10張原圖已逐張查看，原檔與SHA只保存在私庫。同型工程規格未獲證實；已查 CT273 metadata（Q-proportions、engineeringDimensionsM=null）、世界車型目錄與 OpenWorld specs，皆不能把本圖認定為 CT273 或其他真車。表列值一律為**比例推估展示尺寸**。完整判讀／外觀結論見 `docs/art/steam-tender-2026-10-23/README.md`。

原生 +x前／+y左／+z上、公尺、軌面z=0；建模器x前／y上／z右，在 `.flat` 邊界轉換。完整編組由 `steam-locomotive` 平移(+4.35,0,0)、`steam-tender` 平移(−7.25,0,0)，兩件旋轉均0。殼間距0.60m；連結器端面相接；所有輪底在共同z=0。單元原點是配方基準，不以每件bounds重新置中。

需要專案指定 Swift6.4、Node/Playwright/Chromium、Python/Pillow/NumPy、Blender。使用環境既有工具；不增加App依賴。OUT放公開庫以外，PRIOR指向真正初版匯出；不可用最終模型充作前版。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DSteamTenderTests|Map3DModelTests|Map3DModelFileTests'
tools/steam-tender/export.sh OUT
node tools/steam-tender/review.mjs OUT
# 親自查看實際原生模型的配色／白模／剪影：側、正、俯、斜。
# 若修幾何先保留真正前版，重新export、review，再做批次。
node tools/steam-tender/render.mjs OUT
node tools/steam-tender/clay.mjs OUT
node tools/steam-tender/feedback-compare.mjs OUT PRIOR
node tools/steam-tender/feedback-compare.mjs OUT PRIOR cab
node tools/steam-tender/revision-audit.mjs OUT PRIOR
node tools/steam-tender/geometry-audit.mjs OUT
node tools/steam-tender/mutation-check.mjs OUT
python3 tools/steam-tender/support-audit.py OUT
python3 tools/steam-tender/support-audit.py OUT --mutation
node tools/steam-tender/verify.mjs OUT
blender --background --python tools/steam-tender/glb-audit.py -- OUT
python3 tools/steam-tender/verify-png.py OUT
node tools/steam-tender/standalone.mjs OUT
node tools/steam-tender/browser-check.mjs OUT
node tools/steam-tender/browser-check.mjs OUT --standalone
python3 tools/steam-tender/bundle.py OUT ACTUAL_PRODUCER_COMMIT
# ZIP存在後重新測真下載、重包納入結果。最後重測可用 --no-write。
node tools/steam-tender/browser-check.mjs OUT
python3 tools/steam-tender/bundle.py OUT ACTUAL_PRODUCER_COMMIT
node tools/steam-tender/browser-check.mjs OUT --no-write
```

`components.json`的triangle ranges對應最終native，不是額外替代模型。幾何稽核逐封閉實體檢查有向邊、正體積、玻璃到真實cab-wall的反向射線、動輪上緣與踏板間隙、煤水車輪頂與底架間隙。support-audit用實際三角面交線／點面距離／包含測試建立接觸圖，AABB只作候選篩選，12mm為數值與裝配容差；489零件皆連到接地輪組。不是機械強度、動態淨空或物理模擬。突變測試拒收缺面、反面、整片封閉玻璃浮空、踏板切動輪、整個封閉鐘浮空。

五件（兩單元＋完整編組＋兩件風格比較）各七向透明512PNG，兩單元共用尺度，每件七向固定m/pixel；編組正交圖0.020m/pixel。hero／正面局部另取景，風格比較共用相機與尺度。配色／白模／剪影全部來自相同native三角形。最終圖全批重新生成，不混舊圖。`revision-audit`證明鍋爐、車體、窗、管線及其他非修訂零件逐頂點穩定。

ZIP先驗證實際Git producer的所有Map3D配方、這批工具及共用renderer/package bytes；完整解壓、CRC、成員集合與逐檔bytes比對。`source-record.json`保留producer、原圖SHA、來源metadata與各工具SHA。歷史模型標示prototype、producer=null，不冒用最終producer。

資料夾viewer解壓後 `python3 -m http.server --directory OUT 8000`，開localhost:8000。單檔`viewer-standalone.html`內嵌模型與PNG，可斷網旋轉、縮放、下載native／GLB／目前PNG；完整ZIP另附。已測實際瀏覽器下載的SHA。GitHub blob頁不會直接執行HTML，先下載單檔或ZIP。OS雙擊file://未測，斷網內嵌HTML已測。

Linux WebGL、Swift與Blender驗證不代表真機Metal、效能、連桿動畫、車輛物理或營運指派。CI須看最新head Checks，與本機技術／外觀結論分開。
