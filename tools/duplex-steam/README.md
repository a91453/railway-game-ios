# 第二台：雙走行組蒸汽機車＋煤水車

來源是作者本次十一張圖；各張均已實際開啟。兩組三輪、靠前駕駛室、長後鍋爐／寬火箱、短前煙箱及帶欄杆前平臺為本次獨立結構。不是第一台蒸汽機車換殼。沿用專案色票、低階封閉幾何工具與匯出器，不引用未合併的第一台配方。

模型：`Sources/GamePresentation/Map3DDuplexSteam.swift`。原生模型是專案 `M3DM v1`，不是 Blender 檔；Swift 配方是可編輯來源。+x 車頭、+y 左、+z 上，公尺，輪底 z=0；GLB 為 (x,z,-y)。材質 roughness=1、metallic=0，沒有照片貼圖、品牌或原圖車號。

所有尺寸均為**比例推估**，不可當工程規格。私庫台灣車庫 README／CT273 中的 Q 比例與空工程尺寸、世界車輛目錄及 OpenWorld 規格均未提供這台的唯一車型或尺寸。未取用其 mesh。隱藏軸、精確型號、鉸接機構仍資料不足。原圖六個近等大的可見輪位依兩組三輪製作；不宣稱真實軸式已確認。

重建環境：Swift 6.4、Node.js、既有 Playwright、Chromium、Python/NumPy/Pillow；Blender 用於獨立 GLB 匯入。從 repo 根目錄：

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3DDuplexSteamTests|Map3DModelTests|Map3DModelFileTests'
tools/duplex-steam/export.sh /tmp/duplex-final
node tools/duplex-steam/review.mjs /tmp/duplex-final
# 親自查看 previews/*-review.png，完成外觀檢查，再批次匯出。
node tools/duplex-steam/render.mjs /tmp/duplex-final
node tools/duplex-steam/clay.mjs /tmp/duplex-final
node tools/duplex-steam/palette-options.mjs /tmp/duplex-final
node tools/duplex-steam/geometry-audit.mjs /tmp/duplex-final
node tools/duplex-steam/mutation-check.mjs /tmp/duplex-final
python tools/duplex-steam/support-audit.py /tmp/duplex-final
python tools/duplex-steam/support-audit.py /tmp/duplex-final --mutation
node tools/duplex-steam/verify.mjs /tmp/duplex-final
blender --background --python tools/duplex-steam/glb-audit.py -- /tmp/duplex-final
python tools/duplex-steam/verify-png.py /tmp/duplex-final
node tools/duplex-steam/standalone.mjs /tmp/duplex-final
```

若修訂，先保留真正前版整個匯出目錄與配方，再執行 `feedback-compare.mjs FINAL BEFORE`（完整編組）、加 `cab`（完整機車）或 `front`（前汽缸）。兩版使用相同相機中心與公尺範圍；不能以最終幾何製造假前版。

組裝：機車平移 `[4.6,0,0]`，煤水車 `[-6.5,0,0]`，兩者旋轉都是 0。車身間距 0.50m；車鉤接觸於 x=-1.8m，無體積相疊。共同地面 z=0。`components.json` 只標示實際匯出三角範圍；檢查實際三角面、法線、封閉邊、正體積、玻璃支承射線、輪底／踏階淨空、汽缸區域射線、輪根接觸圖；不以配方常數取代幾何檢查。

交付打包：把十一張私有原圖放 `references/01.jpg`…`11.jpg`，參考逐張紀錄、原版歷史與外觀驗收放同私有批次。先 commit producer，再把實際 SHA 寫進 manifest；重新產生 standalone。`browser-check.mjs OUT` 及 `--standalone` 會實際載入、七向切換、拖曳、縮放與下載原生／GLB／PNG。`bundle.py OUT PRODUCER_SHA` 檢查 producer 所有配方／工具逐檔位元組，完整解壓並比對 ZIP。先建 ZIP 再測一般 viewer 可驗 ZIP 下載；最後重建 ZIP 後以 `browser-check.mjs OUT --no-write` 驗證不再改包內容。離線 standalone 的完整 ZIP 為旁置下載，未內嵌，以免自我包含。

外觀驗收及最新 CI 與技術驗證分開記於 `docs/art/duplex-steam-2026-10-23/README.md`／issue #1118。Linux WebGL 不證明真機 Metal、效能、動畫或動態連桿淨空。

這是**靜態素材＋素材庫註冊**。沒有改營運列車綁定，合併後不會自動出現在遊戲中的行駛列車。GameCore、存檔、golden／replay、玩法均未變更。
