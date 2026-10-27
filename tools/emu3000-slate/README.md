# EMU3000 石板藍灰重建

先讀 docs/art/emu3000-slate-2026-10-27/README.md、art-style、原生手冊與第五版製作案例。這是16單元的塗裝修改，不是改車殼。

需求：Swift6.4、Node/Playwright/Chromium、Python NumPy/Pillow、Blender。沿用既有環境，不新增App依賴，全部輸出放公開庫外。

```sh
export PATH=/workspace/scratch/swift-6.4/usr/bin:$PATH
export NODE_PATH=/opt/codex/cua_node/lib/node_modules
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DEMU3000Tests|Map3DHighSpeedSetsTests|Map3DTrainSetTests|Map3DModelTests|Map3DModelFileTests|Map3DRealTrainsTests'
# PREVIOUS為真第五版完整包；比較素材直接讀原native，不重建或重著色。
EMU_PREVIOUS=PREVIOUS SLATE_E500=ACCEPTED_E500_NATIVE SLATE_CHUKUANG=DELIVERED_NAVY_COACH_NATIVE PRODUCER_COMMIT=PRODUCER tools/emu3000-slate/export.sh OUT
python3 tools/emu3000-slate/paint-audit.py OUT PREVIOUS
node tools/emu3000-slate/verify.mjs OUT
python3 tools/emu3000-slate/front-audit.py OUT
python3 tools/emu3000-slate/door-audit.py OUT
python3 tools/emu3000-slate/support-audit.py OUT
node tools/emu3000-slate/review.mjs OUT
# 此時實看近遠ED、EM、EP3與全列四向配色／白模／剪影。
node tools/emu3000-slate/render.mjs OUT
blender -b --python tools/emu3000-slate/glb-audit.py -- OUT
python3 tools/emu3000-slate/verify-png.py OUT
node tools/emu3000-slate/standalone.mjs OUT
python3 tools/emu3000-slate/bundle.py OUT PRODUCER
node tools/emu3000-slate/browser-check.mjs OUT --standalone
node tools/emu3000-slate/browser-check.mjs OUT
python3 tools/emu3000-slate/bundle.py OUT PRODUCER
```

來源先提交為真正producer，再全量重出／查看／驗證。bundle核提交來源bytes、所有原生／GLB／七向SHA及唯一公開overview；ZIP全解壓逐檔bytes。browser會更新verification，打包後重跑必須再打包；ZIP hash在包外避免自我參照。

`capture.sh BASE_WORKTREE BASE_CAPTURE`，同腳本對本分支跑CURRENT；`coexistence.py BASE_CAPTURE CURRENT OUT BASE_COMMIT`核全部32-byte頂點位置／法線／色／layer，僅EMU專用新色單元允許差異；paint-audit另核其實際幾何、功能機構／雨刷與其他色保持。EMUFINGERPRINTS舊20-byte匯出不拿來冒稱完整法線檢查。

原生公尺+X前/+Y左/+Z上，輪底Z=0；GLB=(x,z,-y)。16合法M3DM單元＋2個M3DAssembly展示12節，尾車原生已轉向、不再旋轉一次；Swift與JS組裝payload逐bytes核對。每單元七向同公尺尺度，真第五版／石板藍灰前後保存共同相機參數。沒有品牌／車號／個資或原始照片貼圖。

玻璃、輪胎、雨刷和機構維持原材質。mask為新外觀色，hardware為原炭黑；support/front稽核依功能材質識別，不因換色失去輪胎或雨刷樣本。保留第五版原包；本版不稱已接受，不保證換色可免除侵權風險。
