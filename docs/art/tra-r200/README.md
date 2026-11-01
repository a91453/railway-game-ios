# 臺鐵 R200／R216：第二輪原生近遠景 studies

本輪修正駕駛室／端面、走行設備與屋頂分層；不是營運接入。真正 producer、三角數及實跑結果見 [verification.json](https://github.com/a91453/railway-game-ios/blob/codex/tra-r200-native/docs/art/tra-r200/verification.json) 與完整素材的 manifest，外觀接受仍 UNVERIFIED。

[公開 draft #1589](https://github.com/a91453/railway-game-ios/pull/1589) ↔ [素材 draft #37](https://github.com/a91453/railway-assets-private/pull/37)。兩庫 base main，不合併、auto-merge 或 TestFlight。

## 身分、一般版本與來源

R200 是臺鐵訂購的 Stadler SALi 柴電機車，Stadler Rail Valencia 在西班牙製造，訂購34輛 R201–R234。Cummins 引擎、ABB 牽引變流器與 TSA 馬達的角色分開，不將設備供應商稱為整車製造商。代表 R216，依 Blair 2024-12-12 竹南一般白／深藍塗裝照片（ref-04）；不是活動彩繪、效果圖或運送封套版。

原始來源與逐圖 SHA／權利見 [來源與逐圖 SHA](https://github.com/a91453/railway-game-ios/blob/codex/tra-r200-native/docs/art/tra-r200/sources.json)。重新開啟 R216 全側、R201 正面與駕駛室／燈／連結器近照，對照最終原生圖。R201 2023-07-10 見面會只支持固定外觀，不當正式營運證據；R201 銘牌顯示2022製造，不能把概括的2023起生產當逐車年表。抵臺、整備、試運轉、驗收、首航分開；逐車製造／交付／驗收批次仍未核齊。

正式出國報告及 TSA 部分網址回403；舊 Stadler 網址改到無原新聞內容的頁面，不能宣稱已讀原報告。2021採購期二手資料20.000×2.852×3.900m，與後來二手as-built 20.010×2.852×4.080m不同；本模型暫採後者包絡，官方原圖仍 UNVERIFIED。輪徑／軸距、最大設備寬、批次BOM、官方1／2端、反側全側及正交屋頂／車底照不足。

原照片僅本機觀察，不公開原圖、照片貼圖、第三方mesh或私有路徑，不送生成服務。使用者附圖已目視，但原檔SHA／權利未取得。沒有捏造批次鼻形或固定試車儀器。

## 真正前稿與本輪修正

真正第一輪 producer **65464b23fc0b26058521d362555b9a0d8b550c98**，素材 commit `c30aa55dbd827a49d5914f29edde225339270090`。第一輪技術通過不等於外觀接受；製作者建議再修後，使用者明確說「那你改」。沒有已接受的準確 R200 前版。撤回將第一輪駕駛室輪廓及設備精密形狀視為定稿的推斷。

| 部位 | 第二輪實際修改 | 來源／限制 |
|---|---|---|
| 駕駛室、端面 | 共邊細分後做45mm微弧、下緣收角及頂部弧肩；加寬上部黑罩與風擋，移高方向顯示區 | R201正面；曲率是遊戲尺度推估 |
| 玻璃、燈 | 薄實體跟隨最終弧面，背面嵌接支承；左右燈座切角、分開雙燈群 | 實照固定設備，無Logo或文字貼圖 |
| 台車、輪組 | 保留12輪及軸位；移除封滿輪間的黑箱，改開放側框、橫梁、軸箱支架及輪盤 | R216全側；懸吊細節及尺寸是合理簡化 |
| 連結器與管線 | 單一封閉凹形鑄件、真正開口，兩端鑄件各向外定向一次，避免三個倒角盒重疊；每端四對彎管與分色接頭 | ref-20及附圖；閥件與彎曲是遊戲簡化 |
| 屋頂 | 機艙屋頂降至3.78m，獨立斜肩長罩、風扇座、排氣座與支承管線形成層次 | 斜側照；非已核齊屋頂BOM |
| 側格柵 | 進氣改直向肋條，散熱區保留三欄／分橫格及支架；遠景保留主分區 | R216全側；隱蔽側配置仍暫定 |
| 塗裝與契約 | 主要白藍分區、共同公尺尺度／軸位／軌面／連結器範圍保持 | 不改其他車或全域色票 |

本輪拓樸曾抓到屋頂過渡面方向錯誤與鑄件重複倒角面，已修原生幾何，不放寬共用 gate。端面背襯、階梯立柱、枕梁及吊座保持或貼合新曲面；沒有疊殼遮住第一輪。

## 幾何來源與座標配置

只調用既有 StationKitBuilder 的 box／beam／cylinder／face／civicTube。其最近原 producer 分別見第一輪記錄：StationKitGeometry `6edd8ccaa8d35d19684c71acee1719f3ba1a79af`、CivicKitGeometry `f5e72843ff1412e318e4415eab6cd53714cc49c2`。不修改 shared helper。車體、雙艙、玻璃、台車布局、設備與塗裝均為 R200 自有配方；新共邊細分／端面變形／凹鑄件三角化亦留在 Map3DR200.swift。

私有參考 Q 比例 R200 只有10.218m且工程尺寸null，不取其幾何或尺寸。舊 #910 producer86837eea 是單駕駛室近似，#923保留它，#710是2D設定，均不能當本輪準確R200外觀接受證據。

| 契約 | 數值／定義 |
|---|---|
| 原生 | 公尺、X縱向、+Y左、+Z上；原點機車中心、軌面Z0 |
| +X端 | 三風扇散熱端；-X長屋頂罩端；官方端號未核 |
| 左右 | 站在-X看向+X的左側為+Y，非照片觀者左 |
| 包絡 | 連結器最外端±10.005m；車體寬2.852m；階梯設備最大寬3.0m；最高4.08m |
| 端面 | 白端基準±9.45m，中央微弧外推最多45mm；下緣及弧肩按來源簡化 |
| 走行 | Co′Co′、12輪；輪心Z0.50m／輪徑1m，台車中心±5.90m，軸偏移±1.50m（比例推估） |
| 屋頂 | 機艙屋頂3.78m、長罩最高4.08m、風扇蓋3.99m；精確BOM未核 |
| 組裝 | 近遠各一完整合法單機，不需分件／assembly；正反展示只在模型外旋轉一次 |

## 近遠、比較及驗證

近遠用同一主形和主設備位置；遠景減面，不改軌面、軸數、白藍區及方向。兩端／左右、俯／底／斜的配色、白模、剪影及遊戲尺度均從最終原生頂點產生並親自開啟。真正R1→R2比較使用同相機、同光線、同公尺包絡，沒有各自auto-fit；照片未校準，不把透視像素當尺寸。公開只保留一張真前後總覽；完整素材每輪20張PNG。

原生讀回、有限數／退化／有向邊／正體積、逐輪接觸、兩端與側玻璃第一命中、格柵／燈／風扇／支承及真故障反例、獨立Blender、PNG、viewer與獨立producer重建結果以本型JSON證據為準。抽樣不是全視角碰撞或工程復刻。

```sh
# 在真正前稿65464b23的獨立checkout執行：
tools/tra-r200/build.sh /tmp/r200-r1
NODE_GLOBAL=/path/to/node_modules/ CHROMIUM_PATH=/usr/bin/chromium node tools/tra-r200/review.mjs /tmp/r200-r1
# 在本輪producer checkout執行：
tools/tra-r200/build.sh /tmp/r200-r2
NODE_GLOBAL=/path/to/node_modules/ CHROMIUM_PATH=/usr/bin/chromium node tools/tra-r200/review.mjs /tmp/r200-r2
python3 tools/tra-r200/curate.py /tmp/r200-r2 /tmp/overview.png /tmp/r200-r1
blender --background --python tools/train-shape-refresh/glb-audit.py -- /tmp/r200-r2
```

來源、配置、四態與比較輸入SHA須固定，不事後覆蓋metadata冒稱producer重建一致。完整素材的DELIVERY-SPEC記錄這些輸入；本輪替換同PR第一輪重檔，保留其PNG／README／來源。沒有ZIP／history／old／backup。

## 保護、營運與四態界線

僅 studies，同兩個R200 ID；不改standard、Map3DTrainSets／Trains／RealTrains、R200CK、他車、配車、回退、燈控、GameCore、存檔、fixtures、購車、班表或動畫。原始基準835既有模型已逐bytes及全頂點欄位核對保持；最新main另作實際全量對照，結果見 protection.json。原始基準33項既有共用檢查失敗／34鎖差異保留歷史證據；最新main另驗，不改他車鎖或gate，鎖只更新本輪兩項。

既有r200ChuKuang→R200CK仍用舊近似，尺寸／端別／營運身份接點不完整，本輪不換。沒有來源可靠且接點已核的代表性R216完整牽引編組，未湊客貨全列；單機不叫全列或動態行駛已驗。合併不會自動在遊戲選用。

素材技術依最終證據；明確producer使用者外觀接受、營運、裝置均UNVERIFIED。HTTP viewer不代替file://、Simulator、真機Metal／效能／動畫；離線直開先前被瀏覽器管理政策擋住，本輪亦須分開重驗。正式端號、反側／屋頂車底與批次BOM缺口仍保留。

最新上游基準 `2ebe025a317771e8c89f0c6301066c266c2454d2` 已帶入本分支；DR3100等上游變動與R200改動分開核對，不把上游模型／營運／規則變更算成本輪製作。真正交付producer與最新主線保護、模型包數字見驗證JSON。
