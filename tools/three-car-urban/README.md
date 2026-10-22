# 三節都市軌道車：原生配方與重建

唯一配方為 `Sources/GamePresentation/Map3DThreeCarUrban.swift`。新增三個獨立單元與一個靜態編組，註冊於 `Map3DModelPack.standard`；不變更營運選型、GameCore、存檔或玩法。

使用專案指定 Swift 6.4（本次安裝 `/workspace/swift`，因 `/opt` 不可寫）：

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DThreeCarUrbanTests|Map3DModelTests|Map3DModelFileTests|Map3DGreenCommuterTests|Map3DGreenTramTests'
tools/three-car-urban/export.sh /outside/public/repo/urban
node tools/three-car-urban/render.mjs /outside/public/repo/urban
node tools/three-car-urban/clay.mjs /outside/public/repo/urban
node tools/three-car-urban/verify.mjs /outside/public/repo/urban
node tools/three-car-urban/geometry-audit.mjs /outside/public/repo/urban
python3 tools/three-car-urban/mutation-check.py /outside/public/repo/urban
python3 tools/three-car-urban/verify-png.py /outside/public/repo/urban
blender --background --python tools/three-car-urban/glb-audit.py -- /outside/public/repo/urban
node tools/three-car-urban/browser-check.mjs /outside/public/repo/urban
node tools/three-car-urban/standalone.mjs /outside/public/repo/urban
node tools/three-car-urban/browser-check.mjs /outside/public/repo/urban --standalone
python3 tools/three-car-urban/bundle.py /outside/public/repo/urban ACTUAL_PRODUCER_COMMIT
```

完整包為 4 件新模型、2 件既有比較模型，各有 native／GLB／七向透明 PNG（共 42 張），七向圖對每件模型固定相同 m/pixel，三個單元共用一致尺度；完整編組另用適合全長的尺度。`previews/audit.png` 的四個正交方向共用 0.030 m/pixel；`detail-front` 和立體 hero 為另標示的放大取景。另有完整編組、獨立單元、白模／剪影和同公尺風格比較。`viewer-standalone.html` 可直接雙擊離線開啟，不需伺服器，可載入／旋轉／縮放與下載各模型；不內嵌完整 ZIP，避免遞迴封裝。本環境受管 Chromium 封鎖 file://，以瀏覽器斷網的內嵌 HTML 模式驗證；系統雙擊開檔未直接測試。資料夾版 viewer 以 `python3 -m http.server --directory /outside/public/repo/urban 8000` 開啟，再瀏覽 `http://localhost:8000/`；可拖曳旋轉、縮放與下載 native／GLB／PNG。離線不需 CDN。可選用 `feedback-compare.mjs CURRENT PRIOR` 從兩版實際 native 生成同相機、同尺度前後對照；PRIOR 不進最終 ZIP。

## 組裝規格（展示比例推估，非工程尺寸）

| 單元 | 原生 ID | 中心 x（m） | 外端 |
| --- | --- | ---: | --- |
| 頭車 | urban-three-leading | +15.28 | +x 駕駛面 |
| 中間車 | urban-three-middle | 0 | 兩端連接面，無駕駛設備 |
| 尾車 | urban-three-trailing | −15.28 | −x 駕駛面 |

全部單元不旋轉、不鏡射。車體名義長 15 m，寬 2.65 m，屋頂 3.34 m、空調頂 3.606 m；兩車殼間距 0.28 m。轉向架中心 x=±4.98 m、每架兩軸 x=centre±0.84 m、輪徑 0.68 m。原生 +x 前／+y 左／+z 上，輪底 z=0。作者座標 x 前／y 上／z 右只透過 `Model.flat` 轉換一次。門、燈、輪及空調為靜態幾何。

參考為本輪五張聊天附圖，均目視檢查；沒有本地原圖檔，因此不做像素疊圖或工程尺寸宣稱。私有參考庫 `taiwan-rail-reference-clean/source/rail-3d/README.md` 的模型／編組機制已檢查，但無法從此次無型號圖片唯一匹配真車尺寸，沒有搬用 mesh。`Map3DGreenCommuter` 僅作色票、霧面質感和細節密度比較；車體、底盤、車頭、門窗配置與編組全新編寫。通用封閉 box／tube／facet、native exporter 和 WebGL renderer 沿用專案工具；無新 runtime 或建置依賴。

完整素材只放私有庫 `Railway/game-art-previews/docs/art/three-car-urban-2026-10-22/`。公開庫保留配方、工具、必要測試、文件、一張總覽。詳細外觀驗收見對應 docs/art README；技術與美術結論分開。Linux WebGL／Blender 匯入不等同真機 Metal、效能或動畫驗證。
