# 貓空吊廂修真 producer

獨立studies工具，不註冊到營運。一般／水晶吊廂各near/LOD，原生M3DM v1、indexed GLB、日夜七向透明圖、同尺度真前版比較、自含離線viewer。

輸出與來源：`a91453/railway-assets-private:game-art-previews/docs/art/maokong-cabin-refine-2026-11/`。完整SOURCE.md及授權在該處。公開庫僅這組工具、說明與一張overview；不改決策575、CABLE3D分支、GameCore、存檔、golden或fixture。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3D(ModelFile|StationKit|CoastalKit|DetailKit)Tests'
python3 -m unittest discover -s tools/maokong-cabin-refine -p test_geometry.py -v
node --test tools/maokong-cabin-refine/package.test.mjs
# OUTPUT 必須在公開repository之外；既有Python/Pillow、Node/Playwright、Chromium，無新增套件。
python3 tools/maokong-cabin-refine/produce.py "$OUTPUT" --kind standard
node tools/maokong-cabin-refine/render.mjs "$OUTPUT" standard
# 看過一般版七向／白模／剪影自檢，再做水晶版。
python3 tools/maokong-cabin-refine/produce.py "$OUTPUT" --kind crystal
node tools/maokong-cabin-refine/render.mjs "$OUTPUT" crystal
# 可選：真正前版的模型只輸出到scratch，交付保留PNG，不留前版重檔。
git worktree add --detach /path/to/baseline aaaaaca6f93da7e27d2e62df87fd0ac55979483d
bash tools/maokong-cabin-refine/export-baseline.sh /path/to/baseline /path/to/scratch-baseline
node tools/maokong-cabin-refine/render.mjs "$OUTPUT" '' /path/to/scratch-baseline
bash tools/maokong-cabin-refine/check-native.sh "$OUTPUT"
node tools/maokong-cabin-refine/verify.mjs "$OUTPUT"
python3 tools/maokong-cabin-refine/decode-images.py "$OUTPUT"
node tools/maokong-cabin-refine/browser-check.mjs "$OUTPUT"
blender --background --python tools/maokong-cabin-refine/check-blender.py -- "$OUTPUT"
```

Linux這輪：**VERIFIED** Swift6.4 WAE build、31個既有相關XCTest、8項幾何測試（含門把支架未接玻璃、浮空椅足、玻璃被底板遮住、扁廂、直桿、開面反例）、6項GLB封裝測試；4個原生模型逐頂點／顏色／發光／玻璃layer讀回；GLB全位置／法線／顏色／索引／材質與SHA；56張512² RGBA七向圖解碼及邊界；Chromium WebGL2離線嵌入HTML互動。Blender 4.3.2獨立匯入四個GLB，核對三角形／材質／頂點色。細項以私有包verification JSON為準。

**UNVERIFIED** iOS／Metal／真機效能、file://直接雙擊（環境阻擋）、站台間隙／擺動／開門／脫索／載重、作者外觀接受。這不是營運接入。原生flag2玻璃目前仍不透明，viewer／GLB的alpha blending只是檢視；不要當成原生透明已完成。

廂體1.98×1.873×2.41 m來自2015科展論文轉述客服尺寸，非原廠工程圖；48 mm地板來自捷運官方。吊架約2.05 m、門框、座椅、玻璃有效面積、機構均是照片比例推估；清楚記在SOURCE。一般8人／640kg、水晶5人／400kg是官方限制。

自製封閉幾何保持專案霧面頂點色。白底綠／紅角帶是去廣告示意，並非固定水晶識別色。仍不像：抱索器／吊架接頭太簡化、角柱真實截面與整流罩細節待圖面、玻璃沒有原生透明與真實反射；沒有貼實車廣告。夜圖僅環境光。外觀僅自檢，待作者看過。

前版相較本輪：扁短盒廂／直吊桿改為鼓形廂身／彎折吊架，封閉雙門、通風窗、雙長椅、四角緩衝、薄地板與鋼框。繩軸原點不變；地板從舊稿約−3.6 m改為−4.38 m（比例推估），不能直接接舊站台。沒有開新決策號。
