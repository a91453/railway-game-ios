# 日月潭吊廂 native studies producer

獨立素材研究，沒有註冊studies／standard、沒有營運接入。兩種地板構造：一般紅／黃／藍三塗裝與綠色水晶；每種近景／LOD，共8模型。三色共享一般廂幾何，不冒稱三種不同機構車型。

資料／授權／照片的完整說明在私庫 `a91453/railway-assets-private:game-art-previews/docs/art/sunmoon-cabin-2026-11/SOURCE.md`。官方已知：門寬80 cm、深度140 cm、一般8人、水晶6人；外廓2.20×1.90×2.20 m、吊架約1.66 m、地板40 mm與其餘機構尺寸都為**比例推估**。未知kg載重記null。沒有套貓空尺寸或5人限制。基本綠色省略2024起櫻花彩繪，未宣稱重現所有當代車廂塗裝。

工具核心由自有貓空producer `5cfec2954bde648ad3a40f43f8ec18ff89d11bdf` 沿用封閉box／beam／tube／loft、M3DM讀回／GLB與WebGL檢視流程（前置PR未合，這組工具獨立保存可重建版本）；GLB頂點編碼仍直接重用本repo station-kit。日月潭廂體／曲線角框、兩片下門板、橢圓緩衝墊、蜘蛛支架／四腳太陽能板、底防碰環、兩排椅、玻璃鋼框及燈具獨立製作，沒有把貓空換色。沒有新套件、貼圖或引擎。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter 'Map3D(ModelFile|StationKit|CoastalKit|DetailKit)Tests'
python3 -m unittest discover -s tools/sunmoon-cabin-studies -p test_geometry.py -v
node --test tools/sunmoon-cabin-studies/package.test.mjs
# OUTPUT 在公開repository之外，沿用既有Python/Pillow、Node/Playwright、Chromium。
python3 tools/sunmoon-cabin-studies/produce.py "$OUTPUT" --kind red
node tools/sunmoon-cabin-studies/render.mjs "$OUTPUT" red
# 先看紅色七向／白模／剪影，再依序 yellow、blue、crystal（不是並行製作）。
python3 tools/sunmoon-cabin-studies/produce.py "$OUTPUT" --kind yellow
node tools/sunmoon-cabin-studies/render.mjs "$OUTPUT" yellow
python3 tools/sunmoon-cabin-studies/produce.py "$OUTPUT" --kind blue
node tools/sunmoon-cabin-studies/render.mjs "$OUTPUT" blue
python3 tools/sunmoon-cabin-studies/produce.py "$OUTPUT" --kind crystal
node tools/sunmoon-cabin-studies/render.mjs "$OUTPUT" crystal
bash tools/sunmoon-cabin-studies/check-native.sh "$OUTPUT"
node tools/sunmoon-cabin-studies/verify.mjs "$OUTPUT"
python3 tools/sunmoon-cabin-studies/decode-images.py "$OUTPUT"
node tools/sunmoon-cabin-studies/browser-check.mjs "$OUTPUT"
blender --background --python tools/sunmoon-cabin-studies/check-blender.py -- "$OUTPUT"
```

可選同尺度畫風對照，**貓空不是日月潭前版**。日月潭這是第一輪。從精確私庫commit恢復貓空原生到公開庫外scratch（不交付另一份重檔）：

```sh
mkdir -p "$STYLE_DIR"
git -C "$ASSETS_REPO" show e0378c6896e5ede54c11664857bf9aaeca8a2906:game-art-previews/docs/art/maokong-cabin-refine-2026-11/standard-near/revision-1/standard-near.m3dmodel > "$STYLE_DIR/standard-near.m3dmodel"
git -C "$ASSETS_REPO" show e0378c6896e5ede54c11664857bf9aaeca8a2906:game-art-previews/docs/art/maokong-cabin-refine-2026-11/standard-lod/revision-1/standard-lod.m3dmodel > "$STYLE_DIR/standard-lod.m3dmodel"
node tools/sunmoon-cabin-studies/render.mjs "$OUTPUT" '' "$STYLE_DIR"
```

**VERIFIED（Linux／Swift6.4.0）** WAE build與31項相關XCTest；10個幾何測試，包含椅腳離地、太陽能板離腳、窗橫桿離玻璃、底板遮玻璃、實際窗面遮擋、扁廂、開面反例，另核同三色幾何與LOD；8個Node封裝測試。8模型真正Swift loader逐位元位置／色值／glow／glass layer，GLB全頂點／法線／色值／索引／材質／SHA；112張日夜七向＋56張診斷512² RGBA解碼、透明／不空／不裁邊／SHA；Blender4.3.2獨立匯入三角／材質／頂點色／world bounds及轉軸；Chromium同份HTML關網、112視角日夜、透明／剖視／lamp flag改像素、拖曳縮放、native／GLB／PNG下載SHA與390px。完整證據見私庫verification JSON。

**UNVERIFIED** file://直接雙擊（受管Chromium封鎖，另驗同份HTML關網，沒繞過）、原廠工程尺寸、iOS／Metal／裝置效能、載重、碰撞、站台間隙、旅客／開門／翻椅／脫索動畫、作者外觀接受。只稱自檢。

玻璃：原生flag2正確映射trainGlass，現有Metal仍不透明。完整七向與主圖採不透明玻璃；透明只在明示診斷／viewer切換／GLB供檢視。GLB有不透明、BLEND玻璃、獨立室內發光燈三材質，沒有假稱原生透明已完成。夜間只是預覽環境光＋估位室內燈，沒有臆造航行燈或完整光照模擬。剖視隱藏屋頂／太陽能／吊架，沒有修改交付模型。

原點／接點：metres +x沿索 +y左 +z上，ropeAnchor(0,0,0)、ropeAxis+x，boardingFloor−3.78、doorSide−y、doorClearWidth0.80。未對齊舊貓空／概念站台。接點／容量不是營運資料或安全證明。

仍不像：角框以圓管近似真型材、橢圓緩衝墊與抱索器／吊架接頭細節簡化、門與可翻椅只做靜態、玻璃缺原生透光／反射、整體尺寸仍缺一手圖面。沒有實車公司名、波浪商標、車身廣告或櫻花人物彩繪。作者先看這輪，再決定是否續修；本PR沒有任何後續營運接入授權。
