# slop-newyork 補充：10-23 之後它改了什麼、10-23 沒看的交通與號誌

2026-10-26。作者問「https://github.com/mrdoob/slop-newyork 有我能參考的地方嗎」，接著說「直接在這裡做報告開 pr」。研究者 session_01UvQcP14umjdnDYpqc14Ngx。
- 這份接在 [SLOP_NEWYORK_3D_2026-10-23.md](SLOP_NEWYORK_3D_2026-10-23.md)（以下稱「10-23」）後面，不取代它。10-23 的量測、排序與五方照舊有效。
- 基準：本 repo main `aebfb4a`；slop-newyork commit `be65d0a`（2026-10-26，仍然只有一個 commit）。10-23 讀的是 `7fdaf15`。
- 只是研究，沒有改任何程式。存檔、決策號、golden 都不動。

## 1. 結論

- **10-23 的三件都還沒做，前置條件都已合併，現在可以派。**
  - 第 1 名「城市方塊改實例」：main 上沒有方塊實例，`.far` 照舊是合併好的網格。
  - 第 2 名「太陽陰影用 `.far` 當替身」：`Map3DMetalView` 的太陽深度 pass 在完整 chunk 照舊畫 `chunk.indexCount`，也就是整份完整城市。
  - 第 3 名「小零件放進池、依像素大小剔除」：沒有做。
  - 10-23 要等的 10e（決策 391）與畫風 (e)（決策 370）都在 main 上。
- **10-23 沒看 `traffic.js` 和 `city-config.js`**（它的來源清單裡沒有這兩個檔），但這兩個檔 7fdaf15 就有了。這份補上：
  - **紅綠燈照時鐘變燈**：本作的號誌是固定的（§3.1）。它的做法只看時鐘，合決策 259 的「街景不留狀態」。**建議加成第 4 件**，小、獨立、看得到。
  - **IDM 跟車**、**行人在路口排隊過馬路**：都要每台車、每個人留狀態，和決策 259 衝突。不派，只記下數值。
- slop-newyork 在 10-23 之後多了 `pedestrian-system.js`、`pedestrian-routes.js`（行人群）、`vehicle-physics.js`（碰撞）、`fire-escapes.js`（逃生梯）。前三個是玩家能走能撞的遊戲才要的；逃生梯是紐約的樓。都不搬。
- `scene-culling.js` 只小改（§2），10-23 §4.4、§4.5 的數字不變。

## 2. slop-newyork 從 7fdaf15 到 be65d0a 改了什麼

`git diff --stat 7fdaf15 be65d0a -- js tests`：39 個檔，加 3,280 行、刪 1,493 行。

| 檔 | 變化 | 對本作 |
| --- | --- | --- |
| `js/pedestrian-system.js`、`pedestrian-routes.js`（新） | 附近的行人群：人行道接成路徑，路口有排隊，會聊天，會閃玩家；過不過馬路由 `traffic.js` 給許可 | 不搬：每個人都要留狀態（§3.3） |
| `js/vehicle-physics.js`（新）、`tests/vehicle-physics.test.cjs` | 平面上的剛體碰撞 | 不搬：本作的車不會撞 |
| `js/fire-escapes.js`（新） | 紐約樓房外牆的逃生梯 | 不搬：台灣的樓沒有這種 |
| `js/traffic.js`（−704／+…，淨少） | 重整；行人的部分搬到 `pedestrian-system.js`；IDM 的參數沒變 | 見 §3.2 |
| `js/scene-culling.js`（44 行） | 剔除距離超過 2,000 m 的大東西不再留著整份，改切成 1,000 m 的格子，只做視錐剔除；切格抽成 `replaceWithChunks` | 10-23 §4.4 的公式不變；「大的也切格」本作已經有了（512 m 的 chunk） |
| `js/city-config.js`（−30） | `SIGNAL_TIMING` 不變 | 見 §3.1 |
| 其他（`actor-models.js`、`controllers.js`、`trees.js`、`audio-*.js`…） | 角色模型、操作、樹、聲音的修改 | 10-23 的判斷不變 |

## 3. 10-23 沒看的：號誌、跟車、行人

### 3.1 紅綠燈照時鐘變燈（建議第 4 件）

- **它**（`js/city-config.js` 第 712–720 行）：
  - `SIGNAL_TIMING = { cycle: 60, avenueAmber: 26, avenueRed: 30, streetAmber: 56, walk: 7 }`（秒）。
  - `signalPhase(time, isAvenue)`：週期內的時間 `t = time mod 60`。
    - 大道：`t < 26` 綠，`t < 30` 黃，其餘紅。
    - 小街：`t < 30` 紅，`t < 56` 綠，其餘黃。
    - 兩個方向在 26–30 s 與 56–60 s 有黃燈，沒有全紅。
  - `js/street-details.js` 用同一個時鐘換燈頭和行人燈；`traffic.js` 的車照它停。
  - 只看時鐘，不留狀態。
- **本作**：
  - 決策 355 的號誌 `Map3DProp.signalGo`／`signalStop`（`Sources/GamePresentation/Map3DProps.swift:23–29`）：一個亮綠、一個亮紅，晚上亮的那顆發光。
  - 哪一個方向綠，在蓋場景時就定了：`Map3DRoadMarkings.swift:196` 依那條路和主幹道是否同向（`abs(dot) >= 0.7`）決定 `go`。號誌跟著靜態場景合進 chunk（`Map3DRoadMarkings.addStreetStops`，第 335–339 行）。
  - **所以現在的號誌永遠不會變燈**，主幹道永遠是綠的。
- **搬過來**：
  - 規則：GamePresentation 加一個純函式（時間、主幹道或支道 → 綠、黃、紅），在 Linux 上測。
  - 畫法：燈頭現在是靜態網格的一部分，要變燈，亮的那顆就不能烘在靜態網格裡。可以改成每塊一份小的實例（只放燈的位置、方向、主或支），每幀照函式選顏色；或交給著色器，用 uniform 傳時間，用頂點屬性帶主支。只有 App 端的畫法要決定，網格大小幾乎不變。
  - 時間：用決策 259 街景用的同一個時鐘，畫面上的車流和燈號才一致。
  - **秒數照台灣的，不照抄紐約的 60 秒**。要找有來源的週期、黃燈、全紅秒數（例如交通部的號誌設計規範，或地方政府公開的時制），寫進決策並附來源。找不到才用它的結構加本作自己定的秒數，並寫明是自己定的。紐約沒有全紅，台灣路口多半有，這點要照台灣的。
  - 減少動態效果：照 `.claude/skills/motion/SKILL.md` 決定（變燈是畫面上真實東西的狀態，不是介面動畫，可能不必停，但要寫明）。
- **第二步（不在第 4 件裡）**：讓 `Map3DStreetLife` 的車在紅燈前停。車只看時鐘算位置（決策 259），要在不留狀態的前提下，把「這條車道上的車在紅燈時排隊、綠燈時依序離開」寫成時間的解析式，比較難。等第 4 件合併、作者看過再決定要不要。

### 3.2 IDM 跟車（不派，只記數值）

- **它**（`js/traffic.js` 第 32–34 行）：
  - 車 `{ a: 2.0, b: 3.0, T: 1.2, s0: 2.0, aLat: 3.5 }`，公車 `{ a: 1.1, b: 2.5, T: 1.5, s0: 2.5, aLat: 2.0 }`；`a` 最大加速度（m/s²）、`b` 舒適減速度、`T` 時距（s）、`s0` 停車間距（m）、`aLat` 轉彎時能接受的側向加速度。
  - 往前看 70 m 的車、停止線與號誌。高速公路另一組 `{ a: 1.6, b: 2.8, T: 1.3, s0: 3.0 }`（第 1757 行）。
  - 每台車有自己的速度與位置，每幀積分。
- **本作**：
  - `Map3DStreetLife`（決策 259）每台車只看時鐘和自己的種子算位置，至少隔 9 m（第 561 行），只讓公車（`giveWay`，第 614 行）。
  - 3D 公車 `BusMotion`（決策 400 的 10i-6）：每站停靠不超過單程的 30 %，站與站之間等速，沒有加減速。
- **判斷**：
  - IDM 要每台車留狀態並逐幀積分，和決策 259 衝突，也會讓同一個時刻在兩次打開時看到不同的車流。不搬。
  - 可以只拿公車那組 `a`、`b`，把 `BusMotion` 的進站減速、出站加速寫成時間的解析式（等加速度的兩段），不必留狀態。等作者覺得公車停站太生硬時再派；現在沒有人提過。

### 3.3 行人在路口排隊過馬路（不派）

- **它**（`js/pedestrian-system.js`）：每個人有一條沿人行道的路徑，走到路口就排在路緣，等 `traffic.js` 給許可才過，會閃玩家、會停下來聊天。人數固定 `NUM_PEDS`，只在玩家附近補人。
- **本作**：決策 259 的行人只看時鐘與種子，人數照車站的乘客與城鎮的人口算；車站的人群另外照乘客數。
- **判斷**：要每個人留狀態，而且排隊需要和號誌、車流同步。和決策 259 衝突，玩家從上方斜看也看不出差別。不搬。

## 4. 建議：10-23 的三件加第 4 件

順序照 10-23 §5，加上第 4 件：

1. 城市方塊改實例，先做 `.far`（10-23 §4.1、§5 第 1 名）。
2. 太陽陰影用 `.far` 當替身（10-23 §4.5、§5 第 2 名）。
3. 小零件放進固定大小的池，依像素大小剔除（10-23 §4.3、§4.4、§5 第 3 名）。
4. **紅綠燈照時鐘變燈**（§3.1）。

- 第 4 件和第 1–3 件改的地方不同：規則在 GamePresentation 新的純函式，畫法在號誌的實例或著色器。它不動 `Map3DScene.Builder` 的城市方塊，所以可以和第 1 件同時派；但它要把燈頭從靜態網格裡拿出來，會碰 `Map3DRoadMarkings.addStreetStops`。開工前和第 1 件的 session 對好檔案。
- 第 2 件只改 `Map3DMetalView` 的深度 pass 幾行，最小；10-23 排第 2 是因為它省的只在跟車時看得到。若要先有一件快的，可以先派第 2 件。
- 開工前看 Codex 正在做的 3D 車輛 PR（#1292、#1296）合了沒：它們改 `Map3DModels.swift`，第 3 件也會碰。

### 第 4 件的五方

五方用 10-23 同一把尺（玩家 30、鐵道迷 15、開發 25、美術 15、音樂 15；每方 10 分制，無關的給 5）。

- 玩家 7：街口看起來是活的；跟車或看車站時，路口的燈會換，不再永遠主幹道綠燈。
- 鐵道迷 6：無直接關係；但秒數照台灣的時制、有來源，不照抄紐約的 60 秒週期。
- 開發 7：規則是一個純函式，可以在 Linux 測；畫法要把燈頭從靜態網格拿出來，App 端要選實例或著色器其中一種。
- 美術 6：燈頭的模型不變，只換亮哪一顆；晚上發光的燈照決策 355。
- 音樂 5：無（行人號誌的提示音 10-23 §4.6 已列「之後」）。
- 加權：(7×30 + 6×15 + 7×25 + 6×15 + 5×15) / 100 = **6.40**，和 10-23 的第 1 名（6.30）、第 2 名（6.20）同一級。
- 換成 [NEXT_PRIORITIES](NEXT_PRIORITIES_2026-10-12.md) §19 的尺（每方 1–5 分）：3、4、4、2、2，加權 **3.10**，就是 §22.12 第 1 項。

**同一天的補充**：作者給的台灣 3D 參考包 TW3D（參考庫 release `Tai`，NEXT_PRIORITIES §22.12）有現成的台灣式號誌：橫式燈頭、倒數、小綠人、有聲號誌、台北市府的號誌清單。第 4 件開工時先用它，再看 slop-newyork。

## 5. 授權

- 程式碼 MIT（`LICENSE`：Copyright (c) 2026 Mr.doob），和 10-23 §2 相同。真要搬時，搬過去的檔頭留版權聲明與 MIT 授權全文（或指向 repo 裡的一份 `THIRD_PARTY_NOTICES`），PR 的對照表寫 `原檔:行號 → 本作的檔案／函式`。
- 資料（NYC Open Data、OpenStreetMap 的 ODbL）是曼哈頓的，不用。
- 參考庫（a91453/railway-reference-private）的舊資料夾這次沒有重讀，新的 TW3D 包見上面 §4 的補充；第 4 件開工時，照 CLAUDE.md 先查 `Railway/street_scene_reference_clean/`、`Railway/town-scene-reference-clean/`、`Railway/commuter_journey_reference_clean/` 有沒有號誌的時制或燈號的畫法，有就先用參考庫的。

## 來源

- https://github.com/mrdoob/slop-newyork（MIT），commit `be65d0ab61b24718b6da8886b7d7bed2d68ac178`；和 `7fdaf1545f44c3022ab1e4c345954307e6bc2e9b` 比對。讀過的檔：`js/city-config.js`（第 712–720 行）、`js/traffic.js`（檔頭、第 24–40 行、第 1757–1760 行）、`js/street-details.js`（第 40–100 行）、`js/scene-culling.js`（全部與 diff）、`js/pedestrian-system.js`、`js/pedestrian-routes.js`、`js/vehicle-physics.js` 的檔頭、README、LICENSE。
- 本 repo：
  - 決策 259、355、370、391、400；
  - `Sources/GamePresentation/Map3DProps.swift`（第 23–29 行）、`Map3DRoadMarkings.swift`（第 196、335–339 行）、`Map3DStreetLife.swift`（第 561、614 行）、`Map3DScene.swift`（`Chunk`）；
  - `RailwayGameApp/Views/Map3D/Map3DMetalView.swift`（太陽深度 pass）。
