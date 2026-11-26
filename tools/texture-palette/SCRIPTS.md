# texture-palette 的腳本

一支腳本一行，照字母排。做什麼、怎麼跑、改了什麼寫在那支腳本開頭的說明，不寫在這裡（SPLIT-HOTSPOTS-2：每支舊版車腳本都在 README 表格最後加一列、寫長說明，平行的 PR 撞在同一行）。這個檔 `merge=union`：兩邊各加一行都會留下；改同一行的兩個 PR 合完要看一眼有沒有兩行重複。

- `building_map.py`：把 t003 的分類對到遊戲 `Map3DPalette` 的建築色票位置，輸出 `t003/`（見那裡的 README）
- `classify.py`：舊貼圖分類：內容（磚、屋頂、混凝土、玻璃…）加最近的新色票顏色（工作室 t001、t003）
- `clip_refine.py`：用 CLIP 修 `classify.py` 分不開的立面、俯視圖、其他三類（t003 第 4 輪）
- `cut_faces.py`：有貼圖的舊列車：照平塗貼圖的色塊邊界把三角形切開，輸出無貼圖、每三角形一色的 GLB（t002）
- `flatten.py`：把一張貼圖平塗成幾個色票色塊（t001）
- `kyushu_800.py`：作者舊版的九州新幹線 800 系頭車與中間車（決策 978）
- `kyushu_n700.py`：作者舊版的九州新幹線 N700 系頭車與中間車（決策 977）
- `n700s.py`：作者舊版的 N700S 頭車、中間車、集電弓車（決策 979）
- `port_check.py`：舊版車轉好之後、送工作室審查之前的自動檢查（只用 numpy）
- `thsr_700t.py`：作者舊版的 700 系 → 台灣高鐵 700T（決策 988）；`--train series700` 出原塗裝的 700 系（決策 989）
- `to_swift.py`：把 `cut_faces.py` 切好的舊車 e752e7a2 寫成 `Map3DRedCommuterMesh.swift`（決策 956 起不再用，見 README）
