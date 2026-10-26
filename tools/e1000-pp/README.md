# E1000 原生與雙端PP重建

先讀[製作與來源交接](../../docs/art/e1000-pp-2026-10-26/README.md)及原生車輛五份必讀。此工具屬E1000，不改PP/E500原工具。需要Swift6.4、Node/Playwright/Chromium、Python NumPy/Pillow、Blender；沿用專案工具依賴，不新增App依賴。OUT放公開庫外。

PP parent公開61c6969c，私庫1f81f7c。`PP_ACCEPTED_ROOT`為固定PP包，含manifest/models；匯出器複製真正原生且核PP配方三角payload。`capture-baseline.sh`對固定2be9daca擷取真正第一版E1000，不從新版抓「前版」。PP修正parent已推69a6eb7f，本輪保護pack仍比原61c6969c。

```sh
export PATH=/workspace/scratch/swift-6.4/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DE1000Tests|Map3DPPPassengerTests|Map3DPPIntegrationTests|Map3DTrainSetTests|Map3DModelTests|Map3DModelFileTests|TrainPackTests|Map3DRealTrainsTests'
tools/e1000-pp/capture-baseline.sh PARENT_WORKTREE BEFORE_OUT
PRODUCER_COMMIT=$(git rev-parse HEAD) E1000_BASELINE=BEFORE_OUT/models/before-e1000.m3dmodel E1000_BASELINE_FAR=BEFORE_OUT/models/before-e1000-far.m3dmodel PP_ACCEPTED_ROOT=PP_PACKAGE tools/e1000-pp/export.sh OUT
node tools/e1000-pp/verify.mjs OUT
python3 tools/e1000-pp/support-audit.py OUT
python3 tools/e1000-pp/revision-audit.py OUT TRUE_V1_PACKAGE [BEFORE_SKIRT_PACKAGE]
node tools/e1000-pp/review.mjs OUT
```

先親自看近遠四向配色、白模與剪影；有主要偏差修幾何、重新出全套。然後：

```sh
node tools/e1000-pp/render.mjs OUT
blender --background --python tools/e1000-pp/glb-audit.py -- OUT
python3 tools/e1000-pp/verify-png.py OUT
tools/e1000-pp/capture.sh PARENT_WORKTREE PARENT_PAYLOAD
tools/e1000-pp/capture.sh CURRENT_WORKTREE CURRENT_PAYLOAD
python3 tools/e1000-pp/coexistence.py PARENT_PAYLOAD CURRENT_PAYLOAD OUT
node tools/e1000-pp/standalone.mjs OUT
node tools/e1000-pp/browser-check.mjs OUT
node tools/e1000-pp/browser-check.mjs OUT --standalone
python3 tools/e1000-pp/bundle.py OUT PRODUCER_COMMIT
node tools/e1000-pp/browser-check.mjs OUT
python3 tools/e1000-pp/bundle.py OUT PRODUCER_COMMIT
```

先穩定來源、實跑驗證、提交真正producer，再同commit全量匯出／渲染／驗證。bundle核來源bytes，最終ZIP CRC／完整解壓／逐檔bytes，不在ZIP內放自己的hash。viewer下載驗證會寫verification，最後再包一次。使用者原任務明確要求完整ZIP，本次沿用其授權。

原生公尺X前Y左Z上、軌面0；GLB=(x,z,-y)。前E1000 0°、後E1000 180°；單件M3DM合法，組裝JSON只供展示/GLB。Swift預期三角和JS組裝逐bytes比；刪尾機／錯朝向／錯位拒收。兩端機車有後端貫通門，與E500的無客用通道不同。

支承／可見性／淨空為靜態真三角取樣，不是工程、全表面或動畫驗證。完整PP/E500單元原生bytes保持；新的E1000只有自己的配方，原E500/PP recipe與其他營運服務不變。只替換pushPull機車頭，末端照原規則旋轉；沒有新的玩法／車種／存檔。

第二版的真前版優先使用私庫固定58e929e7套件內models/e1000.m3dmodel及e1000-far.m3dmodel，保持原始native bytes/metadata。capture-baseline可從固定2be9daca重新擷取同三角payload，但擷取工具metadata與原交付不相同，不能宣稱全檔SHA一致。
