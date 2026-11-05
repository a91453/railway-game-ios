# Bumpinto World 研究（2026-11-05）

作者 2026-11-05 要遊戲規劃第 48 任研究 <https://github.com/dohoon84/bumpinto-world>，「號誌輪替排進 114.1 之後 寫進 md 還有什麼可以」。（更正：第一版寫「號誌不輪替」是錯的，決策 429、445 早就做了輪替與行人號誌；排進 114.1 之後的是車與人照燈號停走。）這份記下它是什麼、授權、哪些做法可以學、排在哪裡。讀的是 `main` 的 `2026-11-03` commit（210 個 commit，完整歷史）。

## 它是什麼

韓國 CrazyLabs（김도훈）做的瀏覽器 3D 街景世界：three.js（MIT）、OpenStreetMap 的建築與道路、韓國公車的 OSM 路線、Cloudflare Durable Objects 的多人連線。先做盆唐亭子站周邊約 900 m，後來加了水內到蠶室樂天塔的「走廊」（分塊載入加遠景）。可以走路、搭公車與計程車、拍照、聊天。

## 授權

- **2026-10-28 起（`75be304`）**：自訂的「Bumpinto World Source License」。個人、學習、內部使用可以；**不能拿它或改過的版本做任何商業服務**（收費、訂閱、廣告、贊助都算），換名字、換地區也一樣；公開的版本要在畫面上一直顯示「CrazyLabs」與「Bumpinto World」。
- **之前（`540b6fc`，10-28 00:33 起約 19 個 commit）**：「MIT License with Attribution Requirement」，可以商用，但畫面上要看得到同樣的署名。新授權第 4 條說舊版拿到的照舊。
- **地圖 JSON**：OSM 衍生資料，ODbL；只有韓國，對我們沒用。
- **遊戲規劃的判斷**：**只讀做法、不抄程式**。現行授權禁止商用；舊版雖可商用，但作者改授權就是不要被拿去營利，而且它是 JavaScript／three.js，我們要用 Swift／Metal 重寫，抄程式省不了什麼。若要用舊版程式，是作者的決定（CLAUDE.md：非寬鬆授權的程式碼由作者決定）。下面每一項都是我們自己寫，PR 裡寫「讀過 bumpinto-world 的做法，程式是本專案自己的」。

## 可以學的做法

都在畫面層（GamePresentation／App），不動 GameCore，不影響決定性。

| # | 它有的（檔案） | 我們現在 | 怎麼用 | 排在 |
| --- | --- | --- | --- | --- |
| 1 | **行人號誌輪替**（`src/transit/transit.js`、`src/corridor/crossings.js`）：60 秒一輪，綠 20 秒→閃 6 秒→紅；同一路口（45 m 內）互相垂直的兩向錯開 30 秒；公車前方 45 m 的號誌不是紅燈就停在停止線；路人紅燈（含閃）會等 | 號誌**已經會輪替**：決策 429（70 秒一輪，主路與橫路輪流，四組錯開）、決策 445（行人號誌、小綠人與倒數）；**車與人不看燈**（決策 429「下一步」） | 只做沒做的：街景車流在停止線前等紅燈、路人紅燈（含閃）在路口等；照 `Map3DSignalTiming` 的同一個時鐘，不加狀態 | **114.1 之後**（作者 2026-11-05） |
| 2 | **拍照模式**（`src/camera/`）：遊戲內相機、取景框、存相簿、分享；關著時不加任何渲染負擔 | 沒有 | 3D 地圖加「拍照」：隱藏介面、調焦距，存到照片 App；鐵道迷拍列車很合適 | 之後再排 |
| 3 | **四季的樹**（`src/world/trees.js`）：秋天銀杏黃、楓紅，每棵色調略有差 | 樹沒有季節 | 照遊戲日期換色：阿勃勒（5–6 月黃）、木棉（3 月紅）、櫻花（2 月）、楓香（冬）；可與樹高資料一起做 | 之後再排 |
| 4 | **河堤地形**（`src/world/terrain.js`、`streams.js`）：堤防斜坡→高灘地→水邊，支流匯入時漸深，有樓梯 | 河是平的水面 | 台北的河濱公園（淡水河、基隆河、新店溪）堤外低於堤內，高灘地有自行車道 | 之後再排（3D 城市） |
| 5 | **公車塗裝照路線種類**，每個顏色附出處（README「버스 도색」） | Codex 做客運塗裝（決策 593，#1834） | 114.1 之後的國道客運：真實路線種類→配色，出處寫在決策 | 國道客運時 |
| 6 | **一樓店面來自政府商家資料**（`src/world/groundFloorShops.js`，韓國小商工人市場振興公團） | 店面招牌是程序產生 | 台灣的商業登記開放資料（要先查授權與欄位），讓站前商店街像真的 | 之後再排（先查資料） |
| 7 | **建築外牆色依建物登記推估**（`src/world/buildingColours.js`，結構、用途、使用核准年） | 依類型給色 | 台灣建物資料若有結構與年份可參考 | 之後再排（先查資料） |
| 8 | **街上小生活**：咖啡店內坐滿人、流浪貓見人就跑、下雨才出現的雨傘攤、夜間車燈與光束（`cafeCrowd.js`、`strayCats.js`、`umbrellaVendor.js`、`vehicleLights.js`） | 有路人、車流、夜間窗燈 | 流浪貓、下雨時路人撐傘、車頭燈光束 | 之後再排 |
| 9 | **搭乘紀錄與車資**（`src/ride/fare.js`、`rideLog.js`） | 只有「跟隨公車／列車」 | 跟隨時顯示「搭了幾站、幾分鐘」，玩家自己的搭乘紀錄 | 之後再排 |

不學的：多人連線、遊戲內手機與簡訊、留言板（和這個遊戲無關）；即時公車位置（要 data.go.kr 金鑰與 Cloudflare 代理，牽涉祕密；我們的即時資料另有決策）；依真實時間與 Open-Meteo 真實天氣（遊戲時間是模擬的）。

## 同一天一起看的其他來源

作者 2026-11-05 同時問的幾個網址，遊戲規劃第 48 任的結論：

- **OpenStreetMap、MapLibre、OpenFreeMap、OpenMapTiles**：遊戲已經在用（`DataSourceCredits`、`RailwayGameApp/Resources/Licenses/MapLibre-iOS-LICENSE.md`），照現在的標示即可。OpenFreeMap 可商用、免金鑰、不限次數；離線下載一次最多 3,000 張圖磚或 50 MB，要帶自己 App 的 User-Agent。OpenMapTiles 的授權頁目前 404；MapTiler 賣的現成全球圖磚另有條款，不直接內建。
- **Meta 與 WRI 的高解析樹高圖**（<https://registry.opendata.aws/dataforgood-fb-forests/>）：CC BY 4.0，可商用。標示：「High Resolution Canopy Height Maps by WRI and Meta」，影像「© 2016 Maxar」（Maxar 2025 年改名 Vantor，作者看到的「imagery @ Vantor」就是它；兩個名字都寫）。**台灣有**：第 9 層 quadkey 的圖塊（例如 `chm/132123033.tif`，約 76 MB）在 `s3://dataforgood-fb-data/forests/v1/alsgedi_global_v6_float/chm/`，不用帳號；台灣全島約 1 GB 多。用法：`tools/` 的資料工具讀過算成小資料再進 App，讓 3D 地圖山林與公園的樹照真實高度。之後的 3D 城市工作再排。
- **新加坡開放資料授權 1.0**（<https://data.gov.sg/open-data-licence>）：可商用、修改、散布；要顯著標示「Contains information from {資料集} accessed on {日期} from {來源} which is made available under the terms of the Singapore Open Data Licence version 1.0」並連到授權；不能暗示政府背書、不給商標；有賠償條款（比 CC BY 嚴）。捷運公車多在 LTA DataMall，條款另查。遊戲只有台灣，**做海外城市時才用得到**。
