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

N700S 保留原候選白／藏青色塊；N700ST 使用無標誌象牙白／琥珀色帶，無紅色。兩者共用來源輪廓，N700ST 目前是塗裝變體；不得宣稱它已是經工程資料確認的獨立實車外形。

外觀檢查結果：長鼻錐、A／中間單元區分、端門與窗帶、八輪兩台車均已符合此靜態候選要求；轉向架細部、車鉤與集電設備仍不符合完整實車模型要求；工程尺度及十六節配置資料不足。真正修訂前版保存在 `repair-before/`，更早的無輪組車殼在 `source-body/`；同相機同尺度比較圖與所有最終視圖均由各版原生 M3DM 回讀後產生。沒有主張擁有者已採用造型。

## 重建

從公庫與私庫最新主分支 checkout，準備擁有者提供的 `inputs/` 五 GLB 與 CSV：

```sh
PIPELINE=/private-repo/Railway/railway-asset-pipeline-2026-10-22/n700s-native/tools
OUT=/private-repo/Railway/n700s-n700st-2026-10-24
PRODUCER=$(git rev-parse HEAD)
python3 tools/n700s-n700st/build.py --pipeline "$PIPELINE" --source /private/inputs --out "$OUT" --producer-commit "$PRODUCER"
python3 "$PIPELINE/render_delivery.py" "$OUT/source-body"
python3 tools/n700s-n700st/finish.py --pipeline "$PIPELINE" --root "$OUT" --producer-commit "$PRODUCER"
```

原生軸向 +X 前、+Y 左、+Z 上；單節中心是共同基準，反向使用繞 Z 180 度旋轉，節間來源間距 0.4。GLB 是原生 M3DM 回讀後輸出。完整編組 GLB 超過單檔 15,000 三角上限；原生重建應載入各單元並按 `assembly.json` 放置。

技術狀態請看私庫驗證記錄。Linux 的讀回與 Canvas viewer 不等於 iOS Metal、動畫、車長或真機效能已驗證。合併本分支後素材仍是靜態候選，不會自動出現在遊戲中。

修訂版把原先相接的開放面片依三角邊與面片扇區分開，再補入 0.012 來源單位厚的背面與側壁。修補後五個單元的最終 M3DM 回讀與 GLB 匯入均通過 watertight、繞向一致和正體積檢查；每件低於 15,000 面。車殼正面與前版的位移少於 0.001 來源單位，N700S 原塗裝不變。這是拓樸封閉，不等於已證實零自交或工程實車尺寸。

## N700S-G：遊戲原創藏綠線條

依 #1214 的最新決定，橘色版本保留名稱 **N700ST**，遊戲原創版本稱 **N700S-G**。N700S-G 使用已交付的原始 N700S 五種單元；只把原本 `#2B3356` 藍線三角面換成遊戲色票 `#1D4A44` 藏綠（見 `docs/art/n700-game-style-2026-10-16/README.md`）。車頭、窗、門、底盤、輪組、編組位置及所有其他顏色逐三角保持相同。原始 N700S 與橘色 N700ST 的模型檔都不修改。取消的 N700ST 綠色楔形提案未納入。

本次是**塗裝修訂**，前後比較使用真正的原始 N700S 原生模型，固定相機和來源單位比例。外觀已符合：原 N700S 主輪廓與線條位置保持、藍線改藏綠、沒有新增楔形。仍不符合完整實車要求：細部轉向架、車鉤與完整集電設備。工程尺寸、真實十六節編組與真機 Metal 資料不足。十車體圖只是來源 CSV 的視覺排列。沒有主張使用者已接受最終顏色。

從此分支的 producer commit 重建私庫新目錄 `n700s-g/`（需先有上面交接的原始 `n700s/`）：

```sh
PRODUCER=$(git rev-parse HEAD)
python3 tools/n700s-n700st/repaint_n700s_g.py --pipeline "$PIPELINE" --root "$OUT" --producer-commit "$PRODUCER"
python3 tools/n700s-n700st/finish.py --pipeline "$PIPELINE" --root "$OUT" --producer-commit "$PRODUCER" --variants n700s-g
python3 tools/n700s-n700st/verify.py --pipeline "$PIPELINE" --root "$OUT"
```

每單元 8,108–13,140 三角；完整十車體預覽 95,624 三角，須按 `assembly.json` 使用單元，不能當成單一遊戲模型。這輪僅交付靜態素材、沒有接入遊戲；合併後不會自行出現在畫面上。Linux 原生讀回、GLB、圖片及離線 viewer 驗證，不代表真機 Metal、動畫或效能通過。
