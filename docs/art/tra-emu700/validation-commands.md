# 可重跑的分層檢查

Swift 6.4、Node ≥22、Python/Pillow、Blender，以及既有Playwright/Chromium；不新增專案依賴。先在真正幾何producer checkout依README重建到絕對路徑OUT，輸出不能放在公開庫。

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DEMU700Tests|Map3DModelTests'
node tools/train-models/audit.mjs OUT
node tools/tra-emu700/wheels.mjs OUT
python3 tools/tra-emu700/glass.py OUT
node tools/tra-emu700/lod.mjs OUT
node tools/tra-emu700/mouth.mjs OUT
node tools/tra-emu700/duplicates.mjs OUT /absolute/producer-checkout
node tools/tra-emu700/doors.mjs OUT /absolute/ccc-producer-before-run
swift -swift-version 6 -warnings-as-errors tools/tra-r100/assembly-check.swift OUT tools/tra-emu700/assembly.json
blender -b --python tools/taichung-green/import-glb.py -- OUT
```

最終producer已包含玻璃支承加強版glass.py，輸入為最終producer的原生頂點；門檻45mm源自本型42mm面板堆疊。驗證工具與幾何producer分開，不回填metadata。

最終素材PR的revision-1資料夾亦可當作RUN；其manifest與下載檔均已整理，使用下式檢查實際交付viewer。NODE_GLOBAL與CHROMIUM_PATH依本機既有安裝設定，報告另放公開庫外：

```sh
node tools/train-models/browser-check.mjs /absolute/revision-1 --report-dir /absolute/browser-report
cd /absolute/revision-1
sha256sum -c SHA256SUMS.txt
```

HTTP成功、旋轉／縮放、兩LOD全部10個項目的native／GLB下載bytes均已驗；file://另測受管理政策阻擋，UNVERIFIED。不是金屬材質／Metal、Simulator本車外觀、實機記憶體或動態行駛證明。

全量保護用README的inventory.sh取得真正standard+studies枚舉，再執行protect.py；不可假設共享exporter的預設範圍或`--all`有此語意。另跑相同共享gate：

```sh
node tools/train-models/check.mjs /absolute/unmodified-main-full-inventory --lock /absolute/unmodified-main-checkout/tools/train-models/hashes.lock.json
node tools/train-models/check.mjs /absolute/final-full-inventory --lock /absolute/final-documentation-checkout/tools/train-models/hashes.lock.json
```

鎖值驗證使用最終文件checkout的鎖檔；幾何producer cd01a6f9的原生生成不讀取此檔，不將文件head冒充幾何producer。

此輪兩者均有相同33項既有鎖值不符，未改他車鎖、未加入allow、未放寬gate。全部942個既有runtime模型的實際bytes與十欄FNV另比對相同，本型8件鎖值與幾何預算通過。全量gate不能寫成全綠；具體結果見verification.json。

asset_guard於兩庫真正staged tree提交前，以及commit後HEAD分別執行；PNG另完整解碼並檢查RGBA、非空、透明、四邊留白及2MiB。每輪私庫11張、公開1張。

嘴形舊稿553的階梯細帶原生已拒收；上一輪53候選以「flat colour patch without the observed projecting fold」在新深度檢查拒收；新候選覆蓋兩個EMC單元與兩列八車的兩端，共6個真實車端。檢查曲線色界、正常閉罩與下方空腔兩條射線、五條深度剖面及九條引桿遮蔽射線；壓平實際橘色／藍色頂點深度、前移引桿、壓扁橘色高度與移除真鼻罩三角形的反例須拒收。美觀仍須使用者看圖，不能由此自動接受。
