# 七節暖白霧藍低裙板都市電車

獨立配方 `Sources/GamePresentation/Map3DSevenCarBlue.swift`；僅共用專案的封閉 box／tube／凸面、palette、原生轉換與匯出工具。沒有呼叫其他列車車體、底盤、車頭、門窗或編組配方。前批車輛只作霧面、色票和細節密度比較。

## 判讀與展示規格

作者七張 inline 圖均已實際查看：屋頂／前端一張、完整相反斜視四張、相反側面局部兩張。沒有本地原圖，不能記原圖 SHA 或製造精確正交參考。沒有唯一匹配的真實型號；不擅稱特定城市或製造商。檢查過私庫世界版 formations.js、rolling-stock catalog、台灣 danhai.json（Q-proportions、engineeringDimensionsM=null），都不能證明本圖的工程尺寸或隱藏軸式；不取其 mesh 或 Q 比例。來源資訊只供判讀，沒有原圖／mesh／貼圖進公開庫或外部生成服務。

| 特徵 | 本次採用與依據 |
| --- | --- |
| 類別／編組 | 七節近等長低裙板都市電車：端＋中×5＋反向端，六風琴；頂視九大設備箱＝兩端各2＋中間各1。靜態直線組裝 |
| 主輪廓 | 側面直腰線、窄白上緣、白屋頂、藍肩線；端部上端後收的斜風擋；俯視端部稍收窄；底部低裙板、僅露小輪下緣 |
| 頭尾／左右 | 兩端同型駕駛室朝外；中間無駕駛窗／燈；端節門窗方向隨駕駛室鏡置；兩側同節奏；只有前端集電弓，尾端不添一支 |
| 門窗 | 端節每側1組雙門＋內小窗／寬客窗／窄駕駛側窗；中節每側2組雙門＋小／寬／小三窗；全組每側12組雙門 |
| 屋頂 | 端節各2大設備箱，中節各1大箱及2扁平蓋；單端集電弓置於兩箱之間，有底座／絕緣支承 |
| 走行與車底 | 圖可見小輪、裙板遮住上部；真實架數／軸式不明。每節2架×2軸、全組28軸是隱藏幾何的**展示補全假設**，不是已識別車型的資料 |

**下表全為比例推估的公尺展示規格，不是工程尺寸；不把透視像素當工程量測。**

| 項目 | 規格 |
| --- | --- |
| 端節／中節殼長 | 8.2／7.4 m；端節略長，沒有舊七節長短交替 |
| 寬／屋頂軌面高 | 2.65／3.25 m（門框略寬） |
| 端部收束／風擋離垂直 | .95 m／約10.2°；前橫截面寬為直身93% |
| 輪徑／架內軸距 | .50／1.04 m，隱藏補全；兩架中心距端節5.00／中節4.56 m |
| 外軸至殼端 | 端1.08／中.90 m，裙板遮住輪頂 |
| 殼底／裙板下緣／全寬底板下緣 | .60／.18／.55 m，輪頂.50，50 mm淨空；裙板只在左右兩邊 |
| 窗底／頂／門寬 | 1.065／2.705／1.30 m（雙扇）；側窗細框，不做連續黑窗帶 |
| 大設備箱／集電弓頂 | 3.417／4.120 m（相對軌面） |
| 殼間距 | .20 m；各內端自帶半風琴，組裝後接合 |

配色取現有 `trimBlue`、`shopAwnings[3]`、`tankWhite`、`glazing`，低彩度霧藍、暖白、淺灰門葉；細中縫、寬門玻璃和與窗齊頂。無紅色漆、照片貼圖、品牌或個資。材質 roughness=1、metallic=0、霧面頂點色。配色可調，結構按本輪參考。

## 原生組裝

原生 +x前／+y左／+z上、公尺；建模器x前／y上／z右，只在`.flat`轉一次。所有單元已含正確朝向，只做以下平移，不另旋轉或鏡射。共同軌面z=0。

| 順序 | ID | 中心x m |
| --- | --- | --- |
| 前端 | blue-seven-leading | 23.2 |
| 中1 | blue-seven-middleOne | 15.2 |
| 中2 | blue-seven-middleTwo | 7.6 |
| 中3 | blue-seven-middleThree | 0 |
| 中4 | blue-seven-middleFour | −7.6 |
| 中5 | blue-seven-middleFive | −15.2 |
| 後端 | blue-seven-trailing | −23.2 |

完整編組`blue-seven-formation`。實際bounds／三角數取manifest，不從表格反推。兩個比較單元`metro-four-leading`、`lrt-seven-leading`只作風格比較。只有靜態素材註冊，**合併不會自動替換營運列車**；未加車型指派、物理或鉸接動畫，不改GameCore／Map3DTrainSets／存檔／golden／replay。

## 重建

OUT放公開庫外。使用Swift6.4、Node、Playwright、Chromium、Python/Pillow、Blender；沒有新增遊戲依賴。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DSevenCarBlueTests|Map3DModelTests|Map3DModelFileTests'
tools/seven-car-blue/export.sh OUT
node tools/seven-car-blue/review.mjs OUT
# 親自查看實際原生配色、白模、剪影後，修幾何再重新匯出；才做完整批次
node tools/seven-car-blue/render.mjs OUT
node tools/seven-car-blue/clay.mjs OUT
node tools/seven-car-blue/art-checks.mjs OUT
node tools/seven-car-blue/verify.mjs OUT
node tools/seven-car-blue/geometry-audit.mjs OUT
python3 tools/seven-car-blue/mutation-check.py OUT
blender --background --python tools/seven-car-blue/glb-audit.py -- OUT
python3 tools/seven-car-blue/verify-png.py OUT
node tools/seven-car-blue/standalone.mjs OUT
node tools/seven-car-blue/browser-check.mjs OUT
node tools/seven-car-blue/browser-check.mjs OUT --standalone
python3 tools/seven-car-blue/bundle.py OUT ACTUAL_PRODUCER_COMMIT
```

若有幾何修訂，以真正前版匯出目錄`PRIOR`執行`feedback-compare.mjs OUT PRIOR`及`... OUT PRIOR cab`；兩版用同相機中心、範圍與尺度。沒有改動就不捏造前後。首次ZIP後重測folder/standalone、重新bundle，再重測現有ZIP並確認成員逐檔不變。bundle強制git實際producer每個配方／工具位元相同，ZIP完整解壓／CRC／成員集合／逐檔位元比對。

全10件（7單元＋編組＋2比較）各7向透明512PNG；各件固定公尺尺度、7單元共用尺度。編組正交稽核.035m/pixel；同尺度風格比較使用共同相機。前端放大／hero各自取景，勿當同尺度。白模與剪影只改同一原生頂點色。透明圖完整解碼／alpha／邊界；viewer逐件載入、旋轉、縮放、native/GLB/PNG/ZIP真下載比SHA。玻璃除框支持外還需65mm內真實車殼／門葉，封閉邊與有向平衡抓缺面／反面；故意移開封閉玻璃抓浮空。

公開只配方／工具／必要測試／文件／一張總覽。完整素材和來源紀錄放私庫`Railway/game-art-previews/docs/art/seven-car-blue-2026-10-23/`。外觀結論與技術結論另記；Linux WebGL不代表真機Metal／效能／動畫。單檔viewer以斷網內嵌HTML驗證，環境不提供OS雙擊file://，該操作UNVERIFIED。
