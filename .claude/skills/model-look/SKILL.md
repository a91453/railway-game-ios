---
name: model-look
description: 3D 模型「看圖再改」的規矩：做或改任何會進遊戲的原生 3D 模型（車站、建築、地標、kit 零件、列車、公車、船、纜車）時，動手前先讀。測試全過只代表沒做錯，不代表好看、認得出來；這裡管的是後者：先有真實照片，用遊戲鏡頭的角度與大小拍圖、和照片並排、對清單找毛病、改，自動檢查全過才送審，審查舊版列車 1 輪、其他 2 輪（第 2 輪換家），最後交一張總覽圖給作者或另一個 session 判。Use whenever you build, rebuild or restyle a native 3D model for the game (station-kit, civic-kit, commercial-kit and the other kits, landmarks, rolling stock, buses), or someone says a model「不像」「像盒子」「認不出來」「品質不好」, even if they only ask to "redo" or "fix" one model.
---

# 看圖再改：公開的程式規則

kit 的測試（面數、封底、接點、決定性）只查「有沒有做錯」，一個方盒子也能全過，所以模型一定要看圖。

**誰做、派工單、照片與特徵、每一輪的清單（`references/checklist.md`）、做的人不打分、貼圖還是色票與取色分色、舊版模型怎麼轉、交件的評估範例**是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/model-look/`（同節號）與 `docs/studio/`（README、studio-brief、lessons）。**做或改任何會進遊戲的 3D 模型之前先讀那裡**；這裡只留拍圖工具、停的條件與交付。

## 2. 用遊戲的眼睛看

遊戲鏡頭是從上往下斜看：近看傾 40° 左右，拉遠漸漸變成正上方；光線是故意打平的（天空光為主，太陽只加一點），所以**立體感不能指望陰影，要靠形狀的高低進出與相鄰面的顏色差**。iPhone 上一座 22 m 長的站房在中距離只有 70 點寬。

所以判斷的順序是：

1. **遊戲大小的圖最重要**：在那個大小還看得出它是什麼嗎？屋頂的形狀與顏色佔了大半畫面，先把屋頂做對。
2. 遊戲角度的放大圖：看比例與各部分的關係。
3. 放在地圖上的那一格：單獨看好看的模型，放在近白的地面與淡色的城市旁邊還分得開嗎？
4. 和照片同方向的圖、更近的放大圖：**只用來找毛病**，不用來說服自己「細節很多所以很好」。

拍圖用 `tools/model-look/shoot.mjs`（任何 kit 匯出的 `.m3dmodel` 都能拍；車站用 `tools/model-look/export-station.sh` 匯出）。它出一張寬 800 px 的 JPG：遊戲大小、遊戲角度放大、放在地圖上的樣子（遊戲的地面色、三棟城市建築的通用方塊、一條路，彩色與灰階）、與照片並排，有 `--before` 時每一格都是改前、改後。用法在腳本開頭。看圖前一律縮到寬 800 px 以內的 JPG（大圖只是多花力氣，看不出更多）。

## 3. 每一輪

拍圖 → 真的打開圖看 → 對著照片與清單（私有那份 §3）逐條寫出毛病 → 改 → 寫下這一輪改了什麼、還剩什麼。先修影響最大的（輪廓、屋頂、主色）。

## 4. 什麼時候停

做的人：清單每條都過、自動檢查全過才送審（自己看圖改幾輪不限，以清單為準）；最後由作者或另一個 session 看總覽圖判，做的人不自己打分。測試全綠不是停的理由。

**審幾輪**（作者 2026-11-26 同意，依 90 個模型、241 次審查的統計；全文與數字在私有素材庫 `docs/studio/skills/model-look/SKILL.md` §4）：

- 送審前先跑自動檢查到全過：列車 `tools/texture-palette/port_check.py`，建築、地標、自然景點 `tools/landmark-survey/landmark_check.py`（[landmark-survey](../landmark-survey/SKILL.md)）。
- **舊版列車轉新版：1 輪**。找舊版模型 → 調成真車比例 → 套車頭規則 → `port_check.py` 全過 → 換家審一次 → 過了就合；只退局部小修就修好、自動檢查再過即合；只有換底模或改結構（車鼻重做、窗數或車長改了、編組改了）才再審。全文在私有素材庫 `docs/studio/rolling-stock-studio.md`「舊版轉新版：審一次就合」。
- **舊版建築轉新版、全新列車、全新建築：2 輪**，第 2 輪一定換另一家審。第 2 輪只退小項就修好、自動檢查再過即合；第 2 輪還退大項（形狀、比例、結構、派工單寫錯）才開第 3 輪，第 3 輪是上限。

## 5. 交付

- 重檔（模型、viewer、各輪大圖、照片）放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`）的 `game-art-previews/docs/art/<資料夾>/`，照那邊的 `AGENTS.md`：先跑 `python3 tools/asset_guard.py --base origin/main`，新一輪同 PR 刪上一輪重檔。
- 遊戲 repo 的 PR 只留一張總覽圖與 README（`docs/art/<資料夾>/`）。總覽圖一定用有深度緩衝的畫法：`shoot.mjs`，或排好的網格（`PlacedKitLayout`、車站）用 `tools/layout-overview/`。整片三角形照深度排序（畫家演算法）的簡圖會把大面切出假的三角形，作者會當成破圖（2026-11-25，學校、醫院與香港站）。
- 配方改了，kit 原有的測試照跑；替這次修掉的毛病留一個會在舊幾何失敗的測試（例如「屋脊高於簷口」「山牆在月台側」）。

實例：追分車站（`docs/art/model-look-2026-11-11/README.md`），從紅磚紅瓦的通用站房改成木造灰瓦，四輪的紀錄與並排圖。
