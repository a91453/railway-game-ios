# 阿里山林鐵 DL-38 與阿里山客車（決策 531，修訂 2）

作者看了修訂 1，說「很醜，可以參考 R21 嗎」。修訂 2 照 G12／R21（#1485，`docs/art/g12-2026-10-29/`）的做法重做：照片定比例、端部做到 R21 的細緻度、六格總覽。成品仍是**阿里山的車**：DL-38（日本車輛 1980 年的 25 噸試作機，762 mm 軌距）與阿里山的一般客車。不用 G12／R21 的車身、橘色塗裝或黃黑 V 斜紋。

`overview.png`：每款車兩列，左起正面、左側、俯視；背面、斜視、遠景版左側。上兩列是 DL-38，下兩列是客車。白天光，遊戲的模型光（`tools/train-models/render.mjs`）。

## 原圖核對與授權

原圖都從 Wikimedia Commons 下載，取 API 給的 1920 px 縮圖（原檔被限速）。SHA-256 是那個下載檔的。作者、日期、授權取自 Commons 的 `imageinfo/extmetadata`。照片只用來看，不放進公開庫，不當貼圖，也不送生成服務。

| 原圖（檔案頁） | 作者／攝影日期／授權 | 下載 SHA-256 | 用途 |
| --- | --- | --- | --- |
| [DL 38 阿里山 2023](https://commons.wikimedia.org/wiki/File:AFR_%27DL_38%27_at_Alishan_2023-07-18.jpg) | Industrial Wales／2023-07-18／CC BY-SA 2.0 | `49adaa775bda5c49604ff99f2a9c3e83e1c28c27b3d0050468c7a96250f930ff` | 長機頭端：散熱格柵、「DL-38」號碼牌、右柱單燈、警示牌、頂角黃色旋轉燈、白帶包到前柱；側面成排百葉與門；黑色深端樑與砂箱、鍊條連結器、圓筒油箱、二軸轉向架 |
| [DL 41 阿里山 2023](https://commons.wikimedia.org/wiki/File:AFR_%27DL_41%27_at_Alishan_2023-07-18.jpg) | Industrial Wales／2023-07-18／CC BY-SA 2.0 | `040b895a8980308a0eab74101b0c897ce7c392f6520d30b2760531c2e3598792` | 同代機車的側面比例：駕駛室高出機頭、車架高度 |
| [DL 42 阿里山 2023](https://commons.wikimedia.org/wiki/File:AFR_%27DL_42%27_at_Alishan_2023-07-19.jpg) | Industrial Wales／2023-07-19／CC BY-SA 2.0 | `eb7693f5e60cbead1e72fa7c40faa9710416614cb721e5e81dd4f4215a839a02` | 駕駛室窗、圓角屋簷、扶手的交叉核對 |
| [DL-39](https://commons.wikimedia.org/wiki/File:AFR_DL-39.jpg) | Wentao／2012-12-10／CC BY 2.0 | `eab30e6e91b72741616b0991d6f31c6aaaadbaad083f168f90d04c3ca3a52bee` | 駕駛室端的短機頭：白色 V、號碼牌、燈、警示牌；端樑與連結器、踏階 |
| [PC 8405](https://commons.wikimedia.org/wiki/File:AFR_PC_8405_01.jpg) | maviscwling／2009-05-02／CC BY 2.0 | `5eccf138bbb90ee9829ebc47f45cf1d55278799548dbad8cbe222ba9571b0dc8` | 一般客車的營運塗裝：紅下身、白線、深綠窗帶、紅圓頂；窗與門 |
| [阿里山號 竹崎](https://commons.wikimedia.org/wiki/File:A_Alishan_Express_arriving_at_the_Zhuqi_Station.jpg) | SLs of Taiwan／約 2000／CC BY-SA 4.0 | `a04ffe35cb1137ea1936e1ed3604c8a21278020fa40b39ab6a2cd412e9f6e3fa` | 阿里山號的奶油紅塗裝（沒選，見下） |
| [Alishan Express 00](https://commons.wikimedia.org/wiki/File:Alishan_Express_00.jpg) | 駿瑜 陳／2007-04-06／CC BY 2.0 | `541dff601d79ad0b9b9c785bab1e1a3c9bdd81f50e0bdc1541581fc7db68f2fa` | 客車端面：貫通門、端窗、端燈 |
| [Alishan Express 01](https://commons.wikimedia.org/wiki/File:Alishan_Express_01.jpg) | maviscwling／2009-05-01／CC BY 2.0 | `46e149c0aa028d79497af7d70bd23d7659490662900b91334b909bc6a98b5774` | 客車側面、圓頂與通風器、轉向架 |
| [阿里山鐵路 2014](https://commons.wikimedia.org/wiki/File:Alishan_railway_2014_19.JPG) | Smiley.toerist／2014-10-21／CC BY-SA 4.0 | `c4aa531c0f790d42f5003e51a1f4513b14d8723231fe6eca2d18718648b9e863` | 客車塗裝與窗框的交叉核對 |
| [沼平站](https://commons.wikimedia.org/wiki/File:Alishan_train_stopped_at_Chaoping_Station.jpg) | Gordon Cheung／2016-10-16／CC BY 2.0 | `4fcef4585a348ac89ee2f645996351f3a207e199684932fb9be8208f2f6fc9a1` | 機車加客車的整列樣子、車頂設備 |

下載網址是各檔 `https://thumb.wikimedia.org/wikipedia/commons/thumb/<h>/<hh>/<檔名>/1920px-<檔名>`（Commons API 的 `thumburl`，去掉查詢字串）。另找到 `AFR DL38 01.jpg`、`AFR DL42 01.jpg`、`Alishan Train 09Mar21 01.jpg`、`Nippon Sharyo DL-39 (30027288624).jpg`，但被 Commons 限速、沒有下載，沒有用。

參考庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/garage-blender-v1/` 的 `dl38`、`dl39`、`alicoach` 也看過（作者的，授權可用）：它們標 `engineeringDimensionsM: null`，長度縮短過（dl38 7.318 m、alicoach 8.088 m），所以只取機車紅 `#B83230` 與大致的寬高；網格沒有用（每節三到五萬個三角形，超出預算）。`THIRD_PARTY_NOTICES.md` 對這批車庫模型沒有另外的授權條文。

## 核對結果

| 部位 | 照片／模型 | 判定 |
| --- | --- | --- |
| 機車輪廓 | 長機頭在 +X，駕駛室在 -X 端並高出機頭；短機頭在駕駛室後面；全長 8.9 m（含聯結器）、寬 2.28 m、高 3.21 m（含旋轉燈） | 剪影符合；長度是估的（決策 515 的 `carMetres`），寬高照照片比例量 |
| 長機頭端 | 散熱格柵（12 條橫柵）、號碼牌、右柱單燈、兩側警示牌、頂角黃色旋轉燈、白帶包到前柱、扶手 | 照 DL 38 照片；號碼牌的字是自己的幾何筆畫，不是照片 |
| 短機頭端 | 白色 V、號碼牌、單燈、旋轉燈 | 照 DL-39 照片 |
| 側面 | 長機頭八扇門、上排百葉、下排隔門百葉、前段大百葉、白帶 | 門數照 DL 38 照片數的；百葉片數簡化 |
| 駕駛室 | 前後窗、側窗、雙片窄窗的門、圓角外伸屋簷、喇叭 | 位置照照片估 |
| 車架與轉向架 | 黑色深端樑與砂箱、鍊條、空氣管、圓頭聯結器；二軸轉向架（輪徑 0.66 m）、側樑、軸箱、彈簧、閘瓦；圓筒油箱 | 輪徑與軸距是估的 |
| 客車輪廓 | 13.0 m（含聯結器）、寬 2.32 m、高 3.13 m；圓頂外伸到兩端，四個通風器 | 長度是決策 515 的 `carMetres`；寬高照照片比例 |
| 客車側面 | 每側八個大窗（銀窗框、橫框）、兩端各一扇灰門（有窗）、扶手、踏階、車號牌 | 窗數照 13 m 車身排；照片的窗數因車而異 |
| 客車塗裝 | 紅下身 `#B83230`、白線 `#E9E1CF`、深綠窗帶 `#1E4A3E`、紅圓頂、銀雨水條 | 照 2009–2016 年的一般客車照片 |
| 客車端面 | 灰色貫通門與窗、兩側端窗、低處兩盞燈（紅燈座）、踏板、鍊條、端樑、聯結器、角踏階 | 照 Alishan Express 00 |
| 遠景版 | 同框、顏色是近景的子集、三角形不到一半；車輪 8 邊；客車每側一條長窗帶，兩端各一段，避開端燈 2.8 m | 測試檢查 |

三角形：DL-38 近景 7,712、遠景 2,316；客車近景 3,988、遠景 1,372。

## 沒選的

- **阿里山號的奶油紅塗裝**（參考的 `alicoach`、竹崎那張照片）：那是阿里山號的駕駛客車，不是一般客車；一般客車照片都是紅、白、深綠。修訂 1 用的就是這種，預覽在 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/alishan-dl38/revision-1/`。
- **直接用參考的網格**：太重，長度也縮短過。

## 重建

- 七向日夜圖、GLB、原生模型、檢視器：`a91453/railway-assets-private` 的 `game-art-previews/docs/art/alishan-dl38/revision-2/`（修訂 1 只留 PNG、README 與來源紀錄）。
- 指令：`tools/train-models/run.sh OUT --ids set-ALISHAN-head,set-ALISHAN-car,set-ALISHAN-tail,set-ALISHANFar-head,set-ALISHANFar-car,set-ALISHANFar-tail`，再 `node tools/train-models/render.mjs OUT --time both`。
- 來源與尺寸：`docs/decisions/531.md`。

## 狀態

- 作者外觀接受：**UNVERIFIED**，總覽已送遊戲規劃第 40 任轉給作者。
- 裝置：**UNVERIFIED**，Linux 的 WebGL 預覽不是 Metal；夜裡頭燈與尾燈由遊戲每格點亮（決策 449），預覽看不到。
