# 五節鉸接低地板輕軌

> 最新五節綠松／七節霧藍請用 [lrt-pair 重建工具](../lrt-pair/README.md)。原型別 `coral` 是歷史名稱，目前實際取綠松色票；另修正反向端窗片的切面貼合。以下為前批工具格式紀錄，不是紅色仍在使用。

唯一原生配方：`Sources/GamePresentation/Map3DFiveSectionLRT.swift`。五個獨立單元與完整靜態編組註冊在 `Map3DModelPack.standard`，不綁營運車種，不增加動畫、物理或存檔格式。既有三節電車、雙節通勤車及其遊戲整合不改。

## 展示尺度與組裝

| 單元／ID 後綴 | 車殼長 m | 中心 x m | 配置 |
| --- | ---: | ---: | --- |
| leading | 9.0 | +12.5 | +x 駕駛端、兩組雙門／側、一組雙軸架 |
| suspendedFront | 4.1 | +5.75 | 大窗、無駕駛／門／輪組 |
| middle | 7.0 | 0 | 兩組雙門／側、一組雙軸架 |
| suspendedRear | 4.1 | −5.75 | 大窗、無駕駛／門／輪組 |
| trailing | 9.0 | −12.5 | −x 駕駛端、兩組雙門／側、一組雙軸架、唯一集電弓 |

ID 前綴 `lrt-five-`，完整 `lrt-five-formation`。全部原生 +x 前、+y 左、+z 上，單位公尺；依中心 x 平移，**不旋轉、不鏡射**。車殼四處間距 .20m，兩相接單元各自帶半個風琴與耦合器，半件伸出 .10m。完整車鼻至車鼻 34m，殼寬2.65m，屋頂3.25m；精確外廓與三角形看 manifest。輪徑.58m、每架軸距1.50m；端節架中心 local x=±1.1m，中節=0。輪底原生 z=0；兩短節懸掛在鉸接間，不應單獨落地或加輪。

數字為**遊戲展示比例規格，非製造商工程尺寸**。私有參考 `taiwan-rail-reference-clean/source/rail-3d/integration/FORMATIONS.md` 及 `formations.js` 引述高雄市政府 `https://takao.kcg.gov.tw/article/2127` 的五節／約34m，程式寬2.65m作尺度參照；本次沒有重新認證該頁工程圖。其 `garage-blender-v1/caf.json` 是壓縮 Q 比例與四門群，與本輪圖片不同，不採其形狀、門位或 mesh。本輪五張 inline 圖均目視查看，未提供可下載本地檔，所以不做像素疊圖、不編造圖片 SHA。新圖的長—短—長—短—長與各長節兩組雙門優先。圖片看不見輪組／底部，三架六軸屬合理補全假設，仍資料不足。

造型全新編寫：斜面且收窄的兩端、平窗帶、薄肩線、低裙板；不複製既有車的車體、頭尾、門窗或編組。色票只用專案 `shopAwnings[1]` 珊瑚橘、`shopAwnings[3]` 暖白、既有灰藍玻璃色票的0.62明度與鋼灰；霧面頂點色，不使用貼圖／品牌。既有模型只作同公尺相機下的風格比較。通用 box／封閉 facet／tube、M3DM writer、GLB packer、WebGL viewer 取自專案工具，沒有新依賴。

## 重建與驗證

Swift **6.4**，warnings-as-errors；輸出 OUT 放在公開庫之外。Linux 本次工具鏈 `/workspace/swift/usr/bin`。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DFiveSectionLRTTests|Map3DModelTests|Map3DModelFileTests|Map3DGreenCommuterTests|Map3DGreenTramTests'
tools/five-section-lrt/export.sh OUT
node tools/five-section-lrt/render.mjs OUT
node tools/five-section-lrt/clay.mjs OUT
node tools/five-section-lrt/art-checks.mjs OUT
node tools/five-section-lrt/verify.mjs OUT
node tools/five-section-lrt/geometry-audit.mjs OUT
python3 tools/five-section-lrt/mutation-check.py OUT
blender --background --python tools/five-section-lrt/glb-audit.py -- OUT
# 修訂比較用真實舊匯出，不用 final 充當 BEFORE：
node tools/five-section-lrt/feedback-compare.mjs OUT BEFORE
python3 tools/five-section-lrt/verify-png.py OUT
node tools/five-section-lrt/standalone.mjs OUT
node tools/five-section-lrt/browser-check.mjs OUT
node tools/five-section-lrt/browser-check.mjs OUT --standalone
python3 tools/five-section-lrt/bundle.py OUT ACTUAL_PRODUCER_COMMIT
# 再生成內嵌 producer 的單檔、實測 ZIP 下載，最後重封：
node tools/five-section-lrt/standalone.mjs OUT
node tools/five-section-lrt/browser-check.mjs OUT
node tools/five-section-lrt/browser-check.mjs OUT --standalone
python3 tools/five-section-lrt/bundle.py OUT ACTUAL_PRODUCER_COMMIT
```

8 native／GLB＝5獨立單元＋完整編組＋2既有比較模型。56七向透明512px PNG；五單元與各自七向共用同一m/pixel，完整編組另用固定尺度。`audit.png` 四列正交一致 .030m/pixel；`style-comparison.png` 用模型聯集 bounds 固定相機；`before-after.png` 真正新舊同相機／尺度；局部正面另標放大。

驗證讀取**實際三角形**：原生讀回每頂點／法線、GLB bytes與獨立Blender匯入、編組逐頂點重建、實際輪面群、封閉有向邊、玻璃向內射線的非玻璃支持面、缺面／反面／浮空突變拒收。PNG全部完整解碼且RGBA不裁邊。viewer逐件載入、七向、拖曳旋轉、縮放、native／GLB／PNG及ZIP下載、390px寬；單檔在瀏覽器斷網的內嵌HTML模式實測，受管Chromium不允許file://，未直接測作業系統雙擊。

資料夾viewer：`python3 -m http.server --directory OUT 8000`，瀏覽 `http://localhost:8000/`。單檔 `viewer-standalone.html` 內嵌模型／預覽，不需CDN，完整ZIP另附。Linux WebGL與Blender不代表iPhone／iPad Metal、效能、動畫或營運選型驗證。

`bundle.py` 逐一比對實際 producer commit 的配方、共用幾何／色票／GLB及renderer和本批工具，再寫source-record、SHA；ZIP完整解壓、CRC與每個成員bytes比較。完整模型、預覽、viewer與ZIP僅放私有庫 `Railway/game-art-previews/docs/art/five-section-lrt-2026-10-22/`；公開只有配方、工具、必要測試、文件與一張總覽。
