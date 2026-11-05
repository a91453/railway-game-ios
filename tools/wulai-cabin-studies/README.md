# 烏來大型吊廂 studies producer

第六代白色71人大型往復式吊廂，近景8,992、LOD3,744三角。尺寸全為照片比例推估，容量與歷史91人的區別見 [SOURCE](../../docs/art/wulai-cabin-studies-2026-11/SOURCE.md)。僅新增本工具與文件，無註冊／營運／GameCore／存檔／golden變更。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3D(ModelFile|TransparentGlass|StationKit|DetailKit)Tests'
python3 -m unittest discover -s tools/wulai-cabin-studies -p test_geometry.py -v
node --test tools/wulai-cabin-studies/package.test.mjs
# OUTPUT在公開repo外；兩個模型各只保留revision-1。
python3 tools/wulai-cabin-studies/produce.py "$OUTPUT"
node tools/wulai-cabin-studies/render.mjs "$OUTPUT"
bash tools/wulai-cabin-studies/check-native.sh "$OUTPUT"
node tools/wulai-cabin-studies/verify.mjs "$OUTPUT"
python3 tools/wulai-cabin-studies/decode-images.py "$OUTPUT"
node tools/wulai-cabin-studies/browser-check.mjs "$OUTPUT"
blender --background --python tools/wulai-cabin-studies/check-blender.py -- "$OUTPUT"
```

輸出每件M3DM、GLB、14張日夜七向與7張白模／剪影／opaque／剖視診斷，自含離線index.html，另有整組總覽／方向／四向白模剪影／小尺寸畫風表。viewer透明是WebGL材質示意，GLB使用BLEND，兩者不是Metal證據；native flag2保留語意，宿主必須明確用 `Map3DTransparentGlass.applying(to:)` 或 `studyPack` 才啟用原生透明。這批沒有宿主或營運註冊。

macOS官方Swift6.4及Xcode SDK可另跑：

```sh
bash tools/wulai-cabin-studies/run-metal.sh "$METAL_OUTPUT" "$OUTPUT"
```

工廠抽自真正App，編譯真正shader；沿用已驗證的混色／深度／排序／MSAA故障反例，再畫本輪近／LOD的斜視、底視、日／夜旗標與opaque對照。固定診斷ambient不是完整遊戲夜景。沒有MTLDevice時明記GPU UNVERIFIED；CI的wulai-native-metal artifact只保留14日。沒有改共用native-glass工具或renderer。

公開只留工具、來源／README、單張小總覽與小型核對紀錄。模型與viewer在私庫 `game-art-previews/docs/art/ferry-2026-11/wulai-cabin-studies/`，每件一個revision；不建history或ZIP。只稱自檢，作者看過才確認外觀。
