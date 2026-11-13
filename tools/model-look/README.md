# 看圖再改的拍圖工具

[model-look skill](../../.claude/skills/model-look/SKILL.md) 用的兩支腳本（決策 685）。

```sh
# 車站套件的模型 → .m3dmodel（其他 kit 用自己的匯出器，格式相同）
tools/model-look/export-station.sh <輸出資料夾> station-tra_sched-3acfda8b

# 一張寬 800 px 的 JPG：遊戲大小、遊戲鏡頭角度放大、放在地圖上的樣子、和照片並排
node tools/model-look/shoot.mjs --model 新.m3dmodel --before 舊.m3dmodel \
  --photo '照片.jpg|說明|方向角|仰角' --focus cx,cy,cz,ex,ey,ez --title 標題 --out sheet.jpg
```

- `export-station.sh` 的站名前加 `house:` 匯出地圖實際畫的那一個（`house(_:)`：站房與站前，沒有套件的月台與軌道；套件的藍色月台雨棚會擋住月台側），檔名是 `<站>-house.m3dmodel`；`concourse:`、`hall:` 是擴建後的樣子（決策 705）。
- 鐵道博物館（決策 696）用 `tools/model-look/export-museum.sh <輸出資料夾> hall 0 5 12`：`hall` 是館舍單獨，數字是展品件數（含展品的車頭）。含展品是好幾個模型，超過單一模型的 15,000 個三角形，拍的時候加 `--max-triangles 200000`。
- 畫法是 `tools/station-kit/renderer.js`（正投影、遊戲那種打平的模型光）；不是 Metal，也不是 App 裡的畫面。要看放進地圖的樣子用 `tools/map3d-preview/`。
- 「放在地圖上的樣子」那一格：模型站在遊戲的地面色上，前面一條路，旁邊三棟城市建築的通用方塊（顏色在腳本的 `MAP`，照 `tools/map3d-preview/` 白天量到的明度），右邊是同一張的灰階。看的是清單第 9 條：和背景分得開嗎。
- `--only map` 只出「放在地圖上的樣子」那一格（盤點很多模型時用），`--ground RRGGBB` 換一個地面色試（例如還沒定案的調色）。
- **套件站房在地圖上會被 `Map3DLook` 淡化，`export-station.sh` 匯出的是配方原色**，所以它的第三格比遊戲裡深。要看地圖實際畫的顏色：`ROOF_CONTRAST_REPORT=<資料夾> swift test --skip-build --filter Map3DRoofContrastTests/testReport` 會把每個車站站房、實站研究、地標、廟寫成 `<資料夾>/models/*.m3dmodel`（顏色已是地圖畫的），並在 `roof-contrast.tsv` 給每個模型的取景框（`focus` 欄）與屋頂對四周的明度差。哪一類被淡化、量法與 2026-11-13 的盤點在 `docs/art/roof-ground-contrast-2026-11-13/README.md`。
- 遊戲大小照 `Map3DCamera`：視角 35°、iPhone 直放 844 點高；800 m 起正上方，越近越斜（120 m 時 42°）。
- 需要 Node 與 Playwright（只在開發機用）。雲端 session 已經裝好；這台 Mac 沒有時裝在 scratchpad：`npm install playwright && npx playwright install chromium`，再設 `PLAYWRIGHT_MODULE=<那個 node_modules/playwright>`。`CHROMIUM_PATH` 可指定別的瀏覽器。
- 照片不放進這個 repo；有照片的並排圖放私有素材庫。
