# 文湖線 VAL256／370（INNOVIA APM256）原生草稿

**未完成交付，四態皆 UNVERIFIED。不得以這份草稿替換營運 `wenhu`。**

本目錄保留原文來源與工作，沒有已被使用者接受的兩款原生前版。CI、合併、作者查看與此次任務均非使用者外觀接受。真正 producer 與最終 payload SHA 須以本輪實際重建報告為準，不能拿文件 head 取代。

## 已讀原文與身分

- 捷運局《捷運技術》48期，頁134–135：VAL256為馬特拉VAL系統衍生，1991出廠，1996-03-28木柵線營運；51對102輛、每對兩車。每車13.78×2.56×3.53m、每側2門，獨立客室無貫通通道。GEC ALSTHOM TRANSPORT 1991銘板有實照，馬特拉系統供應／GEC整車製造與後續龐巴迪控制改造須分開；不把改造商當原車製造商。
- 同書頁135：內湖線龐巴迪車101對202輛，主要由匹茲堡製造，其中51對在唐榮車輛科技組裝，13.78×2.54×3.53m。正式營運資料使用370型；INNOVIA APM256是產品辨識名，CITYFLO650是號誌，不當車型。2009-06-30上線與2009-07-04營運通車分開；370專文英文摘要年份與中文內文不一致，保留衝突。
- 北捷370營運專文：A/B車均有端部控制臺；AX/BY端偵障桿位於行走輪與導引輪之前。第48期同步控制表寫A-B-A-B，路網規劃手冊卻寫A-B-B-A且僅A駕駛，**尚未取得足以消除衝突的兩款專型角色／方向配置圖**。
- 2009–2010 VAL256控制改造、2010-12-26復駛與其原製造責任分開。2023–2025內裝空間優化不據此捏造外殼批次。LED燈具照片與未LED歷史照片分開。

上述尺寸沒有明示車體長／連結面距／量測基準，不將13.78m冒稱已證實的車殼長。採購、逐批交付／驗收日期與供應商責任細分仍不足。完整來源URL及照片SHA／權利在 [sources.json](sources.json)。原照只在本機觀察，沒有公開照片、第三方幾何、照片貼圖或商標。

## 角色、四車與交界

兩款各有A、B兩個獨立草稿單元，近遠共8項；兩款各四車近遠共4個通用assembly。草稿依A-B-A-B，+X暫定A的AX／B的BX；單元未預先轉向，assembly全0度。+Y為朝+X觀看的左側，+Z上，跑道接觸面Z0；行走輪中心暫用x±4.65、y±0.94、z0.40，輪徑0.80m，這是配適值，非官方軸位尺寸。

| 順位 | 暫用角色 | 中心X（m） | 旋轉 | 連結面距假設 |
|---|---|---:|---:|---:|
| 1 | A | 20.67 | 0 | 13.78 |
| 2 | B | 6.89 | 0 | 13.78 |
| 3 | A | -6.89 | 0 | 13.78 |
| 4 | B | -20.67 | 0 | 13.78 |

同對內端與車對間使用不同連結器幾何，不加貫通風擋；每車兩個單軸行走結構、四膠輪、水平導引輪與簡化集電靴，不使用鋼輪列車的雙軸台車／軌面或受電弓。但安全輪／轉轍鋼輪、精確集電器與隱藏設備尚未查明，**目前不算全部實際角色或完整走行裝置完成**。

照片可讀30+16（VAL）及130+114（370）兩個車對交界；日期未知，且字母角色／完整四車號碼未同圖證明。因此這兩組號碼僅是歷史交界線索，**沒有把它們宣稱為已證實的近期完整代表列車**。完整四車側面圖無可讀號碼，與有號無日期照片分開記錄。assembly目前為無車號的角色草稿，來源條件仍不符合最終代表編組。

## 共用／獨立／未知

沿用最新main的StationKitBuilder.box／face等primitive；本輪WenhuMesh僅封閉prism、輪圓柱、裁切及圓角窗等primitive。兩款分開的截面、鼻面函式、配色及端面位置，不匯入既有Q比例車殼。原參考套件的engineeringDimensions為空或Q比例bounds、short2明標illustrative，不取代實車尺寸與四車證據。外部沒有匯入程式或新依賴。

鼻部／車頂／輪組量測基準、A/B獨有設備、左右非對稱與外端燈具狀態、底部安全構造：資料不足。草稿中對稱補全及尺寸配適不算已確認。首輪矩形風擋、門葉色界、燈具與屋頂方盒已以真正頂點續修；前稿未獲使用者接受。

## 營運與保護

`Map3DRealTrains` trtc/BR→wenhu四車；TrainType APM亦對wenhu。BR不能可靠區分本兩款，沒有另加奇偶／比例／隨機分車。既有Map3DTrainSets、Map3DTrains、Map3DModels營運選用、燈與fallback未改，僅追加studies。合併本草稿也不會讓營運自動選用。GameCore／存檔／fixtures／購車解鎖／班表／動畫／控制／全域palette／loader／gate不動，EMU700 #1730及素材#45不動。

完整runtime保護使用未改main與候選實際standard/studies匯出、逐native bytes及全頂點欄FNV、索引順序比較，見tools/wenhu/protect.py；不是假設export --all涵蓋全部。standard常駐新增0；裝置CPU/GPU與營運效能未驗。

## 重建與未完成驗收

Swift6.4 warnings-as-errors；從公開checkout根目錄：

```sh
git worktree add --detach /absolute/before-checkout 91a31f0837b4076b6c17f5f4ffe0bea81b504ed9
(cd /absolute/before-checkout && tools/wenhu/rebuild.sh /absolute/before-output)
# 本輪幾何 producer f9b1550a5d67f1f25f9361092b76fcb357ba9ceb
tools/wenhu/rebuild.sh /absolute/output
node tools/wenhu/render.mjs /absolute/output /absolute/before-output
python3 tools/wenhu/sheets.py /absolute/output
python3 tools/wenhu/curate.py /absolute/output
```

通用GLB/package/audit、native讀回的實際執行結果另記。共同尺度渲染固定單車13.80m框／完整55.12m框，兩款與近遠同相機光線；單車與全列框不同，沒有各自auto-fit。WebGL不代表Metal／Simulator／實機或動態碰撞。

尚缺：正式角色方向與有時期四車實號編組、完整逐向來源（特別完整車底／輪組）、白模先行的完整檢查紀錄、近遠跳變與實照旁置全部部件通過、file://及裝置驗證。其餘已實際執行項目見下段與報告，不將分項成功當成全部完成。四態維持UNVERIFIED；不可把通用audit代替這些。

以本文件head的兩份delivery JSON（producer固定f9b1550a5）搭配上述輸出，可執行：`python3 tools/train-models/deliver.py /absolute/output/val256 docs/art/wenhu/val256-delivery.json /absolute/delivery/wenhu-val256/revision-1`，APM相應替換；輸出不得已存在。該設定產生最終自含viewer；後加README／驗證報告不影響viewer。

原生車體截面寬VAL2.56m／APM2.54m，含外凸門構件的整體bounds寬為2.655／2.635m；官方車寬的量測包絡未確認，不把它們視為同一正式量測基準。車列全長55.12m同樣採13.78m連結面距假設。

## 本輪實際驗證

最終producer、每項輸出SHA、真前稿91a31f0（未接受）的同尺度比較與獨立checkout讀回，見provenance.json；最終執行結果見verification.json、png-verification.json、protection.json。幾何producer、文件head與素材commit分開，不從文件head猜producer。

端下凹腔已由鼻面頂點形成，外端連結器為有孔八角環體與支承桿，燈座為環體。玻璃分格依同一鼻面breakpoints貼合，不以黑板封口；行走輪與導引輪包絡分開。近遠共同輪廓高度3.53m，細節不越出遠景包絡。外觀仍須與不足的來源分開判斷。

專用檢查覆蓋全部8單元：每個外向玻璃面質心的可見及65mm內支承、4行走輪／8水平導引輪／2HVAC之連通固體與接觸、導引輪包絡、端孔4射線與端下凹腔2射線。每單元13類真正頂點／連通固體故障及2類端部破壞必須拒收；每份真正四車assembly另5類錯序／漏角色／間距／反向故障。共用audit另拒收缺面／反面。這些是具體取樣與包絡檢查，不是完整工程碰撞認證；不能驗證尚無來源的安全輪或集電器BOM。

親看紀錄分為「已符合」可見的原生鼻面分段、色界、玻璃支承、凹腔及近遠共框；「合理簡化」小螺絲、管線與可見輪組配適；「資料不足」正式角色方向、各角色設備、隱藏安全／轉轍輪、完整集電機構、帶時期完整實號編組；「仍不符合」全部實車角色與完整走行裝置的來源驗收、完整正交屋頂／車底逐圖覆蓋。沒有已接受前版，未獲本producer的使用者外觀接受。

互鏈 [公開draft #1742](https://github.com/a91453/railway-game-ios/pull/1742) ↔ [素材draft #47](https://github.com/a91453/railway-assets-private/pull/47)。來源與裝置等缺口使整體交付仍未完成，保持draft。
