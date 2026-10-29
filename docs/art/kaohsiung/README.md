# 高雄捷運紅／橘線現役西門子原生 studies

本輪獨立重建高雄捷運高運量電聯車（Siemens Modular Metro），一般銀色／綠松塗裝，共用同型車，不依路線另造幾何或紅橘塗裝。靜態展示，不替換營運。使用者外觀接受、營運接入、Simulator／真機均 **UNVERIFIED**。

實際 producer 與交付／驗證連結在本頁後續紀錄；重建入口 [工具](../../../tools/kaohsiung/README.md)，原始來源逐檔 SHA／日期／授權在 [source-record.json](source-record.json)。初版沒有已交付前版，不把過程試作當真前版。

## 查證與特徵

資料查核日2026-10-29。高捷公司2006-10-27簡報（原網站失效，下載Internet Archive原PDF，實看第3、5、7頁照片／配置與參數），主管機關2024-03-20岡山延伸段既有列車動測照片、2427junction各部位實拍，以及Siemens2008《First Class Bogies》第42/43頁原照片／工程圖均已下載、開啟。原圖僅本機觀察，不在兩庫再散布，也未送生成服務。

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

仍不符合：前罩曲率用少量平面，風擋／門角及裙邊較實車方；連結器與輪架細件偏簡、目的地文字用抽象短段，不模仿真實標誌；未作實車屋頂密集細肋或雨刷機構。資料不足：無透視正投影／全俯視照片，另一側及DM1/DM2完整車底箱序、管線、精確殼曲率與支架尺寸。照片推估不冒稱工程精度。

## 保護及前置

main基準50437249。逐張查#1357/#1416/#1342/#1422/#1424/#1437皆MERGED。既有高雄krtc（R/O）→metroGeneric、cars3，與player metro set／GameCore／購車／班表／動畫／所有fixtures保持。

台中使用者接受producer `498d85ef234a00345b4b024c4aa0e6783d73b933`只作風格參考；本分支台中配方SHA256 `2c91ce693c097689f561dc5133e24dcbc9bcf99dc31e4311f755fb2138c40451`與該producer一致。其他模型須以main實際輸出bytes與全部頂點欄位FNV核對，不重寫舊鎖消除既有28項差異。

私有參考庫查得一份高雄示意網格，自標illustrative且engineeringDimensionsM=null；不拿它當工程證據或搬幾何。高捷原PDF與Siemens圖錄補上尺寸與台車；未需要新增第三方程式依賴。私有來源原檔與內部路徑不公開。

五方理由：玩家—兩線共用可辨識車型；鐵道迷—以原始DM/T及第三軌資料約束；開發—studies不增standard常駐負擔、共用匯出工具；美術—既有綠松／銀／藏青霧面頂點色；音樂—無音訊變動。

驗收過程另外抓到studies註冊誤落standard初始化；`testStudiesOnlyAndProtectedOperatingMapping`實際失敗後已移回studies，不以模型輸出成功當註冊正確。完成後將重跑模型包總數／記憶體及全舊payload保護。首次底箱／玻璃驗收漏洞、頂燈裁切近重複頂點及近遠包絡差異皆由實際輸出反例檢查，不改共用gate。

四向實拍對照方法：front旁置主管機關既有列車近正斜照及2427junction正斜照；left旁置2427junction整列斜側及台車近照（無全車正交側照）；top旁置其大寮俯斜照（非無透視正俯視）；isometric旁置同來源斜前。比較圖只留本機，原圖授權未開放再散布。正面確認兩側獨立窗、中央門和U帶，但本模型門框／玻璃角較方；側面確認4門與雙客窗，但未還原所有檢修縫；俯斜確認兩端空調和中段三對通風件，精細頂肋省略。這些限制不因測試通過而撤回。

## 本輪技術交付

最終producer：`62c2da42bf7edb3ef2e359befe206782fbaaf29b`。六獨立近遠單元、兩個完整三車assembly；DM近3806/遠1902，T近2312/遠984，三車近9924/遠4788三角。共18模型／GLB／assembly payload由獨立乾淨worktree重建逐bytes相同。最終15項Swift、5 Node/6 Python工具契約、八件GLB獨立Blender4.3.2匯入、224最終PNG完整解碼、最終viewer互動／24真下載及8下載PNG完整解碼通過。[完整量測與限制](verification.json)、[四種狀態](status.json)。

688他車原生bytes及全部頂點欄位FNV與main50437249相同。本型六鎖正確；main既有28項舊鎖不符名單在verification，不改他車鎖消紅，不能宣稱全包鎖綠。

外觀自檢與實拍逐視角對照已做，但使用者尚未接受此producer。`file://`由瀏覽器管理政策阻擋，獨立記UNVERIFIED；localhost載入／旋轉／縮放／下載成功。不把Linux WebGL或Blender當Simulator、真機Metal／效能／動畫。

素材draft：[railway-assets-private#22](https://github.com/a91453/railway-assets-private/pull/22)；[完整revision-1](https://github.com/a91453/railway-assets-private/tree/codex/kaohsiung-native-2026-10-29/game-art-previews/docs/art/kaohsiung/revision-1)，含自含viewer／原生／GLB／20PNG／來源／SHA。公開draft：[railway-game-ios#1454](https://github.com/a91453/railway-game-ios/pull/1454)。

啟用MOTION_BUDGET_REPORT=1另跑記憶體報告測試通過；standard585模型／133.3MB，靜態studies不入常駐包。最新CI以#1454同head checks為準；素材#22同head guard另查。
