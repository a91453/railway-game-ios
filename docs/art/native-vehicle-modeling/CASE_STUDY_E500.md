# E500 實例：連續設備殼、正面屋頂與局部修訂

這次的教訓是：**設備的縱向分區、橫向截面與安裝高度要分開控制。** 側面排出幾組格柵，不代表中央機殼應該斷成幾個盒子；一塊有支承的共用底座，仍可能在正面形成過寬的「帽沿」。

第三版交付後，使用者回覆「好可以 那需要順便寫製作過程交接手冊嗎」。[接受範圍紀錄][acceptance]對應下列第三版外觀，沒有外推成工程復刻、真機 Metal／效能／動畫或合併／發版授權。這次文件化保持已接受配方、工具執行碼、模型、圖、viewer、ZIP與producer不變。

## 1. 真版本與接手入口

| 項目 | 固定來源 |
|---|---|
| 第一版 | producer `8127c765f8c07570de17b813b6329b93d9871a68`；私庫 `269773e298f974bfaac95b0a1de22f08d70772dd` |
| 第二版，屋頂被圈選要求修改 | producer `68913f4f8c5dd4a681c3ce58140aad3e479c015f`；私庫 `a0dd9016a2e542d1104c1a6aac06fa40f4334b5e`，revision-2 |
| 接受的第三版 | producer `85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a`；私庫 `1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2`，revision-3 |
| 工作追蹤 | [issue #1255](https://github.com/a91453/railway-game-ios/issues/1255)；[公開 draft #1256](https://github.com/a91453/railway-game-ios/pull/1256) ↔ [私有 draft #84](https://github.com/a91453/railway-reference-private/pull/84) |
| 原生配方 | [固定producer的 Map3DE500.swift][recipe] |
| 來源、特徵、營運與限制 | [第三版製作交接][handoff]，其中保留第二版歷史記錄 |
| 完整重建順序與環境 | [專用工具 README][tools] |
| 最終預覽 | [第三版原生總覽][overview] |
| 真正前後 | [第二／三版近景四向][comparison]、[遠景四向][comparison-far]（需私庫權限） |
| 完整交付 | [私有 revision-3 索引][assets]，含七向、四向配色／白模／剪影、GLB、原生、比較、來源與驗證 |
| 可下載素材 | [完整 ZIP][zip]、[離線 viewer][viewer]（需私庫權限；下載 HTML 後開啟，GitHub blob 不執行 viewer） |

文件分支從當時最新main `289fc7d02dec0ee58e0f5516e0e5fb94852cf18c` 建立；兩張模型PR在文件接手時仍是draft、尚未合併，不能假設配方和專用工具已在main。上表刻意使用固定commit，後續main變動不會悄悄替換本案例的證據。

## 2. 先分清來源、尺寸與資料缺口

| 來源 | 可以判讀 | 限制 |
|---|---|---|
| [東芝2024 Vol79 No5 f02.pdf][toshiba]，圖1／4／5 | 實車、Co-Co、20,770mm車長、雙端艙、高壓／中央冷卻／另一端設備分區、一組可見單臂弓 | 沒有完整工程圖，不能補出另一端對稱集電弓或所有隱藏管線 |
| [E506彰化實車照][photo] | 平側板、斜風擋、深色圓收罩、燈組、門、端部與輪架交叉比對 | 單張透視不能確認另一側或精密站位 |
| [E500公開彙整][dimensions] | 寬2.759m、降弓高4.280m、輪徑0.924m、軌距1.067m | 二手資料，來源層級與原廠長度分開記錄 |
| 使用者首輪七圖 | 一張署名K.Y.Chung／Nanyue Express示意、六張模型展示；比對輪廓與配置 | 未稱模型展示為實車；示意標示CC BY-NC-ND，只觀察結構，不描線／取圖素／再散布原圖 |
| 使用者後補五圖 | 三張實體鐵道模型照片、兩張彩色輪架／屋頂結構示意 | 逐張實看；模型塗色、透視像素與示意色塊不是工程規格 |
| 使用者圈選第二版及參考側圖 | 精確定位中央格柵列與正面灰色過寬平台 | 圈選表示要求修正，沒有確認隱藏結構 |
| 私庫e500.webp、metadata與三張側面圖示 | 首輪四張逐張查看，找出既有簡化資產的差異 | metadata工程尺寸null、Q比例長9.818m，不能當實車尺寸或沿用整排側格柵 |
| 已接受Codex E200／EMU3000 | 色票、霧面與細節密度 | 不借用車殼、車頭、門窗、底盤或設備站位 |

轉向架中心±6.1m、各架軸偏移±1.65m、設備殼寬高與站位均為**比例推估**，不是從透視像素量出的工程尺寸。兩端艙可見，不代表左右設備與屋頂配置必須鏡像。未見側／底部接線、內裝、精密懸吊機構仍屬資料不足。

原始私有圖片／mesh／貼圖沒有公開或送外部生成服務。最終為獨立程式建模，使用遊戲綠松／藏青／灰色票與霧面頂點色，沒有紅色、真品牌、車號或個資。

## 3. 製作順序與兩次回頭修形

先確認原遊戲實際使用的E500與營運映射，再做公尺長寬高、側／正／俯／斜主輪廓、雙端車頭截面、兩組三軸輪組、門窗與大型設備，最後才補格柵、燈框、扶手和端部管件。原main對照為base `41c00fa51f7975d1423b1645aadb9d5b019ff6a1`，不是事後倒造的差版本。

第一版對走行、屋頂與車頭的「已符合」自評過寬；使用者補圖後撤回，沒有用封閉測試通過反駁外觀偏差。第二版補連續輪架側架、軸箱／彈簧／拉桿、車頭平面圓收、風擋罩／膠囊燈座、端梁／連結器、分片側玻璃及有支點扶手。依原廠圖4／5移除無證據補出的後端收折弓，保留一組單臂弓；正面上弓臂不再形成寬A架。

第二版仍有屋頂主形偏差，使用者圈出後，第三版只修屋頂。不能因前次已做過屋頂或技術檢查綠燈，就繼續把它列「已符合」。

| 第二版的問題 | 第三版修法 | 必須保護 |
|---|---|---|
| 三個分離中央箱把連續機殼誤讀成幾座小盒 | 一座連續中央外殼，近景六格框／百葉；遠景同一外殼、簡化連續格柵帶 | 大平側板、車殼與兩端艙 |
| 共用高底座長14.5m、寬2.38m，正面像大帽沿 | 移除整片高底座；設備殼直接坐在真平車頂Z=3.75m | 風擋、黑罩、圓燈、雨刷、門窗 |
| 中央箱過高、另一端高度層次不清 | 收低中央殼，保留較低長殼、上肩小倒角與薄蓋板 | 兩組輪架、端梁、管線與配色 |
| 高壓托盤過寬，與大底座一起擴張正面 | 較窄支座貼頂承托較窄托盤 | 既有集電弓機構、絕緣子與最高點 |

**機殼、分格、格柵是三層結構。** 先定連續殼體及橫向截面，再在殼上排格；不要直接用格柵數量決定盒子數量。另查底面是否真的坐在屋頂、上部是否過寬、從目標相機看是否成帽沿。把設備埋進車身或用裝飾擋住接縫，都不能代替修正支承與輪廓。

## 4. 用真正輸出證明局部修改

[roof-audit.py][roof-audit]比較真正第二／三版完整52-byte原生三角記錄的多重集合，包含實際頂點payload與旗標，沒有只比較配方常數。

- 全部三角差異限本案屋頂ROI：`|X|≤7.30m、Z≥3.60m`。
- ROI外近景7,876／遠景3,652個三角記錄逐bytes保持；集電弓機構與絕緣子另核實際記錄，總XYZ bounds保持。
- [revision-audit.py][revision-audit]仍核真正第一版輪胎／中央側板三角、201縱向殼切片與XY包絡，保護先前已做對的部分。
- 181個其他原有模型相對隔離base41c00fa5的payload保持；不擴稱已本機測過另一分支後加的所有模型。

總bounds相同不等於局部硬體相同；側面上下包絡相同也不等於所有側面色塊或投影像素相同。ROI、切片、payload和固定相機對照各回答不同問題。

下列數值直接量最終原生幾何，**不是實車工程尺寸、相似度或通用門檻**：

| 模型量測 | 第二版 | 第三版 |
|---|---:|---:|
| Z=4.00m中央殼連續截線，近／遠 | 每段約2.10m | 連續6.60m |
| 上部正面幾何包絡寬，近 | 2.380m | 2.051m |
| 上部正面幾何包絡寬，遠 | 2.380m | 2.002m |
| 中央屋頂最高點，近 | 4.313m | 4.190m |
| 中央屋頂最高點，遠 | 4.270m | 4.140m |

真正第二版在連續截線、寬度、頂高三項近遠各失敗，共6項；第三版通過。另刪除實際中央殼橋面、把實際屋頂頂點加寬，檢查必須能拒收。這比斷言「格柵數=6」更能抓出看得見的缺陷，但仍不能代替看圖。

## 5. 看過原生四向，才重出全套

每次改幾何後，先自己看近遠景側／正／俯／斜的配色、白模、剪影及同相機同公尺第二／三版對照。第三版從這些圖確認分離小盒、過高箱列與正面大帽沿已修；未見內部機構仍列資料不足。保留真正前版模型，不靠把新版調壞製造前後差異。

本案只有一個獨立機車單元：中心(0,0,0)、旋轉0°，沒有單元排列或間距；近遠是同車的兩個LOD。原生公尺X前／Y左／Z上，輪底Z=0；builder X前／Y上／Z右只轉換一次；GLB=(x,z,-y)。完整包絡X±10.385、Y±1.540、Z0–5.381m含踏板、連結器與升弓，不能稱車殼寬或降弓高度。

第三版近景9,964、遠景3,992三角，沿用E500專用近景10,000、共用遠景4,100上限。本輪未增加預算；不把這些上限套成所有車型的規格。

所有最終視圖由同一份最終原生模型產生，再導出GLB、每件七向透明PNG、四向配色／白模／剪影、完整預覽、風格比較、真前後、viewer與ZIP。最終總覽與先行檢視版本逐像素相同，三張原生來源PNG也全同；不是另一套概念mesh。

## 6. 交接時分開記錄驗證層級

以下是**第三版製作當時**的紀錄與[私有證據][assets]；本輪純文件沒有重跑模型／Swift／viewer／ZIP驗證。

| 層級 | 實際範圍與限制 |
|---|---|
| 外觀 | 使用者接受固定producer第三版；不代表工程復刻或其他修訂也接受 |
| Swift | Linux Swift6.4 warnings-as-errors建置；38項相關測試，1項既有成本skip、0失敗 |
| 原生 | 真讀回、法線、有向封閉／正體積；缺面／反面實際三角反例拒收 |
| 裝配與可見性 | 玻璃背襯／向外可見性、12輪胎貼軌／上方淨空、屋頂與輪架取樣支承；浮／埋玻璃、升輪、浮架、拉長燈反例拒收；非完整碰撞／懸吊驗證 |
| 屋頂與保護 | [roof-verification.json][roof-proof]記實際切片／投影包絡、真第二版6項失敗、刪橋面／加寬故障、非屋頂與弓記錄保持 |
| 交換格式 | Blender4.3.2獨立匯入8個GLB，核軸向、bounds、三角、頂點色、霧面與無貼圖 |
| PNG | 56張七向RGBA透明圖、全包159張PNG完整解碼／非空／留白不裁邊 |
| viewer | Chromium實際載入8模型、七方向、拖轉／縮放、native／GLB／PNG／ZIP下載SHA、390px與離線嵌入檢查；未稱Safari或真機已驗 |
| ZIP與來源 | 228 members完整解壓、CRC、檔案集合及逐檔bytes；source對真producer；GitHub重新下載ZIP亦核SHA及解壓內容 |
| 同producer CI | [Swift run 40242439742][swift-ci]、[iOS run 40242439717][ios-ci]；文件接手查詢仍in_progress／結論null，不能寫成通過；讀者須再查同85647d0a的最新結果 |
| 真機／動畫 | Metal、FPS／記憶體、人工Simulator外觀、輪轉／門／弓／輪架動畫、懸吊／接觸網／全動態碰撞仍UNVERIFIED |

ZIP SHA-256：`981ac319c755765457b66d6de5afdb2bcefd899a341655a26782d1d58969d498`，見[package-verification.json][package-proof]。來源SHA、模型與圖片記錄在manifest／source.json；這份案例文件不是素材producer，不得將文件head寫回素材來源冒充重出。

## 7. 重建與實際遊戲替換

先以固定producer開獨立worktree，照[工具README][tools]指定Swift6.4與依賴執行。依序取得base41c00fa5的真原生、真第一／二版及初版觀察輸出，匯出、原生／支承／屋頂／保護稽核、先行四向看圖，再全量渲染、GLB獨立匯入、PNG、viewer實際下載、封包與來源驗證。工具命令中的`BASELINE`、`ACTUAL_REVISION_1/2`、`ACTUAL_FIRST_PASS`是必須準備的真檔案目錄，不能拿當前輸出自當基準。新修訂使用自己的真producer，不覆寫已接受的包。

營運接點是公開PR內的`Map3DTrainSets.swift`：E500CK、MINGRI、STAR的機車頭使用E500專用近遠景；效能alias `e500ChuKuang`對應E500CK。<500m近景、500–<900m遠景、≥900m沿用盒形回退。其他使用E200CK的莒光不變；客車、其他包／classic／解鎖／fallback及玩法不隨本次屋頂修訂改動。

**公開模型PR合併並重建App後，上述營運E500才實際顯示。** 私庫素材合併、只註冊GLB或本次文件PR合併都不會更新App；已安裝App也不自動變更。升弓只是靜態姿態，沒有因此驗證任何動畫。不推main、不合併、不開auto-merge或TestFlight。

下一位AI先讀本案例與[獨立驗收表](REVIEW_CHECKLIST.md)，再看真模型四向；將連續外殼、分格與格柵分開，保護已接受部位。E500的尺寸推估、設備站位、ROI、切片高度與預算不能移植成另一型機車的規格。

[acceptance]: https://github.com/a91453/railway-game-ios/issues/1255#issuecomment-6404729265
[recipe]: https://github.com/a91453/railway-game-ios/blob/85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a/Sources/GamePresentation/Map3DE500.swift
[handoff]: https://github.com/a91453/railway-game-ios/blob/85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a/docs/art/e500-refresh-2026-10-25/README.md
[tools]: https://github.com/a91453/railway-game-ios/blob/85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a/tools/e500-refresh/README.md
[overview]: https://raw.githubusercontent.com/a91453/railway-game-ios/85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a/docs/art/e500-refresh-2026-10-25/overview.png
[comparison]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/previews/revision-2-vs-3.png
[comparison-far]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/previews/revision-2-vs-3-far.png
[assets]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/README.md
[zip]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/asset-package.zip
[viewer]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/viewer-standalone.html
[roof-audit]: https://github.com/a91453/railway-game-ios/blob/85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a/tools/e500-refresh/roof-audit.py
[revision-audit]: https://github.com/a91453/railway-game-ios/blob/85647d0a5e5eaaebdcdee1d5bc512fd931ee6c3a/tools/e500-refresh/revision-audit.py
[roof-proof]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/roof-verification.json
[package-proof]: https://github.com/a91453/railway-reference-private/blob/1b74b0a8cb5b1f8f2a0c38f89c843808a004e5f2/Railway/game-art-previews/docs/art/e500-refresh-2026-10-25/revision-3/package-verification.json
[toshiba]: https://www.global.toshiba/content/dam/toshiba/jp/technology/corporate/review/2024/05/f02.pdf
[photo]: https://commons.wikimedia.org/wiki/File:TRA_E506_at_Changhua_Station_20240410.jpg
[dimensions]: https://zh.wikipedia.org/w/index.php?title=台鐵E500型電力機車&oldid=94736285
[swift-ci]: https://github.com/a91453/railway-game-ios/actions/runs/40242439742
[ios-ci]: https://github.com/a91453/railway-game-ios/actions/runs/40242439717
