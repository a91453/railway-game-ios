# TPE-MRT-ELEVATED：淡水信義線高架車站外觀（決策 826）

- 2026-11-17，雲端 project thread「做淡水信義線高架車站外觀」，分支 `claude/project-thread-vqunh2`（遊戲 repo 與素材庫同名）。
  NEXT_PRIORITIES §29.22 第 1 名（3.45），REAL-STATIONS-3D 的第一批。存檔版本、golden schema、GameCore 都不動。
- 作者額度不多，台灣 18:20 先停，**22:00 額度重置後接著做**。

## 做到哪裡

- 素材庫 `a91453/railway-assets-private` PR #133，`game-art-previews/docs/art/tpe-mrt-elevated-2026-11/`：
  - `README.md`：工作室派工單。四型 standard（圓山、士林、芝山、明德、石牌、唭哩岸、奇岩）、jiantan、beitou、xinbeitou；
    軌道淨空、預算、色票格位、自查表。§3、§6 已照 Commons 照片改寫：standard 與新北投是**宮殿式**（金黃兩坡長屋頂、兩層簷、
    山牆白搏風板與圓窗、月台層兩側開、簷下紅梁），不是底稿的紅磚盒。
  - `base/`：灰色底稿 GLB（大形起點，改寫自 Slop New York，Copyright (c) 2026 Mr.doob，MIT，https://github.com/mrdoob/slop-newyork ；
    作者 11-17 定：版權只寫 Slop New York）與十站的 OSM 外框（ODbL）。
  - `ref/`：15 張照片（CC BY／BY-SA／CC0，`ref/SOURCE.md`）。作者舊版 `~/SwiftRailMac/assets/分類/` 看過 48 個，沒有可沿用的。
  - `revision-1/`：工作室第 1 輪（8 個 GLB、7 向圖、遊戲大小、總覽）＋審查：**needs-fix**（站體長度以外的淨空）。
- 工作室（作者 Mac）：任務 `tpe-mrt-elevated`，做的人 Codex A（額度快用完，用完換 Codex B `--profile pro` 接手，作者 11-17 指示），
  審查 Claude Pro。第 2 輪開工中。

## 接下來

1. 工作室做完第 2、3 輪，審查給結論（最多三輪）；每輪推到素材庫 `claude/project-thread-vqunh2`。
2. 接回遊戲：GLB 轉 Swift mesh，照決策 625／665 的 `Map3DExteriorStudy` 放在真實站點與方位（玩家在那裡蓋了站時畫，
   離軌道與月台太近的零件照舊拿掉）；Slop New York 的 MIT 聲明加進遊戲的第三方授權清單；OSM 出處照 `DataSourceCredits`；
   寫 `docs/decisions/826.md`；遊戲 repo 只留一張總覽圖與 README（`docs/art/tpe-mrt-elevated-2026-11/`）。
   **軌道接上站體（作者 11-17 問）**：模型的名義軌面在 Z = 9.0 m，遊戲那一站真實高架的軌面高度不一定是 9.0（`level-profiles.json` 的 `flatOffsets`）。
   接回時要把站體整個上下移到那一站在遊戲裡的軌面高度、墩柱往下拉到地面，並加一個測試：每站淨空的底等於遊戲在站中心的軌面高度
   （±0.3 m），淨空裡沒有站體的面；站體兩端外面也不能有零件擋住進站的軌道（第 1 輪審查退回的就是這條）。
   **屋頂不拆成骨架（11-17 定）**：決策 625 的 `Map3DTrainRoom`（每股兩側 3.2 m、軌面上 6.5 m，零件蓋住 25% 以上就畫成肋條）
   會把這四型的屋頂（軌面上約 3.95 m）拆成骨架。這四型是為遊戲專做、量過淨空的，改用自己的規則：只切派工單 §4 的淨空盒，屋頂照畫；
   列車進站時被屋頂蓋住，和真的站一樣。軌道下的大廳與中間墩柱照舊讓遊戲的高架橋。五方：玩家 金頂是認站的關鍵；鐵道迷 真站也看不到月台上的車；
   開發 多一個「專做站體」的分支，有淨空測試保護；美術 不會出現一半肋條一半實心；音樂 無。工作室第 3 輪會出「現行切法／只切淨空盒」兩張對照圖。
3. 新外觀：總覽圖給規劃看過才合（決策 482）。

## UNVERIFIED

- 都還沒進遊戲，沒有在 App、Simulator 或實機看過。
