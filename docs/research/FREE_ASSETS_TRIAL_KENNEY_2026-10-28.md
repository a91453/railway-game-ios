# Kenney 免費素材試做（派工單 BJ，2026-10-28）

接 `FREE_3D_ASSET_SOURCES_2026-10-28.md`（派工單 BE）§6 第 1 項：先只做 Kenney（CC0）。這次是試做，**沒有接進遊戲**，沒改 `Sources/`；真正接進 `Map3DModelPack` 另開一張，等派工單 BF（模型包瘦身，改 `Map3DModels.swift`）合併之後。

成品、預覽、授權全文與重建指令都在 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/free-assets-kenney/`（`SOURCE.md`、`revision-1/README.md`，PR #11）。本文只寫結論。

## 1. 下載了什麼

2026-10-28 從各包頁面的「Continue without donating」下載，zip 的 SHA-256、頁面版本、zip 裡 `License.txt` 的版本與日期都記在私庫的 `SOURCE.md`；授權全文（各包 `License.txt`、CC0 1.0 法律條文）存在 `revision-1/licenses/`。

| 包 | 版本 | GLB 數 | 面數（中位數／最多） | 格式 | 授權 |
| --- | --- | --: | --- | --- | --- |
| City Kit (Suburban) | 2.0 | 40 | 800／2,062 | 一張外部色票貼圖＋`KHR_texture_transform` | CC0 |
| City Kit (Commercial) | 2.1 | 41 | 246／5,246 | 同上 | CC0 |
| City Kit (Industrial) | 2.0 | 37 | 876／2,422 | 同上（太陽能板多一張高光色票） | CC0 |
| Nature Kit | 頁面 1.0，`License.txt` 2.1 | 329 | 76／720 | 每個材質一個平塗色＋`KHR_materials_unlit` | CC0 |
| Train Kit | 1.1 | 103 | 416／1,944 | 色票貼圖 | CC0 |
| Watercraft Kit（查港口用） | 2.1 | 46 | — | 色票貼圖 | CC0 |
| Pirate Kit（查碼頭用） | 2.1 | 72 | — | 色票貼圖 | CC0 |

七包每個 GLB 的面數、節點、材質在私庫的 `revision-1/inventory.json`（668 個）。

**能不能進遊戲（每包）**：

- **授權**：七包都是 CC0（頁面「License: Creative Commons CC0」、`License.txt`、Kenney 支援頁），可以打包進 App、放進公開 repository、改作、免署名；只是不能用 Kenney 的 logo。
- **面數**：Nature 的樹、灌木、石頭（幾十到兩百面）遠低於行動裝置的預算；City Kit 的整棟建築 1,000–5,000 面偏重；Train Kit 的列車 1,000–1,900 面（列車本來就由 rolling-stock 自己做，不採用）。
- **風格**：Kenney 原色飽和（青綠的葉、橘色樹皮、正紅貨櫃），換成遊戲色票之後和自家的住宅、商業套件放在一起，顏色看不出差別；但造型比自家套件粗、簡單（見 §3）。Train Kit **沒有月台零件**（只有軌道、列車、車廂），月台由自家車站套件負責。

## 2. 轉檔：`bridge.mjs` 能轉 Kenney，但要先烘

- **原檔直接轉被拒**：Train Kit 的 `track.glb`「textures are unsupported」；Nature Kit 的 `tree_default.glb`「unsupported extension KHR_materials_unlit」。
- **先烘再轉，13 件全部成功**：私庫的 `scripts/bake.py` 讀色票（三角形重心 UV 的顏色）或平塗材質，換成遊戲色票（`Map3DPalette` 與它在 `Map3DBuildings`、`Map3DShopStreet`、`Map3DOverheadLine` 的延伸），烘成頂點色，寫成只有 POSITION／NORMAL／COLOR_0 的 GLB，網格節點保留 Kenney 的名字（`bridge.mjs` 的白名單要名字；BE 時 Polyfork 沒轉成功就是卡在這裡，Kenney 的節點都有名字）。
- 換色的規則：Nature 照材質名直接對到遊戲的角色色（葉→`crown`、樹皮→`trunk`、草→`embankment`）；有色票的在 CIELAB 裡彩度乘 0.5、明度拉高，再找最近的調色盤色。轉換器最後把每件縮成最多 8 色。
- **兩個坑**，接進遊戲時照做：
  1. `tools/glb-to-m3dmodel` 的轉換器把 COLOR_0 當 sRGB 直接乘（和它讀 `baseColorFactor` 一樣），不是 glTF 規定的線性值；照規範寫線性值整件會暗一截。
  2. Kenney Nature Kit 的材質色寫的是 sRGB/255，不是線性值。

## 3. 試做的 10 件＋港口 3 件

和自家的窄面透天厝、騎樓透天厝、便當店、手搖飲店（住宅、商業套件）並排，七向 × 3 種（換色後／Kenney 原色／港口），私庫 `revision-1/views/`。總覽：`lineup-game-palette-isometric.png`。

一份記憶體 = 三角形 × 3 × 40 bytes（`Map3DVertex`，審查 K1-1 的算法），CPU、GPU 各一份。

| 件 | 位置 | 面數 | `.m3dmodel` | 一份 | 自家已有 | 結論 |
| --- | --- | --: | --: | --: | --- | --- |
| tree_pineTallA（針葉樹） | 自然（山區、高海拔路段） | 78 | 4.8 KB | 0.009 MB | 沒有針葉樹 | **建議進**，連同 Nature Kit 其他 pine 2–3 種 |
| plant_bushLarge（灌木） | 站前花台、沿線 | 60 | 3.9 KB | 0.007 MB | 沒有零散灌木（只有高架花圃、蕨、蘆葦） | **建議進** |
| detail-tank（臥式儲槽） | 沿線（工廠、貨場） | 308 | 16.8 KB | 0.037 MB | 只有 IBC 桶、屋頂水塔 | **建議進** |
| tree_default（闊葉樹） | 自然 | 114 | 6.7 KB | 0.014 MB | `Map3DProp.tree`、工程套件 `leafyTree` | 不進（重複） |
| tree_palmTall（椰子樹） | 站前、沿線 | 190 | 10.6 KB | 0.023 MB | 工程套件 `palmTree` | 不進（重複） |
| detail-parasol-a（陽傘） | 站前 | 96 | 5.7 KB | 0.012 MB | 商業套件 `cafeUmbrellaSet`、`umbrellaTable` | 不進（重複） |
| detail-awning-wide（遮雨棚） | 站前 | 40 | 2.8 KB | 0.005 MB | 站前商店街的店棚、`retractableAwning` | 不進（重複；Kenney 的是沒有牆的獨立棚，接不上騎樓） |
| solar-panel-landscape-group（地面太陽能板） | 沿線 | 976 | 51.5 KB | 0.117 MB | 車站套件 `solarArray`、住宅 `roofSolar` | 不進（重複，且 976 面偏重） |
| windmill（風機） | 沿線（西部海岸） | 456 | 24.5 KB | 0.055 MB | 沒有 | 不進：葉片粗短、塔身像玩具；拉到台灣風機的 90 m 輪轂高度時一看就不像。要做就寫自家配方，Kenney 只看構造 |
| railroad-straight（軌道段） | 軌道 | 376 | 20.3 KB | 0.045 MB | 遊戲照路線逐段畫道碴與鋼軌 | 不進：固定 9.6 m 一段的磚塊接不上程式畫的曲線與坡度；轉檔可行已確認 |
| ship-cargo-a（貨輪） | 港口 | 1,058 | 55.8 KB | 0.127 MB | 沒有 | 只當參考（§4） |
| boat-tug-a（拖船） | 港口 | 469 | 25.1 KB | 0.056 MB | 海岸套件只有小漁艇 | 只當參考 |
| structure-platform-dock（木碼頭） | 港口 | 324 | 17.6 KB | 0.039 MB | 工程套件 `woodenJetty` | 不進（重複，海盜風木樁） |

- **10 件合計** 2,694 面、`.m3dmodel` 147,548 bytes，模型包一份多 0.32 MB（兩份 0.65 MB）。
- **建議進的 3 件** 446 面，一份 0.05 MB；加上 Nature 另外 2–3 種針葉樹與 2 種灌木，估計 1,000 面以內、一份約 0.12 MB。模型包現在一份 168 MB（K1-1），增加不到千分之一；街道設施是畫實例，件數多不增加模型包。
- 第一次挑選量過、沒進本輪的：water-tower 968 面（美式鐵架水塔，台灣少見）、shipping-container-a 389 面（工程套件已有 20／40 呎貨櫃）、low-detail-building-a 188 面（遠景大樓，遊戲已用真實建物足跡擠出）。
- 本輪沒試、下一輪可以看的：Nature Kit 的石頭與崖壁（`rock_*`、`cliff_*`，給河谷、海岸、山區路段）、農作物（`crops_*`，給田）。

## 4. 港口：貨輪、港口吊車、碼頭（NEXT_PRIORITIES §22.2 第 18a 名「新車抵台卡」3D 版）

- **港口吊車**：Kenney 沒有（搜尋 crane、harbor、dock、pier 都沒有結果；City Kit Industrial 也沒有）。自家工程套件有 `gantryCrane`（貨場門式起重機），但碼頭邊卸櫃的岸邊起重機沒有。
- **貨輪**：Watercraft Kit 有 `ship-cargo-a`（1,060 面）、`ship-cargo-b`（850）、`ship-cargo-c`（362），還有 `ship-large`（1,849，帆船）、`ship-ocean-liner`（2,796，郵輪）、`boat-tug-a`（471）。都能轉；但船身長寬比約 2.7 比 1（真的貨輪約 7 比 1），甲板上的貨箱是真貨櫃的四倍大，和自家 20 呎貨櫃並排時一看就是玩具（`lineup-port-candidates-*`）。
- **碼頭**：Pirate Kit 有 `structure-platform-dock`（324）、`structure-platform-dock-small`（312）、`platform-planks`（48），都是木樁海盜風；Watercraft Kit 有 `cargo-container-a`（160）、`cargo-pile-a`（176）、`ramp-wide`（128）。
- **對 18a 的意思**：3D 版的港口要自己做貨輪船身與岸邊起重機（照工程、海岸套件的配方做法），自家已有的貨櫃、門式起重機可以直接用；Kenney 只提供參考構造，不提供能直接上場的件。3D 版的成本因此比「有現成船與吊車」高，維持遊戲規劃原本「先做 2D 插畫卡」的排法。

## 5. 五個角度

- **玩家**：真正補到畫面的是針葉樹（自家套件沒有針葉樹，山區也是闊葉樹）、灌木（站前與沿線的空地）、臥式儲槽（工業區）；其餘自家都有了，換來換去玩家看不出差別。
- **鐵道迷**：Train Kit 沒有月台、只有美式列車與固定長度的軌道段，對台鐵沒有用；港口貨輪比例不對，新車抵台的畫面不能用它。
- **開發**：CC0 沒有授權疑慮；`bridge.mjs` 先烘就能轉，3 件只多 0.05 MB；但每件都要記來源、照 art-style §7 改造形狀，接進去時與 BF 的模型包測試（頂點數鎖）一起改。
- **美術**：換成遊戲色票之後顏色合得上；造型比自家套件粗，放在近景會顯得廉價，所以只建議放樹、灌木、儲槽這類遠看、量多的東西，建築與站前小物不用 Kenney。
- **音樂**：無。

## 6. 下一步（另派）

1. 等 BF 合併後，把 3 件（加 Nature Kit 的針葉樹 2–3 種、灌木 2 種）接進 `Map3DModelPack`：先照 art-style §7 改造（例如針葉樹改成自家樹幹、層數與比例重組，灌木合併成不同大小的叢），再轉檔；`.m3dmodel` 進 App 的第一張 PR 照 `tools/glb-to-m3dmodel/README.md` 加 glTF-Validator。
2. 放置：針葉樹照地形高度放在山區、灌木放站前廣場與沿線、儲槽放工業用地。
3. 下一輪可試 Nature Kit 的石頭、崖壁與農作物；KayKit 只在 Kenney 缺的小件時才看（本輪沒用到）。

## 7. 驗證

- VERIFIED（Linux，本 session）：七包下載與雜湊；原檔被 `bridge.mjs` 拒絕；烘後 13 件 `bridge.mjs` 轉檔成功；`scripts/build.sh` 重跑後 13 個 `.m3dmodel`、13 個 GLB、21 張 PNG 與私庫的檔案逐位元相同；七向預覽是 Chromium WebGL（swiftshader）拍的。
- UNVERIFIED：iPhone Metal 上的樣子與效能；接進模型包之後的實際記憶體（上表是用頂點數推算的）。
