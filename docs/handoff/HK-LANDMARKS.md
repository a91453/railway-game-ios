# HK-LANDMARKS：香港地標上 3D 地圖（決策 791）

- 2026-11-15，雲端 thread session，分支 `claude/project-thread-yz1qsu`（PR #2280）；素材 `a91453/railway-assets-private` #118（`game-art-previews/docs/art/hk-landmarks-2026-11/`）。
- 做完：八棟進香港地圖（環球貿易廣場、國金二期、中環廣場、中銀、長江中心、中環中心、尖沙咀鐘樓、文化中心）；model-look `references/studio-brief.md` §5 寫了工作室做建築的經驗。

## 還留下什麼

1. **滙豐總行、會展**：審查不給過。另開工作室，派工單寫明主樓、柱塔、桁架（會展：屋頂、玻璃牆、基座）分開減面，先單做滙豐一棟。底稿在 `base/`，第 3 輪的腳本與審查報告在 `revision-8/`。
2. **六棟的已知缺點**（決策 791 §4）：下一輪工作室一起修。
3. **青馬大橋**：在地政總署的 `INFRASTRUCTURE/`（圖幅 10-NE-3A 附近），還沒取。
4. 換成新模型：重跑 `python3 -I tools/hk-landmarks/glb_to_swift.py --out Sources/GamePresentation/Map3DHongKongLandmarkMeshes.swift <GLB…>`，在 `Map3DHongKongLandmark` 加 case、位置與 `baseHeight`（`base/landmarks.json`），測試的尺寸表加一行。

## UNVERIFIED

- 沒有在 App（Metal）或 iOS 上看過；工作室的圖是 Blender 出的。截圖：工作室做、審查過的模型不拍 CI 截圖（ui-review §3）。
- 地面高程比模型腳高的地方（中銀在斜坡上）腳會埋一點，沒有逐棟在遊戲裡確認。
