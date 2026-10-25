# N700S / N700ST 原生靜態素材交接

本分支提供可重建配方，不接入遊戲營運類型，也不替換現有 700T。輸入是擁有者提供、僅限私庫的五種 N700S GLB。公開庫不包含原始網格、貼圖、私有參考圖或完整模型。完整輸出在私庫 `Railway/n700s-n700st-2026-10-24/`。

## 造型特徵與判斷

| 項目 | 結論 |
| --- | --- |
| 類別／單元 | 高速電聯車；A 駕駛端，B–E 不同中間車體 |
| 輪廓 | A 長鼻錐、低風擋；中間車為等寬長車身；D／E 屋頂設備不同。左／右窗帶均保留來源位置 |
| 頭尾 | A 只有鼻端有駕駛窗；十節預覽尾端旋轉 A 180 度 |
| 相對尺度 | A 約 20.75、B–E 約 20.5 來源單位；不是工程公尺 |
| 門窗／設備 | 沿用來源表面 UV 區域；中間端門與車窗、D／E 的屋頂設備保留 |
| 走行 | 每單元兩個雙軸轉向架，共八輪；位置為比例推估，踏面 z=0 暫定軌面 |
| 編組 | 來源 CSV 的 `1,2,3,4,5,5,-4,-3,-2,-1`，不是實車十六節證明 |
| 缺口 | 正式車長、台車錨點、集電弓完整幾何、車鉤、實車十六節對應、Metal 真機效能 |

N700S 保留原候選白／藏青色塊。N700ST 依作者新給的四張照片改為亮白車身、白屋頂、金屬灰下緣、藏綠 `#1D4A44` 車側帶；橘色不再出現。駕駛門下的藏綠色楔形朝車頭收尖，鼻尖保持白色。這是無標誌的遊戲塗裝，並非實車認證版。兩者共用來源輪廓，N700ST 目前是塗裝變體；不得宣稱它已是經工程資料確認的獨立實車外形。

新四張聊天附圖已逐張目視：第一與第三張呈現右前斜視，第二張為正前斜視，第四張呈現另一側與上方；共同可辨白色長鼻、灰色下緣、橘色側帶與門下楔形。聊天圖片沒有本地可讀檔路徑，因此不宣稱逐像素量測，也沒有複製原圖到公／私庫。公開配方 `livery.py` 以來源 UV 區域分割車殼三角面，最後把橘色替成遊戲 N700 風格文件既有的藏綠；無浮空貼片。來源圖片的真實商標與文字均未沿用。

外觀檢查結果：長鼻錐、A／中間單元區分、端門與窗帶、八輪兩台車均已符合此靜態候選要求；轉向架細部、車鉤與集電設備仍不符合完整實車模型要求；工程尺度及十六節配置資料不足。真正修訂前版保存在 `repair-before/`，更早的無輪組車殼在 `source-body/`；同相機同尺度比較圖與所有最終視圖均由各版原生 M3DM 回讀後產生。沒有主張擁有者已採用造型。

## 重建

從公庫與私庫最新主分支 checkout，準備擁有者提供的 `inputs/` 五 GLB 與 CSV：

```sh
PIPELINE=/private-repo/Railway/railway-asset-pipeline-2026-10-22/n700s-native/tools
OUT=/private-repo/Railway/n700s-n700st-2026-10-24
PRODUCER=$(git rev-parse HEAD)
python3 tools/n700s-n700st/build.py --pipeline "$PIPELINE" --source /private/inputs --out "$OUT" --producer-commit "$PRODUCER"
python3 tools/n700s-n700st/rebuild_n700st.py --pipeline "$PIPELINE" --source /private/inputs --root "$OUT" --producer-commit "$PRODUCER"
python3 "$PIPELINE/render_delivery.py" "$OUT/source-body"
python3 tools/n700s-n700st/finish.py --pipeline "$PIPELINE" --root "$OUT" --producer-commit "$PRODUCER" --variants n700st
python3 tools/n700s-n700st/verify.py --pipeline "$PIPELINE" --root "$OUT"
```

原生軸向 +X 前、+Y 左、+Z 上；單節中心是共同基準，反向使用繞 Z 180 度旋轉，節間來源間距 0.4。GLB 是原生 M3DM 回讀後輸出。完整編組 GLB 超過單檔 15,000 三角上限；原生重建應載入各單元並按 `assembly.json` 放置。

技術狀態請看私庫驗證記錄。Linux 的讀回與 Canvas viewer 不等於 iOS Metal、動畫、車長或真機效能已驗證。合併本分支後素材仍是靜態候選，不會自動出現在遊戲中。

修訂版把原先相接的開放面片依三角邊與面片扇區分開，再補入 0.012 來源單位厚的背面與側壁。修補後五個單元的最終 M3DM 回讀與 GLB 匯入均通過 watertight、繞向一致和正體積檢查；每件低於 15,000 面。車殼正面與前版的位移少於 0.001 來源單位，N700S 原塗裝不變。這是拓樸封閉，不等於已證實零自交或工程實車尺寸。

本次 N700ST 塗裝前的真正五件模型保存在私庫 `livery-before/n700st/models/`，並封入新版 ZIP 的 `revision-before/`。`Railway_N700ST_Livery_Before_After.png` 用同一來源單位尺度、同一相機比較舊／新斜視與側視。外觀核對：白色前鼻、藏綠帶、左右楔形及灰色裙邊已符合照片主要色塊；照片較細的深藍上緣、玻璃的藍綠透光、門框細節仍不符合完全寫實。照片沒有車體工程尺寸、隱藏設備與實車完整編組資料。
