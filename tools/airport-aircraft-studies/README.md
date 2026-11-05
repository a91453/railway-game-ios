# Airport and aircraft studies producer

決策 594。只做原生 3D 素材與接點，不接營運。公開 Swift 配方在 `Map3DAircraftStudies`、`Map3DAirportStudies`；私庫輸出的 M3DM、GLB、日夜七方向透明 PNG 與自含 `index.html` 由本目錄 `produce.py` + `render.mjs` 重建。外部座標 x 前、y 左、z 上，公尺，地面 0。

```sh
python3 -m unittest discover -s tools/airport-aircraft-studies -p 'test_*.py'
python3 tools/airport-aircraft-studies/produce.py /path/to/railway-assets-private/game-art-previews/docs/art/airport-aircraft-2026-11
node tools/airport-aircraft-studies/render.mjs /path/to/railway-assets-private/game-art-previews/docs/art/airport-aircraft-2026-11
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter Map3DAirportAircraftStudiesTests
```

既有 `ferry-studies/produce.py` 只提供基本封底幾何、M3DM 寫檔與有限／法線檢查，`station-kit/package.mjs` 提供同一 native 讀取與 GLB 編碼；渲染沿用同一七方向 WebGL renderer。全批 18 種單元各近遠景，GLB 無動畫軌，關節和接點在 manifest。夜燈是 native triangle glow flag；通用 GLB 軟體不保證發光。

幾何測試驗每個 solid 封底、正體積、有限、三角預算、LOD 簡化、輪子著地，以及城市組景兩扇空橋的艙門高度和翼前間距。這不是組合 mesh 的布林交集證明，也不等於航空器、跑道、滑行道的工程或運行驗證。`file://` viewer 使用嵌入模型與 renderer，不向網路取資料。Linux/WebGL 不等於 Metal 實機；作者看外觀以前只稱自檢。
