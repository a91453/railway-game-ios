# 高雄捷運紅／橘線現役西門子原生 studies

**目前交付第三版：使用者已接受外觀**。producer `bd57e163391bfdf7492cc408c7697451578ae8e1`。原交付公開[#1454](https://github.com/a91453/railway-game-ios/pull/1454) ↔ 原交付素材[#22](https://github.com/a91453/railway-assets-private/pull/22)。[完整revision-3／viewer／原生／GLB／20PNG／SHA](https://github.com/a91453/railway-assets-private/tree/codex/kaohsiung-native-2026-10-29/game-art-previews/docs/art/kaohsiung/revision-3)。[同相機真前後預覽](overview.png)。

使用者：「側面可以了 只是正面塗裝是不是有點方 還要調整嗎」。先前接受僅限第二版producer `3874b4259a99bd7b4f7e42f1b94fa23a34d4cf2c`的側面。使用者看過第三版後詢問是否還需修正，並在建議保留第三版後回覆「就這樣」；2026-10-29據此記錄第三版producer `bd57e163391bfdf7492cc408c7697451578ae8e1`的studies外觀接受 **VERIFIED**。真前版公開head `bb67bfa14870aeaa624df4f5a1d3a9aa08db7f63`／素材commit `1f73fb1cdba56ce99e0e3cdc3313175915d0ac92`。本輪只細分正面本體分色：黑罩上緣由水平改淺弧、肩部收角漸圓，白／綠松U帶增加分段；中央逃生門保留實拍所見直邊，不把整張正面任意磨圓。

實體車頭曲面未動；用兩真producer的shellOnly匯出，逐原曲面平面格比較雙向三角形交集覆蓋。直側面X≤9m所有52-byte原生三角形記錄（含每個頂點座標／色值／flags）完全一致；T近遠兩件完整bytes相同。車頭外硬體幾何／flags保持；前端分色會出現在斜／側視的鼻端，鄰近烘焙陰影也可能變，不宣稱整張側視圖逐像素一致。屋頂、底盤、玻璃、門框、燈、雨刷、裙板、連結器及編組配方保持。

DM近5790／遠2686、T近2312／遠984；三車近13892／遠6356三角。格式單件上限、六單元近遠及完整編組預算分開檢查。最終資料與驗證見[verification.json](verification.json)，四種狀態見[status.json](status.json)。第二版重檔在同素材PR移除，保留20PNG、README、來源／授權與狀態，以真commit恢復，不新增history或ZIP。

本輪獨立重建高雄捷運高運量電聯車（Siemens Modular Metro），一般銀色／綠松塗裝，共用同型車，不依路線另造幾何或紅橘塗裝。靜態展示，不替換營運。使用者對第三版producer外觀接受 **VERIFIED**；營運接入及裝置驗證仍 **UNVERIFIED**。

實際 producer 與交付／驗證連結在本頁後續紀錄；重建入口 [工具](../../../tools/kaohsiung/README.md)，原始來源逐檔 SHA／日期／授權在 [source-record.json](source-record.json)。初版沒有已交付前版，不把過程試作當真前版。

## 查證與特徵

資料查核日2026-10-29。高捷公司2006-10-27簡報（原網站失效，下載Internet Archive原PDF，實看第3、5、7頁照片／配置與參數），主管機關2024-03-20岡山延伸段既有列車動測照片、2427junction各部位實拍，以及Siemens2008《First Class Bogies》第42/43頁原產品圖／工程圖（產品圖未證實是照片或渲染）均已下載、開啟。原圖僅本機觀察，不在兩庫再散布，也未送生成服務。

| 項目 | 採用與可信度 |
|---|---|
| 正式名稱 | 高雄捷運高運量電聯車；西門子製，Modular Metro家族。原始高捷資料稱DM-Car/T-Car；DM1–T–DM2用於分辨兩端駕駛動力車。沒有虛構車系編號。 |
| 製造分工 | Siemens Transportation Systems／SGP奧地利廠製造組裝，維也納生產；西門子為機電統包。Siemens原轉向架圖錄明列SF3000、KMRT Kaohsiung。未查得台灣組裝此批車之證據；細部分包供應商不猜。 |
| 既有／新車 | 2005–2007交付42列、2008開始載客之西門子車。增購Hyundai Rotem岡山路竹延伸車、黃線Stadler及CAF/Alstom環狀輕軌分開排除；不以效果圖當現役照。未以舊資料證明2026每列即時妥善狀態。特殊彩繪不作本輪塗裝。 |
| 紅／橘線 | 高捷原簡報：兩線相同機電設備、共42列DM–T–DM；兩線共用車型與基本銀／綠松塗裝。 |
| 尺寸 | 高捷原資料：DM21.945m、T21.560m、三車65.450m、寬3.150m、車門淨寬1.4m、貫通道淨寬1.4m/淨高1.9m。模型門外框1.54m非淨開口；未建開門動畫。3.60m車體與約3.75m設備頂為照片及次級資料解讀，非該簡報正式總高。 |
| 走行 | 鋼輪鋼軌、1.435m、750V DC底觸第三軌。Siemens原圖錄SF3000軸距2.3m、新輪850mm/磨耗770mm；本模型採新輪。每車兩台車、每台兩軸；DM為動力、T為無動力，不放集電弓。台車中心±7.15m是照片配置推估。 |
| 兩側門窗 | 每側4組對開門；門間雙客窗，端部不虛構客窗。DM另有駕駛側窗；T無駕駛窗、頭燈或外端自動連結器。另一側設備箱序並未完整攝得，不能稱全還原。 |
| 正面範圍 | 圓肩頂弧銀色車身；綠松頂冠、寬深色罩、兩側獨立玻璃、中央逃生門；目的地幕在單側風擋上方。深色下緣淺U，細白帶再接綠松帶與銀色下裙；兩組左右小圓燈，頂部中央小燈、低置連結器。色帶直接切本車殼體，不疊色片遮縫。 |
| 屋頂／底部／連接 | 實拍可見兩端低空調盒、中央三對低通風件，細肋條及底箱作尺度簡化。風琴位於內端；共同連結平面明記。外端連結器為簡化Scharfenberg體塊，未還原管路及內部鎖。 |
| 兩端差異 | 兩個獨立DM輸出；可見車殼／門窗／空調共用本型配方。只對外觀大設備採同構，不宣稱DM1/DM2隱藏箱序完全鏡像；小型管線省略。完整工程設備配置仍資料不足。 |

## 比例、造型與限制

先匯出shellOnly實際原生白模／剪影並看正側俯斜；原生第一試作頂部缺面已撤回，修正裁切多邊形首三點共線問題後重看，之後修門窗和近遠簡化。車頭橫向弧、肩、玻璃與各色塊依上述實拍重新建立，未複製台中／三鶯／C371/C381殼體或底盤。

已符合：銀色直側四門、雙客窗、獨立駕駛側窗、綠松頂冠及淺U白／綠帶、第三軌台車、兩端空調、三車內端風琴。最終原生多視角旁置實拍，供製作者自檢，不等同使用者接受。

仍不符合（第二輪）：前罩仍以有限平面近似，風擋圓角／斜率與小型燈座有照片推估；輪架、連結器管線與機構仍簡化，目的地用抽象短段、不模仿商標；屋頂密集細肋省略。雨刷已補有支點的靜態機構，非動畫。資料不足：無透視正投影／全俯視照片，另一側及DM1/DM2完整車底箱序、管線、精確殼曲率與支架尺寸。照片推估不冒稱工程精度。

## 保護及前置

main基準50437249。逐張查#1357/#1416/#1342/#1422/#1424/#1437皆MERGED。既有高雄krtc（R/O）→metroGeneric、cars3，與player metro set／GameCore／購車／班表／動畫／所有fixtures保持。

台中使用者接受producer `498d85ef234a00345b4b024c4aa0e6783d73b933`只作風格參考；本分支台中配方SHA256 `2c91ce693c097689f561dc5133e24dcbc9bcf99dc31e4311f755fb2138c40451`與該producer一致。其他模型須以main實際輸出bytes與全部頂點欄位FNV核對，不重寫舊鎖消除既有28項差異。

私有參考庫查得一份高雄示意網格，自標illustrative且engineeringDimensionsM=null；不拿它當工程證據或搬幾何。高捷原PDF與Siemens圖錄補上尺寸與台車；未需要新增第三方程式依賴。私有來源原檔與內部路徑不公開。

五方理由：玩家—兩線共用可辨識車型；鐵道迷—以原始DM/T及第三軌資料約束；開發—studies不增standard常駐負擔、共用匯出工具；美術—既有綠松／銀／藏青霧面頂點色；音樂—無音訊變動。

驗收過程另外抓到studies註冊誤落standard初始化；`testStudiesOnlyAndProtectedOperatingMapping`實際失敗後已移回studies，不以模型輸出成功當註冊正確。完成後將重跑模型包總數／記憶體及全舊payload保護。首次底箱／玻璃驗收漏洞、頂燈裁切近重複頂點及近遠包絡差異皆由實際輸出反例檢查，不改共用gate。

四向實拍對照方法：front旁置主管機關既有列車近正斜照及2427junction正斜照；left旁置2427junction整列斜側及台車近照（無全車正交側照）；top旁置其大寮俯斜照（非無透視正俯視）；isometric旁置同來源斜前。比較圖只留本機，原圖授權未開放再散布。正面確認兩側獨立窗、中央門和U帶，但本模型門框／玻璃角較方；側面確認4門與雙客窗，但未還原所有檢修縫；俯斜確認兩端空調和中段三對通風件，精細頂肋省略。這些限制不因測試通過而撤回。

## 第一輪技術交付（歷史，已由第二輪取代）

最終producer：`62c2da42bf7edb3ef2e359befe206782fbaaf29b`。六獨立近遠單元、兩個完整三車assembly；DM近3806/遠1902，T近2312/遠984，三車近9924/遠4788三角。共18模型／GLB／assembly payload由獨立乾淨worktree重建逐bytes相同。最終15項Swift、5 Node/6 Python工具契約、八件GLB獨立Blender4.3.2匯入、224最終PNG完整解碼、最終viewer互動／24真下載及8下載PNG完整解碼通過。[完整量測與限制](verification.json)、[四種狀態](status.json)。

688他車原生bytes及全部頂點欄位FNV與main50437249相同。本型六鎖正確；main既有28項舊鎖不符名單在verification，不改他車鎖消紅，不能宣稱全包鎖綠。

外觀自檢與實拍逐視角對照已做，但使用者尚未接受此producer。`file://`由瀏覽器管理政策阻擋，獨立記UNVERIFIED；localhost載入／旋轉／縮放／下載成功。不把Linux WebGL或Blender當Simulator、真機Metal／效能／動畫。

素材draft：[railway-assets-private#22](https://github.com/a91453/railway-assets-private/pull/22)；[完整revision-1](https://github.com/a91453/railway-assets-private/tree/codex/kaohsiung-native-2026-10-29/game-art-previews/docs/art/kaohsiung/revision-1)，含自含viewer／原生／GLB／20PNG／來源／SHA。公開draft：[railway-game-ios#1454](https://github.com/a91453/railway-game-ios/pull/1454)。

啟用MOTION_BUDGET_REPORT=1另跑記憶體報告測試通過；standard585模型／133.3MB，靜態studies不入常駐包。最新CI以#1454同head checks為準；素材#22同head guard另查。


## 第二輪獨立驗收與外觀對照（歷史）

共用拓樸及刪面／反面／編組移位仍通過，新增實際前玻璃埋入150mm／外浮90mm、封住凹孔的真面片及反移目的地幕的真三角形反例，近遠各自拒收。真第一輪四個DM原生也分別被「反側顯示幕／實心連結器」拒收。玻璃保留所有殼／框遮擋，只辨識雨刷範圍內的實際細桿；每個抽樣玻璃外表面55mm內有實體背板。屋頂／八輪／淨空／風琴照實際輸出重驗。

固定比較由producer中的`tools/kaohsiung/compare-fixed.mjs TRUE_R1 FINAL OUT`產生，使用每單元／編組兩版共同bounds中心、正交公尺尺度、相同日光／背景／材質，四向配色／白模／剪影。前後各自auto-fit未用來比比例。原生全近遠及編組七向、白模／剪影均重看，最終前／側／俯／斜與有來源實拍旁置；無真正正投影／全俯視來源的方向保留資料不足。

已符合：顯示幕改到實拍所見觀者左側；兩側獨立風擋、圓角中央逃生門與曲面分色連續；共同燈座、頂燈圈、雨刷支點、下裙缺口及連結器凹孔可見。仍不符合及資料不足如前述，不用技術通過推斷已獲外觀接受。

Siemens SF3000原圖錄的設備產品圖未註明是攝影或渲染，本輪將它與尺寸／工程圖分開記，不冒稱已證實為實車攝影。原高捷簡報同時含實拍與示意圖，也只依各自性質使用。

## 第三輪對照與驗收

本輪建模基準main `fd91b75c250f63d19331d87f33e502ef72a1daf8`已含三鶯營運整合#1448與六分片CI#1455，逐張確認為MERGED後納入；不能沿用舊688件名單當最新保護證據。本輪重新匯出最新main的696模型與本分支全部模型比對，台中綠線既接受producer `498d85ef234a00345b4b024c4aa0e6783d73b933`未改。

固定比較以真R2的最終單元／編組為before，同公尺尺度、相機、光線；配色／白模／剪影四向192張僅暫存，最終各單元及編組七向224張亦不整批提交。兩庫本輪只留20張私有PNG和1張公開總覽。實拍旁置四向只本機保留，未散布原照片。

已符合（製作者自檢）：頂冠／黑罩收角更接近實拍弧線，U帶中央與邊角轉折較連續；側面接受範圍、T車、車頭實體曲面與硬體受保護。仍不符合：霧面風格的玻璃／門框／燈組保留低細節切角，非實車光學材質，遠景弧線刻意較少分段。資料不足：無無透視正面／全俯視工程外形，肩部與分色曲線是照片推估；隱藏的DM1／DM2設備序與連結器管線未全還原。技術通過本身不代表外觀接受；本次接受依據是使用者後續明確回覆。

接手：第三版已依「就這樣」定稿，本次只補接受狀態，不再修改外觀。保持studies及krtc既有metroGeneric三車映射；營運接入與裝置視覺／真機Metal、效能與動畫仍UNVERIFIED；交付程式的Xcode Simulator CI成功另記，不外推成裝置接受。file://依管理政策可能受阻，localhost viewer另有實測；不以瀏覽器模擬替代裝置驗證。

第三輪素材commit：[`5ee6fe9ceafb07ea8d137ad01d413182f8b74484`](https://github.com/a91453/railway-assets-private/tree/5ee6fe9ceafb07ea8d137ad01d413182f8b74484/game-art-previews/docs/art/kaohsiung/revision-3)。staged tree與提交後asset_guard皆通過，本PR95新增檔案、unique blobs17.1MB；本輪20PNG及44檔SHA清單完整解碼／核對。最新CI結果另查兩PR的最新head，不沿用前版結果。

## 第三版外觀接受補記

2026-10-29使用者「就這樣」對應producer `bd57e163391bfdf7492cc408c7697451578ae8e1`，不是對新producer或真機的授權。本次只改狀態、交接、viewer內嵌狀態及SHA；六原生單元、兩編組、GLB和20PNG全部保持。素材原PR#22已由其他流程合併（main `e945f452`），兩庫原交付PR#1454／#22皆由其他流程合併；接受補記改由兩庫最新main的獨立draft PR交付，[素材補記#24](https://github.com/a91453/railway-assets-private/pull/24)。造型producer不變，後續接受metadata與重建配方分開；在producer重建時預設UNVERIFIED是歷史狀態，套用本次status.json才得到接受紀錄。

交付程式head `cd92b3c6`實際CI：Swift40800314232 gate及六selected分片SUCCESS、Xcode40800314226 SUCCESS、工具contracts40800314233 SUCCESS；素材head `5ee6fe9` guard40800317496 SUCCESS。UI額外分片依PR計畫、iPad未觸及tutorial而SKIPPED；Superseded檢查因正常成功流程SKIPPED，沒有取消或補跑。metadata新head另查CI，不沿用舊結果當新head通過。
