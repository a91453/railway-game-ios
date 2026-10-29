# 共用列車製作、驗收與交付工具

新車使用本工具，專用的門窗／支承／輪軌驗收才另開目錄。既有配方與工具不重寫，模型／雜湊不因工具更新而改變。先讀 [rolling-stock](../../.claude/skills/rolling-stock/SKILL.md)、[原生手冊](../../docs/art/native-vehicle-modeling/README.md) 與兩庫 AGENTS.md。

需要 Swift 6.4、Node 22以上、既有 Playwright／Chromium、Python／Pillow；獨立 GLB 匯入仍用既有 Blender。輸出放公開 checkout 外。

## 匯出、預算與圖片

```sh
tools/train-models/run.sh OUT --tag after --ids model-a,model-b
node tools/train-models/check.mjs OUT
node tools/train-models/render.mjs OUT --time both
node tools/train-models/render.mjs OUT --time day --material clay
node tools/train-models/render.mjs OUT --time day --material silhouette
node tools/train-models/viewer.mjs OUT/comparison.html BEFORE OUT
python3 tools/train-models/overview.py OUT overview.png --time both model-a model-b
```

七向為 top／bottom／left／right／front／back／isometric。`png/<time>[-<material>]/<id>-<view>.png`。`render.mjs` 用決策370的遊戲模型光；`--features 1` 可看玻璃／不鏽鋼預覽。WebGL不等於Metal；沒有全場景太陽影、霧或完整材質遮蔽。`viewer.mjs` 是靜態圖比較頁；需要旋轉／縮放／下載改用下方 `inspect.mjs`。

`run.sh OUT --night-lights --ids set-emu800-head` 匯出既有營運車的夜燈，manifest的 `night_lights` 記是否啟用。`triangles`／`hash` 仍是pack原模型，`package.mjs` 另記含燈的 `exported_triangles`／`exported_bounds`，不把其混作配方雜湊。

`standard` 與 `studies` 都可用ID讀取。遊戲不畫的靜態模型放 `studies`；不要增加standard的常駐頂點。新增營運車時另驗set／映射及常駐預算，並跑啟用的 `Map3DMotionBudgetTests.testWhatTheMapKeepsInMemory`。

預算仍以 `budgets.json` 及當下loader為準：近景一節20,000三角、十二節240,000、遠景120,000，遠景單節少於近景一半且同框。精細新set以 `check.mjs OUT --new-set key` 驗遠景。**M3DM v1的單檔15,000是另一個上限**，本工具的GLB／通用assembly交付會拒收超限獨立單元；不能用場景預算放寬格式。高於單檔上限時先設計合法分件／格式契約，不擴大loader常數。

雜湊鎖包含standard與studies。`--lock`會重寫整份鎖，先輸出到暫存檔再只加入本車項；舊項變動須查明，不能整份覆蓋以消除紅字。刻意改的模型以 `--allow id` 說明，禁止把新車加入grandfathered。

## 通用編組：不再為每台新車加 Swift 分支

先將這台車的所有獨立單元匯出，再給JSON：

```json
{"assemblies":[{"id":"example-formation","placements":[
  {"unit":"model-a","translation":[12,0,0],"rotation_degrees":0},
  {"unit":"model-b","translation":[-12,0,0],"rotation_degrees":180}
]}]}
```

以上僅說明格式，12m不是三鶯線車長。位移為原生公尺，+X前／+Y左／+Z上，軌面Z0；只允許0／180度，不縮放。尾車若已有反向幾何，不可再旋轉一次。

```sh
tools/train-models/run.sh OUT --ids model-a,model-b --assembly-spec SPEC.json
# 或匯出後單獨執行：
node tools/train-models/assemble.mjs OUT SPEC.json
node tools/train-models/package.mjs OUT
node tools/train-models/audit.mjs OUT
node tools/train-models/inspect.mjs OUT OUT/index.html
node tools/train-models/browser-check.mjs OUT
```

輸出既有M3DAssembly v1，僅嵌入所引用合法單元；整列不是一個可載入的超限M3DM。`assembly_payload`的bin只供JS展開比對，**不是獨立Swift證據**；另有Swift直接編組時，需獨立比對。舊 `--assembly taipei610` 保留以重建歷史；新車只用 `--assembly-spec`，不新增車名特例。舊工具輸出不搬不刪。

`package.mjs`沿用station-kit GLB writer，原生與GLB軸向只轉一次（GLB +X前／+Y上／-Z左），保留頂點色與glow。GLB是霧面交換格式，材質標記及遮蔽不等同遊戲Metal。`audit.mjs`查有限數、bounds、退化面、有向邊平衡、連通殼正體積、GLB writer逐bytes重建，並對每模型做缺面／反面及編組100mm錯位反例。邊量化1e-5m，不是工程精度或全部自交證明。

**仍須專用驗收**：真玻璃埋入／浮空、雨刷排除、設備實體接觸、逐輪貼軌／淨空、近遠景可見性；依新車的實際來源設門檻，不抄C371尺寸。獨立GLB importer、PNG完整解碼與實際看圖也不可省略。

## 限量交付

完整本機驗收圖可以多於21張；提交到資產庫的整個模型輪次最多21張PNG，不是每單元21張。先填一份交付spec（路徑皆相對RUN）：

```json
{
  "repo":"/absolute/public-checkout",
  "producer":"40-character-public-producer-commit",
  "rebuild":"tools/train-models/run.sh /absolute/output --ids model-a,model-b --assembly-spec path/to/spec.json",
  "sources":"source-record.json",
  "status":"status.json",
  "license_files":[],
  "pngs":["png/day/model-a-front.png","png/night/model-a-isometric.png"]
}
```

來源JSON至少有 `origin`、`date`、`license`、`public_use`，另記逐張照片網址／作者／授權及哪些只供觀察。納入第三方素材時，`license_files`明選其授權文字。來源與授權是否合法仍須人工確認。修訂再加 `previous_producer` 記真正前版commit。

```sh
cp tools/train-models/status-template.json OUT/status.json
# 填完來源、四種狀態與交付spec後：
python3 tools/train-models/deliver.py OUT DELIVERY.json /assets/game-art-previews/docs/art/model/revision-1
```

`deliver.py`確認producer存在、目前tracked Sources/tools與其一致，拒收非RGBA、空白、不透明或裁邊PNG，最多21張且各≤2MiB；只複製模型、明選PNG與授權，不複製整包。自含index.html有七向、日夜、拖曳旋轉、縮放、native／GLB及當前畫面PNG下載。README、來源、status與SHA清單同輪產生。目的輪次已存在時拒絕覆蓋；重新交付到另一個新目錄，確認後依正常PR操作替換。

此工具**不代替**獨立producer重建bytes驗證、實際viewer下載驗收或整張PR的asset_guard，也不自動清除上一輪。用 `browser-check.mjs DELIVERED --report-dir SCRATCH` 實測最後viewer，把報告放交付輪次之外以免使SHA清單過期；再在素材庫同PR刪被取代輪次的重檔、保留PNG／README／來源。不能提交ZIP或history／old／backup副本。

資產庫規則：`a91453/railway-assets-private`，每檔≤50MiB、PR新增≤200MiB、最多3候選且僅選中候選留重檔。使用前再讀它的AGENTS.md；stage後用 `python3 tools/asset_guard.py --base origin/main --head "$(git write-tree)"`，commit後再跑預設HEAD檢查。不要為清理舊違規擴張本輪範圍。

## 完成狀態與新對話

`status-template.json`四欄預設UNVERIFIED；VERIFIED必須附證據：

| 欄位 | 證據 |
|---|---|
| asset | 最終producer的原生／GLB／圖／viewer及技術驗證 |
| appearance | 使用者明確接受的版本，accepted_producer必須等於交付producer；作者的外觀自檢另記 |
| integration | set／營運映射與實際遊戲行為；只有studies註冊仍未接入 |
| device | 實際Simulator／裝置、時間及測項；不得拿Linux WebGL替代 |

使用者要合併不等於四欄全部通過。公開只放一張約≤2MB總覽及配方／工具／文件；兩庫開互鏈draft PR、更新#1041及HANDOFF，不merge／auto-merge／TestFlight。

[新車通用prompt](../../docs/art/VEHICLE_ASSET_HANDOFF_PROMPT.md)；[三鶯線prompt](../../docs/art/native-vehicle-modeling/SANYING_PROMPT.md)。單元測試：`node --test tools/train-models/test.mjs`、`python3 -m unittest discover -s tools/train-models -p 'test_*.py'`；實際匯出／browser／Blender驗證另跑，不把fixture測試當實車驗收。

台中捷運綠線的玻璃／八輪／屋頂接觸與反例、獨立GLB匯入、Swift編組對照：[`tools/taichung-green`](../taichung-green/README.md)。只提供本型資料與驗收，匯出／交付沿用本共用工具。

高雄紅／橘線現役西門子 studies 專用編組與幾何反例：[tools/kaohsiung](../kaohsiung/README.md)。
