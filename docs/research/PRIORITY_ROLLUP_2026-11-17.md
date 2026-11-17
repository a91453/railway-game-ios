# 優先清單總表（2026-11-17 深夜）

作者 11-17 說「整體優先順序呢，含之前未做的，我記得很亂」。這份把散在各處的未完成項目收成一張表：NEXT_PRIORITIES §29.9–§29.29（兩個 §29.29）、`BACKLOG_AUDIT_2026-11-17.md` 表一、`MODEL_PALETTE_REVIEW_2026-11-15.md` §3、`docs/priorities/MISC-BACKLOG.md`（#2380）。基準 `main` `f35a8d3`，每項都對過 `main` 的合併紀錄。分數照原出處，不重打；權重照 §19。

狀態怎麼對的：「已完成」看 `main` 的合併紀錄（PR 號寫在第 4 節）；「未做」的前幾名另外在程式裡找過（極光、雪花與結冰、到站語音、島式雨棚、堤防、港鐵四款車型、颱風停駛，`Sources/` 與 `RailwayGameApp/` 都沒有），不只看文件寫的狀態。

排法：bug 在前，再照分數；同分照玩家、開發、鐵道迷。「卡」欄是派之前要等的事。進行中、等作者、已完成的另列，不佔名次。

**11-18 更新**：#2371 DEPOT-REAL、#2375 ROVANIEMI-FARE（連 #2355）、#2379 交接、#2364 實景道路、#2372 淡水高架第 4 輪（素材庫 #136）、#2382 SANTA-FLIGHT 已合，下面的「卡」與第 3、4 節照此改；作者 11-18 點名的淡水剩下三項（`docs/priorities/TPE-MRT-ELEVATED.md`）照現行五方評分插進第 2 節。

## 1. bug（還沒修、可以派的）

| 名次 | 項目 | 分 | 出處 | 卡 |
| --: | --- | --: | --- | --- |
| 1 | ROAD-RAMP-HEIGHT：匝道橋和主橋併成一座後全站在主橋高度 | 3.15 | §29.29（822） | 無；大單 |
| 2 | 左營月台上方的白條（決策 625 屋頂骨架的肋） | 3.10 | MISC-BACKLOG | 無；先出兩三種預覽 |
| 3 | ROAD-STRIP-WEDGE：橋端後面斜楔形與急彎尖刺 | 2.65 | §29.29（822） | 可和第 1 名同一張 |
| 3 | ROAD-FORK-CELL：斜拖分岔多佔一格 | 2.65 | §29.26 | 和 ROAD-SNAP／ROAD-HINT 一張 |
| 5 | HK-LATE-RUNS：香港擬實大半班次誤點、每天十幾班沒發 | 2.60 | §29.25 | 動 GameCore |
| 6 | 八堵停住時自動救回 | 2.45 | §29.8 B1 | 等實機確認還會不會停 |
| 7 | HK-NIGHT-PARKED：過夜車停在中途站 | 2.40 | §29.25 | #2371 已合：新買的線不再發生，只剩作者舊存檔（靠 DEPOT-ADD-MID 2.15） |
| 8 | DEPOT-DAWN-QUEUE：機捷清晨同時出庫 | 2.40 | `priorities/DEPOT-REAL.md` | 可派；動 GameCore、死結類 |
| 9 | REVIEW-L19 P3 剩下的六項 | 2.05 | §29.8 B2 | 工作室 |
| 10 | 舊存檔沒有活動場館與新漁港 | 1.95 | §29.15 | 下一個碰 `SavedGame.swift` 的 PR |
| 11 | 示範地圖配不到車時訊息照說在跑；真愛碼頭月台略過 | 1.90 | §29.15 | — |

REVIEW-L27（#2376，`priorities/REVIEW-L27.md`）留下的：bug HK-PEAK-CONTROL（香港簡＋控尖峰漏 31/740）2.40，和第 7、8 名同分；MAP-PACK-ONCE 1.80、ELEVATED-SHELL-CHUNK 1.70、SNAP-REANCHOR 1.55 排在第 11 名之後；功能 OPEN3D-PEAK-MEM 1.55、VALLEY-TREES-GPU 1.40、NOTES-138 1.30 在 2.80 以下。

等觸發才做的 bug（不派）：PERF-2D-STALL 2.15、機捷舊線傍晚六段卡住 1.95、管制關著多一次全車掃描 1.3、點車站當機的根因、START-CRASH SIGTRAP。

## 2. 功能前 25 名（還沒做、沒人在做）

| 名次 | 項目 | 分 | 出處 | 卡 |
| --: | --- | --: | --- | --- |
| 1 | 雪景剩下的：樹變白、河湖結冰、下雪 | 3.75 | §29.11 F | 無；12/1 前最好上 |
| 2 | 港鐵其餘四綫真車（屯馬、東鐵、南港島、迪士尼） | 3.35 | §29.9、MODEL_PALETTE #3、MISC-BACKLOG | 工作室，一次一款 |
| 3 | 極光（羅瓦涅米） | 3.30 | §29.11 I | 無 |
| 3 | ~~ROAD-GRADE-CAP：國道快速道路坡度 ≤ 5%、高架與路塹~~ | 3.30 | §29.23 | **已做**（決策 833，國道；快速公路沒做，見 `handoff/ROAD-GRADE-CAP.md`） |
| 3 | 島式月台雨棚（台灣與香港） | 3.30 | MISC-BACKLOG | 無；station-kit |
| 6 | 香港地面顏色（土地利用網格＋生境圖） | 3.25 | §29.12 | 原本等 REGION-LOOK-HK，已合，可派 |
| 6 | 機廠檢修庫牆分上下段 | 3.25 | MISC-BACKLOG | #2371 已合，可派 |
| 6 | TW-CARS：台灣汽車、廂型車換掉盒子 | 3.25 | §29.15 | 部分：車色已有計程車黃（`Map3DStreetLife.carPaints`），車形還是盒子 |
| 6 | REINDEER：羅瓦涅米的真馴鹿（吃草的群、拉雪橇的）（玩家 3、開發 4、美術 4、鐵道迷 4、音樂 1） | 3.25 | §29.17，11-17 深夜重評同分 | 模型派 Mac 工作室，**等作者說再派**；放置接在羅瓦涅米開放（11-30）之後；冬季活動 12/1–1/6，有時效。聖誕老人（#2382）的雪橇現在是方塊，模型到了照決策 831「換模型的接點」換（`handoff/SANTA-FLIGHT.md`） |
| 9 | 北歐建築逐棟、羅瓦涅米四座地標 | 3.20 | §29.11 G | 工作室 |
| 10 | 颱風、地震停駛與復駛 | 3.10 | §29.9 | 先寫設計；動 GameCore |
| 10 | VIADUCT-PIERS：公路高架墩不站在路面上 | 3.10 | §29.23 | 和 ROAD-GRADE-CAP 同區 |
| 10 | PLAYER-BOX：玩家的住宅、商店、辦公換掉黃盒子 | 3.10 | §29.15 | 無 |
| 13 | 淡水線十站逐站測試（真實場景每站有外殼、淨空零切到） | 3.05 | `priorities/TPE-MRT-ELEVATED.md` | 無；雲端、只寫測試（玩家 3、開發 5） |
| 13 | 101 夜裡照星期換色 | 3.05 | §29.22 | 和地標夜窗一起 |
| 13 | REAL-STATIONS-3D 下一批（淡水高架以外） | 3.05 | §29.9 | 和 STATION-KIT-LOOK 2.75 同一批站 |
| 13 | 車齡、故障與檢修 | 3.05 | §29.9 | 先寫設計；動 GameCore |
| 13 | 榕樹灰樹皮、氣根 | 3.05 | MISC-BACKLOG | 等榕樹接進遊戲 |
| 18 | LEVEE：河岸堤防 | 2.95 | §29.22 | 無 |
| 18 | 北投四角石塊比屋頂深（照片是比屋頂亮的米白） | 2.95 | `priorities/TPE-MRT-ELEVATED.md` | 工作室第 5 輪，和新北投白圓柱同一輪 |
| 20 | 車門開關（近景停站滑門） | 2.90 | MISC-BACKLOG | 白天版本後 |
| 20 | 列車到站廣播 | 2.90 | §29.9 | 無 |
| 20 | 芬蘭列車 Sr3、Sr2、雙層客車 | 2.90 | §29.11 H | 工作室 |
| 20 | TRACK-STROKE：一筆畫多段曲線 | 2.90 | §29.16 | 無 |
| 20 | TRACK-REALIGN-BEND：拖折點改線 | 2.90 | §29.24 | 826 已合，可派 |
| 25 | TRACK-SPEED-LAYER：已鋪軌道依限速上色 | 2.85 | §29.16 | 無 |
| 26 | ROAD-SNAP＋ROAD-HINT | 2.80 | §29.16 | 和 ROAD-FORK-CELL 一張 |
| 26 | HK-NAMES；車站與車身廣告；自由曲線道路（等作者看 ROAD-SMOOTH） | 2.80 | §29.9、§29.19 | 廣告動 GameCore |

2.80 以下照原出處（2.75 建材外銷、ROAD-JUNCTION、TPE-LANDMARKS-2…）；新北投牌樓柱不是白圓柱 2.70（`priorities/TPE-MRT-ELEVATED.md`，和北投石塊同一輪工作室）；DEPOT-ADD-MID 2.15、三線共用小蠔灣車廠 1.85（`priorities/DEPOT-REAL.md`）。

**有期限的**：羅瓦涅米開放（ROVANIEMI-OPEN，目標 11-30，沒打分，BACKLOG_AUDIT 表二「高」），ROVANIEMI-FARE（#2375）已合，可派；雪景第 1 名也最好趕 12/1。

## 3. 不佔名次的

- **進行中**：無。
- **11-18 已合**：REVIEW-L27＋HEALTH-137 #2376、DEPOT-REAL #2371、ROVANIEMI-FARE #2375（連 #2355）、SANTA-FLIGHT #2382（3.15；雪橇暫用方塊，等 REINDEER）、淡水高架第 4 輪 #2372（素材庫 #136）、交接 #2379、ROAD-LOOK-REAL-2 #2364。聖誕老人要把手機日期調到 12/24 晚上才看得到，實機由作者自己看。
- **等作者說**：REINDEER 馴鹿（3.25，排在上表功能第 6 組；作者 11-17 說模型要給 Mac 工作室，先不派）。
- **另一帳號在做**：無（TRACK-CURVE-COLOUR 已合）。

## 4. 清單裡還寫「未派」但其實已經做完的

清單沒同步，看起來亂多半是這個。下面這些在 `main` 都合了，併回時把狀態改成已完成：

FACADE-VARIETY（#2352）、ROAD-SMOOTH（#2356）、ROAD-LOOK-REAL（#2364）、E200-REDO 與 DR1000／DR3100 遠景 bug（#2367）、TPE-MRT-ELEVATED 前三輪（#2363）、TRACK-CURVE-COLOUR＋TRACK-ALIGN（#2362）、MAPPACK-FIX（#2349）、PERF-3D-FIRST（#2365）、DEADLOCK-HK（#2347）、ZHUZHONG-SIDE、ROAD-JOIN-DRAW（#2338）、MUSIC-REFRESH（#2335）、MUSIC-WINTER（#2333）、music-review skill（#2343）、NATURE-BASE（#2336）、SUN-TIMES（#2331）、REGION-LOOK-HK（#2330）、art-style §7 兩句（併在 MODEL-AGE #2334）、FULLLANE-136（L26 P2-1，#2341）、DOCNUM-CI＋CONFLICT-WATCH（#2369）、PRIO-FILES（#2378）、REVIEW-L27＋HEALTH-137（#2376）、DEPOT-REAL（#2371）、ROVANIEMI-FARE（#2375）、SANTA-FLIGHT（#2382）、TPE-MRT-ELEVATED 第 4 輪（#2372）。

## 5. 重複或衝突要合併的

- **港鐵四綫真車**寫在三處（§29.9 MTR-1～5 3.35、MODEL_PALETTE #3 3.20、MISC-BACKLOG 3.35）：以 3.35 為準，同一件。
- **自由曲線道路**有兩個分（§29.16 第 8 名 2.05、§29.19 第 4 名 2.80）：以 §29.19 較新的 2.80 為準，前提都是作者看過 ROAD-SMOOTH 仍不滿意。
- **同一局經營台灣＋香港**（§29.9 2.80）和**航線 B 段**（B1 2.75、B2 3.45，B0 2.05）是同一件事的兩種寫法；併成航線 B 段一條。
- **地標夜裡窗不亮**（2.55）、**101 夜裡換色**（3.05）改的是同一處，一張單。
- **REAL-STATIONS-3D** 和 **STATION-KIT-LOOK**（2.75）是同一批站。
- **HK-NIGHT-PARKED** 被 DEPOT-REAL 接手：#2371 已合，新買的線不再發生；只剩舊存檔，和 DEPOT-ADD-MID 併成一件。
- **冬季曲與雪地環境聲**（2.95）：冬季曲已做（#2333），只剩雪地環境聲。
- NEXT_PRIORITIES 有**兩個 §29.29**（PR 卡著、ROAD-LOOK-REAL 留下的），之後新項目改寫 `docs/priorities/`，不會再撞號。

## 五方

這份只整理、不重打分。五方理由在每列的出處。
