# E500 第二版原生重建

先讀 [製作手冊](../../docs/art/native-vehicle-modeling/README.md)及[外觀／接手記錄](../../docs/art/e500-refresh-2026-10-25/README.md)。本車專用配方、容差與預算，不套用 E200／EMU3000 車體。

需求：Swift 6.4、Node、已安裝 Playwright／Chromium、Python NumPy／Pillow、Blender。無新增遊戲依賴。OUT 在公開庫外，禁止上傳私有原始圖片到生成服務。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DE500Tests|Map3DTrainSetTests|Map3DModelFileTests|Map3DRealTrainsTests|Map3DModelTests'
# BASELINE 為 base 41c00fa5 的真原生檔；不要從已替換的 pack 再抓 baseline。
PRODUCER_COMMIT=$(git rev-parse HEAD) E500_BASELINE=BASELINE E500_PREVIOUS=ACTUAL_REVISION_1 E500_FIRST_PASS=ACTUAL_FIRST_PASS tools/e500-refresh/export.sh OUT
node tools/e500-refresh/verify.mjs OUT
python3 tools/e500-refresh/support-audit.py OUT
python3 tools/e500-refresh/revision-audit.py ACTUAL_REVISION_1 OUT
node tools/e500-refresh/review.mjs OUT
# 親自打開近遠景四向配色／白模／剪影。主要偏差先修幾何並重出。
node tools/e500-refresh/render.mjs OUT
blender --background --python tools/e500-refresh/glb-audit.py -- OUT
python3 tools/e500-refresh/verify-png.py OUT
node tools/e500-refresh/standalone.mjs OUT
node tools/e500-refresh/browser-check.mjs OUT
python3 tools/e500-refresh/bundle.py OUT PRODUCER_COMMIT
node tools/e500-refresh/browser-check.mjs OUT
python3 tools/e500-refresh/bundle.py OUT PRODUCER_COMMIT
node tools/e500-refresh/browser-check.mjs OUT --standalone
```

每次修改配方後全量重出；模型、GLB、PNG、viewer 來自同一 M3DM。原生 X前/Y左/Z上、公尺、輪底 Z=0；GLB=(x,z,-y)。唯一單元中心 (0,0,0)，無外加旋轉或間距；依原廠圖4／5保留一組升起的單臂弓，靜態。

verify 驗實際三角有向邊／正體積，缺面與反面變異會紅；support-audit 對真正玻璃面取樣背襯及向外可見性、12 輪胎連通體輪底與上方淨空、實際屋頂與轉向架實體取樣支持，真玻璃外移／埋入、升輪、浮空側架與拉長燈反例拒收。非全表面碰撞或動畫驗證。兩種 LOD 各自執行，不以封閉代替可見性。

revision-audit核真正8127c765近遠輪胎／中央側板三角、201縱向殼切片與X/Y包絡；真正前版在連續側架及上弓臂投影共紅10項，新版綠，刪真正側架反例拒收。數值為E500模型量測，不是通用工程容差。

render 固定同相機中心／包絡，產七向透明 PNG、真 main 前後與同尺度 E200／EMU3000 風格比較（只比較材質與密度）。review 為配色／白模／剪影。glb-audit 用獨立 Blender 匯入，PNG 全量 Pillow 解碼、透明與留白檢查。viewer 瀏覽器實際轉動／縮放／下載 native、GLB、PNG、ZIP 並核 hash；standalone 封裝離線 HTML。bundle 核真正 producer 的來源 bytes，完整解壓 ZIP 逐檔比對。

coexistence 用 capture.swift 在 base 與本分支同樣讀 pack，排除六個 E500 head 的預期變更與新 far 名稱，其他原有模型 payload 必須逐 bytes 相同。保留原 main 的 E500 幾何作對照，不宣稱前版通過本版檢查。
