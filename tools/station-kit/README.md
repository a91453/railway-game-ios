# 台灣車站與組件生成

從 [station-kit 技能](../../.claude/skills/station-kit/SKILL.md) 開始。本批為 **544 站點、96 種零件、1 個組景範例**，共 641 個原生模型／GLB 與 4,487 張標準方向 PNG。

生成碼直接使用 GamePresentation 的 `Map3DMesh`、`Map3DModelPack`、形狀與調色盤，無新 App 依賴。六面與立體圖使用同一幾何；不是把多張概念圖片拼成模型。

```sh
# PATH 上使用專案規定的 Swift 6.4；Node / Python / Playwright / Chromium 已安裝
tools/station-kit/rebuild.sh ../railway-reference-private/Railway/game-art-previews/docs/art/station-kit-2026-10-21
```

`CHROMIUM_PATH` 可指定已安裝的 Chromium。大型輸出不准放在公開 checkout 內；這是 CLAUDE.md 的既有安排。私有庫從作者的素材目錄開工作分支，生成後只 stage 本批資料夾，開 draft PR。

各步驟：

- `catalog.py`：讀本專案 `track_stations.geojson`、`tra_station_class.json`，按系統／站名去重，決定明確代表站與一般站型；`--check` 檢查生成 Swift 是否過期。不下載或修改站點來源。
- `export.sh`／`export.swift`：Swift 6.4 warnings-as-errors 建置與連結；641 個原生檔全部經 `Map3DModelFile` 逐頂點讀回。
- `package.mjs`：原生 z-up 轉 GLB y-up；內含單一 buffer、霧面單面材質、頂點色與 glow；`package.test.mjs` 檢查座標、色彩、雜湊、範圍及拒收不完整檔案。
- `render.mjs`：4,487 張 384 px RGBA 圖；全批非空、留白、SHA 與接點檢查圖。`render-cache.json` 只在模型、renderer、既有圖片都逐一 SHA 相同時重用；刪除可強制全畫。
- `viewer.html`／`renderer.js`：離線本機互動檢視，不用外部服務。搜尋／分類／路網、七方向、旋轉、縮放、底色及原生／GLB／PNG 下載。
- `verify.mjs`：站點完整覆蓋、原生／GLB 字節轉換、色彩、法線、圖片 SHA／RGBA／尺寸與接點；記錄公開生成碼 SHA。
- `browser-check.mjs`：641 模型全部載入、篩選與互動、下載雜湊、390 px 及無外部請求／缺件／JS 錯誤。

最後執行 warnings-as-errors 建置及 `Map3DStationKitTests|Map3DModelFileTests`。匯出驗收與視覺檢查記錄在私有素材包 `verification.json`；公開入口與範圍見 [素材說明](../../docs/art/station-kit-2026-10-21/README.md)。
