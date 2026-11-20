# SUNMOON-LANDMARKS（2026-11-18）

工作串「把舊版日月潭地標搬進遊戲」，分支 `claude/project-thread-nu6bq4`，決策 879。GameCore、存檔版本、golden 不動。

## 做了什麼

- 作者舊版日月潭場景的碼頭、三艘遊艇、廟、涼亭搬進台灣地圖：水社碼頭、文武廟中殿、梅荷園（`Map3DSunMoonLandmarks.swift`，模型由 `tools/landmarks/glb_to_swift.py --legacy sunmoon` 產生）。
- 新的 `replacedPlots`：地標換掉一棟建物時只是不畫它，周圍的民宅照舊（`Map3DFootprints.swift`）。

## 還留下什麼（都未派，分數在素材庫 `a91453/railway-assets-private-2` `docs/priorities/SUNMOON-LANDMARKS.md`）

1. **實機看一次**：下一版 TestFlight 請作者在台灣地圖看水社碼頭與文武廟（Metal 的畫面、幀率沒驗）。
2. **廟的石台沒有階梯**：正面是一面灰牆。照舊版 `sunmoon-main.js` 沒有階梯；可以照文武廟的照片加。
3. **其他碼頭**：伊達邵、玄光寺碼頭可以各放一座，在 `Map3DSunMoonLandmark.all` 加一列（座標、朝向）就會畫，會自己滑到岸。
4. **拉魯島與慈恩塔**：舊版沒有模型，要交工作室新做。
5. **涼亭的遠景**：舊版目錄列了 `pavilion-lod1` 但快照裡沒有檔；現在遠景不畫。

## 注意

- 產生模型：`python3 -I tools/landmarks/glb_to_swift.py --legacy sunmoon --assets ../railway-reference-private/OpenWorld/reference_snapshot/play/assets/sunmoon --out Sources/GamePresentation/Map3DSunMoonLandmarkMeshes.swift`。
- 拍圖的鏡頭寫在 `docs/art/sunmoon-landmarks-2026-11-18/README.md`。文武廟的地面約 828 m、湖面約 748 m，鏡頭高度要照這個給。
