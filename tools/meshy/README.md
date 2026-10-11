# Meshy 的 3D 模型

用作者的 [Meshy](https://www.meshy.ai/) 帳號生成 3D 模型，縮小之後放進 3D 城市試作（`Web/CityView/`，ARCHITECTURE 決策 161）。生成照 Meshy 官方的 skill（`.claude/skills/meshy-3d-generation/`，[meshy-dev/meshy-3d-agent](https://github.com/meshy-dev/meshy-3d-agent) `644fd70`，MIT）用官方的 CLI（`meshy-cli` 0.4.0，MIT）；`meshy.mjs` 只負責之後的 `pack`。要做哪些模型寫在 `models.json`，做好的出處記在 `generated.json`。

目前的模型是臺鐵的兩種列車，在臺中車站的高架上跑（`Web/CityView/src/world/trains.js`）：

| id | 用途 |
| --- | --- |
| `emu900-cab`、`emu900-car` | EMU900 區間車的頭尾車與中間車（10 節） |
| `emu3000-cab`、`emu3000-car` | EMU3000 自強號的頭尾車與中間車（12 節） |

## 登入

不用 API 金鑰。在 session 裡執行 CLI 的瀏覽器登入（`meshy auth login --device`），畫面上會出現一個網址與一組代碼；作者打開網址、登入 Meshy、輸入代碼、按同意，CLI 自己拿到憑證。憑證存在容器的 `~/.config/meshy/`，不進 repo、commit 或對話；容器回收後要重新登入。

已經有 API 金鑰的話，也可以放在環境變數 `MESHY_API_KEY`（雲端 session 的環境設定），CLI 會優先用它。不要把金鑰或代碼貼到對話、issue 或 PR 裡。

## 做一個模型

從 repository 根目錄，需要 Node 22.12 以上與 `Web/CityView` 的套件（`cd Web/CityView && npm ci`，`pack` 用其中的 sharp）。CLI 不用安裝，以 `npm exec --yes --package=meshy-cli@0.4.0 -- meshy …` 執行。

1. 在 `models.json` 加一筆：id、prompt、面數、`out`。
2. 照 skill 的流程生成（文字或照片轉 3D、要遊戲用的低面數就用 smart topology）。`WORKSPACE` 是 `Web/CityView/data/raw/meshy/<id>/`（不提交），交付的檔案是那裡的 `<id>.glb`。花點數之前先報價、等作者同意。
3. `node tools/meshy/meshy.mjs pack <id>`：GLB 的圖縮到 1024 px（`--size=` 可改），不透明的轉 JPEG，寫到 `models.json` 的 `out`，更新同一個資料夾的 `index.json`；workspace 裡 CLI 的任務紀錄（任務編號、prompt、模型、點數）記進 `generated.json`。GLB 的 `asset`、`extras` 原樣保留：Meshy 條款 §2.4 要求不移除輸出裡的 AI 識別資訊。
4. `tools/procedural-city/build_city_view.sh` 重新建置 App 打包的頁面。

價格（2026-10，Meshy 7.1）：文字轉 3D 的網格 20 點、上貼圖 10 點；照片轉 3D 含 2K 貼圖 30 點；smart topology（meshy-t2）的網格 5 點。實際用掉的看任務的 `consumed_credits`。

## 做好之後

1. 看預覽：是不是單獨一節車、比例對不對。不對就改 `models.json` 的 prompt 再生成（又要花點數，先問作者）。
2. 看駕駛室朝哪一個軸，把 `models.json` 的 `front` 填成 `+x`、`-x`、`+z` 或 `-z`（沒填時當作 `+x`），再 `pack`。城市頁面把模型轉成駕駛室朝前、縮放成車長 × 2.9 m 寬 × 3.9 m 高，頭尾車用 `-cab`（尾車轉 180°），中間用 `-car`；兩個只有一個時每節都用它。
3. `tools/procedural-city/build_city_view.sh`，提交 `Web/CityView/public/models/trains/` 與 `RailwayGameApp/Resources/CityView/`。
4. 沒有模型（`index.json` 是 `{}` 或讀不到檔）時列車照舊畫方塊，塗裝是臺鐵的顏色。

## 授權

Meshy 的使用條款（§3.2）：付費方案的使用者擁有自己生成的輸出（Customer Output）；免費方案的輸出歸 Meshy 所有，以 CC BY 4.0 提供，須標示 Meshy。作者是付費方案，所以這些模型是本專案的素材；第一批模型加進 App 時，在資料來源畫面的「3D 城市試作」註明由 Meshy 生成。條款也禁止用輸出訓練與 Meshy 競爭的 AI 模型（§2.6），並要求保留 AI 識別資訊（§2.4）。Meshy 不保證輸出獨一無二（§7.2）。

模型的外觀是 prompt 描述的臺鐵車型的近似，不是原廠圖面。
