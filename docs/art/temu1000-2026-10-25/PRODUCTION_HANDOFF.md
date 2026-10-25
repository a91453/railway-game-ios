# TEMU1000 製作交接與可重用經驗

此頁是目前版本的接手入口。逐輪的造型判讀保留在 [README](README.md)；其中「本輪前後對照」是當時的紀錄，**現行** `previews/before-after.png` 比較的是公開 producer `cea94afc` 與最新原生端車。任一新修訂都要先保存真正前版，再重做同相機、同公尺尺度的比較。

## 目前交付與狀態

- 公開 [issue #1228](https://github.com/a91453/railway-game-ios/issues/1228)／[draft PR #1230](https://github.com/a91453/railway-game-ios/pull/1230)：`Sources/GamePresentation/Map3DTEMU1000.swift` 是唯一車形配方；`Map3DModelPack` 註冊四種車廂，`Map3DTrainSets.temu1000()` 將單元用於 `taroko` 的營運 3D 顯示。公開 PR 合併前遊戲不會使用此新造型。
- 私有 [draft PR #78](https://github.com/a91453/railway-reference-private/pull/78)：`Railway/game-art-previews/docs/art/temu1000-2026-10-25/` 有最終 M3DM、GLB、每件七向 PNG、四單元／八節預覽、白模、剪影、同尺度風格比較、真正前後圖、viewer、manifest、來源紀錄、SHA 與完整 ZIP。原始參考圖沒有本機檔案或 SHA，沒有放進公開庫。
- 模型是**靜態**遊戲素材，沒有動畫。GameCore、存檔、golden、replay 和玩法沒有為此修改。兩張 PR 仍是 draft；作者尚未認可造型。最新 CI 應以 PR 當下的 head 與 checks 為準，不沿用本頁的快照。

## 最終外觀判讀

| 項目 | 已見於最終原生渲染 | 仍需留意 |
|---|---|---|
| 車首 | 收圓而向前鼓出的鼻端、下移的深色風擋、置中的白色下臉、中央雙燈與環鼻細腰線 | 近景鼻罩、裙板與燈座仍有低多邊形折面；屋頂灰色在單側打光下有亮度差，不能用明暗當幾何對稱證據 |
| 側身 | 深色窗帶內有獨立霧藍灰客窗、細柱與門窗；輪盤較舊版小 | 另一側真實門窗位置、窗內構造與車底設備資料不足 |
| 編組 | TED 端車兩節、TEM 中車四節、TEP 集電設備車兩節；中車沒有駕駛窗或頭燈 | 單元功能順序及隱藏設備是展示假設，並非工程確認 |

檢視入口：私包 `previews/overview.png`、`passenger-detail-left.png`、`after-front.png`、`cab-detail-left.png`、`before-after.png`、`units.png`、`directions.png`；每件完整七向在 `views/`。本次對使用者提出的三件事：輪盤半徑 0.39→0.33 m、車窗在黑帶內明確分格、灰色屋頂材質不再落到風擋下方單側。輪徑是遊戲比例推估，不是實車尺寸。

## 如何重建與核對

1. 先讀本頁、[製作紀錄](README.md)、`tools/temu1000/README.md`、私包 `README.md`、`manifest.json` 和 `source-record.json`。原生座標是公尺、+X 車首、+Y 左、+Z 上，軌面 Z=0。四角色次序及所有中心平移在 manifest；目前節距 23.9 m 是比例推估。私包的 `geometry-scope.json` 記真前版與終版原生輪盤頂點的差異及 TEP 高位集電弓頂點未變。
2. 只改獨立配方 `Map3DTEMU1000.swift`，再用 Swift 6.4、warnings-as-errors 執行 `tools/temu1000/export.sh OUT`。執行 `node tools/temu1000/render.mjs OUT`、`node tools/temu1000/clay.mjs OUT`；任何模型修改後都要重新匯出最終視圖，不要沿用舊 PNG。
3. 目視原生模型的正、側、俯、斜及白模／剪影。先判整體長寬、頭尾曲面，再判輪組、門窗、設備；若改了造型，將前版原生模型保留於私庫，以 `node tools/temu1000/feedback-compare.mjs OUT PRIOR` 重做同相機同公尺尺度的前後圖。用「已符合／仍不符合／資料不足」記錄結果，不以測試通過代替外觀驗收。
4. 執行 `node tools/temu1000/verify.mjs OUT`、`python3 tools/temu1000/verify-png.py OUT`、`node tools/temu1000/browser-check.mjs OUT`，並以 Blender 執行 `tools/temu1000/glb-audit.py`。原生讀回、三角數、法線、八節平移組裝、輪底、PNG 完整解碼／透明／不裁邊、viewer 旋轉／縮放／下載都須核對。相關 Swift 測試是 `Map3DTEMU1000Tests`、`Map3DModelTests`、`Map3DTrainSetTests`；最後一次模型修訂後本機共 27 項通過，CI 結果仍看新 head。
5. 公開 producer commit 確定後才執行 `python3 tools/temu1000/bundle.py OUT PUBLIC_PRODUCER_COMMIT`。它寫入配方 SHA、逐檔 SHA 與 ZIP，並檢查解壓、CRC、每個成員與現場檔案位元組相同。公開 `overview.png` 必須與私包最終總覽 SHA 一樣。若公開文件使 producer commit 改變，須更新私包 `source-record.json`、`package-verification.json` 和 ZIP；模型未變時不必重做幾何／PNG。

## 本次可重用的檢查教訓

| 先前失誤 | 能抓到問題的檢查 |
|---|---|
| 側面黑帶在遠景像整條貼片 | 放大側視；核對每片客窗的實際幾何及與黑底的亮度差，不能只數窗配方常數 |
| 輪盤太大 | 在同一公尺比例下並排真前版和新版；讀回輪盤頂點，確認軸位、最高點及軌面接觸 |
| 正面灰色看似歪斜 | 分別檢查材質分界、左右頂點／三角切法及光照；灰色屋頂不可隨縮小鼻端截面落入風擋下方 |
| 車首從側面顯得扁平 | 側視和斜視同時看短端面、斷面放樣與前凸曲面；換色不能補救輪廓 |
| 正面中央燈曾消失 | 正面與斜視要檢查燈罩、實體支承與頭尾兩端；中間車不能殘留駕駛設備 |
| 歷次紀錄把「目前前版」寫成固定舊版 | 現行交接只指向最新真前版；舊章節明列為歷史紀錄。每次再修都同步更新這個入口、HANDOFF、PR 與私包來源紀錄 |

下一位接手者若要繼續修外觀，先拿到更明確的正側正交資料或使用者對這份最終預覽的具體指正。現有圖仍不足以宣稱工程輪徑、另一側配置與隱藏設備已確認。真機 Metal、實際效能、動畫與全面碰撞採樣維持 **UNVERIFIED**。
