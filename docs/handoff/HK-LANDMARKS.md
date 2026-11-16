# HK-LANDMARKS：香港地標上 3D 地圖（決策 791）

- 2026-11-15，雲端 thread session，分支 `claude/project-thread-yz1qsu`（PR #2280）；素材 `a91453/railway-assets-private` #118（`game-art-previews/docs/art/hk-landmarks-2026-11/`）。
- 做完：八棟進香港地圖（環球貿易廣場、國金二期、中環廣場、中銀、長江中心、中環中心、尖沙咀鐘樓、文化中心）；model-look `references/studio-brief.md` §5 寫了工作室做建築的經驗。

- 2026-11-16，本地派工 session（Mac），HSBC-REDO（決策 793）：**滙豐總行大廈進地圖**，現在九棟。分支 `claude/hsbc-redo`；素材 `railway-assets-private` #128（`revision-9/`：滙豐新做，其餘八棟的 GLB 從 `revision-8/` 搬過去、內容不變）。

## 還留下什麼

1. **會展**（HKCEC-REDO，決策 798）：照滙豐這次的做法另開工作室（屋頂、玻璃牆、基座分開做）。底稿在 `base/`。滙豐的派工單、三次審查報告與腳本在 `revision-9/`，可以照抄。
2. **共面閃爍**（LANDMARK-FLICKER）：`coplanar_check.py` 2026-11-16 起多印真的重疊的對數（`overlap`）。revision-9 的九棟：

   | 檔 | 外框重疊 `boxes` | 真的重疊 `overlap` |
   | --- | ---: | ---: |
   | 國金二期 近／遠 | 97／7 | 76／4 |
   | 長江集團中心 近／遠 | 64／0 | 60／0 |
   | 中環廣場 近／遠 | 62／2 | 37／0 |
   | 中銀大廈 近／遠 | 0／12 | 0／10 |
   | 環球貿易廣場 近／遠 | 2／13 | 0／6 |
   | 文化中心 近／遠 | 169／108 | 2／0 |
   | 中環中心 近／遠 | 135／0 | 1／0 |
   | 尖沙咀鐘樓 近／遠 | 49／49 | 0／0 |
   | 滙豐總行 近／遠 | 12／13 | 0／0 |

   派工單點名的三棟（文化中心、中環中心、國金二期）是照舊的數排的；照新的數，最多的是國金二期、長江中心、中環廣場。
3. **六棟的已知缺點**（決策 791 §4）與**滙豐的十條**（決策 793）：下一輪工作室一起修。
4. **青馬大橋**：在地政總署的 `INFRASTRUCTURE/`（圖幅 10-NE-3A 附近），還沒取。
5. 換成新模型：重跑 `python3 -I tools/hk-landmarks/glb_to_swift.py --out Sources/GamePresentation/Map3DHongKongLandmarkMeshes.swift <全部的 GLB…>`（每棟先 `-far` 再近景、照檔名排，沒改的那幾棟輸出才會逐位元組不變），在 `Map3DHongKongLandmark` 加 case、位置與 `baseHeight`（`base/landmarks.json`），測試的尺寸表加一行、`testOnHongKongsMap` 的清單視位置加上。素材庫一個資料夾只能有一輪留 GLB：開新的 `revision-N/`，沒重做的用 `git mv` 搬過去。

## UNVERIFIED

- 沒有在 App（Metal）或 iOS 上看過；工作室的圖是 Blender 出的。截圖：工作室做、審查過的模型不拍 CI 截圖（ui-review §3）。
- 地面高程比模型腳高的地方（中銀在斜坡上）腳會埋一點，沒有逐棟在遊戲裡確認。
- 滙豐（決策 793）沒有在 App 或實機上看過；底層架空處和地面怎麼接沒有確認。
