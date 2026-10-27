# 莒光自動門客車重建

先讀 docs/art/chukuang-coaches-2026-10-26/README.md 及原生製作手冊。本工具沿用PP的格式／渲染／下載驗證機制，車殼與編組另設；沒有營運替換。

需求 Swift6.4、Node、Playwright/Chromium、Python NumPy/Pillow、Blender。NODE_PATH指向既有Playwright。所有輸出放公開庫外。

```sh
export PATH=/workspace/scratch/swift-6.4/usr/bin:$PATH
export NODE_PATH=/opt/codex/cua_node/lib/node_modules
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DChuKuangPassengerTests|Map3DModelFileTests|Map3DModelTests'
tools/chukuang-coaches/capture.sh BASE_WORKTREE BASE_CAPTURE
# BASE_WORKTREE固定1b40e4f4；PREVIOUS_ORANGE是已交付橘色前版，不能用新輸出自比。
CHU_BASELINE=BASE_CAPTURE/before-chukuang-standard.m3dmodel CHU_PREVIOUS=PREVIOUS_ORANGE CHU_ACCEPTED_EMU3000=ACCEPTED_EMU3000_REVISION_5 CHU_ACCEPTED_E500=ACCEPTED_E500_REVISION_3 PRODUCER_COMMIT=PRODUCER tools/chukuang-coaches/export.sh OUT
node tools/chukuang-coaches/review.mjs OUT
# 親自查看四個近遠角色review；主要偏差要修並全量重出。
node tools/chukuang-coaches/verify.mjs OUT
python3 tools/chukuang-coaches/paint-audit.py OUT PREVIOUS_ORANGE
python3 tools/chukuang-coaches/support-audit.py OUT
node tools/chukuang-coaches/render.mjs OUT
blender -b --python tools/chukuang-coaches/glb-audit.py -- OUT
python3 tools/chukuang-coaches/verify-png.py OUT
node tools/chukuang-coaches/standalone.mjs OUT
python3 tools/chukuang-coaches/bundle.py OUT PRODUCER
node tools/chukuang-coaches/browser-check.mjs OUT --standalone
node tools/chukuang-coaches/browser-check.mjs OUT
python3 tools/chukuang-coaches/bundle.py OUT PRODUCER
```

最終ZIP之後的browser-check會改verification，必須再打包核逐檔bytes。來源／producer／公開overview一致才封包。ZIP SHA記包外package-verification.json，沒有遞迴內含自身。

capture對base及本分支各跑，coexistence.py BASE CURRENT OUT核所有既有模型payload不變。其含E500／EMU3000／PP／E1000，直接與已接受包比對另看私包protection-record。GLB／七向／viewer／ZIP全來自同一最終M3DM。四節組裝每節平移-20m，第一客車在-20.385m，E500原樣；客車間風擋約40mm間隙，coupler接觸。這只是展示，不是認證當班編組或推拉控制。
