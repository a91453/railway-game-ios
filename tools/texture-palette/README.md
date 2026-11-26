# texture-palette：作者舊版素材的色票轉換

作者自製的舊版素材（舊版遊戲的貼圖與模型）是作者自己的作品，原檔留在作者的電腦與私有庫，不進這個公開 repo。新版不用貼圖（一個三角形一個色票顏色），所以舊素材要轉：

| 檔案 | 做什麼 |
| --- | --- |
| `classify.py` | 舊貼圖分類：內容（磚、屋頂、混凝土、玻璃…）加最近的新色票顏色（工作室 t001、t003） |
| `building_map.py` | 把 t003 的分類對到遊戲 `Map3DPalette` 的建築色票位置，輸出 `t003/`（見那裡的 README） |
| `flatten.py` | 把一張貼圖平塗成幾個色票色塊（t001） |
| `cut_faces.py` | 有貼圖的舊列車：照平塗貼圖的色塊邊界把三角形切開，輸出無貼圖、每三角形一色的 GLB（t002） |
| `to_swift.py` | 把 `cut_faces.py` 切好的舊車 e752e7a2 寫成遊戲的 `Sources/GamePresentation/Map3DRedCommuterMesh.swift` |
| `kyushu_n700.py` | 作者舊版的九州新幹線 N700 系頭車與中間車：貼圖讀成長方形色塊再切面，放回真車尺寸，輸出給 `tools/train-models/glb_to_swift.py` 的 GLB（決策 977） |
| `n700s.py` | 作者舊版的 N700S 頭車、中間車、集電弓車：同 `kyushu_n700.py` 的切法（藍線、裙板、前窗、燈照量到的位置給，細線不畫），放回真車尺寸，頭車不另外拉長（決策 979） |
| `thsr_700t.py` | 作者舊版的 700 系頭車與中間車：不照貼圖切，直接在車身上畫色塊（位置在實車照片上量），放回真車尺寸，頭車多兩格窗到 27 m，車端加全周幌；出台灣高鐵 700T（決策 988），`--train series700` 出原塗裝的 700 系五種車（決策 989） |
| `port_check.py` | 舊版車轉好之後、送工作室審查之前的自動檢查（只用 numpy）：異色共面、退化面、朝內的面、每扇門一個 node 且牆加門剛好蓋滿（含 `Door.contains` 0.5 mm 的框法）、全周幌 0–4° 不相碰、頭尾燈左右面數相同、`--old` 時車鼻和舊版差 ≤ 1 mm、軌距、面數對 `report.json`。也能直接讀 `Map3D…Mesh.swift`。全過結束碼 0；`--md` 寫出的表照抄進送審單。用法見檔頭 |
| `kyushu_800.py` | 作者舊版的九州新幹線 800 系頭車與中間車：貼圖上每塊顏色的位置寫成表（每次對一次貼圖）再切面，放回真車尺寸（頭車照真車照片量的比例：車身乘 1.30、多排一格窗成 14 格，車鼻乘 1.14；中間車的窗帶多排兩格成 16 格，窗和頭車一樣大，後面那扇門往車端移 0.52 m；每個連結端補一圈深色的全周幌），門框照貼圖補回、門板另成一個材質格位，輸出同上（決策 978） |

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
