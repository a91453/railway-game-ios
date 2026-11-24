# texture-palette：作者舊版素材的色票轉換

作者自製的舊版素材（舊版遊戲的貼圖與模型）是作者自己的作品，原檔留在作者的電腦與私有庫，不進這個公開 repo。新版不用貼圖（一個三角形一個色票顏色），所以舊素材要轉：

| 檔案 | 做什麼 |
| --- | --- |
| `classify.py` | 舊貼圖分類：內容（磚、屋頂、混凝土、玻璃…）加最近的新色票顏色（工作室 t001、t003） |
| `building_map.py` | 把 t003 的分類對到遊戲 `Map3DPalette` 的建築色票位置，輸出 `t003/`（見那裡的 README） |
| `flatten.py` | 把一張貼圖平塗成幾個色票色塊（t001） |
| `cut_faces.py` | 有貼圖的舊列車：照平塗貼圖的色塊邊界把三角形切開，輸出無貼圖、每三角形一色的 GLB（t002） |
| `to_swift.py` | 把 `cut_faces.py` 切好的舊車 e752e7a2 寫成遊戲的 `Sources/GamePresentation/Map3DRedCommuterMesh.swift` |

## 舊車 e752e7a2 → 遊戲

> 決策 956 起，遊戲的 `Map3DRedCommuterMesh.swift` 改由 `tools/train-models/glb_to_swift.py` 從工作室的京急新1000形精細車寫出；下面的流程只留作紀錄，**不要再跑 `to_swift.py` 寫回那個檔**（會蓋掉新網格）。

```sh
# 1. 平塗與切面（Pillow、numpy）。OLD_ASSETS：作者的舊版素材資料夾；
#    WORK：flatten.py 的平塗圖與色票 palette.json 所在；OUT：輸出
uv run --with pillow --with numpy python tools/texture-palette/cut_faces.py \
  --glb OLD_ASSETS/models/<舊車>.glb \
  --flat WORK/<舊車>-flat.png \
  --palette WORK/palette.json \
  --out-dir OUT --min-area 22 --rdp-eps 1.8
# 2. 寫成 Swift（不用第三方模組）
python3 -I tools/texture-palette/to_swift.py OUT/e752e7a2-cut.glb \
  Sources/GamePresentation/Map3DRedCommuterMesh.swift
```

`to_swift.py` 做的事：
- glTF 的 `COLOR_0` 是線性值，先轉回 sRGB 再對色票（`tools/glb-to-m3dmodel/convert.mjs` 不轉，直接用它轉的 v1 檔顏色會暗很多）；
- 每個三角形存色票索引，顏色由 Swift 端決定（`Map3DRedCommuter.meshPalette`）：紅色車身是 `Map3DPalette.trainRed`（#8C1C1C，原平塗色 #711604 在遊戲光下偏咖啡），`glass` primitive 用 `Map3DTrainStyle.glass`，所以夜裡會亮、白天會反光；
- 從 glTF 軸（+y 上、車沿 z）轉成遊戲軸（+x 車頭、+y 左、+z 上），車廂中心在 x 0、最低點在 z 0；
- 舊車只有一端有駕駛室，中間車是駕駛室車的後半節加上它的鏡像。

不要批次轉其他舊車（作者 2026-11-15：舊車要進遊戲時一台一台做）。
