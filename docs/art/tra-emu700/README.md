# 臺鐵 EMU700 原生近遠研究與完整八車交付

本輪為獨立配方，不沿用其他EMU整殼。現有私庫Q版EMU700不具工程尺度，非已接受前稿。全部使用者外觀接受為UNVERIFIED。

正式身份：EMU700通勤交流電聯車；不是將「阿福號」當作正式型號。日本車輛／台灣車輛製造；2005採購，2007–2008交付計畫。前三個四車子單元日本製、後續台灣車輛在技轉下生產的細分，尚需原廠逐組交付紀錄。不能將採購公告的計畫年份當實際驗收日期。東芝電機系統供應責任仍待原廠文件補核。

來源：日本車輛[產品頁](https://www.n-sharyo.co.jp/business/tetsudo/pages/ztaiw_emu700.htm)、[採購公告](https://www.n-sharyo.co.jp/business/tetsudo/topics/tp050609.html)，台灣車輛[產品頁](https://www.trsc.com.tw/train/tran-58acf525031f4)，實車觀察[Blair Yu攝影文章](https://blair-train.blogspot.com/2011/09/emu740.html)，角色交叉核對[維基條目](https://zh.wikipedia.org/wiki/台鐵EMU700型電聯車)。原始照片僅本機觀察，未發布、未做貼圖、未送生成服務。文章版權所有；文章2011-09發布，照片圖說另有2011–2020日期；逐圖日期見來源JSON。已從下載原文對應圖說，沒有把文章日期代替每張照片日期，也未拼接成2026現役證據。

台灣車輛頁的ED／EMA／EP／EMB與其他角色原文矛盾；本輪明列此差異，採EMC／EP／ET／EM交叉定義，尚待官方編組圖補核。

候選代表為739+740，來源照片可讀EMC740、EM740；其餘六車號由編組表支持。原文另列739+740於2020-10-05的2133次運用，僅當歷史代表期證據，沒有完整八號同日可讀照片，不宣稱指定列2026營運。排除701+702京急彩繪、原型舊黑面、試車及模型照片。

供應責任與時序：日本車輛2005-06-08公告以台灣車輛為主契約者、住友商事參與商務／當地化支援，交付2007–2008為當時計畫。日車提供設計／技轉及前三組原型、台車量產組裝的細分由KASHIWA原文交叉支持；740實照製造牌為2007。東芝牽引／輔助系統、Nabtesco HRA軔機由技術文章記述，ET的TOSHIBA牌另有實照；FAIVELEY CX弓由攝影原文圖說支持，分供合約未取得。不能將行銷「全車自製」解讀成每一個零件均在台灣製造。

2007-08-28啟用、翌日上線及驗收曾因資訊設備延宕，依技術文章；各組確切交付／驗收日期未取得。電軔優先改造文字稱2015初完成，原驗收表未取得；無階化改造為2016年的二次來源記錄，2020年實照已顯示無階化門。原型與量產ET主風泵的歷史外觀有兩張不同實照，本包僅量產739+740，不把試驗／原型圖套成現役變體，也不由此捏造鼻形差異。2026指定編組狀態仍未驗。

八車配置：+X端← EMC739 / EP739 / ET739 / EM739 | EM740 / ET740 / EP740 / EMC740 →-X端。前四單元不旋轉，後四單元僅assembly旋轉180度一次。EP兩車為受電弓車；EMC與EM為動力車，ET拖車含無障礙設備。EM–EM中央交界屬半永久連結，不是兩個駕駛頭互接；中央端面與普通車間端的完整實物差異仍資料不足。

原生公尺，+X朝本子單元駕駛端、+Y左、+Z上，軌面Z0；左右從+X朝向定義。EMC連結面距20.743m、其他20.3m，總長163.286m，非每車平均長；連結面貼接，殼端退讓產生間距，不再額外加縫。台灣車輛頁寬2.890m，其他資料2.889m，配方採2.889m；車頂3.7m、含AC約3.95m、弓升起包絡另列，不能把含設備高度當殼高。模型台車中心±7.15m（對稱原點假設，端部絕對距離未取得工程圖）、官方中心距14.3m／軸距2.3m、輪徑新輪0.86m／磨耗0.78m、軌距1.067m；配方採新輪。輪心高度0.43m，軸位±7.15±1.15m。

| 部件 | 決策及證據 |
|---|---|
| primitive、轉軸 | 沿用main StationKitBuilder.box／beam及Model.flat（main a4dddd40）；輪與圓柱以本型獨立共用環頂點生成，沒有沿用他車整殼；producer隨最終commit固定 |
| 殼／鼻／色界 | 本型獨立截面及前部曲面，色界直接切殼；多方向自檢見visual-review.json |
| 駕駛窗／上雙燈／下燈群 | 實照支持位置；獨立幾何，工程站位推估 |
| 門窗 | 每側三門；EP／ET廁所盲窗分配目前僅合理簡化，反側設備須補逐車圖 |
| 台車／車底 | 正式軸距與中心距支持；框架及設備箱合理簡化，BOM與管路未知 |
| 弓／AC | 單臂弓實照已開啟；EP車位交叉來源支持，弓肘朝駕駛端、端部高壓設備在其駕駛端一側；依左右側照片核對，工程站位仍屬照片配適 |
| 鼻下連結器 | 照片顯示一般關閉罩；一般營運關閉罩，下方已有實際開放連結器框／引桿；升罩維修狀態未製作，凹區工程形狀屬簡化 |

實際選用：只預備studies，standard常駐增量0；實際standard+studies全量原生bytes與十欄頂點FNV保護記錄見preservation.json；不改Map3DTrainSets／Trains／RealTrains、燈或回退。現有localTrain是比例挑其他EMU，沒有可靠EMU700身份／正式角色／八車映射，不能按區間車名稱冒認。本PR合併也不會自動出現在營運。動態行駛、裝置Metal、Simulator、使用者接受各自UNVERIFIED。

技術結果見 verification.json、producer-verification.json、preservation.json 與 visual-review.json；此頁在兩庫draft PR完成後固定連結。真正幾何producer `ccc21854a16f21cb2d4f188749efaf6affd81d39`，驗證工具／文件head與素材commit另記，不倒填producer。此producer包含全部四種角色近遠、完整八車兩LOD；近景49,612三角，遠景24,508三角。每單元近景≤15,000；遠景逐角色少於近景一半，bounds同框。連結器與空調／車底殼體保留閉合實體，框架與孔洞為實際留空。

可執行重建（Swift 6.4、Node、既有Chromium／Playwright、Python/Pillow、Blender依共用工具README準備）：

```sh
git worktree add --detach ../emu700-producer ccc21854a16f21cb2d4f188749efaf6affd81d39
cd ../emu700-producer
pwd
git rev-parse HEAD
tools/tra-emu700/build.sh /tmp/emu700-rebuild
node tools/tra-emu700/render.mjs /tmp/emu700-rebuild
python3 tools/tra-emu700/sheets.py /tmp/emu700-rebuild
```

驗證工具沿用：通用audit／package／inspect／browser-check；獨立Swift編組解碼器使用main的tools/tra-r100/assembly-check.swift，獨立GLB匯入器使用tools/taichung-green/import-glb.py。新工具tools/tra-emu700/wheels.mjs及glass.py讀取實際原生頂點／連通固體，檢查八輪、輪軌、玻璃、屋頂設備、弓及連結器，修改實際輪胎／玻璃／AC／弓／框架做反例。射線只查指定外露面的三角中心與設備接點；雨刷例外僅識別出的兩個真實細長固體，不是整片風擋豁免；玻璃完整固體含未標玻璃的背面不作自己的支承。不是完整表面、自交、工程碰撞或動態證明。

仍缺：指定739+740的近期八號同日可讀營運照片、批次逐車交付／驗收與改造時序、屋頂正交／車底BOM、中央交界完整獨有設備，以及裝置Metal／效能與行駛。四態均UNVERIFIED：已跑技術項逐一記錄，但file://被瀏覽器管理政策阻擋；沒有明確producer的使用者外觀接受；營運未接入；Simulator／裝置未驗。HTTP viewer成功不代替離線直開、Metal或動態列車。沒有已接受EMU700前版，其他EMU只作風格參考。

公開僅此配方／必要studies註冊、專用檢查／配置／來源與驗證，以及一張共同公尺尺度總覽。私庫10張sheet涵蓋每單元及完整八車、七向／日夜／白模／剪影；全輪加公開總覽共11張，沒有照片、第三方幾何、ZIP或重複舊重檔。輪組及設備下方接觸與其餘機械隱藏結構仍為模型簡化，未稱工程複製。

近遠比較的20.8m單車框與163.286m全列框均固定，相同相機與光線；互動viewer則為每個項目自行適配鏡頭，不能用它的auto-fit畫面作定量尺度比較。夜景為靜態未啟動燈具材質，不宣稱已接上營運頭尾燈。更詳細的實際選用路徑與缺口見integration.json。

完整包與可旋轉縮放下載viewer：[私有素材分支](https://github.com/a91453/railway-assets-private/tree/codex/tra-emu700-native-2026-11-02/game-art-previews/docs/art/tra-emu700/revision-1)。以兩張互鏈draft PR的最新head為準。

本輪原創配方、原生／GLB及文件依公開庫 [LICENSE.md](https://github.com/a91453/railway-game-ios/blob/main/LICENSE.md)：Copyright © 2026 a91453，著作權所有。照片與技術文章維持各原作者權利，未作為交付素材。瀏覽器實測為Linux Chromium／SwiftShader，Safari、Firefox及行動裝置實際載入未驗；不需解壓API，viewer未壓縮。

最終註冊head僅將本型追加於studies末端；既有910個模型的順序／索引、原生bytes及十欄FNV均與未改main相同。standard 696件、studies 214→222件；standard頂點陣列增量0，本型studies增加4,447,200 bytes，不等於裝置GPU配置實測。幾何producer不因註冊順序、驗證工具或文件提交而改寫。

重建完整inventory與保護（從最終文件head呼叫本型專用helper，第二參數必須是實際乾淨checkout；共享exporter預設只匯出部分車輛）：

```sh
tools/tra-emu700/inventory.sh /tmp/emu700-main-inventory /absolute/unmodified-main-checkout
tools/tra-emu700/inventory.sh /tmp/emu700-final-inventory /absolute/final-checkout
python3 tools/tra-emu700/protect.py /tmp/emu700-main-inventory /tmp/emu700-final-inventory /tmp/preservation.json
```

獨立重建viewer：於幾何producer checkout執行下式，輸入為素材PR的完整revision-1資料夾；manifest／status／原生／GLB及渲染器SHA均在producer-verification.json固定。輸出應與交付index.html逐bytes相同：

```sh
node tools/train-models/inspect.mjs /absolute/revision-1 /tmp/emu700-viewer.html
cmp /tmp/emu700-viewer.html /absolute/revision-1/index.html
```
