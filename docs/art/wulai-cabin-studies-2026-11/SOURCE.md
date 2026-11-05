# 烏來大型往復式吊廂來源

取得日期：2026-11-05。這是現行第六代白色吊廂的第一輪靜態 studies，沒有前版。並非烏來台車，也不是將貓空／日月潭八人吊廂放大。

## 有來源的資料

| 來源 | 可支持的內容 | 使用方式 |
|---|---|---|
| [新北市觀光旅遊網：烏來空中纜車](https://newtaipei.travel/zh-tw/Attractions/Detail/110844)，頁面更新2026-09-22 | 第六代71人、往復式、斜距382m、高差164.59m，及當代白色車廂照片 | 容量記71；route資料僅用於展示索線平均坡度，不寫進營運資料 |
| [當代爬升近照](https://newtaipei.travel/content/images/attractions/73475/1024x768_attractions-image-rgdlrjzq5ekevfr3gcb9-q.jpg) | 白色長廂、中央雙門、矩形窗、圓角底部、高三角吊架與輪列 | 實際查看；輪廓及結構參考，不複製照片像素 |
| [當代車廂及瀑布](https://newtaipei.travel/content/images/attractions/73478/1920x1080_attractions-image-amlmscinue2llb6zazubga.jpg) | 車身／吊架相對大小、另一個斜視、白色基本塗裝 | 實際查看；遠距透視不能提供工程尺寸 |
| [車內端窗／座椅／天窗](https://newtaipei.travel/content/images/attractions/73471/1024x768_attractions-image-ecvlcezpxuk4l8pv-def_q.jpg) | 側邊座椅、端窗護欄與屋頂透明天窗 | 實際查看；座椅／天窗數量、尺寸與精確位置仍為補全推估 |
| [端窗內部近照](https://newtaipei.travel/content/images/attractions/73473/1024x768_attractions-image-bibpgrhwe0kfklg6xku4tw.jpg) | 金屬水平護欄、窗框、深色座椅 | 實際查看；不包含原照片、人物、文字或貼圖 |
| [水利署2014年資料](https://www.wra.gov.tw/epaper/Article_Detail.aspx?n=30173&s=802&sms=9942) | 歷史第四代91人及當時承載索資料 | 用於辨別年代，不將91人當成第六代容量 |

搜尋過原廠／公部門的車長、車寬與車高，但沒有取得本代製造圖或可核定的外廓尺寸。沒有把路線長382m當車長，也沒有用舊代重量當成新代載重。

## 比例推估與缺口

| 欄位 | 研究值／狀態 |
|---|---|
| 廂殼長×寬×高 | **4.80×2.68×2.56m，比例推估**；不含吊架、底架、護欄、凸出的天窗框 |
| 門淨寬 | **約1.50m，比例推估**；兩側中央雙門的不可見細節為補全，不是站台界限規格 |
| 地板 | 實心、封閉、不透明；登乘基準z=−5.20m，依本模型索線原點定義 |
| 走行輪 | 雙列各8輪的外形研究；輪槽半徑0.17m、索距1.10m均為**比例推估**；現代精確輪系／制動器內構未取得原廠圖 |
| 展示坡度 | `asin(164.59/382)`約25.5°；由公開斜長與高差算的平均線坡度，只供靜態姿態，不是全線每段實際坡度 |
| 座椅／握環／燈具 | 依可見資料作簡化配置；數量與機構位置為推估；71人包含站位，不代表71個座椅 |
| 載重kg、碰撞、站台淨空與機械安全 | 未取得／未驗證；kg欄位為null，不由容量換算 |

原生軸為公尺 +x前／+y左／+z上。索線中點為(0,0,0)，兩承載索接點(0,±0.55,0)，索軸及吊架pivot隨展示姿態一併記在manifest。GLB只作標準軸轉換(x,z,−y)。接點描述的是輸出幾何，不授權營運或工程用途。

## 原始碼、畫風與權利

- 自有日月潭producer `074b085c03329edcda9f212927783b5787857adc` → 封閉box／beam／tube／loft等基本形狀、M3DM編碼、七向WebGL流程；大型廂殼、門洞、天窗、三角吊架、走行輪與內部均重新建模。沒有搬八人廂mesh或尺寸。
- 本repo `tools/station-kit/package.mjs` → 原生逐頂點讀回與GLB基本編碼；本輪分成霧面、透明及發光三材質。
- 本repo `Map3DTransparentGlass`與`tools/native-glass` → 讀回後明確opt-in材質及實際Metal驗證方法；沒有修改renderer或standard／營運映射。
- 作者OpenWorld已讀SANITIZATION_REPORT及sunmoon ropeway來源；只有小型循環式吊廂方法，沒有烏來大型往復式車型可直接沿用。
- 照片僅用於觀察及資料核對，沒有重分發、描摹貼圖、人物、商標、公司名或車身廣告。歷代彩繪不與現代白色車廂混用。成品及本輪程式為專案自有素材；外部照片的權利不隨成品轉授。
- 既有Python、Node、Playwright／Chromium、Pillow、Blender、Swift6.4；沒有新增依賴、貼圖或外部生成服務。

照片視角未提供的底部設備、輪組內構及另一側門的細節，只能視為靜態外觀補全。外觀紀錄為自檢，作者接受、精確工程尺寸、動畫及iOS真機效能分開確認。

## 已實際查看的照片 SHA-256

以下原照片僅在scratch查看，不隨公開或私庫成品分發。

| 本機觀察標籤 | SHA-256 |
|---|---|
| official-view.jpg | `8d89209731ee7c43a16ff45d4b9743f1009c0ce6c20eca62488b7c761b787c03` |
| official-climb.jpg | `c545707aea019484bd5b7e178debd7613aeb5598f70ef7e91c14f630730fb5de` |
| ref-3.jpg | `bfd77b7ce75e32952a7c964596bfc3ead013f599a2dad7acee298f86f8e9d395` |
| ref-5.jpg | `625f7382c209d5226a2c6e8bf73c24f8cf1241a6b19d58d2c9762a6d77703709` |
