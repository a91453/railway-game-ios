# 海風／山嵐：EMU500 改造 studies

沿用共用匯出／GLB／geometry／viewer／限量交付；本目錄只補兩款配置、原生接觸／故障檢查、獨立Swift組裝、共同公尺相機與選圖。

```sh
tools/tourism-emu500/build.sh /absolute/run
tools/train-models/run.sh /absolute/run/baseline --ids emu500-emc,emu500-ep,emu500-et,emu500-em,emu500-formation
for fleet in haifeng shanlan; do
 node tools/train-models/audit.mjs /absolute/run/$fleet
 python3 tools/tourism-emu500/audit.py /absolute/run/$fleet
 tools/tourism-emu500/compare-assembly.sh /absolute/run/$fleet $fleet
 blender -b --python tools/train-shape-refresh/glb-audit.py -- /absolute/run/$fleet
 node tools/train-models/render.mjs /absolute/run/$fleet --time both
 node tools/train-models/inspect.mjs /absolute/run/$fleet /absolute/run/$fleet/index.html
done
node tools/tourism-emu500/review.mjs /absolute/run
python3 tools/tourism-emu500/curate.py /absolute/run /absolute/overview.png
```

Swift 6.4 warnings-as-errors、Node22+、既有Playwright/Chromium、Python numpy/Pillow、Blender。工具路徑環境差異以NODE_GLOBAL／CHROMIUM_PATH指定。assembly的EM尾車只有一次180°；不在模型內預先反向。車殼19.88m（駕駛端到19.99m）、中心距20.33m，連結面距20.33m屬沿用原EMU500尺寸規格，改造後連結面實測未取得；弓的4.95m是展示升弓包絡，非降弓官方高度。

本機完整圖可多於21張，交付僅20私庫PNG／款及公開共同1張，無ZIP。最終Sources/tools producer先提交，再獨立checkout重建全部模型／PNG／viewer並核SHA；`deliver.py`與素材staged/HEAD asset_guard各驗。技術、外觀接受、營運、裝置四態分開記錄。

第二輪：窗框／玻璃 cap 沿原EMU500弧頭三角面切分，保留原殼支承；燈座／連結器可見性及實際位移／凹區封堵反例另驗。前稿 f036e7f7 未經外觀接受。完整重建後以 `python3 tools/tourism-emu500/delivery-spec.py /absolute/run FULL_PRODUCER_SHA` 產生本型來源／狀態與交付spec，再交給共用 `deliver.py RUN/FLEET RUN/FLEET/delivery.json DEST/revision-N`。spec讀取此producer已提交的來源／四態，不能以其他版本的metadata覆蓋後宣稱相同bytes。
