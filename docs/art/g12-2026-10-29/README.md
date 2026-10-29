# G12 / 臺鐵 R21 靜態研究

本輪選 **1960 年首批 R21–R24 中的 R21，照片所見橘色塗裝（以 2014、2018 年照片核對）**。原廠形式 EMD G12，臺鐵正式型式 R20 型；1966 年 R51–R72 雖亦稱 G12，但機件有差異，不拿來混合。R21 於 1960-04-03 到臺，製造商 GM-EMD。車長 14.226 m、寬 2.787 m、高 3.665 m、軌距 1.067 m、A1A-A1A 是維基條目所列次級規格，尚未取得工程原圖核實；台車中心、軸距、輪徑、窗與設備位置都是觀照估算，不能當工程尺寸。型式與批次參考：https://zh.wikipedia.org/wiki/台鐵R20型柴電機車 （2026-10-29 查閱；條目標註來源不足）。

## 原圖核對與授權

原圖皆由 Wikimedia Commons 直接下載、以 image viewer 打開；未放入公開庫、未送生成服務。SHA-256 是本地下載檔。作者、日期、授權取自 Commons `imageinfo/extmetadata`；這些照片僅供觀察。使用者附的南粵急行示意圖標示 CC BY-NC-ND 4.0，只作提示，不重製、發布或用作模型貼圖。

| 原圖（檔案頁） | 作者／攝影日期／授權 | 下載 SHA-256 | 用途 |
| --- | --- | --- | --- |
| [R21 彰化](https://commons.wikimedia.org/wiki/File:TRA_R21_Diesel_locomotive_at_Changhua_Station.jpg) | 夢夢狐／2010-05-22／CC BY-SA 2.0 | `6e5f3433ff1caf30d1ada30df8a7afb9613f5c5e98e504b5479f20180745b4b7` | 長罩正斜、燈、台車、散熱 |
| [R21 新竹](https://commons.wikimedia.org/wiki/File:TRA_R21_Diesel_locomotive_in_Hsinchu_Station.jpg) | Tbatb／2020-12-08／CC BY-SA 4.0 | `6387e132d329ff1dc86ea56badfda79d8db8685789f455672dbdde8a94bdbd70` | 側面色帶、短罩、兩端扶手與連結器；較晚年份僅交叉核對 |
| [R20 2007](https://commons.wikimedia.org/wiki/File:TRA_R20_02.JPG) | Josephjong／2007-03-11／Public domain | `13e9736547a6a3359726b292ef0cf3ee3ccfd07530d` | 同型機車罩側門、格柵、燃油箱；非 R21，僅輔證 |
| [R21 2014](https://commons.wikimedia.org/wiki/File:TRA_R21_20141018.jpg) | 江東翰／2014-10-18／CC BY-SA 2.0 | `4f9097051d9c8f3f7a9756233c5269b6e32bb9884c265c6f881c5a93429e7b9a` | **短端**雙燈、號碼牌、抓手、白帶與端板；revision-2 修正依據 |
| [R21 2018](https://commons.wikimedia.org/wiki/File:TRA_R21_Diesel_locomotives_2018-0814.jpg) | Rsa／2018-08-14／CC BY-SA 3.0 | `aa3f4f10538032767833499d2a78daa692c37139b3aa24d3a1bed2735b0b9e12` | 長端正斜面與端板交叉檢查 |
| [R21 扇形車庫](https://commons.wikimedia.org/wiki/File:TRA_R21_at_Changhua_Roundhouse.jpg) | Lokseng01／2021-04-04／CC BY-SA 4.0 | `294e306d26c8ba1a68aab8677e0179aadeae5e5c480b5e9754f03dd1705eefe7` | 長端正面與燈位確認 |

原檔下載網址：`https://upload.wikimedia.org/wikipedia/commons/f/f2/TRA_R21_Diesel_locomotive_at_Changhua_Station.jpg`、`https://upload.wikimedia.org/wikipedia/commons/4/47/TRA_R21_Diesel_locomotive_in_Hsinchu_Station.jpg`、`https://upload.wikimedia.org/wikipedia/commons/0/08/TRA_R20_02.JPG`、`https://upload.wikimedia.org/wikipedia/commons/9/97/TRA_R21_20141018.jpg`、`https://upload.wikimedia.org/wikipedia/commons/6/6d/TRA_R21_Diesel_locomotives_2018-0814.jpg`、`https://upload.wikimedia.org/wikipedia/commons/f/fb/TRA_R21_at_Changhua_Roundhouse.jpg`。只發布本人的原生幾何與渲染；不包含照片像素、真商標或照片貼圖。

已檢查 owner 參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/garage-blender-v1/r20.json`：其模型標 `engineeringDimensionsM:null`、長度 9.678 m，屬示意而非本輪 14.226 m 量尺；未複製它的網格或顏色。現有 SceneKit R20 也不是本輪可替換的正式 R21 配方。

## 核對結果

| 部位 | 原圖觀察／模型 | 判定 |
| --- | --- | --- |
| 輪廓與朝向 | 長罩朝模型 +X，駕駛室與短罩在 -X；約中後方較高駕駛室 | 符合主要剪影 |
| 前後端燈 | 長／短罩端照片各支持高處兩側標示燈、中央縱列雙燈；端面輪廓按不同高度分開建模 | 符合主要相對位置；燈座細形仍簡化 |
| 駕駛室窗 | 側窗與短罩前方風擋可見 | 形狀簡化 |
| 側面格柵、散熱 | 駕駛室前小格柵與長端大型散熱區、側門分件 | 大格柵位置近似；反側資料不足 |
| 屋頂與排煙 | 深灰連續罩頂、排煙凸件 | 位置推估；俯視原圖不足 |
| 台車與燃油箱 | 兩台三軸 A1A，中央油箱、軸箱／側梁 | 六輪與位置近似；輪徑與軸距推估 |
| 踏板、扶手、連結器 | 兩端皆有端平台、扶手、踏板及連結器 | revision-3 前端扶手增亮並有端板／防撞板支承；管路細節簡化 |
| 橘白塗裝 | 長罩側帶下降到端面下緣；短罩側帶接到短端兩側，再在結構端板形成 V | revision-3 長端白帶在端面降到防撞板上緣；短端 V 保留；門板曲率仍近似 |

這是靜態 studies 的原生霧面頂點色近／遠景配方。`Map3DModelPack.standard`、SceneKit R20 `05_TRA_classic_3x2-05`、莒光 `R100CK`／`R200CK` 等營運映射完全不變；合併後玩家不會在營運列車看到這版。無商標、無照片貼圖。

使用者否定 revision-1 producer `b073c6c600bae8280cda31695aa28b0b413ee10f` 的整體外觀，又明確指出 revision-2 producer `69de18da3a8864b94e3bdc8f85d30b12c630a92c` 的正面「超怪」；兩版均不得寫成外觀已接受。revision-3 保留已核對的中央上下雙燈、號碼牌和短端白 V，重看 2021 扇形車庫長端正面與 2014 短端斜面原圖後，修正長端白帶停得太高、白帶下大片黑框、防撞板中央黃黑 V 反向、過窄的防撞板、幾乎看不見的扶手和暗到消失的排障器。長端白帶沿同一車殼側帶降到端面防撞板上緣，短端 V 仍由端板本體分色。端面板縫是細實體線，扶手有外側端板支承；沒有照片貼圖或浮貼色片。原圖沒有提供正交工程量尺，以上高度與寬度仍是按比例推估。

最終輸出近景 6,228 三角、遠景 2,764 三角（44.4%），兩者原生邊界皆 `[-7.11, 7.11] × [-1.37, 1.37] × [0, 3.63] m`。固定相機和遊戲模型光的七向日夜圖、GLB、原生模型、可旋轉／縮放／下載的 inspector 在私庫 `game-art-previews/docs/art/g12/revision-3/`。revision-1、revision-2 均只留 PNG、README、來源紀錄以追溯真前版；重檔由各自 producer 重建。公開總覽僅 [overview.png](overview.png)。照片並排圖只存工作區 `/workspace/scratch/g12-r3-private-comparison.jpg`，原圖不再散布；照片透視不等於固定正交相機。正面並排觀察：長端白帶與防撞板接縫、中央黃黑 V、兩側扶手和排障器層次比 revision-2 更接近照片；簡化的橘色平面、燈座、端面角部圓角和管線仍有差異。側、俯、斜視圖保持同尺度重看；大型散熱網、轉向架細形與屋頂設備仍有資料不足或簡化處。

Producer `501f339a6c8180f3924b337eb805737b2d5786b7`（真前版 `69de18da3a8864b94e3bdc8f85d30b12c630a92c`）。在獨立 `/workspace/g12-rebuild` checkout 執行 `tools/train-models/run.sh OUT --ids g12-r21,g12-r21-far` 與 `node tools/train-models/package.mjs OUT`，四個成品（兩個 `.m3dmodel`、兩個 `.glb`）逐 bytes 比對交付前匯出；SHA 詳見私庫 `manifest.json`。共用 `check.mjs`、`audit.mjs` 及 `g12-verify.mjs` 通過；六個輪位貼軌、兩端燈高、玻璃外露、兩端連結器、短端白 V、長端低白帶、防撞板頂中央黃 V、端扶手與七個位移故障反例已驗，且新版驗收拒收 revision-2 的長端白帶。Blender 4.3.2 獨立匯入近遠兩 GLB，分別 6,228／2,764 三角；56 張本地 PNG 完整解碼。Swift 6.4 `warnings-as-errors` 建置與相關測試另見本輪 PR 檢查。最終交付 viewer 本機 loopback 載入、旋轉、縮放、native／GLB／PNG 下載 byte 與 390px 視窗驗證通過；`file://` 因本機瀏覽器管理設定擋下，**UNVERIFIED**。這些檢查不等於 Metal 或動態碰撞。

## 狀態

- 素材技術：**VERIFIED**，限上述原生／GLB／渲染／viewer 技術驗收；`file://` 及工程量測未驗，見私庫 revision-3 的 `status.json`。
- 此 producer 使用者外觀接受：**UNVERIFIED**。revision-1 整體、revision-2 正面均被否定；revision-3 尚無使用者明確接受。
- 營運接入：**UNVERIFIED**，僅 studies；既有 SceneKit R20 與全部營運映射不變。
- 裝置：**UNVERIFIED**，無 iOS Metal／Simulator／真機驗證。
