# 台中綠線專用驗收

建模／來源／限制：[交接](../../docs/art/taichung-green/README.md)。
共用匯出、GLB、編組、拓樸、渲染、viewer 與交付全部使用 `tools/train-models`。
本目錄只放本車的編組資料與缺少的獨立驗收；不調 loader 上限。

```sh
tools/train-models/run.sh /tmp/tg --ids taichung-green-dm1,taichung-green-dm2,taichung-green-dm1-far,taichung-green-dm2-far --assembly-spec tools/taichung-green/assembly.json
node tools/train-models/package.mjs /tmp/tg
node tools/train-models/audit.mjs /tmp/tg
python3 tools/taichung-green/audit.py /tmp/tg
blender -b --python tools/taichung-green/import-glb.py -- /tmp/tg
tools/taichung-green/compare-assembly.sh /tmp/tg
node tools/train-models/render.mjs /tmp/tg --time both
node tools/train-models/render.mjs /tmp/tg --material clay
node tools/train-models/render.mjs /tmp/tg --material silhouette
python3 tools/taichung-green/check-png.py /tmp/tg
node tools/train-models/inspect.mjs /tmp/tg /tmp/tg/index.html
node tools/train-models/browser-check.mjs /tmp/tg --report-dir /tmp/tg-browser
```

Swift 6.4 warnings-as-errors；Node 22+；既有 Playwright/Chromium、Blender、Python Pillow/numpy。
環境使用不同位置時設 `NODE_GLOBAL`、`CHROMIUM_PATH`；工具鏈設 PATH。
`compare-assembly.sh` 使用本輪 Linux Swift 6.4 integrated build 物件位置，先執行 run.sh。

玻璃：真外表三角重心射線、排除背面；雨刷低於前窗取樣區。把實際玻璃連通殼向內移 100mm 必須失敗。
輪軌：每車八個輪胎各自 Z0、半徑視覺推估 0.39m；從輪頂向上射線驗至少 100mm 實體淨空；抬輪 40mm 必須失敗。
設備：兩座空調中央底面接觸真屋頂，抬設備 60mm 必須失敗。此為中央接觸取樣，不代表完整結構支承／工程認證。
近遠各驗，不沿用近景結論。編組 0/180°、±11.085m，由共用工具的最終單元重建；Swift 另讀最終單元組裝，逐頂點核對 JS 展開 payload 的位置與色值。
共用 audit 另驗缺面／反面及整列 100mm 位移反例。以上都不是所有視角的全像素或全碰撞保證。

重建版本由交付 README 的 producer 釘住。首次新增沒有先前已交付版本；不把試作當使用者接受的前版。

風琴端面逐單元確認到達共同連結平面−11.085m；實際風琴縮回100mm反例必須失敗。

第三版新增中央開口及連結器凹孔實際射線；照片只支持造型，1.6m射線深度與45mm虛擬凹孔門檻是本顯示模型的驗收約束，非工程尺寸。
封中央開口的實際面片必須失敗。以真第二版原生跑 `audit.py RUN --previous PREVIOUS_RUN`，近遠四單元均因凹孔不足被拒收。

另以實際支承內部探點的向外出射法線，檢查兩轉向架枕座及連結器吊座；逐件刪除實際支承三角皆須失敗。第二版這些間隙未受舊屋頂支承取樣涵蓋，本輪補件並新增檢查。
