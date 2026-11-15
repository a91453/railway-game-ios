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

## 還沒驗證

- 這幾個模型都還沒轉 `.m3dmodel`、沒進遊戲，也沒在實機看過（榕樹的氣根在遊戲距離夠不夠粗、人物 300 面夠不夠）。
- 人物只有站姿；走路的兩個姿勢還沒做。
