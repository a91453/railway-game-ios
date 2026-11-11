# 看圖再改的拍圖工具

[model-look skill](../../.claude/skills/model-look/SKILL.md) 用的兩支腳本（決策 685）。

```sh
# 車站套件的模型 → .m3dmodel（其他 kit 用自己的匯出器，格式相同）
tools/model-look/export-station.sh <輸出資料夾> station-tra_sched-3acfda8b

# 一張寬 800 px 的 JPG：遊戲大小、遊戲鏡頭角度放大、和照片並排
node tools/model-look/shoot.mjs --model 新.m3dmodel --before 舊.m3dmodel \
  --photo '照片.jpg|說明|方向角|仰角' --focus cx,cy,cz,ex,ey,ez --title 標題 --out sheet.jpg
```

- 畫法是 `tools/station-kit/renderer.js`（正投影、遊戲那種打平的模型光）；不是 Metal，也不是 App 裡的畫面。要看放進地圖的樣子用 `tools/map3d-preview/`。
- 遊戲大小照 `Map3DCamera`：視角 35°、iPhone 直放 844 點高；800 m 起正上方，越近越斜（120 m 時 42°）。
- 需要 Node 與 Playwright（只在開發機用）。雲端 session 已經裝好；這台 Mac 沒有時裝在 scratchpad：`npm install playwright && npx playwright install chromium`，再設 `PLAYWRIGHT_MODULE=<那個 node_modules/playwright>`。`CHROMIUM_PATH` 可指定別的瀏覽器。
- 照片不放進這個 repo；有照片的並排圖放私有素材庫。
