# 原生吊廂透明玻璃

只新增可明確啟用的材質與繪製流程。既有trainGlass／trainGlassLit仍是原來的不透明反光材質；沒有修改任何吊廂配方、模型pack的standard、營運映射、GameCore、存檔、golden或fixtures。

```swift
let source = try Map3DModelFile(decoding: bytes, named: "cabin").model
let pack = Map3DTransparentGlass.studyPack([source])
// 由已有的study host明確呼叫 renderer.useModels(pack) 並提供實例。
// 本PR不把pack接到地圖或營運。
```

只有已標成trainGlass／trainGlassLit的三角會轉換，鋼材、框架、椅及一般塗裝不變。不憑顏色猜玻璃。原生模型+z朝上，|normal.z|>0.8的水平玻璃用地板設定；其他玻璃用窗設定。預設每表面opacity窗0.14、水平玻璃0.06，封閉薄板有內外兩面，效果會累積。可用Style調整，不是真實光學厚度／折射模型。M3DM v1原檔與格式不變，讀回後才opt-in。

材質新增layer −16／−17（後者夜間發光）。頂點u為透明度，v保存原反光遮蔽值，color alpha仍是線色替換比例，40-byte ABI不變。Opaque pass丟棄新材質片段；之後在sky／ground shadows都畫完後，依所有實例的各三角視深度遠到近做source-alpha混色，使用既有reversed-Z測不透明深度，不寫depth。雙面繪製可從廂內、廂外或地板下方看；新材質不寫太陽深度圖，不投整塊不透明影子。既有材質走原分支。

這是常規三角中心排序，沒有宣稱order-independent transparency；相交／交織透明曲面仍可能需要切分。透明pass支援這批model實例，不支援把材質直接丟進city chunk或靜態prop run。沒有啟用中的模型時，不建立每幀玻璃batch。

現行main的貓空Swift配方把部分玻璃當plain色塊；這輪不去改它。後續接入時須由配方以語意標記玻璃、再明確套材質，不能拿色碼認玻璃。本輪以真正貓空與日月潭M3DM studies（含玻璃旗標）核對原生流程，不把GLB／WebGL畫面當Metal證據。

## 驗證

**VERIFIED（Linux）**：Swift6.4 `swift build --build-tests -Xswiftc -warnings-as-errors`，`swift test --skip-build --filter 'Map3D(TransparentGlass|ModelFile|TrainMaterial|TrainLights|Reflection|CableCar)Tests'`，52個相關測試通過（其中9個新材質測試）。另以 `tools/native-glass/check-cabins.sh FIXTURES REPORT.json` 真正讀回貓空／日月潭8個近遠景M3DM，驗玻璃／水平玻璃設定、opaque全屬性保持、雙實例world normals與全局排序；見native-cabin-cpu-verification.json。驗材質選擇、水平玻璃／夜燈、有限值、跨實例及模型內三角視深排序、鏡頭反向、同深穩定順序、非等比變換法線、塗裝alpha不冒充透明、零透明與非法輸入、standard沒有opt-in。

macOS：`tools/native-glass/run-metal.sh OUTPUT FIXTURES`。腳本抽出Map3DMetalView真正使用的pipeline工廠，編譯同份Map3DShaders.metal及Swift，沒有另造一個近似shader。Metal可用時做真offscreen blending／透明地板／不透明遮擋／depth不寫入／跨實例排序／1x與4xMSAA，以及關閉blend、錯depth write、倒序三種故障反例；再畫真吊廂日夜／斜面／底面及不透明基準。runner若沒有MTLDevice，JSON明寫GPU UNVERIFIED，不會拿編譯當出圖。

[Native glass Metal probe workflow](../../../.github/workflows/native-glass-metal.yml) 只用read權限與暫存輸出；從本repo固定producer恢復公開配方產生M3DM，不存取私庫／密鑰。貓空producer5cfec2954、日月潭074b085c；來源與尺寸限制承接各study SOURCE。原模型無改，不重新分發原照片／品牌／人物。

iOS SDK／Metal真實渲染以本PR CI實際結果為準；真機效能、作者外觀接受、平台間隙、載重與營運接入仍UNVERIFIED。macOS offscreen不是iOS裝置。未合併、不auto-merge、不TestFlight。下一步：作者看原生證據後，再另派是否接入特定studies；沒有自動變更已上線吊廂。

### CI 核對補記

`a6a9587` 的 [Swift CI](https://github.com/a91453/railway-game-ios/actions/runs/41844401938) 與 [iOS build／Simulator smoke](https://github.com/a91453/railway-game-ios/actions/runs/41844401425) 已成功（VERIFIED；iOS 使用 runner 的 Apple SDK，不等於真機或透明玻璃出圖）。獨立 [Metal probe 41844401509](https://github.com/a91453/railway-game-ios/actions/runs/41844401509) 在版本檢查停止：Xcode 26.6 隨附 Apple Swift 6.3.3，未符合 SwiftPM 檢查限定的 6.4。沒有執行 GPU，也沒有圖像。workflow 現明確下載／檢查簽章／安裝 swift.org 官方 6.4.0 pkg，僅替此獨立 job 選用 toolchain；版本檢查保留，完整顯示版本訊息。修後 Metal 編譯與出圖仍以新 run 實際結果為準（未跑前 UNVERIFIED），不放寬版本要求來消除紅燈。

第二次 probe 41928962732 已用官方 Swift 6.4 完成實際 Metal shader 與 GamePresentation WAE 編譯（VERIFIED），接著工具的固定中間目錄定位失敗，GPU 未執行。現抽出共用 build-inputs.sh，依模組實際位置尋找 SwiftBuild 產物、接受檔案或目錄型 swiftmodule；test-build-inputs.sh 覆蓋 classic／SwiftBuild、不同套件及 target 名稱，不將定位修正算成 GPU 驗證。
