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

外觀檢查結果：長鼻錐、A／中間單元區分、端門與窗帶、八輪兩台車均已符合此靜態候選要求；轉向架細部、車鉤與集電設備仍不符合完整實車模型要求；工程尺度及十六節配置資料不足。真正修訂前版是 `source-body/` 的五種原生模型；同相機同尺度比較圖與所有最終視圖均由各版原生 M3DM 回讀後產生。沒有主張擁有者已採用造型。

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

來源車殼的 GLB 在頂點焊接後仍未通過 watertight 檢查。新增的輪／架基本體法線朝外，但車殼拓樸仍需修補；因此不能把此候選宣稱為幾何封閉的正式成品。
