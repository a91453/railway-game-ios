# MTR-REAL-TRAINS：港鐵其餘四綫真車＋馴鹿＋石斗車（交接）

## 進度

- 做到哪：屯馬綫接進遊戲了（#2409，決策 839），馴鹿也接進了（#2414，決策 840）；馴鹿的換色 #2416 也已合併。東鐵綫第 6 版由 Codex 審過，已合進素材庫（assets #159）；**還沒接進遊戲**。南港島綫、迪士尼綫還沒開工。石斗車做完兩輪後停了，等人叫醒。
- 已驗證：工作室新版（assets #158：規則檔自動跟上 main、`runner.py sync-kit`、`retry --note`）在雲端 Linux 跑 `tests.py`，86 個全過。在作者 Mac 上還沒裝（見下面「Mac」）。
- 下一步的第一個指令：Mac 上 `STUDIO_CONDUCTOR=1 python3 -I /Users/chienlinyeh/AlongTheLine-Studio/bin/runner.py sync-kit --repo /Users/chienlinyeh/Developer/railway-assets-private --check`。印「不用裝」就代表作者已經裝好了。

session `session_01YGNNuq5GFB4XjtpH5pQdKz`，分支 `claude/project-thread-q98be6`。這條 session 壓縮了 3 次，照規則停在這裡，以下由下一條接。存檔版本、golden schema 不動。

## 還留下的

### 1. 東鐵綫接進遊戲（新決策，到 #2118 取號）

**已做**（2026-11-18，#2424，決策 843）：九節 D P M F P M M P D，玻璃照 #2417 逐面認；EAL、EAL_LMC 改畫這款。以下留作紀錄。

- 素材：素材庫 main 的 `game-art-previews/docs/art/mtr-east-rail-line-2026-11/revision-6/`。四種車 `cab`、`car`、`first`、`pantograph`，各有近景和遠景，共 8 個 GLB。另有 `overview.jpg`、`front-view.jpg`、`check_report.json`、`stats.json`。
- 做法照屯馬綫那次（commit d679c2360，#2409），要動的檔：
  - `Map3DMTR<線>.swift` 與 `…Mesh.swift`
  - `Map3DRealTrains.swift`
  - `Map3DTrainRegistryList.swift`
  - `tools/train-models/locks/<id>.json`
  - 測試
  - `docs/art/<模型>/README.md` 與 `overview.jpg`
  - `docs/decisions/<N>.md`
  
  GLB 轉進遊戲的經驗寫在 `.claude/skills/rolling-stock/SKILL.md`（#2409 加的那一節）。
- **玻璃**：要等 #2417 合進 main，再照它的寫法做。`Map3DRedCommuter.decodedMesh(glass:)` 要傳 GLB 的 `glass` 材質在色票裡的格位，寫法照市區綫、屯馬綫、機場綫的 `glassIndex`。沒傳的話，港鐵的深灰（charcoal、mask、hardware、dark）晚上會被當成窗點亮。新車也要加進 `Tests/GamePresentationTests/Map3DTrainOwnGlassTests.swift` 的 `studioCars`。light-* 窗模型的雜湊以 #2417 合併後的 main 為準。
- 編組與車長照 revision-6 的 README。工作室審過的模型不用拍 CI 截圖（作者 2026-11-15）。

### 2. 南港島綫、迪士尼綫（工作室）

- 派工單和 ref/ 照片都已經在素材庫 main：`mtr-south-island-line-2026-11/README.md`、`mtr-disneyland-line-2026-11/README.md`。
- 開工參數照 mtr-east-rail-r1：`--preset art --use codexa=claude,codexb=codex`。任務名用 `mtr-south-island-r1`、`mtr-disneyland-r1`，同時最多跑兩個工作室任務。
- 指令一律用完整路徑開頭：`STUDIO_CONDUCTOR=1 python3 -I /Users/chienlinyeh/AlongTheLine-Studio/bin/runner.py start …`。不要用 `~`，前面也不要接 `cd … &&`，不然會被 auto mode 擋（RUN-RUNNER「規則只認一模一樣的開頭」）。
- Codex 判 pass 之後，由 Mac 上的 Claude 從 origin/main 開 `claude/integrate-<模型>` 分支，合進 pass 的那一版，跑 asset_guard，再 push。雲端這邊開 PR，用 **squash** 合（只留最終檔，不把舊輪的 GLB 歷史帶進 main）。

### 3. 石斗車（freight-hopper-r1）

- 照片已經合進 main（assets #155）。做的人做完第 1、2 輪（commit f0aabfbe、d0cd5c04），在等照片，沒有交件。主迴圈也已經結束了。
- 作者裝好新版工作室之後，先用新程式在背景重開 `runner.py loop --task freight-hopper-r1 --repo <它原本的 repo>`，再跑 `runner.py retry --task freight-hopper-r1 --role codexa --note "照片已合進 main：…ref/，用 git show origin/main:<路徑> 讀，照照片量，做完第 3 輪交給 Codex B 審"`。
- 審過之後接進遊戲：照 `docs/handoff/FREIGHT-LOOK.md` 的貨車做法。

### 4. Mac（作者那一次安裝）

- 新版工作室要用 RUN-RUNNER「安裝」那一行裝**一次**。Mac 上的 Claude 拷 bin 會被 auto mode 擋，所以 11-18 已經請作者自己貼。之後換程式都用 `runner.py sync-kit`，它在已經放行的 runner 規則裡；規則檔開 AI 前會自己跟上 main。
- 不放寬的兩件事（作者定的權限，要改請問作者）：
  - Mac 上的 Claude 經工作室 push 成品：studio-kit 的 pre-push 不放行。
  - 做的人的指令串接：`00-common.md` 禁止。

### 5. 其他

- 素材庫在 GitHub 上是 3.0 GiB（11-18 量），門檻是 3.5 GB，已經告訴規劃準備開下一個 repo。新照片一律照 RUN-RUNNER「開派工單前先附照片」縮小：每款最多 8 張、長邊 1280 像素、JPEG 品質 80。
- 本 session 學到的，已經寫進 skill 或 md 的：
  - 顏色和車頭輪廓要逐項對照片：素材庫 #154，以及 model-look checklist。
  - 指令要用完整路徑開頭：素材庫 #153。
  - 派工單要先附照片：素材庫 #158。
