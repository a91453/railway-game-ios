# 145 模型接回 D：香港與 Meshy（交接）

寫於 2026-11-23。工作串 session_01JMHz9ZKTNWfEB6SYp3UtzK 壓縮第 2 次後停手，這裡是沒收完的部分。

## 已做完

- **M+ 與香港故宮文化博物館**（assets-2 #282，決策 931）：PR #2597，分支 `claude/models-145-hk-meshy`。
  地標登錄制一座一檔，145 更新說明各一行。留下的在決策 931 §4（M+ 塔樓比實測厚 8 m、偏北約 34 m：
  已由 revision-2 解決，決策 931「後來」；`hall_lit` 在 Metal 上的亮度沒在實機看過）。
- **Meshy 腳踏車 ×2 與行人 ×5**（assets-2 #256、#257，決策 918）：分支 `claude/models-145-meshy`
  （疊在 #2597 上，已含當時的 `origin/main`）。本機建置乾淨，碰到的測試都過。

## 還沒做完（接手的人照順序做）

1. #2597 的 CI（`Swift CI (gate)` 與 iOS App Build）綠了就合（merge commit）。`main` 再動、
   更新說明那一段又衝突時：併 `origin/main`，`WhatsNew.swift` 的 `2026-11-23-145` 與
   `.github/testflight-whats-new.md` 兩邊的行都留，等新 head 綠。合了在 #2118 留 merge SHA。
2. `claude/models-145-meshy` 的 PR：#2597 合了以後併 `origin/main`（應該沒有衝突，#2597 已在裡面），
   CI 綠了就合，在 #2118 留 merge SHA。
   - `main` 上別的 PR 又加模型進模型包時，`Map3DModelPackLockTests.testTheOrderAndTheLampsAreAsBefore`
     的總雜湊會衝突：留 `main` 的註解、跑測試、把斷言換成測試印出的新值（這次是 `90f60392fb308ced`）。
     `Map3DModelPackSizeTests`、`Map3DModelTests`、`Map3DTaiwanCarsTests`、`Map3DWinterLightsTests`
     的模型數同理。這些是模型包的鎖，不是 golden。
   - `DataSourceCredits.swift` Meshy 那一段衝突時：留 `main` 的句子，再把行人那一句換成
     「行人，以及公車站旁停的腳踏車」的版本（中英都是）。
3. 兩個都合了以後：在 #2118 留「145 模型接回 D 完成」，列每個模型的結果，並通知遊戲規劃。

## 決策 918 留下的（也寫在決策裡）

- 腳踏車放在公車站旁，因為 kit 的 `bikeRack`／`bikeShed` 還沒放上地圖；之後放了車架再把車移過去。
- 公共自行車只在台灣地圖出現。
- 模型是 Swift 編碼的網格，不是 `.m3dmodel`（`tools/glb-to-m3dmodel/bridge.mjs` 不收 AI 來源）。
- 實機上腳踏車的大小、有沒有擋到站牌、行人走路的姿勢，作者看（145 的「請幫忙看」有一行）。
