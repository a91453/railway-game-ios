# Airport and aircraft studies producer

決策 594、698。只做原生 3D 素材與接點，不接營運。遊戲用的 Swift 配方在 `Map3DAircraftStudies`、`Map3DAirportStudies`（建模方法在 `Map3DStudyMesh`）；私庫的 M3DM、GLB、日夜七方向透明 PNG 與自含 `index.html` 由本目錄 `produce.py` + `render.mjs` 重建。兩邊是同一份配方，`parity.sh` 逐三角形比對（組景只有預覽，沒有 Swift 配方）：**改了一邊，另一邊要跟著改**。外部座標 x 前、y 左、z 上，公尺，地面 0。

```sh
python3 -m unittest discover -s tools/airport-aircraft-studies -p 'test_*.py'
PACK=/path/to/railway-assets-private/game-art-previews/docs/art/airport-aircraft-2026-11
python3 tools/airport-aircraft-studies/produce.py "$PACK"
node tools/airport-aircraft-studies/render.mjs "$PACK"          # PLAYWRIGHT_MODULE、CHROMIUM_PATH 同 tools/model-look/shoot.mjs
tools/airport-aircraft-studies/parity.sh "$PACK"                # Swift 配方 == 這一包
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter Map3DAirportAircraftStudiesTests
# 看圖（model-look）：飛機用 tools/model-look/shoot.mjs 和照片並排；零件與組景的日夜並排：
node tools/airport-aircraft-studies/sheet.mjs --title T --out sheet.jpg runway="$PACK/runway-near/revision-1/runway-near.m3dmodel"=跑道
```

`ferry-studies/produce.py` 提供 M3DM 寫檔與封閉／法線檢查，`station-kit/package.mjs` 提供同一 native 讀取與 GLB 編碼；渲染沿用同一七方向 WebGL renderer，`night.mjs` 替它加夜間。19 種單元各近遠景，GLB 無動畫軌，關節和接點在 manifest。夜燈是 native triangle glow flag：燈具發光，它照亮的地面是鋪面自己的顏色加同一個旗標，白天看不到；通用 GLB 軟體不保證發光。

幾何測試驗每個 solid 封底、正體積、有限、三角預算、LOD 簡化、輪子著地，決策 698 修掉的毛病（機鼻收尖、螺旋槳、圓輪、灰色鋪面、航廈在一塊地上、夜燈），以及城市組景兩扇空橋對到艙門、在機翼之前。這不是組合 mesh 的布林交集證明，也不等於航空器、跑道、滑行道的工程或運行驗證。`file://` viewer 使用嵌入模型與 renderer，不向網路取資料。WebGL 不等於 Metal 實機；外觀由作者或規劃看總覽圖判。
