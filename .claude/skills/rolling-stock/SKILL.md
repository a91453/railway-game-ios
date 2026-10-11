---
name: rolling-stock
description: 3D 城市畫面裡的列車：怎麼依照片做一款新車、怎麼檢查、怎麼給作者看。做或改 Web/CityView/src/world/trains.js 的車輛外型、塗裝、編組時先讀。Use before adding or changing a train in the 3D city view (Web/CityView/src/world/trains.js) — car shape, livery, formation, or when judging whether a train looks right.
---

# 3D 城市的列車

城市畫面（ARCHITECTURE 決策 152、161）裡的列車全部由 `Web/CityView/src/world/trains.js`
畫出來。這份寫下做一款新車要知道的約定、要跑的檢查，以及 2026-10-11 做台灣高鐵 N700ST
時踩過的坑。

## 1. 先決定：畫，還是生成

**預設用程式畫。** 2026-10-11 用 Meshy 生 N700ST 花了 45 點，兩次都不能用：

| 方式 | 點數 | 結果 |
| --- | --- | --- |
| 照片轉 3D | 15 | 塗裝像，但長寬比 1.9（真車 8.1）：斜拍的照片看不到車身長度 |
| 文字轉 3D | 30 | 比例對，但 391,054 個三角形，橘色帶只剩一條看不見的細線 |

原因是結構性的，不是 prompt 寫不好：列車是**規則的工業造形加上固定高度的精確塗裝**，
擴散式模型兩樣都做不到。整列 12 節用程式畫是 3,312 個三角形，色帶位置寫死在程式裡。

生成只在**不要求精確、形狀不規則**的東西上划算（雜物、樹、一次性地標）。找現成模型也查過：
GitHub 上的 Shinkansen repo 都沒有 LICENSE 檔，CC0 素材庫沒有高鐵，Sketchfab 的 CC-BY
標示和說明互相衝突。**沒有授權可用的現成模型。**

## 2. 約定（照著做，不要自己發明）

- **座標**：`+Z` 是行進方向（車頭朝 +Z），`+Y` 上，軌面 `y = 0`。`dummy.lookAt` 已經假設 +Z 朝前。
- **尺寸**：車身寬 2.9 m；車頂 3.75 m；地板 1.0 m（方塊車）或裙擺下緣 0.62 m（放樣的殼）。
  每節車的幾何長度是 `stock.length - 0.6`（留車間縫）。
- **一個 stock 一個材質**，貼圖是一張 2048 × 512 的 canvas：
  - 最上面 16 px 是純色色票（`plainUv(geo, u)`：`u = 0.25` 車身色，`u = 0.75` 深色底盤）；
  - 16–256 px 是車側；其餘留白。
  - 方塊車：車側佔滿寬度，車頭另外畫在左下角。
  - 放樣的殼：**左半是頭車、右半是中間車**，`u` 沿車身、`v` 沿斷面高度。
- **第二張貼圖是夜間發光**（`emissiveMap`）：車窗、頭燈、方向幕畫在上面，白天 0.2 強度。
- **面數預算**：整列 400 × 節數個三角形。手機上同時有好幾列。

### 放樣的殼（有車頭的車）

`shellRing(z, t)` 回傳一圈點，`t` 是沿車頭的參數（0 在車身交界、1 在鼻尖）。每個點帶著
**自己在那一圈裡的相對高度**，那就是貼圖的 `v`。所以貼圖上畫一條**直的**橫帶，到了車頭會
自己被斷面的收縮拉成往前下方掃的曲線——和真車上漆的方式一樣，不用手算曲線。

斷面是超橢圓，稜線以下比以上飽滿（真車車身是圓角矩形，不是橢圓），稜線處微微外鼓成翼線。
最後 12% 收口（`cap`），否則鼻尖會是一個平切面，**只有正面角度看得出來**。

## 3. 先去參考庫拿數字

作者的參考庫（`a91453/railway-reference-private`，CLAUDE.md 授權直接取用）裡有做好的車隊資料。
開工前先接上：`add_repo` 之後 `git clone --depth 1 … /home/user/railway-reference-private`。

| 路徑 | 是什麼 | 信不信 |
| --- | --- | --- |
| `Railway/…/memories/*/fleet/catalog.json` | 13 款車的工程尺寸（`pitchM`／`widthM`／`heightM`／`roofM`／`floorM`／`role`）**每筆附出處** | **信**。這是第一手的尺寸來源，比網路搜尋可靠 |
| `OpenWorld/…/taiwan-tra/*.glb` | 作者做的整列模型（EMU3000、普悠瑪、太魯閣） | **顏色信，形狀不信**（見下） |
| `Railway/…/rail-3d/assets/blender-map-v1/` | 40 款車的 LOD 網格與 `manifest.json`（含 700T） | 同上；`manifest.json` 標 `illustrative: true` |
| `Railway/…/data/tra_special_trains.json` | 作者寫的車種說明 | 信（塗裝的文字描述） |

**參考模型不是拿來出貨的，是拿來量的。** 作者的 EMU3000 GLB 是 199,588 個三角形，
這裡整列 12 節約 3,300 個。但它比照片好用：沒有透視、不會把反光讀成塗裝、沒有看不到的另一側。

**而且要分辨它哪裡可信。** 2026-10-11 量 EMU3000 的 GLB：斷面在整列 245.7 m 裡從未收窄到
流線型該有的程度，每節車兩端都是圓頭——它沒有車頭，是示意用的地圖模型（manifest 自己標了
`illustrative`）。材質名稱卻是刻意分部位命名的（`Pearl_Livery`、`Signature_Red`、
`Smoked_Blue_Glass`…），顏色是作者的決定。**結論：顏色照抄，形狀另外找依據。**
量完一定要算圖看一眼再決定信哪部分。

```sh
node .claude/skills/rolling-stock/measure.cjs <reference.glb> \
  [--metres <真實全長>] [--pitch <車距>] [--slices 120] [--json]
```

它印出：整體尺寸、每個材質的顏色與**高度帶**（色帶的 row 從這裡讀）、以及沿車身的斷面。
參考模型通常是**整列**而不是一節，斷面會每一節車縮腰一次；`--pitch` 會把整列**折成**
一節頭車和一節中間車的斷面表，那就是放樣的 station。沒給 `--pitch` 它會自己從縮腰間距猜。

模型常常不是以公尺為單位（EMU3000 那個是 1/6.5）。寬度或高度小得不像車時用 `--metres`
給真實全長來換算，不要直接採用。

## 4. 流程

0. **先去參考庫量**（第 3 節）。有參考模型就用它，照片是補不足的，不是第一順位。
1. **再驗照片**。一張雜亂的照片會讓後面全白做。要求：主體佔畫面大部分、背景和車身分得開、
   整節車入鏡。白車配白背景（發表會的白坡道、亮螢幕）是最糟的組合。
2. **逐區看，不要整張看**。把照片切成九宮格逐區放大檢查，再放大鼻尖與車側兩處。
   整張看會漏掉東西——N700ST 車頭下半那一大片灰，就是這樣漏掉的。
3. **寫下識別特徵**，以及**這個視角看不到什麼**（車頂、車尾、另一側、轉向架通常都看不到）。
   看不到的就寫成假設，不要假裝知道。
4. **改 `trains.js`**：加一筆 stock、需要的話加塗裝分支。
5. **跑檢查**（下一節）。有紅的先修，不要先看圖。
6. **跑預覽，自己先看**（Read 那張 PNG），再用 SendUserFile 給作者。
7. **重新建置 App 的網頁**並提交（`trains.js` 一改，`RailwayGameApp/Resources/CityView/`
   的 bundle 就過期了）。臺中的圖塊資料不在雲端容器裡，所以只能重跑 vite 那一步；
   跑完逐檔比對，確認只有 `assets/index-*.js` 和 `index.html` 變了。

### 塗裝的四個坑（N700ST 四個都踩到了）

1. **車窗形狀**：先假設是方窗就錯了。新幹線是**小而直立的膠囊形、綠色玻璃**。
2. **門與色帶的先後**：門有深色框，而且**色帶是橫過門面的**。順序必須是
   門 → 色帶 → 車窗，寫反了色帶會被門切斷。
3. **下半身**：不是底部一條窄邊，是**一大片灰色**，而且車頭下半也是灰的。
4. **頭車的色帶不是水平的**：N700ST 的橘帶往車頭俯衝，上面壓一條深藍帶；中間車才是水平的。
   做之前先確認這款車的頭車和中間車塗裝是不是一樣。

## 5. 檢查與預覽

```sh
# 先裝一次 Web/CityView 的套件
(cd Web/CityView && npm ci)

NODE_PATH="$(npm root -g)" node .claude/skills/rolling-stock/preview.cjs \
  --stock hsr --out <scratchpad>/sheet.png          # 檢查 + 一張對照圖
NODE_PATH="$(npm root -g)" node .claude/skills/rolling-stock/preview.cjs \
  --stock hsr --check-only                          # 只跑檢查
NODE_PATH="$(npm root -g)" node .claude/skills/rolling-stock/preview.cjs \
  --stock tra --reference <ref.glb> --reference-metres 245.7 \
  --out <scratchpad>/compare.png                    # 和參考模型用同一組鏡頭並排
```

`--stock` 是 `hsr`、`tra`，或任何路線名稱（選車是依路線名稱，和畫面裡一樣）。
用環境內建的 Chromium，不下載東西。有檢查紅掉會以 exit 1 結束。

檢查都是**量實際算出來的幾何**，不是看宣告值：

| 檢查 | 它抓什麼 |
| --- | --- |
| 建得起來、沒有 console error | 寫錯的 stock 欄位 |
| 整列在面數預算內 | 一節車暴增到幾十萬面 |
| 沒有東西低於軌面 | 車沉進軌道（側面看不出來） |
| 每節車長度接近 `stock.length` | 縮放寫錯 |
| 沒有超出限界（寬 ≤ 3.2 m） | 同上 |
| 頭車有收窄（最小／最大**斷面積** ≤ 0.6） | 車頭做成一根粗細不變的管子 |
| 小的那端朝 +Z | 車頭裝反 |

斷面積而不是寬度：鴨嘴車頭**故意**到鼻尖都還很寬（照片為證），只是很扁；
用寬度判斷會把形狀推離真車。（這條檢查的想法來自 img2threejs 的 taper gate。）

對照圖有六格：斜前方、頭車正側、**正面**、中間車正側、整列、夜景，最後一格是模糊後的剪影。
給了 `--reference` 時每一列變成「我們的／參考的」並排，鏡頭完全相同——這是判斷形狀對不對
最可靠的方式，比對照片準。
**正面那格要看**——鼻尖的平切面只有從正面看得出來，N700ST 就是這樣抓到的。
剪影那格是因為玩家在城市畫面裡只會掃一眼，剩下剪影還認得出來才算數。

## 6. 現在做不到的事

- **貼圖沒有橫向座標**。`v` 只帶斷面高度，所以同一高度的一圈都會上到色。想畫一塊
  「只在車頭正中央、不繞到兩側」的東西（例如比較窄的擋風玻璃）做不到——現在的駕駛窗從正面
  看是一條橫跨全寬的黑帶。要解需要另一套 UV，還沒做。
- **硬稜線做不出來**。翼線目前只靠貼圖上一條淡影線，不是幾何的折邊。
- **駕駛窗是畫的不是幾何**，某些角度看是平的。
- **城市畫面沒有環境反射**（`environment.js` 的 `installSkyLight` 把環境貼圖反射關掉了，
  天光改由 light probe 提供）。亮面感只能靠色調映射和天光，不要指望反射。

## 7. 驗證怎麼寫

Linux 上能做的：`npm test`、`vite build`、這份 skill 的檢查與算圖。這些可以寫 **VERIFIED**。
App 裡的實際畫面要 macOS CI 與 TestFlight，寫 **UNVERIFIED**（CLAUDE.md）。
算圖用的是城市畫面相同的 ACES 色調映射與近似天光，但**不是** App 本身，不要寫成 App 驗過了。

## 8. 外部工具

- [img2threejs](https://github.com/img2threejs/img2threejs)（Apache-2.0）：照參考圖用程式重建
  3D 的 Claude skill。2026-10-11 跑到 blockout pass。**它的檢查值得學**（這份的照片驗收、
  逐區掃描、收窄檢查都來自它），但它的幾何語彙不適合列車：斷面只能是橢圓、重複系統只支援
  環狀排列（排不出車窗列）、無法表達硬稜線，一節車 10,440 個三角形。模型不用它做。
- Meshy：見第 1 節。流程在 `.claude/skills/meshy-3d-generation/` 與 `tools/meshy/README.md`。
- 畫 App 裡的 2D 圖（圖示、角色）是另一回事，看 `.claude/skills/art-style/SKILL.md`。
