# FREIGHT-LOOK

- 派工：協調者（新專案），2026-11-18，總表功能 6（3.25，FREIGHT_DEEPENING F1）。工作串「讓貨運列車看得見」（雲端）。分支 `claude/project-thread-cxud51`。決策 [837](../decisions/837.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。

## 做了什麼

貨運線的車照車上的貨換車廂（空車＝空平車、貨物＝貨櫃、建材＝半高開頂櫃載砂石），有貨運場的車站在月台另一側有 3D 貨櫃場或砂石場（works-kit 零件第一次上地圖）。細節在決策 837。

## 還留下什麼

1. **石斗車（工作室）**：派工單在 railway-assets-private `game-art-previews/docs/art/freight-hopper-2026-11/BRIEF.md`（同名分支）。工作室交件、照片對照三輪審過後，只換 `Map3DFreightWagons.model(.stone / .stoneGreen / .stoneTail)` 的配方（或照決策 782 的 `meshPalette` 接 GLB 轉的網格），重算 `tools/train-models/locks/freightWagons.json`（`tools/train-models/run.sh OUT --lock tools/train-models/hashes.lock.json`，只留 `freightWagons.json` 的變動）。貨場裡的兩只開頂櫃（`Map3DFreightYard.stoneYard`）照舊，或換成停在貨場線上的一節石斗車。工作室要作者在自己終端機開總機（`runner.py serve`）才能開工。
2. 其餘評分在 `docs/priorities/FREIGHT-LOOK.md`：會動的街景卡車、水泥罐車（等 F3）、貨場的裝卸線。

## UNVERIFIED

- iOS 建置、Metal 畫面、實機：貨場在真實地圖（路多）上能放下的比例沒量；放不下的那站就沒有貨場。
- 截圖：新模型屬第三級；作者 11-17 常設「大型 3D 截圖自己判斷」，這張用 Linux 的模型預覽自己看過（PR 附總覽），沒跑 `website-screenshots.yml`。
