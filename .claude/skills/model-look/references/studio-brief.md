# 交給本地工作室：派工單範本、交件自查、接回遊戲

第一次走完整條路的是香港機場鐵路列車（決策 780，2026-11-15）。它的派工單在
`a91453/railway-assets-private` 的 `game-art-previews/docs/art/mtr-airport-line-2026-11/README.md`，
審查退回的紀錄在同一處 `revision-4/review/`，Blender 腳本在 `revision-4/tools/build.py`。新的模型照抄它。

## 1. 派工單（放素材庫 `game-art-previews/docs/art/<資料夾>/README.md`）

依序寫：

1. **是什麼、為什麼做**：優先清單的項目與分數、決策號。
2. **命名**：用路線或用途描述，不用車隊暱稱或會被誤認成別的遊戲的名字；不放公司商標、標誌、文字。
3. **找過哪裡**（model-look §1）：作者舊版素材、私有素材庫、參考庫各找到什麼；有用的複製進工作室的 `brief/`
   （工作室的 AI 只看得到自己的 worktree 與 `brief/`）。
4. **憑什麼被認出來**：三到五條。
5. **尺寸表**：量到的寫來源，推估的註明。
6. **哪幾種要做**：外觀一樣的合成一種（列車通常是駕駛室車、中間車、集電弓車、特殊車），每種近景與遠景（`-far`）。
7. **材質表**：材質名、sRGB、用在哪；遊戲已有的顏色沿用同一個名字。一個材質＝一個色票色，沒有 UV、沒有貼圖。
8. **座標**：前方 +X、上 +Z、地面（軌面）Z = 0、中心 X = 0、公尺；匯出前把物件的變換 Apply 掉。
9. **三角形預算**：近景與遠景各多少；遠景同框（同長、同高、貼地），顏色是近景的子集。
10. **看三輪**（model-look §2–4）：7 向圖＋遊戲大小圖，和照片並排。
11. **交件**：素材庫的哪個 branch、`revision-N/` 放什麼、跑 `tools/asset_guard.py`，不合併。

## 2. 交件前自查（寫進派工單，要做的人交件前自己數）

機場鐵路列車第一次審查退回的五條，每條都要報數字：

| 查什麼 | 要的結果 |
| --- | --- |
| 朝內的面（側、頂、頭、底各數） | 0；合併共點後重算法線，不要對斷開的面各自翻 |
| 站出車身的板（門、窗、框）埋進曲面 | 0；順著車身剖面的折點分段，整片站出約 1.5–2.5 cm |
| 該有的零件（例：中間車兩端、駕駛室車後端的連結器） | 都在 |
| 零面積三角形 | 0 |
| 塗裝起止位置 | 和側面照片同一處（寫明從哪裡開始） |
| 近遠景同框 | 長、寬、高差 ≤ 1 mm |
| 清晨亮窗（玻璃換 #F2D9A0 拍一張） | 門是車身色、只有門上小窗亮；客室窗一格一格，不是一整條；單塊亮玻璃 ≤ 0.7 m²（rolling-stock §4） |
| 共面／重疊面（車頂零件、端牆、接縫） | 0；疊在車頂上的零件至少凸出 2 cm，不用貼面薄片畫格子（rolling-stock §4） |

## 3. 工作室流程的卡點

- 做的人 commit 之後不一定會通知審查；去看它的 branch，或請它交件。
- 審查的座位卡在舊登記時，由 Mac 上的 session 跑 `studio.py takeover --task <任務> --role <角色>`，不要請作者打指令。
- 審查只寫「通過／退回＋毛病清單」；退回時把清單原樣交回做的人，下一輪再審。
- 工作室不用時就收掉（吃額度）。

## 4. 接回遊戲（雲端 session）

1. `tools/train-models/glb_to_swift.py`（用法在它開頭）：材質名照 `--materials` 的順序變成色票索引，
   glTF 軸轉成遊戲軸，寫出 `Sources/GamePresentation/Map3D<名字>Mesh.swift`。
2. 照決策 782 的註冊表接（`rolling-stock` skill §2.1）：模型的 enum（`meshPalette` 與 `--materials` 同順序）、
   這款車自己的色票（`extension Map3DPalette`）、set 與遠景 set（`extension Map3DTrainSet`）、
   `static let registration = Map3DTrainRegistration(...)`（列車展示的列、三角形與長度範圍）都寫在車自己的
   `Map3D<名字>.swift`；`Map3DTrainRegistryList.swift` 最後加一行；雜湊鎖寫在 `tools/train-models/locks/<id>.json`；
   這款車自己的測試、決策、`docs/art/<資料夾>/`（總覽圖不含照片）。範例是 `Map3DMTRAirportLine.swift`。
3. `Map3DScene.swift`、`Map3DTrainSets.swift`、`Map3DShowcase.swift`、`hashes.lock.json` 與模型包大小、雜湊測試都**不用改**，
   所以兩款車可以同時接，不會衝突（清單那一行由 `.gitattributes` 的 `merge=union` 自動合併）。
4. 工作室做、審查已通過的模型不用拍 CI 截圖（ui-review §3），CI 綠就合。
