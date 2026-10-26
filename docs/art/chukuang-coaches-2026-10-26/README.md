# 莒光自動門客車經典塗裝研究

本批是獨立原生配方及靜態展示，**尚未接入營運**。合併後沒有營運編組改用本批模型；E200CK／E500CK／R100CK／R200CK／SUMMER、PP、鳴日及環島之星保持原接點。現行型錄只指定莒光等級，沒有確立本批 10400 系的專用年代／系列配置，故不以同一牽引機車作替換依據。

工作 issue #1305。公開／私有 draft PR 及最終同提交 CI 結果在 issue 交付留言；不合併、不 auto-merge、不發 TestFlight。配方在 `Map3DChuKuangPassenger.swift`；完整素材在私庫 `Railway/game-art-previews/docs/art/chukuang-coaches-2026-10-26/`。

## 來源與範圍

四張使用者附件逐張實看：一為 TRC 模型包裝照（兩標準窗列及中央小窗特殊配置）；二為端門斜實照；三為 2015 車種拼圖，含 35SP／40FP／40FPK 手動門、35FPK10400 自動門、餐車／行李／電源等不同角色；四為自動門客車側實照。拼圖不是同一系列的工程圖。兩張實照可確認經典橘／米色、細腰線、端部淺色區下收；精確車號不當作已辨識個車。

[Train Collection 10400系介紹](https://emu300ct.web.fc2.com/index/trapc/chu-kuang_cars/CK-10400s.htm)實際讀取 Big5 頁面，查看 10400 左／右及 11400 左／右實車照。頁面列 1994–95 唐榮、10400標準車、11400車長／無障礙車、TR-54、滑軌式車長聯控自動門、20,000 × 2,885 × 3,800 mm。這是專門研究站的資料，非取得原廠工程圖。著作權／CC BY-NC-SA原圖只作觀察，不取圖素、不公開散布或自動描圖。尺寸端點、精確設備及不可見管線仍不足。

- `standard`：10400系標準客車外觀研究。一側五大窗＋四小窗，另一側五大窗＋五小窗，端門、窄端牆；照片推估窗位與大小，並非工程定位。
- `conductor-study`：使用者模型照中央小窗配置的獨立展示角色；**尚未確定子系列，不命名為11400**。它不是前述11400左右照的復刻，也不投入營運。
- 不製作拼圖中所有手動門、餐車、電源車、行李車；不能以本車換色冒充它們。

公開只保留自製模型總覽，不包含附件、外部照片、私庫mesh／貼圖。照片與私庫素材未送外部生成服務。使用既有莒光橘 `TrainLivery.chuKuangCoach`、米色 `0xECE2BC`、E500玻璃、藏青與灰色票；霧面平塗，不含紅色細線、真品牌／商標／車號／人臉。

## 私庫原模型檢查

確有 `juguang` 原模型及來源紀錄。較新 Taiwan rail snapshot 的 catalog 註明 FPK10400，body19.3m、pitch20m、width2.9m為三型折衷，門窗與body為推估；解壓近景3532／遠景396三角，實際讀原始Float32、轉四向查看。原始 mesh 本身未被本次覆寫。

具體差異：原端門葉區約1.45m寬、本次參考照片窄門約0.7m；原左右表鏡像、照片左右小窗不同；原端部橘／米色沒有照片的下收分界；遠景整條窗帶失去五窗節奏，輪底Z約0.0215m；車頂／車下是原推估配置。故不是單純改色可完成的相符車殼，本次依照片獨立製作。沿用既有幾何primitive及匯出／驗證工具做法，**不以PP、EMU3000、鳴日或環島之星的車殼換色**。早期私庫 `tra-chukuang` 為概念素材，另經Blender匯入，亦不採其殼。

私有來源路徑、原mesh SHA、附件 SHA、來源研究圖放私有 `reference-record.json`／`reference-study/`；公開文件只列必要判讀，不散布來源payload。

## 模型契約與真前後

原生公尺+X前、+Y左、+Z上，輪底Z=0；GLB=(x,z,-y)。單元合法M3DM v1 ≤15,000三角；完整E500＋四客車展示用合法單元內嵌的M3DAssembly，不把超限編組冒充遊戲單檔。實際bounds／三角／SHA／平移在manifest。客車coupler pitch20m，body19.3m屬依私庫及照片的解讀；精確門窗、冷氣罩、輪架／管線為比例推估。標準車近遠各自保留分格窗列。

已接受 E500第三版、EMU3000第五版及已交付PP／E1000配方不動；capture與coexistence核整份位置／法線／色／layer實際payload。E500展示原生直接比對已接受包並原樣複製。EMU3000風格比較直接讀私庫第五版原生且保持其bytes／producer，不假設main已包含第五版；main模型另作共存payload保護。

`before-after` 是 base1b40e4f4 的真營運通用客車與獨立新模型，**不是新模型的舊修訂**；`first-pass-vs-final` 是本次真正第一輪輸出。固定共同相機中心、extent與公尺尺度。第一輪空調封面接縫、浮空格柵／端面屋頂色及誤用垂直圓柱的輪盤修正；真第一輪保留於素材包，不倒造劣稿。新增獨立車殼，沒有聲稱只改色或拓樸不變。

## 驗收與限制

交付外觀逐項紀錄在私包appearance-review.json：近遠側／正／俯／斜配色、白模、剪影、左右側近景、七向、編組與同尺度風格比較親自查看。外觀自檢不代表使用者認可，不宣稱工程復刻或相似度百分比。10400左右資料較完整，特殊角色精確型別及背面設備資料不足。

技術證據依私包實際verification／support／glb-import／package紀錄，不把計畫當已驗：Linux Swift6.4 warnings-as-errors、相關測試、原生讀回／法線／有向封閉／正體積、刪面反面反例、玻璃支承與遮擋、輪貼軌、組裝payload、保護payload、Blender獨立GLB、PNG完整解碼透明留白、Chromium旋轉縮放／下載SHA、ZIP解壓逐檔比對。抽樣支承與射線不是完整自交／碰撞或工程裝配證明。

UNVERIFIED：人工Simulator外觀、真機Metal／FPS／記憶體、輪轉／車門／輪架動畫、坡彎動態、懸吊及真實營運編組。沒有改GameCore、存檔、golden、replay或玩法。

重建見 [工具README](../../../tools/chukuang-coaches/README.md)，最終producer與同head CI見issue及私包source.json。素材producer固定後若再改影響輸出的來源，必須全量重出，不把後續文件head冒充素材producer。
