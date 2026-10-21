# 原生 3D 場景細節

在專案根目錄執行 `tools/detail-kit/rebuild.sh PRIVATE_OUTPUT_DIRECTORY`。先將 Swift 6.4 的 bin 放入 PATH。輸出必須在公開 checkout 外，交付位置是私有庫 `Railway/game-art-previews/docs/art/detail-kit-2026-10-21/`。

流程：原生 Swift 配方 → M3DM v1（原生 loader 逐頂點讀回）→ GLB → 七方向 RGBA → 全量檔案驗證 → 瀏覽器驗證 → warnings-as-errors build 與相關測試。現有 Node／Python／Playwright／Chromium 足夠，沒有新增依賴。

- `export.swift`：96 種零件、16 姿態、6 組景，以及 32 個獨立 body。
- `package.mjs`：重用 station-kit 的 GLB 編碼，保持頂點色與原生 glow 旗標。
- `joints.js`：依 native 座標操作活動 body；固定 body 位元組保持不動。驗證器對照全部 16 個 Swift 姿態。
- `render.mjs`：826 張 384 px 透明圖與檢視頁／分類表／組景／下斜視／畫風檢查；與 station-kit 共用 renderer，不複製維護另一套著色器。
- `verify.mjs`：逐檔 SHA、完整 GLB 重建、全部 PNG、分類數、關節一致性。
- `browser-check.mjs`：每個模型可讀、篩選、七向、旋轉、縮放、16 動作滑桿、下載與手機寬度。

`index.html` 需經 localhost 伺服器開啟，例如 `python3 -m http.server 8080 --directory PRIVATE_OUTPUT_DIRECTORY`，再開 `http://localhost:8080/index.html`。檢視頁僅用本機資產，沒有 CDN。PNG 可用於組景；GLB 是靜態模型，動作資料在 manifest，活動／固定 body 另存以便宿主動畫。PNG 滑桿預覽不會暗中改寫下載的原始 GLB。

這是獨立素材配方與組景工具。真機 Metal、runtime 物件放置、碰撞與動畫接入另行驗證。相關使用規則在 `.claude/skills/detail-kit/SKILL.md`。
