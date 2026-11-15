# Meshy 與 Blender 串接（2026-11-15 第一次實做）

第 1 節「選做法」的表從這次三個試作來。這份寫怎麼做、哪裡會踩坑，讓下一次直接照做。

## 試過的三種

| 試作 | 做法 | 結果 | 點數 | 素材庫 |
| --- | --- | --- | --: | --- |
| 舊版圓冠樹 `item_af025c6c` | 舊版白模在貼圖上換三色 | 舊版的 47 棵樹全是交叉透明貼圖片（4–142 面），換色後俯視穿幫、轉檔變實心方塊；**不用** | 0 | `street-trees-2026-11/revision-1/old-af025c6c-*` |
| 榕樹 | 背景 Blender 腳本手寫：圓錐樹幹、主枝、12 條氣根、少邊數球體疊扁平冠，照部位上色票 | 586 面，和遊戲的 `leafyTree`、`kenney-pine` 並排風格一致、認得出是榕樹 | 0 | `street-trees-2026-11/revision-1/`（`tools/banyan.py` 改參數就能換樹種） |
| 站立的通勤乘客 | Meshy 生成 → 背景 Blender 減面、每面取色 | 300 面在遊戲距離認得出是背背包、站著的人；臉上有幾片誤判成頭髮色、上衣混進深色，取色規則要再修 | 30 | `commuter-figure-2026-11/revision-1/`（`tools/figure.py`） |

素材庫是 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/`。

## 環境（作者的 Mac）

- `claude mcp list` 有 `meshy`（`~/.local/bin/meshy-mcp`）與 `blender`（`uvx mcp-for-blender`），Antigravity 也接同一組（`~/.gemini/config/mcp_config.json`）。Mac 上另有 `~/Meshy/WORKFLOW.md` 的規則，照它。
- 雲端 session 沒有這兩個 MCP，用 Remote Control 在 Mac 上跑。
- **Blender 一律用背景模式**：`/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python <腳本> -- <參數>`。Blender MCP 的 9876 埠是工作室在用的，不開視窗、不接手、不關別人的 Blender。
- Blender 外掛內建的 Meshy 生成器保持關閉：開它要把 Meshy 金鑰交給外掛，也繞過報價與記帳。

## Meshy 生成

教訓的全文在素材庫 `meshy-batch-2026-10/LESSONS_AND_HANDOFF.md`。要點：

1. 先用 `meshy_check_balance` 查餘額（免費）。
2. **報價，等作者本人在對話裡說好**；另一個 AI 轉述的同意不算。
3. 標準模式：`model_type: standard`、`ai_model: meshy-7.1`、`should_remesh: false`。preview 20 點＋refine（2K、`enable_pbr: false`）10 點＝30 點。
4. prompt **不要**加「low poly game asset, flat colors」，形狀會更差；結尾寫 `Single object only, no base, no ground, no text, no logos.`。平塗留給 Blender。
5. 每一步只送出一次，記任務編號與 `consumed_credits`，做完再查餘額對帳。
6. 不滿意**不要用 MCP 重生**（一定扣點）：小毛病在 Blender 修（0 點）；要重抽就請作者在網站按「重新生成」（每月有免費次數，只有網站的按鈕能用），再把 GLB 或任務編號給 session。兩邊生出來的品質一樣，差別只在設定。
7. 原檔（通勤乘客 62 萬面、21.5 MB）留在 `~/Meshy/meshy_output/`，不進 repo；README 記任務編號與 sha256。修改版另存新檔。
8. 進遊戲時資料來源頁標示 AI 生成（Meshy 條款 §2.4、§3.2，`tools/meshy/README.md`）。

## Blender 整理（0 點）

1. 匯入、合併、縮放成真實尺寸，底部放在 z = 0。
2. **先體素重建，再減面。** Meshy 的網格是很多分開的小塊，直接 Decimate（collapse）最少只到約 1,100 面，再減就碎。先 Remesh（`VOXEL`，人物用 1.2 cm）成一個封閉曲面，再 collapse 到預算：人物 300、小物 600、車 1,500。
3. **每個面一色。** 在面的中心與往三個角的三點，各找 Meshy 原版表面上最近的點（`BVHTree.find_nearest`），讀它的 UV 與貼圖顏色，分類取多數，換成遊戲的色票色（人物照 `Map3DStreetLife.swift`）。分類規則依顏色亮度、飽和度與高度判；臉部和深色背包最容易判錯，看圖檢查這兩處。
4. 拍 45 度斜上方與正面，再和遊戲裡同類模型同比例並排一張總覽（JPEG 約 85）。
5. Mac 上有通用工具 `~/Meshy/tools/meshy_to_game.py`（背景 Blender）：寫一份配方 json（名稱、高度、目標面數、參考色對到遊戲色，可依高度分帶），一行指令就做完上面 1–4 步；範例 `~/Meshy/tools/recipes/commuter-figure.json`，用法在 `~/Meshy/WORKFLOW.md` 第 6 節。
6. 手寫白模（樹這類）時，面數在腳本裡就控制在預算內，部位一開始就分好，上色不用猜。

## 預設流程：Meshy 生成後直接交工作室（作者 2026-11-15 問、通勤乘客那串的結論）

通勤乘客走了「雲端 session 先在 Blender 減面取色、雲端再修色與做走姿、最後才交工作室審」，結果審查第 1 輪退回的三條（浮空碎片、零面積面、缺遊戲大小的近景圖）全是 Blender 那一步就該處理的，又來回一輪。所以之後：

1. **雲端 session**：報價、等作者說好、Meshy 生成（上面那節），原檔留 Mac；寫派工單（studio-brief §1），把下面「交件前自查」列進去。
2. **工作室做的位置（Antigravity＋背景 Blender）**：減面、取色、要的姿勢（人物至少站、走兩姿；走姿要屈膝，不要只把直腿轉個角度）、自查、出七向圖與遊戲大小圖。
3. **工作室審的位置（Codex，或 Claude Pro）**：對照片審，至少三輪；退回原樣交回做的位置。
4. **雲端 session**：審過的 GLB 接回遊戲（轉 Swift 網格或 `.m3dmodel`），比對接回的網格和審過的 GLB 逐面相同，CI 綠就合。

例外：只放素材庫看、不進遊戲的試作，照舊雲端自己跑 `meshy_to_game.py` 就好，不用工作室。

### 交件前自查（Meshy 模型多這幾條，補 studio-brief §2）

| 查什麼 | 要的結果 | 通勤乘客踩到的 |
| --- | --- | --- |
| 共點連通元件 | 1 個（只留最大的封閉主體） | 減面後留下 6 片沒連在主體上的碎片（背包頂上 3 片最大的 6 cm） |
| 單面邊、零面積面 | 0 | 18 條單面邊全在碎片上；轉成毫米後一片退化成零面積 |
| 臉與手 | 沒有頭髮色、上衣色的面 | 額頭一大片、耳朵一片頭髮色 |
| 上衣與背包 | 胸前沒有深色（背帶在這個面數下像破洞，歸上衣） | 胸口兩條、肩上四片深色 |
| 每人不同色的部位 | 單獨一個材質（遊戲裡 alpha 0 吃實例色） | 上衣 |
| 遊戲大小圖 | 鏡頭在換模型的距離以內（人物 120 m），1 格 1 點 | 第一次只給了 400–800 m 的圖，審查不能驗 |

Antigravity 看圖：一次最多 2 張、先縮小，JPEG 先轉 PNG（工作室修正 #124、#125）。

### 接回遊戲（人群這類一次畫很多個的）

- 近處用新模型、遠處留舊的簡單模型，並限一個畫面的數量（決策 787：離眼睛 120 m 內、最多人數上限的四分之一、至多 150 人），照決策 446 機車的寫法。
- 遊戲的網格由工具從 Meshy 減面檔重產時，轉正方向、修色、原點要在刪碎片**之前**算（碎片會讓朝向差零點幾度、座標差 1–2 mm，和審過的 GLB 對不上）。`tools/commuter-figure/to_swift.py` 是範例。

## 審查

Meshy 或腳本那一步只是「做」。照第 5 節「做的人不打分」，要進遊戲的模型交本地工作室審（Codex 或 Antigravity 對真實照片看圖，至少三輪，第 1 節的派工單流程），通過才轉 `.m3dmodel`。試作、只放素材庫看的不用審。榕樹這次是同一個 session 做又自己看，還沒經過工作室審；通勤乘客後來送審，第 1 輪退回、第 2 輪通過（素材庫 PR #123 `game-review/`）。

## 還沒驗證

- 榕樹還沒進遊戲。通勤乘客已接進遊戲（決策 787，288 面，站與走），但都沒在模擬器、實機看過。
- 通勤乘客的走姿是雲端用腳本擺直腿做的，側面像剪刀步（審查列可不修）；下一款人照上面的預設流程由工作室做姿勢。
