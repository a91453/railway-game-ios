# Meshy 的 3D 模型

`meshy.mjs` 用作者的 [Meshy](https://www.meshy.ai/) 帳號，以 Text to 3D API 文字生成 3D 模型，縮小之後放進 3D 城市試作（`Web/CityView/`，ARCHITECTURE 決策 161）。要做哪些模型寫在 `models.json`，做好的紀錄在 `generated.json`。

目前的模型是臺鐵的兩種列車，在臺中車站的高架上跑（`Web/CityView/src/world/trains.js`）：

| id | 用途 |
| --- | --- |
| `emu900-cab`、`emu900-car` | EMU900 區間車的頭尾車與中間車（10 節） |
| `emu3000-cab`、`emu3000-car` | EMU3000 自強號的頭尾車與中間車（12 節） |

## API 金鑰

金鑰只從環境變數 `MESHY_API_KEY` 讀，不寫進任何檔案，也不能進 repo（這個 repo 是公開的）。

- Claude Code 雲端 session：在環境設定（session 標題列的雲端環境選單 → Edit）加上 `MESHY_API_KEY`，新的 session 才會讀到。
- 本機：`export MESHY_API_KEY=...` 再執行。

金鑰在 Meshy 網站的 API 設定頁建立。不要把金鑰貼到對話、issue 或 PR 裡。

## 指令

從 repository 根目錄執行，需要 Node 22 與 `Web/CityView` 的套件（`cd Web/CityView && npm ci`，`pack` 用其中的 sharp）：

```sh
node tools/meshy/meshy.mjs balance                       # 剩下的點數
node tools/meshy/meshy.mjs generate emu900-cab emu900-car emu3000-cab emu3000-car
node tools/meshy/meshy.mjs pack emu900-cab emu900-car emu3000-cab emu3000-car
tools/procedural-city/build_city_view.sh                 # 重新建置 App 打包的頁面
```

- `generate`：先做 preview（網格，Meshy 7.1，重新拓樸到 `target_polycount` 個三角形），再 refine（貼圖 2K，不要 PBR），把 GLB 與縮圖下載到 `Web/CityView/data/raw/meshy/<id>/`（不提交），prompt、任務編號、用掉的點數記在 `generated.json`。已經有紀錄的 id 會從那個任務重新下載，不再花點數；要重做加 `--again`。
- `pack`：GLB 的圖縮到 1024 px（`--size=` 可改），不透明的轉 JPEG，寫到 `models.json` 的 `out`（`Web/CityView/public/models/trains/`），並更新同一個資料夾的 `index.json`。GLB 的 `asset`、`extras` 原樣保留：Meshy 條款 §2.4 要求不移除輸出裡的 AI 識別資訊。
- 每個模型 30 點（preview 20、refine 10，2026-10 的 Meshy 7.1 價格）；四個共 120 點。

## 做好之後

1. 看 `data/raw/meshy/<id>/thumbnail.png`：是不是單獨一節車、比例對不對。不對就改 `models.json` 的 prompt，`generate --again`。
2. 看駕駛室朝哪一個軸，把 `front` 填成 `+x`、`-x`、`+z` 或 `-z`（沒填時當作 `+x`），再 `pack`。城市頁面把模型轉成駕駛室朝前、縮放成車長 × 2.9 m 寬 × 3.9 m 高，頭尾車用 `-cab`（尾車轉 180°），中間用 `-car`；兩個只有一個時每節都用它。
3. `tools/procedural-city/build_city_view.sh`，提交 `Web/CityView/public/models/trains/` 與 `RailwayGameApp/Resources/CityView/`。
4. 沒有模型（`index.json` 是 `{}` 或讀不到檔）時列車照舊畫方塊，塗裝是臺鐵的顏色。

## 授權

Meshy 的使用條款（§3.2）：付費方案的使用者擁有自己生成的輸出（Customer Output）；免費方案的輸出歸 Meshy 所有，以 CC BY 4.0 提供，須標示 Meshy。作者是付費方案，所以這些模型是本專案的素材；第一批模型加進 App 時，在資料來源畫面的「3D 城市試作」註明由 Meshy 生成。條款也禁止用輸出訓練與 Meshy 競爭的 AI 模型（§2.6），並要求保留 AI 識別資訊（§2.4）。Meshy 不保證輸出獨一無二（§7.2）。

模型的外觀是 prompt 描述的臺鐵車型的近似，不是原廠圖面。
