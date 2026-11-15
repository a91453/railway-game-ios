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
7. **材質表**：材質名、sRGB、**遊戲裡的色**、用在哪。一個材質＝一個色票色，沒有 UV、沒有貼圖。
   **色一律從 `Map3DPalette`（建築用 `cityOfficeWalls`、`cityConcreteWalls`、`cityRoofs`、`hallWalls` 等）與舊材質對照表
   `tools/texture-palette/t003/building-map.csv` 取**，表裡寫出是哪一格；遊戲沒有的色標「新提」並寫原因（例：遊戲沒有金色）。
   不可以自己挑一組色（香港地標第一版派工單就是自挑 12 色，2026-11-15 改回）。
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

## 5. 建築與地標（第一次：香港地標十棟，2026-11-15，進行中、隨輪次補）

派工單：`a91453/railway-assets-private` 的 `game-art-previews/docs/art/hk-landmarks-2026-11/README.md`。
和列車不同、或這次踩到的：

**底稿**

- 先找**測量來的外形**當底稿，從它減面，不重新捏：香港用地政總署 3D Visualisation Map 的無貼圖模型（`GLTF0`，
  一棟一個 `.gltf`）；台灣用 OSM 的建物輪廓與高度，或作者舊版的模型。比例、高度、位置就不會錯。
- 底稿先在雲端處理好再交工作室：併點、去零面積與重複三角形、底面中心放原點、地面 Z = 0、軸是 +X 東 +Y 北 +Z 上
  （Blender 匯入後）；一份 `landmarks.json` 記來源 ID、經緯度、底的高程、原始檔 sha256。腳本在派工單的 `tools/`。
- 底稿裡可能混了別的東西：滙豐的底稿有約 7.5 萬面是行道樹，先刪掉再減。
- 地政總署的下載（`download.map.gov.hk`）**雲端容器抓得到**，Mac 檔案工具的 VM 抓不到（403）。

**派工單要多寫的**

- 每棟一行：檔名、高、底稿三角形、近景預算（列車的「哪幾種要做」改成這張表）。十棟近景合計也給上限。
- 招牌、標誌、文字一律不做（銀行、商場頂上的字）。
- **結構複雜的要先拆「主體＋特徵零件」再各自減面**，派工單裡就點名哪幾棟（香港：滙豐的桁架、國金二期的冠、
  會展的翼形屋頂）。整棟直接 Decimate，簡單方柱沒事，這幾棟會崩。
- **不准用盒子重建**：第 1 輪滙豐減完超預算，第 2 輪改用盒體重建，面數漂亮但被審查判「認不出來」。
  超預算就回底稿、分零件減，不換做法。
- **遠景另外驗**：近景過了不代表遠景對；第 2 次審查退回的一半是遠景走形與缺口。遠景要和近景一樣出 7 向圖。

**交件前自查（建築多加兩條，和 §2 一起報數字）**

| 查什麼 | 要的結果 |
| --- | --- |
| 輪廓誤差：減面後和底稿比 | 目標 ≤ 0.5 m（冠、屋頂等特徵 ≤ 1 m）；**雙向**量（底稿到成品、成品到底稿）、分高度段報，不要只報一個數字 |
| 色帶、線條、窗框埋進牆面 | 0（從正面量）；整片站出牆面約 0.3 m（建築比列車大，2 cm 遠看不到） |
| 遊戲大小圖 | 每棟各自約 150 px 高、放在城市背景裡，不要十棟擠一張 |

**照片**

- 用 Wikimedia Commons，挑 CC BY／CC BY-SA／CC0，`ref/SOURCE.md` 每張寫檔名、作者、授權。
- **看縮圖確認是哪一棟**：檔名不可靠（這次一張標「中環中心」的其實是長江中心）。
- Commons API 連續查詢會被限流（雲端容器尤其），照片改由 Mac 那邊找。

**工作室流程（建築這次新踩到的，§3 之外）**

- Antigravity 開工前確認是自動允許：Antigravity 的 `/config` 把 Tool Execution Policy 設成 always-proceed
  （settings.json 的 `"toolPermission": "always-proceed"`），deny 照擋。跳出核准請求時**先放寬權限，不要中途換人**；
  真要關一個做到一半的 session，先查狀態、把沒 commit 的檔備份。
- Antigravity 看圖回 400（`INVALID_MEDIA`）：Blender 存的 JPEG 內嵌的 ICC 編號是 0，Gemini 讀不了；看圖前先
  `sips -s format png <圖> --out <暫存>.png`（assets #125）。
- 每輪先寫 `revision-N/README.md` 才開下一輪（這次連開三輪沒寫紀錄）。
- **重開審查前先 `studio.py takeover`**：不然新開的審查看到座位還掛著上一個 session，會一開就停在等人接手，
  介面上看起來像沒在跑。

**接回遊戲**（決策 791）：地標不走列車的註冊表。
- `tools/hk-landmarks/glb_to_swift.py` 把 GLB 寫成 `Map3DHongKongLandmarkMeshes.swift`：頂點用**公分**（x、y Int16，z UInt16），
  因為高樓超過列車那套公釐 Int16 的 ±32 m；材質名照工具裡的 `MATERIALS` 順序對色票。
- `Map3DHongKongLandmark`：每棟一個 case，位置（`base/landmarks.json` 的經緯度）、`baseHeight`（模型腳的高程）。
- 密集市區**不清 64 m 格子**（會連鄰樓一起清），只不畫中心落在地標本體裡的那棟足跡（`landmarkPlots`）。
- 審查判「不建議交付」的不進遊戲，照舊由一般建物畫，另派工作室；「交付但列缺點」的照進，缺點寫進決策的下一步。
- 資料來源寫進已有的那一項（加一句與連結），不另開 id。
