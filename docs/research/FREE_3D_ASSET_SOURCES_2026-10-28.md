# 免費 3D 素材來源評比（派工單 BE，2026-10-28）

作者的要求：「幫我寫文件研究目前專案適合什麼：Kenney、KayKit、Quaternius、Polyfork，或是有更好的網站，用評分機制評比。」

只做文字研究，沒有素材檔進 repository。授權句子都來自官方頁，查證日是 **2026-10-28**；查不到的寫「查不到」。

## 0. 先弄清楚專案現況

- 遊戲是原生 iOS（SwiftUI）。3D 地圖的模型多半是 `Sources/GamePresentation` 裡用程式寫的配方（`Map3DModelPack`、各 `Map3D*Kit`），風格是「資料照真的，外觀像精緻的模型玩具」：平塗、頂點色、淡、低彩度（art-style §7）。
- `tools/glb-to-m3dmodel/` 把 GLB 轉成遊戲的 `.m3dmodel`。新的靜態入口（`bridge.mjs`）**只收沒有貼圖、沒有骨架、沒有動畫的三角網格**，並要求列出每個網格節點的名字；舊的 Meshy 入口會把貼圖取樣成最多 8 個平塗色。
- `Web/CityView/public/models/town/` 已用 Kenney 的 City Kit（Commercial）、Train Kit、Car Kit、Mini Characters、Nature Kit、City Kit（Roads），`SOURCES.json` 記了來源與面數。**那是網頁版**，與 App 打包的模型包是兩回事。
- 審查 K1-1：模型包從 74 MB 長到 168 MB（`docs/archive/PR1288_1340_REVIEW_HANDOFF.md`），所以面數與貼圖大小是硬限制。
- railway-game-ios 是公開 repository，App 打包的檔案等於公開；不能公開轉載的素材只能放私庫 `railway-assets-private`（HANDOFF「素材放哪裡」那段）。
- 需要的東西：台灣街景（騎樓、透天厝、廟、夜市、機車、公車、號誌）、車站與月台零件、鐵道設施、人物、樹木與自然、車輛。

### 本次親手量的數字

- 網頁版已用的 Kenney 模型（`SOURCES.json`）：車 2,032–2,474 面（目標 ≤1,500）、人 690–756 面（目標 ≤500）、樹 62–196 面、商業建築 1,100–2,960 面、軌道段 376 面、列車 1,418–1,616 面。
- 從 Polyfork 下載 4 個 GLB 到 scratchpad 量（不進 repository）：外送機車 1,752 面、交通號誌 606 面、市區巴士 2,008 面、客車廂 3,252 面。四個都是**頂點色、沒有貼圖、沒有骨架**，但每個網格是**不共用頂點**的三角（頂點數 = 3 × 面數），而且網格節點沒有名字。
- 用 `bridge.mjs` 試轉外送機車：被拒絕，原因是節點白名單要有名字，而 Polyfork 的網格節點多半沒有名字（只有 `body`、`front-assembly` 有）。要轉就得先在 Blender 或腳本裡改名，**本次沒有轉成功，轉檔 UNVERIFIED**。
- Kenney、KayKit、Quaternius 的新包這次沒有下載量面數（Kenney 的數字來自上面的 `SOURCES.json`；其餘面數 UNVERIFIED）。

## 1. 評分表

每項 1–5 分，加權後滿分 5.00。

| # | 項目 | 權重 | 為什麼 |
| --- | --- | --: | --- |
| L | 授權 | 30% | 能不能打包進上架 App、能不能放進公開 repository、要不要署名、能不能改。授權不行，其他再好都不能用 |
| S | 畫風合不合 art-style | 15% | 平塗、淡、低彩度、頂點色；貼圖要淡；不寫實也不失真的卡通 |
| C | 涵蓋專案需要的東西 | 20% | 台灣街景、車站月台、鐵道設施、人、樹、車 |
| T | 技術合不合 | 15% | 格式、面數、貼圖或頂點色、能不能經 `tools/glb-to-m3dmodel` 轉 |
| Q | 品質與一致性 | 10% | 同一來源的包能不能混用（共用調色盤、比例） |
| K | 取得成本 | 10% | 免費或付費、要不要帳號、能不能批次下載 |

授權欄的打分：5 = 官方寫 CC0 或等同，能放公開 repository；4 = 免費商用但有署名；3 = 能打包進 App，但官方文字禁止轉載原檔，放公開 repository 有風險，或官方文字前後矛盾；2 = 逐檔不同，或查不到原文；1 = 不能商用。

## 2. 授權（逐字引用）

### 2.1 Kenney —— CC0

- 網址：https://kenney.nl/support
- 原文：「Yes, all game assets on the asset pages are public domain licensed (CC0). You're free to use them, even in commercial projects.」「Attribution is not required, but if you choose to give credit you can do so by mentioning "Kenney". Do not use our logo, as it is reserved for official projects by our studio.」
- 單包頁面也寫：Train Kit https://kenney.nl/assets/train-kit 「License Creative Commons CC0」；City Kit (Suburban) https://kenney.nl/assets/city-kit-suburban 同。
- 結論：可打包、可放公開 repository、可改、免署名。不要用 Kenney 的 logo。

### 2.2 KayKit（Kay Lousberg）—— CC0

- 網址：https://kaylousberg.com/game-assets/city-builder-bits
- 原文：「Free for personal and commercial use, no attribution required. (CC0 Licensed) Included files are .OBJ, .FBX and .GLTF」。
- Furniture Bits、Restaurant Bits、Prototype Bits、Forest Nature Pack、Character Animations、Characters : Adventurers 的頁面是同一句。
- 查不到：總覽頁 https://kaylousberg.com/game-assets 沒有授權文字，也沒寫哪些包要錢（「Complete KayKit Collection」的價格頁面沒有寫）。
- 結論：每個免費包的頁面都寫 CC0，可放公開 repository。

### 2.3 Quaternius —— **網站自己前後不一致，是這次最大的疑點**

兩份官方文字並存：

1. 常見問題 https://quaternius.com/faq.html：「these assets can be used for free without the need for attribution in commercial, educational, and personal projects. All models are under the CC0 License.」「you are free to modify the models in any way you like, including combining them with other asset packs.」
2. 授權頁 https://quaternius.com/license.html，標題「Quaternius Asset License (QAL) v1.0」，「Last updated: 8/28/2026」：「You just can't resell or redistribute the assets themselves as assets.」第 3 條：「You may not extract, repackage, sublicense, sell, or otherwise redistribute the Assets (in original or modified form) as a standalone asset, asset pack, stock file, template, or similar product, whether for free or for payment, and whether alone or bundled with other assets. This restriction applies regardless of how much the Assets have been modified. It does not restrict distributing a completed Product that merely incorporates the Assets.」第 7 條：「Changes will not apply retroactively to Assets you've already obtained under an earlier version; the version in effect at the time you obtained the Assets governs your use of them.」
3. 各包頁面（2026-10-28 抽查 10 包：Downtown City MegaKit 315 個模型、Modular Train 15、Modular Streets 25、Public Transport 12、Simple Buildings 10、Ultimate Textured Buildings 76、Stylized Nature MegaKit 116、Universal Base Characters 26、Ultimate Nature 150、Cyberpunk Game Kit 71）都寫「License CC0」。

HANDOFF 與私庫 README 寫「Quaternius 的檔案不得公開轉載」，**這句話不完全對、也不完全錯**：

- 對：QAL 第 3 條禁止把素材（含改過的）當作獨立素材、素材包轉載，「不管改多少」。把 GLB 或轉好的 `.m3dmodel` 放進公開 repository，別人可以直接拿走，很可能算「轉載」。
- 不全對：很多包頁面與 FAQ 仍寫 CC0，CC0 是放棄權利，不是這種限制。網站沒有說哪些包受 QAL 約束（授權頁的範圍是「released under this License」，但沒有列包名）。**哪些包是 CC0、哪些是 QAL，查不到。**
- 做法：這次不替作者判斷。要用 Quaternius 的包前，先寫信問作者（授權頁底下有信箱），或在下載時存下當天的頁面文字與檔案雜湊；在回信前，一律當成「不能放公開 repository」。

### 2.4 Polyfork（https://polyfork.dev，不是 polyfork.com）—— 免費商用，**禁止轉載原檔**

- 網址：https://polyfork.dev/licensing，「Last updated October 2026」。
- 原文：「Use any asset you download here in personal and commercial projects: games, apps, websites, prototypes, videos, client work and products you sell. Modify anything: recolor, remix, decimate, combine, animate.」「No attribution required, ever.」
- 禁止：「Resell or redistribute the assets themselves. That means no re-uploading the files (GLB or ES module, original or modified) to other marketplaces, asset packs, template libraries or file-sharing sites, whether free or paid, and no offering them through tools that hand the files to other people. Your game can ship the models inside it; the files as standalone assets stay here.」
- 另：「Do not use anything you get here to build or train a commercial asset generator」。本專案不做生成器，不受影響。
- 免費範圍：「Every low poly model is free, and so is every kit.」不用帳號可以從 CDN 取 GLB，整包 zip 要免費帳號。
- 結論：App 內附模型可以；放進公開 repository 的 GLB 或 `.m3dmodel` 是「檔案本身公開」，與「files as standalone assets stay here」衝突，所以只能放私庫。
- 疑慮：Polyfork 自稱「AI-native」，素材是程式生成的；網站沒有說素材是否由 AI 生成、著作權歸誰（查不到）。`bridge.mjs` 對 AI 來源的輸入有另一條規定（README：AI 標記的輸入必須走 Meshy 入口），採用前要先問規劃 session。
- 首頁寫 2,692 個低多邊形素材、43 個 kit（親手查 API：43 個 kit）；第三方文章寫的數字較舊，不採用。

### 2.5 其他來源

| 來源 | 授權（官方頁） | 網址 |
| --- | --- | --- |
| Poly Pizza | 官方授權頁抓不到（403）。從搜尋結果看：Kenney、Quaternius 的上架模型標 CC0，「Poly by Google」的標 CC-BY 3.0，一個 credits 頁會混合多種。**逐模型不同**，Poly Pizza 本身的政策原文查不到 | https://poly.pizza |
| Poly Haven | 「Our assets are all licensed as CC0」「Anyone can then use the work in any way and for any purpose.」可轉載、可放進賣的產品；免署名 | https://polyhaven.com/license |
| ambientCG | 「All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal License.」 | https://docs.ambientcg.com/license/ |
| OpenGameArt | 接受 CC0、CC-BY 3.0/4.0、CC-BY-SA、OGA-BY、GPL。CC-BY：「You must state that you have used the work and credit the original artist.」CC-BY-SA：「If you make derivative works, you must distribute them under the same license」。「You must follow only one of the licenses.」逐檔不同 | https://opengameart.org/content/faq |
| Sketchfab | 逐模型不同。Standard 與 Editorial 兩種付費授權限制不同，Editorial 不可商用、不可用於宣傳。CC0 與 CC BY 的模型要看模型頁；CC BY 需署名、BY-NC 不可商用、BY-SA 須相同方式分享（用 CC BY-SA 的模型，改作也要同授權） | https://sketchfab.com/licenses 、https://help.sketchfab.com/en/articles/16152217 |
| itch.io 上的包 | 逐包不同。例：Low Poly Japanese Houses（3 棟房、1 面牆、2 種電線桿，FBX）「free for commercial use」但不是 CC0、不可轉售或原樣轉載（來自搜尋摘要，未讀原頁） | https://yarenkrmn.itch.io/low-poly-japanese-houses |
| Synty Studios（付費對照） | 有「單次購買」與「訂閱」兩種授權，原文寫「Under this licence, you will have perpetual rights to use the specific pack(s) you have purchased directly.」EULA 全文（是否禁止原檔進公開 repository、是否可用於手機遊戲）這次**查不到**；一般商用付費包都禁止轉載，但沒有原文，不下結論 | https://syntystore.com/pages/licences-overview |

## 3. 每個來源的內容與打分

### 3.1 Kenney —— L5 S4 C4 T4 Q5 K5 = **4.50**

- 內容（官方 3D 分類頁，部分列出）：City Kit（Roads／Commercial／Suburban／Industrial）、Car Kit、Train Kit（近 50 個模型，含軌道，1.1 版加了軌道）、Mini Characters、Nature Kit、Modular Buildings（約 90 個）、Building Kit（約 80 個）、Fantasy Town Kit 等。專案網頁版已經用過。
- 畫風：色塊簡單、明亮，接近「精緻模型玩具」；但色票偏飽和，要換成遊戲色票。
- 技術：GLB／FBX／OBJ 都有；用一張色票貼圖（colormap）。`bridge.mjs` 不收貼圖，所以要先在 Blender 把色票烘成頂點色或各材質平塗色，或走舊入口取樣（取樣是每個 8×8 區塊的平均，色票格子大，應該可行，這次**沒有測**）。面數：車 2,000+ 超過目標，人 700+ 超過目標，樹與建築可以。
- 缺：沒有台灣特色（騎樓、廟、夜市、機車、公車、台灣號誌）。`SOURCES.json` 自己也寫「Scooter (機車) and Taiwanese city bus models are absent」。
- 取得：免費，下載要點「Continue without donating」，不用帳號；也有付費的 All-in-1 合集。

### 3.2 KayKit —— L5 S4 C2 T4 Q5 K5 = **4.10**

- 內容：官方列 18 包，大多是奇幻、冒險、平台遊戲。跟專案有關的只有 **City Builder Bits**（32 個以上低多邊形模型，「Top-Down」，單張 1024×1024 漸層色票，可縮到 128×128）、Furniture Bits、Restaurant Bits、Prototype Bits、Forest Nature Pack（樹）、Characters／Character Animations（人與動作）。沒有鐵道。
- 畫風：圓潤卡通，比 Kenney 更「遊戲化」，與 Mapbox Standard 那種淡色不太一樣；色票貼圖小，換色容易。
- 技術：OBJ、FBX、glTF 都有；單張小色票，面數低（面數 UNVERIFIED）。
- 取得：免費；Complete KayKit Collection 的價格查不到。

### 3.3 Quaternius —— L3 S4 C5 T4 Q4 K4 = **3.90**

- 內容最廣：**Downtown City MegaKit**（315 個模組，波士頓／紐約風街廓，含窗戶內部著色器與頂點色磨損的 Unity／Godot／Unreal 專案）、Modular Streets（25）、Modular Train（15）、Public Transport（12）、Cars（8）、Simple Buildings、Ultimate Textured Buildings（76）、Stylized Nature MegaKit（116）、Ultimate Nature（150）、Universal Base Characters（26）、Cyberpunk Game Kit（71）。
- 畫風：寫實度比 Kenney 高一點，美式／歐式街景為主，台灣騎樓與透天厝也沒有；要大改才合。
- 技術：FBX／OBJ／Blend，部分有 glTF；多數用小圖集貼圖，部分是各材質平塗。
- 授權扣分見 2.3：若只當 CC0 用，授權會是 5、總分 4.50；若 QAL 適用，就不能放公開 repository。取得：免費，Source 版（Unity 專案）要付費或 Patreon 點數。

### 3.4 Polyfork —— L3 S4 C4 T5 Q5 K4 = **3.80**

- 內容（親手查 API）：43 個 kit，其中和本專案有關的：
  - **Countryside Railway**（102 個零件）：蒸汽機車、柴油機車、客車廂、貨車、軌道維修車、鐵道巴士、車站建築、貨場地磅、沿線樹（469 面）。
  - **Japanese Suburban City Street**（kit 標題在總表是「Little Tokyo kit」或相近名；API 內的 kit id 為 `japanese-suburban-city-street-baa482`，兩者是否同一個**未確認**）：外送機車（1,752 面）、號誌（606 面）、凸面反射鏡（502 面）、交通錐。這是目前所有來源裡**最接近台灣街景**的（機車、號誌、日式住宅街）。
  - Medieval Japan（寺廟殿堂 1,676 面、鐘樓 1,782 面）、New York City Kit（巴士 2,008 面、公車亭 308 面）、Chrome Arcology Transit（接駁巴士）。
- 畫風：統一調色盤與比例（「every part in a kit sharing one palette and one scale」），頂點色、沒有貼圖，與專案的「頂點色、平塗」路線相同。
- 技術：GLB，沒有貼圖，沒有 KHR_texture 擴充，**正是 `bridge.mjs` 要的輸入類型**；缺點是網格節點沒有名字要先改名，頂點不共用（檔案會比較大）。人物 3,700–4,900 面，遠超行動目標（≤500），不可用。
- 取得：免費，不用帳號可以直接取 GLB；有 MCP／REST API（`polyfork.dev/mcp`），可批次查詢與下載；整個 kit 一個 zip（需免費帳號）。
- 授權扣分見 2.4：不能放公開 repository。另外網站太新，授權條款「Last updated October 2026」，有可能再改。

### 3.5 Poly Pizza —— L3 S3 C3 T4 Q2 K4 = **3.15**

- 是一個索引：收集 Kenney、Quaternius 以及 Google Poly 舊模型（CC-BY 3.0）等，GLB 為主，有 API（要免費帳號與金鑰）。
- 風格與面數混雜，同一來源以外沒有一致性，授權逐模型。**不建議當來源**：要 Kenney／Quaternius 的東西，直接去原作者的網站拿，授權與版本更清楚。

### 3.6 Poly Haven、ambientCG —— 3.15、2.95

- Poly Haven：模型分類有 Vehicles & Transport、Architecture、Industrial & Infrastructure 等，但多是掃描級高細節；HDRI 與貼圖是 CC0。對低多邊形玩具風不合（S1），模型數量與面數沒有查（API 讀取），UNVERIFIED。
- ambientCG：主要是 PBR 材質，CC0。專案不貼照片貼圖（art-style §7，決策 231、242 的淡灰階除外），只可能拿來取「清水模」等灰階細節的參考。
- 分數：Poly Haven L5 S1 C2 T2 Q3 K5；ambientCG L5 S1 C1 T2 Q3 K5。

### 3.7 OpenGameArt —— L2 S2 C3 T3 Q1 K5 = **2.55**

- 老牌站，CC0／CC-BY／CC-BY-SA／GPL 混合，Kenney 與 Quaternius 的包也有鏡像。每件要查授權，CC-BY-SA、GPL 要避開；風格不一致。只有「找單一冷門物件」時用。

### 3.8 Sketchfab（篩 CC0／CC-BY）—— L2 S2 C4 T3 Q1 K4 = **2.65**

- 可以找到非常特定的東西（台灣機車、廟、騎樓可能有人做過；這次沒有逐一搜尋，UNVERIFIED），但每個模型的畫風、面數、貼圖都不同，常是高面數加 PBR 貼圖，要重做才合風格；CC BY 要署名（要在遊戲內致謝清單），模型頁的作者可能改授權（Sketchfab 說「你取得時的授權」仍有效）。適合當**參考圖**，不適合當批次來源。

### 3.9 itch.io 上的低多邊形包 —— L2 S3 C2 T3 Q2 K4 = **2.50**

- 搜尋「Japanese street／city」只找到零散的小包（日式房屋 3 棟、日本店面等），沒有找到 CC0 的台灣或日本街景 3D 包。逐包授權、逐包風格。Eclair Assets 有幾個 CC0 GLB 小物（路燈、消防栓，從搜尋摘要，未讀原頁）。不建議當主要來源。

### 3.10 Synty Studios（付費對照）—— L2 S3 C4 T3 Q5 K2 = **3.00**

- POLYGON 系列有 City、Town、Station 等，畫風平塗低多邊形，一致性是頂級；缺點：付費，授權要買才能讀 EULA 全文，大概不能進公開 repository（原文查不到，不下結論），貼圖是圖集，不是頂點色。品牌辨識度高，很容易讓人認出是「Synty 的風格」，與「不要像從別的遊戲搬來的」衝突。

## 4. 總分排名

| 排名 | 來源 | L 30% | S 15% | C 20% | T 15% | Q 10% | K 10% | 總分 |
| --: | --- | --: | --: | --: | --: | --: | --: | --: |
| 1 | **Kenney** | 5 | 4 | 4 | 4 | 5 | 5 | **4.50** |
| 2 | **KayKit** | 5 | 4 | 2 | 4 | 5 | 5 | **4.10** |
| 3 | **Quaternius** | 3 | 4 | 5 | 4 | 4 | 4 | **3.90** |
| 4 | **Polyfork** | 3 | 4 | 4 | 5 | 5 | 4 | **3.80** |
| 5 | Poly Pizza | 3 | 3 | 3 | 4 | 2 | 4 | 3.15 |
| 5 | Poly Haven | 5 | 1 | 2 | 2 | 3 | 5 | 3.15 |
| 7 | Synty（付費） | 2 | 3 | 4 | 3 | 5 | 2 | 3.00 |
| 8 | ambientCG | 5 | 1 | 1 | 2 | 3 | 5 | 2.95 |
| 9 | Sketchfab | 2 | 2 | 4 | 3 | 1 | 4 | 2.65 |
| 10 | OpenGameArt | 2 | 2 | 3 | 3 | 1 | 5 | 2.55 |
| 11 | itch.io 單包 | 2 | 3 | 2 | 3 | 2 | 4 | 2.50 |

**只看「能放進公開 repository 的」**：Kenney 4.50 > KayKit 4.10 > Poly Haven／ambientCG（風格不合）；Quaternius 與 Polyfork 要等授權確認，才能放進這個清單。

**敏感度**：若 Quaternius 的 CC0 頁面被確認（授權 3→5），它變 4.50，與 Kenney 並列第一；若 Polyfork 作者同意公開 repository 內放轉換後的模型（3→5），它變 4.40，排第三。授權權重 30% 時排名只在這兩家之間會變，前兩名與最後幾名不變。

## 5. 五個角度的建議

- **玩家**：先用 Kenney（車站前的商店街、樹、路燈、軌道零件）補地圖空白；台灣特徵（機車、公車、騎樓、廟）所有免費來源都缺，玩家一看就知道不是台灣，這些仍然要靠程式配方自己做（`Map3D*Kit`），素材只當比例與構造的參考。
- **鐵道迷**：Polyfork 的 Countryside Railway 與 Quaternius 的 Modular Train／Public Transport 是歐美外型，不能直接代表台鐵車型；鐵道迷要認得出車型（art-style §7），列車繼續自己做（rolling-stock skill）。素材只適合沿線設施（號誌、月台零件、信號機、地磅）。
- **開發**：先用 CC0 的（Kenney、KayKit），沒有法律疑慮、可以放公開 repository、可以直接進 `SOURCES.json`；轉檔前先在 Blender 把色票烘成頂點色並改名網格節點，然後用 `bridge.mjs`；每個進模型包的模型都要記面數與增加的 MB（K1-1）。Polyfork 的 GLB 最容易轉（沒貼圖），但只能放私庫。
- **美術**：第一輪試做放在 Kenney City Kit（Commercial／Suburban）＋Nature Kit，換成遊戲色票後和現有透天厝並排看；KayKit 的圓潤造型與現有風格不一致，除非作者喜歡，不要混用。Quaternius 要大改比例才有台灣感，成本高。Polyfork 的 Japanese Suburban Street 是最接近台灣街景的，但也是日本風，要改窗、招牌、屋頂。
- **音樂**：無。這些來源都是 3D 模型。（Kenney 另有音訊分類，這次沒有逐包查證。）

## 6. 建議做法（排序）

1. **先用 Kenney**（CC0）：City Kit（Suburban／Commercial／Industrial）、Nature Kit、Train Kit 的軌道段與月台類零件、Modular Buildings。
2. **KayKit City Builder Bits** 當第二來源，只在需要小型街道零件時用。
3. **Quaternius**：先去信確認哪些包是 CC0，並在下載當天存頁面文字與雜湊。確認之前當作「只能放私庫」。
4. **Polyfork**：只放私庫當參考與預覽。想放進 App 打包的檔案，先問作者條款是否允許「公開 repository 裡含轉換後的模型」，並確認素材是否由 AI 生成。
5. **不要用**：Poly Pizza（不如去原作者那裡拿）、OpenGameArt、itch.io 單包（逐檔授權、風格不一致，不值得審查成本）、Synty（付費、風格太有辨識度、授權原文未取得）。
6. **只能放私庫當參考**：Quaternius（未確認前）、Polyfork；Sketchfab 的模型只拿來看構造，不進 repository。

## 7. 這份研究沒做的事

- 沒有逐包下載 Kenney、KayKit、Quaternius 量面數與貼圖，只量了 Polyfork 的 4 個，Kenney 的面數引用 `SOURCES.json`。
- `bridge.mjs` 對 Polyfork 的 GLB **沒有轉成功**（節點沒名字被拒）；對 Kenney 色票的取樣沒有測。
- 沒有逐一搜尋 Sketchfab 的台灣模型，也沒有查 Poly Pizza 官方授權頁（403）、Synty 的 EULA 全文、KayKit 付費包價格、Quaternius 哪些包屬於 QAL。
- 沒有寫信給任何作者；沒有放進任何素材檔。
