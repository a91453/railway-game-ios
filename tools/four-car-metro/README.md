# 四節暖白金砂都市列車

獨立原生配方 `Sources/GamePresentation/Map3DFourCarMetro.swift`。作者本輪五張 inline 參考均已逐張查看：俯斜正面、兩個相反側面局部、兩個相反斜視完整編組。原圖沒有本地檔案，不能提供原圖 SHA 或假裝產生精確正交參考。新車不呼叫既有列車的車體、底盤、車頭、門窗或編組配方；只共用專案封閉 box、tube、凸多邊形 face、色票與檔案匯出工具。

## 特徵與尺寸依據

四節等長的傳統高地板都市軌道車，非前批五／七節長短交替低地板輕軌。兩端駕駛室朝外，中間兩節無駕駛窗、頭燈、緩衝塊。每節每側兩組雙扇門，三個分離窗位；前端窄直窗、中間寬窗、連接端小窗。每節兩組雙軸轉向架，四節16軸；輪組在參考中部分被側架遮住，採常規雙軸補全。車頭近直立、橫向風擋、低位雙燈、雙緩衝塊和中央連結器；前後外端同型但方向相反，內端是風琴。兩側門位相同，外端窄窗隨駕駛室方向調整。屋頂低肩倒角，每節兩片低矮檢修蓋；圖中沒有可辨識集電弓，不擅加集電設備。

本輪未能唯一辨識製造商／真實車型。已查私庫 OpenWorld `train-model-specs.js`、世界版 `rolling-stock/catalog-2026-10.json`、`rail-3d/integration/formations.js`、程序素材 `MODEL_CATALOG.json`；其車型資料不能唯一匹配本圖。只取原生規格、低階幾何、色票與工具，不取私有 mesh／圖片／貼圖，也不送外部生成服務。**下表全部為公尺展示比例推估，不是工程尺寸；透視像素不當工程量測。**

| 項目 | 展示規格 |
| --- | --- |
| 殼長／寬／屋頂軌面高 | 12.00／2.70／3.65 m |
| 每節輪徑／架內軸距／架心距 | .76／1.56／7.70 m |
| 端部收束長度／風擋相對傾角 | .50 m／約3.15°離垂直 |
| 端部軸心至車殼端 | 1.37 m，連結器另伸出 |
| 車身底／窗底／窗頂 | .84／1.875／約3.025 m |
| 雙門中心x／門寬／門高 | ±2.63／1.57／2.27 m |
| 檢修蓋中心x／高度 | ±4.05／.044 m |
| 兩節殼間距 | .30 m；各帶半風琴，靜態直線組裝 |

暖白 `shopAwnings[3]` 為主，金砂 `containers[3]` 用於車頭與腰下帶，深藍灰框／門與灰藍玻璃用既有 palette。霧面頂點色，無紅色漆、品牌、照片貼圖。風擋與側窗用封閉薄體，背後65mm內必須有車殼或支承，不接受玻璃與浮空框相互背書。整片底架最低.78m，輪頂.76m，保留20mm展示淨空；架體以中央承板支持。

## 組裝

原生 **+x前、+y左、+z上，公尺**。建模器 x前/y上/z右，只在 `Model.flat` 轉換一次。導出的四件只平移，無旋轉／鏡射：

| 順序（+x到−x） | ID | 中心x |
| --- | --- | --- |
| 前端 | metro-four-leading | 18.45 |
| 中前 | metro-four-middleFront | 6.15 |
| 中後 | metro-four-middleRear | −6.15 |
| 後端 | metro-four-trailing | −18.45 |

完整編組 `metro-four-formation`。共同軌面z=0，四節輪底皆貼地；風琴沿共同中線。原生內外朝向已做好，不要再轉反向端。完整尺寸和每件三角數以 manifest 的實際 min/max 為準。比較模型 `urban-three-leading`、`lrt-seven-leading` 只作同尺度風格對照。

**只註冊靜態素材庫。未新增營運、物理、鉸接動畫或車型指派。** 合併這份素材 PR 不會自動替換目前營運列車；後續整合須選定車型並按12.3m節距組裝，不改 GameCore／存檔／golden／replay。

## 重建與檢查

OUT須在公開庫之外；本機 Swift 6.4 位於 `/workspace/swift/usr/bin`。Node、Playwright、Chromium、Python/Pillow、Blender使用環境既有工具，無新遊戲依賴。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DFourCarMetroTests|Map3DModelTests|Map3DModelFileTests'
tools/four-car-metro/export.sh OUT
node tools/four-car-metro/render.mjs OUT
node tools/four-car-metro/clay.mjs OUT
node tools/four-car-metro/art-checks.mjs OUT
node tools/four-car-metro/feedback-compare.mjs OUT ACTUAL_INITIAL_EXPORT
node tools/four-car-metro/feedback-compare.mjs OUT ACTUAL_INITIAL_EXPORT cab
node tools/four-car-metro/revision-audit.mjs OUT ACTUAL_INITIAL_EXPORT
node tools/four-car-metro/verify.mjs OUT
node tools/four-car-metro/geometry-audit.mjs OUT
python3 tools/four-car-metro/mutation-check.py OUT
blender --background --python tools/four-car-metro/glb-audit.py -- OUT
python3 tools/four-car-metro/verify-png.py OUT
node tools/four-car-metro/standalone.mjs OUT
node tools/four-car-metro/browser-check.mjs OUT
node tools/four-car-metro/browser-check.mjs OUT --standalone
python3 tools/four-car-metro/bundle.py OUT ACTUAL_PRODUCER_COMMIT
```

首次ZIP不存在時 browser記錄zip_download=false；bundle後再執行folder browser／standalone並重包，最後再測一次現有ZIP而不改驗證內容。逐檔解壓比對和實際producer程式 SHA 是 bundle 強制條件。

七向圖來自同一原生模型，各件七向固定同一m/pixel，四個單元共用尺度；正交稽核 .035m/pixel；風格比較相機和公尺尺度相同。hero／前端局部另行取景，標示清楚。白模／剪影直接修改同一份 native 頂點色，不替換形狀。

公開庫僅配方、工具、測試、文字與一張 overview；完整七件原生／GLB、49七向圖、白模、風格比較、viewer、來源紀錄和ZIP在私庫 `Railway/game-art-previews/docs/art/four-car-metro-2026-10-23/`。初版真實模型另存 `-initial/`，幾何有修訂時用同相機／尺度比較。

技術與外觀結論分開記錄於素材文件。Linux Swift／Blender／WebGL通過不代表真機Metal、效能、動畫或營運接入驗證；受管瀏覽器不支援 file://，單檔以斷網內嵌HTML驗證，OS雙擊未測。
