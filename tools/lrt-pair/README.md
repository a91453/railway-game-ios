# 五節綠松・七節霧藍輕軌

原生靜態配方分別為 `Map3DFiveSectionLRT.swift`、`Map3DSevenSectionLRT.swift`。五節改色，七節按作者四張新圖重新建立十二角截面、較陡且收窄的兩端、七單元門窗與設備；七節不呼叫五節的車體／底盤／門窗建模。共用專案低階封閉box／tube／facet、切面裁切原理與序列化。兩套只有靜態庫註冊，沒有營運、物理或動畫功能。

五節 `coral` 保留歷史public symbol名稱，但現在值為 `shopAwnings[0]` 綠松；七節 `trimBlue` 霧藍、`shopAwnings[3]` 暖白屋頂與細邊。玻璃用既有灰藍色票0.62明度，霧面頂點色、不用貼圖／品牌。最終兩套均無紅色漆。

## 單元組裝（公尺展示規格）

| 組 | 原生ID後綴，依+x到−x排列 | 殼長 | 中心x |
| --- | --- | --- | --- |
| 五節 | leading／suspendedFront／middle／suspendedRear／trailing | 9／4.1／7／4.1／9 | 12.5／5.75／0／−5.75／−12.5 |
| 七節 | leading／suspendedFront／middleFront／suspendedCentre／middleRear／suspendedRear／trailing | 9／4.1／7／4.1／7／4.1／9 | 18.25／11.5／5.75／0／−5.75／−11.5／−18.25 |

ID前綴 `lrt-five-`／`lrt-seven-`，完整編組後綴`formation`。原生+x前／+y左／+z上，**全部只平移，不旋轉或鏡射**。殼寬2.65m、屋頂z=3.25m；每相鄰殼間距.20m，各單元帶半個風琴與耦合器。五節全長34m、4500三角；七節全長45.5m、6424三角。五／七實際含門檻寬2.784／2.769m，含集電弓高4.545／4.465m。單元精確min/max、三角數看manifest。

長節各每側兩組雙門：五節2/0/2/0/2、七節2/0/2/0/2/0/2。只有兩個外端有駕駛室，中間不得附駕駛窗／燈。各長節一組雙軸架，五節6軸、七節8軸；三個短節懸浮、不能加輪或下移。五節短節最低z=.22，七節=.24，但兩者頂部仍分別z=3.38／3.371，維持共同軌面。輪底z=0，輪徑.58m；五軸距1.50m、七1.44m；只有trailing一端有集電弓。

**尺寸與走行為展示規格／推估，不是工程尺寸。** 五節34m與2.65m尺度沿用前批私有台灣庫FORMATIONS.md引用的高雄市政府車輛介紹。新七節未能唯一辨識真車型號；全長45.5m以專案寬度與新圖長短節相對比例推估，不能宣稱高雄存在這套七節車。輪組被裙板遮住，四架八軸屬合理補全假設。另檢查私有世界版formations.js／rolling-stock catalog，沒有可唯一匹配本圖的工程規格；不使用CAF五節Q比例mesh。所有9張inline參考均目視看過，無本地原檔，不偽造圖片SHA或像素工程尺寸。

## 限定的五節窗片修正

檢查兩側發現反向端車窗片沿用了正向殼面對角，造成白色破口。只把trailing端左右玻璃／薄背框沿實際車殼三角面裁切；不改車體、門窗節奏、輪位、設備或編組。`verify.mjs`與真正舊producer `5a2fd38e33019df359c124f3707fec658e905da1`逐三角比對：除x在trailing駕駛側窗、|y|>1.1、z=.69..2.93m的窗片體積外，其餘位置／法線／順序／alpha／glow完全相同。不能再宣稱整件每個頂點完全沒變。

舊紅色五節與新綠松用同一相機／尺度做`five-before-after.png`；七節窗片修正用真正初版新藍色native做`seven-before-after.png`。基準分別存在私有前批與本批`-initial/`，不放進最終模型選單。新增支持射線穿過深色背框，還必須在65mm內碰到彩色車殼／承板；初版真實缺陷會失敗，不能讓浮空框替浮空玻璃自己背書。

## 重建與驗證

OUT放公開庫之外；FIVE_BEFORE是前producer5a2fd38e的五節實際匯出，SEVEN_BEFORE是本輪修窗前的七節工作樹native。Swift6.4、warnings-as-errors；本環境`/workspace/swift/usr/bin`。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DSevenSectionLRTTests|Map3DFiveSectionLRTTests|Map3DModelTests|Map3DModelFileTests|Map3DGreenCommuterTests|Map3DGreenTramTests'
tools/lrt-pair/export.sh OUT
node tools/lrt-pair/render.mjs OUT
node tools/lrt-pair/clay.mjs OUT
node tools/lrt-pair/art-checks.mjs OUT
node tools/lrt-pair/verify.mjs OUT FIVE_BEFORE
node tools/lrt-pair/geometry-audit.mjs OUT
python3 tools/lrt-pair/mutation-check.py OUT
blender --background --python tools/lrt-pair/glb-audit.py -- OUT
node tools/lrt-pair/feedback-compare.mjs OUT FIVE_BEFORE five
node tools/lrt-pair/feedback-compare.mjs OUT SEVEN_BEFORE seven
python3 tools/lrt-pair/verify-png.py OUT
node tools/lrt-pair/standalone.mjs OUT
node tools/lrt-pair/browser-check.mjs OUT
node tools/lrt-pair/browser-check.mjs OUT --standalone
python3 tools/lrt-pair/bundle.py OUT ACTUAL_PRODUCER_COMMIT
node tools/lrt-pair/standalone.mjs OUT
node tools/lrt-pair/browser-check.mjs OUT
node tools/lrt-pair/browser-check.mjs OUT --standalone
python3 tools/lrt-pair/bundle.py OUT ACTUAL_PRODUCER_COMMIT
```

16 native／16 GLB＝12獨立單元＋2完整編組＋2未改比較模型；112七向透明512px PNG。12單元共用同一m/pixel、兩個完整編組共用另一個m/pixel，各件七向固定一致；audit各列.030m/pixel。overview與style-comparison共用聯集bounds的相機與公尺尺度。各單元hero為另行取景，不能當同尺度編組比例圖。

技術驗證：原生逐頂點／法線讀回、五／七逐頂點重建、實際輪面群；GLB bytes一致與獨立Blender讀回；12單元封閉有向邊、216主要玻璃三角的承板與車殼支持，五／七各三個缺面／反面／完整玻璃浮空突變拒收。PNG完整解碼、不裁邊、透明度；viewer16件載入／七向／旋轉／縮放／逐件native／GLB／PNG／ZIP下載、390px。ZIP完整解壓與逐檔bytes，source-record綁實際producer全部Map3D Swift／GLB與renderer／本批工具。

單檔`viewer-standalone.html`內嵌模型與預覽，ZIP另附；資料夾版以`python3 -m http.server --directory OUT 8000`開啟。受管Chromium禁止file://，單檔採斷網內嵌HTML模式實測，作業系統雙擊未直接測。Linux WebGL不代表真機Metal／效能／動畫／營運接入通過。

私有完整包`Railway/game-art-previews/docs/art/lrt-pair-2026-10-22/`；舊資料夾保留歷史。公開僅配方、工具、必要測試、文件與一張新總覽；無私有原始圖片／mesh／貼圖外洩或送外部生成服務。
