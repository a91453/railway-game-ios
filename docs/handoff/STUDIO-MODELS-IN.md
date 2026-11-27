# STUDIO-MODELS-IN：審過的工作室模型接進遊戲

## 進度

- 做到哪：上架前的三批（熊本城與水前寺、佛光山與野柳、香港三座廟）已合（#2768，決策 1018）；地標預算改成分區算、懸吊式單軌換 revision-3 是決策 1018 續。
- 已驗證：見 PR 的「驗證」一節。
- 之後接的：N700S かもめ塗裝（#2778，決策 998 續）、小倉城與唐津城（#2780，決策 1018 續 2）已合，兩件的經驗檔都改成已接（素材庫 -2 #573、#574）。
- 門司港三件與水前寺能樂殿、兩座石橋（決策 1018 續 3，規劃 4 分支 `claude/project-thread-4jg8o2`）已接；下面順序 1 做完。
- 淡水線高架站 r5 重轉、筑後川昇開橋、太宰府天滿宮三件、宗像大社／祐德稻荷／青井阿蘇、通潤橋與天門橋（決策 1018 續 4，規劃 4 分支 `claude/project-thread-goqu5m`）已接。登錄多了選填的 `replaces`（OSM 把好幾棟畫成一塊、模型只取代其中一部分時用，太宰府本殿第一個用）。太宰府的迴廊沒有模型，中庭是空地；天門橋一端的路比橋面低 12 m、通潤橋兩端比遊戲畫的地面高，都還沒在畫面上看過。
- 第二張（西螺與大樹鐵橋、小琉球客輪、無棚電停、水泥車與筒倉、大村車廠；決策 1033）在另一串做。
- 下一步：0.6.1 的項目照下面的順序派單，從順序 3 香港童話樂園開始（順序 2 已接）。

雲端工作串，分支 `claude/project-thread-qzu8e8`。存檔版本、golden schema、GameCore 都不動。對照表在專案共用資料夾 `studio-models-in/INVENTORY.md`，摘要在決策 1018 §1。原本登記的 1019、1020 已釋出。

## 怎麼接一件地標（照決策 895 的登錄制）

1. 用 `tools/landmarks/glb_to_swift.py` 把工作室的近景、遠景 GLB 轉成 `Map3D<Name>Mesh.swift`：`--materials` 照 GLB 材質順序、`--centre` 讓外框中心在原點、模型方位不對就 `--turn`（逆時針為正）、底要埋進地裡就 `--raise` 並在登錄寫同樣的 `sink:`。
2. 寫 `Map3D<Name>.swift`：調色盤只用 `Map3DPalette` 的色（`Map3DPaletteGuardTests`；工作室挑的是別的模型的色，就照決策 1018 §2.3 加進 `Map3DPalette` 並刪掉 `tools/palette-guard/baseline.txt` 對應那行），id 要寫成 `Map3DLandmarkRegistration(id: "…"` 字面（測試從原始碼找），登錄的經緯度用 OSM 的輪廓或節點，`size` 照轉檔印出的尺寸。
   - 登錄的 `id` 要等於 GLB 檔名（`encoded` 用檔名當鍵），不然模型解不出來，鎖檔會寫成 0 個三角形。
   - `--centre` 移的是**轉好之後**的外框中心（工具印出 `footprint middle … east`）；工作室原點在 OSM 外接矩形中心、模型一端窄（小倉城的付櫓）時，登錄的經緯度要照印出的位移移過去。
3. `Map3DLandmarkRegistryList.swift` 加一行。
4. `LANDMARK_LOCKS_WRITE=1 swift test --skip-build --filter Map3DLandmarkRegistryTests` 寫鎖檔 `tools/landmarks/locks/<id>.json`，再不帶變數跑一次。
5. PR 說明寫經驗檔 `railway-assets-private-2` `docs/studio/lessons/<model>.md`（`lessons-link.yml`）。
6. 預算（決策 1018 續，`Map3DLandmarkRegistryTests.testTheBudgets`）：任一塊 32 km 見方裡的近景合計 ≤ 60,000 三角形（台灣最滿的一塊 23,602）；整張地圖所有地標近景加遠景 ≤ 20 MB（台灣 9.9 MB）。

同一個模型擺好幾處（佛光山八塔、野柳蕈狀岩）照 `Map3DFukuokaTanks` 的 `model(_:as:)`（或 `Map3DFoGuangShanPagodas.model(as:)`）：同一份編碼，給每一處自己的 id。

## 0.6.1 的順序（要改規則、影響效能或要先補模型）

| 順序 | 素材庫資料夾 | 要先做的 |
| --: | --- | --- |
| 1 | `suizenji-garden-2026-11` 能樂殿、兩座石橋 | **已接**（revision-4 補了遠景，決策 1018 續 3） |
| 2 | `kumamoto-station-2026-11`、`duoliang-station-2026-11`（`tw-rail-ref-landmarks-2026-11` 的多良站同一件） | **已接**（決策 1020：第 1～3、5 條；博多站同一張修好）。第 4 條（站房來源順序、月台對準 OSM）是 (c) 單 |
| 3 | `hk-dream-castle`、`hk-park-layout`、`hk-park-main-street`、`hk-park-rides`、`hk-park-zones-north`、`hk-park-zones-south`（皆 `-2026-11`） | 童話樂園整座一起擺，照 `hk-park-layout` 的配置；會轉的設施要動畫（`motion` 技能），香港地圖預算約 20,132，七件加起來先算 |
| 4 | `hk-ocean-park-landmarks-2026-11` | 摩天輪會轉、纜車要畫線 |
| 5 | `estate-amusement-park`、`estate-department-store`、`estate-hotel-tower`（皆 `-2026-11`） | 換玩家蓋的建物外觀；遊樂園要慢轉 |
| 6 | `pedestrians-2a`、`pedestrians-2b`、`scooter-old`（皆 `-2026-11`） | 路人款式池、分區權重、機車數量預算；先量效能 |
| 7 | `meshy-temple-animals-2026-11` | 寫擺在廟前哪裡的規則 |
| 8 | `viaduct-shops-2026-11` | 高架下開店的規則（另一張程式單） |
| 9 | `kumamoto-tram-lowfloor-2026-11`、`hk-peak-tram-car-2026-11` | 遊戲還沒有熊本市電、山頂纜車的路線；有路線才接 |

## 車站地標的規則（Chien 2026-11-27 定）

Chien：「都可以依你覺得對遊戲最好的方式，但記得車站的規則要統一」。所以熊本站、博多站（已登錄的 `Map3DHakataStation`）和之後的每一座車站都照同一套。分三張（Chien 同日：「感覺是個大工程，每條收購線跟台灣已做的站房要對準」；不是一站一站手調，而是一套共用規則加一支量測工具）：(a) 第 1～3、5 條：熊本、博多、多良；(b) 量測工具：每張地圖每個能收購的站，量遊戲月台和 OSM 月台的偏差、站房足跡和軌道的重疊，先出一張表，不改遊戲；(c) 照表把第 4 條的規則套到所有地圖，量出來對不上的少數站才個別處理，台灣先做（月台資料已在 App 裡）。各張派工前照 §19 評分。已知歪很多的站（Chien 記得）：台南的舊地面站（站房是決策 626／665 的外觀研究 `Map3DStationExteriorBatch2.tainan`，照 OSM 位置放；收購鋪的月台沒照 OSM 月台，兩者對不上），(b) 的表和 (c) 的測試要包含它，修好要拍改前改後：

1. **買線後照樣顯示。** 現在 `isClearOfTrack`（`Map3DTaipeiLandmarks.swift`）只要地標外框裡有非隧道的軌道或月台就整件不畫，所以九州新幹線一買，博多站就消失，熊本站接了也會。車站地標不套這條，改成檢查：遊戲鋪的高架與月台落在模型留的空間裡（熊本站模型留四座 OSM 月台、Z 10～16.5 m）；不在裡面就不畫並在測試裡變紅，不是悄悄消失。
2. **取代遊戲自己的站房與雨棚，只留月台。** 那一站不畫遊戲自蓋的站房、雨棚（找 `RealLineAcquisition` 的站與 `Map3DStudioStation` 怎麼換台灣站房，讀 `real-line-laying` 技能），免得兩棟疊在一起。`Map3DStudioStation`（工作室站房換台灣站房）也用同一套判斷。
3. **沒買線也顯示**，當地景。
4. **站房的來源順序（Chien 同日：「月台要整合既有存在建物」，看 Overture 畫的月台與站房擺法）。** 每一站的站房照這個順序挑一個，所有地圖都一樣：工作室的車站模型（熊本、博多）→ 決策 625 的站房外觀研究 → **真實足跡**（官方或 Overture/OSM 在站點附近標成交通用途、或 OSM `building=train_station` 名稱對得上的那棟，留下來當站房，不再因為碰到站的格子被 `underRailway` 拿掉）→ 遊戲自己的站型套件。Chien 同日：「類似覆蓋車站的3d建物模型做法 先套用真實模型 再移除3d建物那層」：先放挑到的站房模型，再把它底下的 Overture／官方 3D 建物那層拿掉（地標已經這樣做：`underLandmark`、`replacedPlots`，決策 791、879），不是先清空再補。月台仍由遊戲鋪（玩法要用），位置跟著真實軌道，島式／側式已照 OSM（決策 741）。Chien 同日：「那月台記得對準一點」：遊戲鋪的月台要對準 OSM 的 `railway=platform` 輪廓（中線橫向、兩端），量每站的偏差寫進決策，偏太多的站要修到對上，並加一個測試守住偏差上限（上限照量到的數字定）。11-27 查過現況：收購沿 OSM 軌道中心線鋪，所以橫向大致在軌道上，島式隔 11 m、岸式隔 5 m（決策 760）；但月台沿線的位置與長度是照站點和站等的長度推的，不是照 OSM 的月台。台鐵各站 OSM 月台兩端已經在 App 裡（`tra_platforms.json`，`RealStationData.platform(forStation:)`），卻沒有程式在用；日本、香港、芬蘭的地圖還沒有這份資料。先例是決策 625（真實站房照 OSM 位置放、切開讓出軌道）。要先做的：量每張地圖有幾站配得到真實足跡；跨站式站房（橫跨軌道）要抬到軌道上方或切開；高架站底下的建物不當站房；改了很多站的樣子，要拍改前改後給規劃看。
5. **多良站**不是遊戲的車站（龍溪與金崙之間的廢站，只在 `AttractionCatalog` 是 t142），當跨在南迴線上的風景地標：軌道從兩座月台中間穿過（間隙 8.1～9.8 m，要對列車寬度）、模型軌面 Z 0 對齊遊戲的軌道高度（不是地面；模型擋土牆到 Z −2.5，用 `--raise 2.5` 與同樣的 `sink`）、先確認遊戲在那一段是單線還是雙線、算台東那一塊 32 km 見方的預算。它也照第 1 條：軌道穿過時照樣畫。

`tw-rail-ref-landmarks-2026-11` 裡的大佛已由 `fgs-big-buddha-2026-11` 取代，不接。

## 決策 1033：要寫程式的五件（規劃 4 串「接入鐵橋、客輪、電停和水泥貨車」，分支 `claude/project-thread-v1klmk`）

- 第一張 PR：西螺大橋、大樹舊鐵橋（逐跨擺，`Map3DTrussBridges.swift`）與小琉球高速客輪（`Map3DFerry.Boat.liuqiu`）。
- 第二張 PR：無棚電停（路面軌道的短側式月台代替有雨棚的月台）、水泥貨車與筒倉（建材貨物的外觀，偶數編號的站是筒倉）、大村車輛基地（遊戲沒鋪這座機廠，改成兩個登錄地標，登錄地標加 `body`）。規則寫在決策 1033 的「續」。
- 之後：熊本市電上線時用無棚電停；真的要鋪大村機廠（玩法）時先讀 `depot-work`。

## 還要做的（素材庫那邊）

各批合併後，在 `railway-assets-private-2` 開一張 PR，把接了的模型的經驗檔「接回遊戲」一節改成已接（附遊戲 PR），並更新 `MODEL-INVENTORY.md`。
