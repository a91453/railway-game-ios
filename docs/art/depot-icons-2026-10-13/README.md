# 機廠美術候選（2026-10-13）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `preview.png` 和文字紀錄；其他 5 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/depot-icons-2026-10-13/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

**已定案**：作者選定的三個圖示由 #555 合併（決策 214）。下面保留定案前的說明。

（定案前：）尚未定案。作者要求先開 draft PR，供另一個 AI 審查。本目錄是設計候選；沒有加入 App 的 Asset Catalog，也沒有改功能程式。推薦 D-A／S-A／I-B，仍須作者選定。

先看 [方案總覽](preview.png)，或分別看 機廠（`a91453/railway-reference-private: Railway/game-art-previews/docs/art/depot-icons-2026-10-13/choice-1.png`）、出入庫（`a91453/railway-reference-private: Railway/game-art-previews/docs/art/depot-icons-2026-10-13/choice-2.png`）、在庫（`a91453/railway-reference-private: Railway/game-art-previews/docs/art/depot-icons-2026-10-13/choice-3.png`）。標記與整組圖示對照（`a91453/railway-reference-private: Railway/game-art-previews/docs/art/depot-icons-2026-10-13/contexts.png`） 包含灰階、各種路線色、既有 16 張地圖圖示，以及同一列車同時入庫和等待的情況。HTML 和 PNG 是同一份設計示意，不是 App 截圖。

## 方案

| 項目 | 方案 | 感覺與取捨 |
| --- | --- | --- |
| 機廠 | **D-A 雙門車庫（推薦）** | 看得出兩個庫門；拉遠少掉庫門前短軌，縮小仍可讀。 |
| 機廠 | D-B 拱棚與列車 | 鐵道味較強；拉遠省略車窗，細節比 A 多，也較像隧道入口。 |
| 機廠 | D-C 停車線俯視 | 三股平行線，沒有具體建物樣式；需要機廠名稱幫忙。 |
| 出入庫 | **S-A 穿過庫門（推薦）** | 出庫的箭頭離開庫門、入庫的箭頭進到庫門；小尺寸差異最大。箭頭是相對庫門，不隨車頭旋轉。 |
| 出入庫 | S-B 升起／落下 | 一眼有離開／回來的意思；容易想到上傳／下載，小尺寸差異較小。 |
| 在庫 | I-A 庫棚 | 沿用機廠雙門，視覺一致，但容易被理解成實體場所。 |
| 在庫 | **I-B 列車與底座（推薦）** | 列車穩穩停著，也適用未放上軌道的車；保留「在庫」文字。 |

每個 SVG 都是 24 × 24 單色模板，只用實心形狀、even-odd 挖空，不含描邊、漸層、濾鏡、CSS、transform。共 12 張：三種機廠各近／遠一張、兩組出入庫各兩張、兩種在庫徽章。

## 建議的外觀與圖層（作者選好後才寫入正式文件）

| 項目 | 建議規則 | 沿用圖層 |
| --- | --- | --- |
| 機廠 | 暖黃圓角方徽章，外框用 `Palette.ink`、內圖用 `stationSymbol`；一般站的圓與高鐵第二圈仍代表客運站。近／遠示意為徽章 28／18 點、圖示 17／11 點；這是候選設計尺寸，並非已實作的縮放門檻。 | 30：車站 |
| 出庫中／入庫中 | `markerFill` 底、`ink` 外框與圖形的切角方牌，圖形靠庫門與箭頭的位置區分。尺寸示意為方牌 24／18／16 點；狀態圖形不跟車頭旋轉。FollowBar 仍寫狀態文字。 | 50：列車車身之後；51 的等待環、死結警告、小牌仍在上方 |
| 在庫 | 面板小徽章，圖示 16 點、字用 `Theme.textPrimary`、底用 `Theme.panel`。未放上軌道的車也可用，不暗示實體機廠位置。 | 面板，沒有地圖新層 |
| 停車線 | 完全照一般軌道的道床、中心線、外框畫，不增加圖示或專用道床。 | 23：軌道；不新增圖層 |

等待／死結提示優先：出入庫牌先避開既有等待環和小牌，擠不下時保留等待／死結。這份只訂外觀方向；狀態讀取、避讓、上限和建造工具由實作 session 接。

#548 的資料語意：機廠是 `Station.isDepot` 旗標，不是新的車站營運模式；路線指定所屬機廠；入庫與出庫是空車回送，在庫還包含原有的隱形車庫。圖示不新增 GameCore 狀態，亦不代表 L2 檢修、L3 轉盤／調車功能。

## 檢查

- **VERIFIED（Linux，Chromium 設計預覽）**：照 art-style 的 `preview.cjs` 檢查淺／深面板與地圖、48／24／16／10 點、模糊、灰階；已逐張目視。預裝 Playwright 缺 headless shell，scratchpad 副本只改為系統 Chromium 啟動與 1400 點檢查視窗；專案腳本沒有改，也沒有下載瀏覽器。
- **VERIFIED（Linux）**：12 張 SVG 的 XML、viewBox、尺寸、單色與元素／屬性範圍通過。所有候選並排看過，沒有引用品牌、角色、商業遊戲素材；D-B 較像隧道，S-B 較像傳檔箭頭，已在取捨中說明。
- **VERIFIED（Linux，3 倍螢幕）**：出入庫圖形在 10／13／16 點、模糊 0.6 點後的差異，S-A 為 73.4／77.2／80.1%，S-B 為 22.1／25.0／27.0%，都超過 art-style 約 20% 的門檻。定義是 `sum(abs(A-B)) / sum(max(A,B))`，只比圖形，不把共用底牌算進來；不是使用者辨識率。數值與方法在 [validation.json](validation.json)。
- **VERIFIED（Linux，WCAG 2 公式）**：模板對暖黃底 8.69:1；出入庫圖形／字對 `markerFill` 淺／深為 13.29／9.64:1。只用既有色票。
- **UNVERIFIED**：Asset Catalog 編譯、Canvas／FollowBar 真實排版、iOS 與實機；尚未接 App，不宣稱已驗證，也不跑發佈流程。

## 參考對照（PR 可沿用）

只讀參考庫的清單與模型 metadata；沒有載入、搬入或描繪任何網格、材質、貼圖、照片。

| 參考檔案／規則 | 這次的目標 | 使用方式 |
| --- | --- | --- |
| `.claude/skills/art-style/SKILL.md`、`UI_THEME.md`，既有 `MapGlyphTrain`／`MapGlyphHouse` 等 16 張模板 | `candidates/*.svg`、預覽 | 沿用這個專案的 24 格、圓角、粗實心筆畫、色票與留白；2D 自行畫。 |
| `ARCHITECTURE.md` 決策 168、205、210；#540 PR 說明 | `contexts.png`、圖層建議 | 第二圈留給高鐵客運站；新狀態不使用環形或文字小長牌，靠形狀而非路線色。 |
| #548 PR 說明（決策 209、存檔 54；尚未合併） | 外觀語意 | 車站旗標、路線所屬機廠、出入庫、在庫；不接功能。 |
| `Railway/site_archive_clean/rail-3d/assets/historic-buildings-v2/catalog.json`（blob `0dec4efa64b544826b6f6441936958ca20121d08`） | 3D 後續參考清單 | 有彰化扇形車庫、羅東林場檢車庫；這次未取用模型。 |
| 同目錄 `changhua-roundhouse/model.json`（blob `e646bebb7d25c9ef142b9d8d4c26ec0c8a01fb11`） | 無 2D 移植 | 只確認扇形庫房、轉盤、放射庫線等 metadata，留給之後的 3D。 |
| 同目錄 `luodong-forest/model.json`（blob `ec92d42c9349d9080989ed3b4b3d0f388cf819b6`） | 無 2D 移植 | 只確認木造檢車庫等 metadata，留給之後的 3D。 |
| 外部專案 | 無 | 這次未搜尋或取用外部圖像；候選為本專案自行畫製。 |

這次沒有可移植的 2D 圖示；缺口自行畫製。SVG 與預覽檔的 SHA-256 放在 [manifest.json](manifest.json)，之後把作者選定的檔案放進 imageset 時逐檔比對。

## 給審查 session

先讀根目錄的 `CLAUDE.md`、`.claude/skills/art-style/SKILL.md`，再看三張方案圖和 `contexts.png`。這次請回報問題與推薦；作者選定前，不把任何候選加入正式 imageset，也不接功能。

1. D-A／D-B／D-C 和現有車站、房屋、其他建物相比，是否看得出是機廠？留白與墨量是否一致？尤其 D-B 是否太像隧道或鎖頭、D-C 是否太像柱廊。
2. S-A 的庫門與箭頭在 10–16 點、灰階、模糊後是否容易理解？切角方牌會不會和 #540 的等待小牌、量表環或決策 168 的高鐵第二圈混淆？不要只用像素差異當作玩家辨識的證明。
3. I-B 是否適合實體機廠內與未放上軌道的在庫列車？配著「在庫」文字時是否仍太像一般車站圖示？
4. 第 23／30／50 層沿用是否合理？出入庫牌避開等待／死結提示的規則是否有缺口？目前大小是設計示意，未定義新的程式縮放門檻。

請用繁體中文回覆：先列需要修的問題，再各選一個 D／S／I；每項附一句原因。若要修改，請指出具體哪一塊、大小或位置，避免整個造型重畫。作者的選擇才是定案。

## 後續

1. 審查 session 回報建議，作者選 D／S／I。
2. 定案後才加入正式 imageset，補 `MAP_LAYERS.md` 與 `UI_THEME.md`，用 `manifest.json` 比對選定的 SVG。
3. 功能接線留給 #548 合併後的實作 session。這個 PR 保持 draft，等待美術選定；即使文件 CI 綠，也不代表 App 外觀或正式資產已驗證。
