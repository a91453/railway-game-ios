# 安坑／淡海輕軌專用資料與驗收

兩獨立配方、ID、來源與四態：[交接](../../docs/art/new-taipei-light-rail/README.md)。只做studies；不替換營運。Swift6.4 warnings-as-errors、Node22+、Playwright/Chromium、Python Pillow/numpy、Blender glTF importer；無新增專案依賴。

```sh
tools/new-taipei-lrt/build.sh /absolute/run
for fleet in ankeng danhai; do
  node tools/train-models/audit.mjs /absolute/run/$fleet
  python3 tools/new-taipei-lrt/audit.py /absolute/run/$fleet
  tools/new-taipei-lrt/compare-assembly.sh /absolute/run/$fleet $fleet
  blender -b --python tools/train-shape-refresh/glb-audit.py -- /absolute/run/$fleet
  node tools/train-models/render.mjs /absolute/run/$fleet --time both
  node tools/train-models/render.mjs /absolute/run/$fleet --material clay
  node tools/train-models/render.mjs /absolute/run/$fleet --material silhouette
  node tools/train-models/inspect.mjs /absolute/run/$fleet /absolute/run/$fleet/index.html
done
node tools/new-taipei-lrt/review.mjs /absolute/run
python3 tools/new-taipei-lrt/curate.py /absolute/run /absolute/overview.png
```

環境的Swift放PATH；既有Playwright／Chromium位置不同時設`NODE_GLOBAL`（node_modules目錄，尾端/）及`CHROMIUM_PATH`。編組比較獨立Swift讀回單元，原生組裝逐頂點比對JS展開payload的位置／顏色。

兩車均五不等長模組，M2／M4無輪，三台車12個輪胎、四道中空關節、中央單弓雙舟。單檔15000、整列／LOD預算各驗；沒有修改loader或gate。實際射線抽樣玻璃可見性與24mm支承、四個逐輪Z0／淨空、每角色設備底面接觸、實際關節通道；真浮／埋玻璃80mm、輪抬35mm、設備抬80mm／位移150mm，以及錯序／反向／錯位組裝皆須失敗。共用audit另拒收缺面、反面與實際組裝位移。近遠各驗；直接從原生近景肩部切片取樣並向近遠景射線，拒收真實81de6bb2遠景肩部露空及200mm肩部後退反例。雨刷只排除真12三角連通18mm薄梁，沒有豁免整片風擋。遠景省12mm格柵頂細節，其他bounds保持，允差15mm不代表精密工程允差。抽樣不是全碰撞或全像素證明。

PNG本機全量可多，提交每款20張＋公共共用1張。`curate.py`只讀最終原生渲染；同公尺比較用`review.mjs`固定相機。原始照片僅本地逐向旁置，不提交原圖。全RGBA解碼／alpha／留白用共用`deliver.py`內`verify_png`，viewer用`browser-check.mjs`實載／旋轉縮放／下載SHA。

在影響輸出的Sources/tools已提交producer後，以獨立checkout跑以上指令，核對所有模型、PNG與viewer的bytes；source-record與status各自填交付spec，用共用`deliver.py`輸出兩個revision-1。最後素材staged tree與HEAD均跑`asset_guard.py`。只新增本輪20個鎖項，保護舊735原生payload／全頂點FNV。全量舊鎖32差異與TEMU2000預算一項必須先在未改main重現，不動他車／gate。
