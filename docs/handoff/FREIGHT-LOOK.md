# FREIGHT-LOOK

- 派工：協調者（新專案），2026-11-18，總表功能 6（3.25，FREIGHT_DEEPENING F1）。工作串「讓貨運列車看得見」（雲端）。分支 `claude/project-thread-cxud51`。決策 [837](../decisions/837.md)。
- 存檔、golden、SaveFixtures、ReplayFixtures、GameCore：不動。

## 做了什麼

貨運線的車照車上的貨換車廂（空車＝空平車、貨物＝貨櫃、建材＝半高開頂櫃載砂石），有貨運場的車站在月台另一側有 3D 貨櫃場或砂石場（works-kit 零件第一次上地圖）。細節在決策 837。

## 還留下什麼

1. ~~石斗車（工作室）~~ **做完（2026-11-18，工作串「把石斗車接進遊戲」，分支 `claude/project-thread-8g0wpu`）**：工作室第 5 版（素材庫 #165）由 `glb_to_swift.py` 轉成 `Map3DFreightHopperMesh.swift`，`Map3DFreightWagons.model(.stone / .stoneGreen / .stoneTail)` 改回傳石斗車（黑門、35B1000 鐵鏽紅門、尾車），解不開時才退回半高開頂櫃。沒有玻璃面，夜裡只亮尾燈。貨場的兩只開頂櫃照舊。已知缺點：砂石在遊戲大小像平灰塊（規劃接受，不再改模型；以後改 `stone` 堆腳的直邊）。總覽在 `docs/art/freight-hopper-2026-11/`。
2. 其餘評分在 `docs/priorities/FREIGHT-LOOK.md`：會動的街景卡車、水泥罐車（等 F3）、貨場的裝卸線。

## UNVERIFIED

- iOS 建置、Metal 畫面、實機：貨場在真實地圖（路多）上能放下的比例沒量；放不下的那站就沒有貨場。
- 截圖：新模型屬第三級；作者 11-17 常設「大型 3D 截圖自己判斷」，這張用 Linux 的模型預覽自己看過（PR 附總覽），沒跑 `website-screenshots.yml`。
