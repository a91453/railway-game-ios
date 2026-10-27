# 610 專用驗收

共用匯出／遊戲光七向使用tools/train-models，GLB writer與assembly decoder沿用EMU900已交付工具，不複製其他車殼。

Swift6.4：`tools/train-models/run.sh OUT --ids taipei610-a,taipei610-a-far,taipei610-a-light,taipei610-c,taipei610-c-far,taipei610-c-light,taipei610-d,taipei610-d-far,taipei610-d-light,taipei610-b,taipei610-b-far,taipei610-b-light --assembly taipei610`。
`node tools/taipei610-audit/prepare.mjs OUT PRIVATE_ART_ROOT`從固定已接受私包讀E500v3／EMU3000v5，將同一原生轉GLB。
`node tools/taipei610-audit/geometry.mjs OUT`獨立讀回真原生，驗封閉有向邊、法線、退化、正體積及刪面／反面反例；Swift／JS完整編組逐bytes與移車反例。
`NODE_GLOBAL=/opt/codex/cua_node/lib/node_modules/ CHROMIUM_PATH=/usr/bin/chromium node tools/train-models/render.mjs OUT --time both`。

Linux WebGL與幾何抽樣不是人工Simulator、Metal、動態碰撞或動畫驗收。確切執行結果在私包，不以工具存在冒稱已執行。

固定交付重建：匯出後依序prepare（第四參數BASE_CAPTURE可由EMU900 capture.sh在接手commit產生，讀真set-wenhu-head）、geometry、support.py、glass-mutations.py、common render日夜七向／--material clay及silhouette、details、png.py、Blender既有glb-audit、standalone、bundle.py OUT PRODUCER、browser.mjs、再次bundle。根據source-files.json取得原附件與官方報告；未取得的檔案不造SHA。對照私包直接用已接受固定包，不重造。

`browser.mjs`實際HTTP與自含HTML載入後切斷網路，逐角色／七向點選、縮放、拖曳和下載bytes；file://受環境管理政策阻擋，未驗。公開只留overview，私庫完整來源／候選／最終包不覆寫。固定producer與整合head若不同，需全量重建比native／GLB bytes。
