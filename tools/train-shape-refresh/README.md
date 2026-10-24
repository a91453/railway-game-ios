# E200 / 700T 原生外形研究

獨立配方 `Map3DTrainShapeRefresh.swift`，既有列車只作色票與密度比較。入口只新增靜態單元註冊，**不替換營運車輛**。沒有 GameCore、存檔、golden、replay 或玩法變更。

## 建模前特徵表

| 特徵 | E200 | 700T |
|---|---|---|
| 類別／編組 | 雙端電力機車，獨立單機；不捏造牽引客車編組 | 兩頭車＋十中間車，反向尾車；第4、9車集電設備沿用專案排列，非照片完整確認 |
| 側／前／俯輪廓 | 長直身、直立雙窗端面、上角收肩、雙菱形弓 | 寬扁圓鼻、上升風擋、圓肩、低裙板；中間車平端 |
| 頭尾／左右 | 雙端同型；不可見側的門／設備鏡置為補全假設 | 頭尾旋轉180°，中間無駕駛窗；兩側鏡置 |
| 尺寸 | 車體17.049m、寬2.972m取私庫附出處catalog；4.1m為資料中的降弓全高，展示弓升起高度另量 | 車體25m、寬3.38m、屋頂3.65m、節距25.4m皆**比例推估**，不宣稱工程尺寸 |
| 門窗設備 | 端側窄門、雙前窗、側設備縫、頂部設備 | 小客窗、薄門、寬風擋；頭車／中車／集電車獨立 |
| 走行系統 | 兩架三軸；輪徑／架距推估 | 兩架兩軸、裙板遮輪；底部設備與輪徑推估 |
| 缺口 | 駕駛室內裝、車底不可見細節、精確門／設備座標 | 工程尺寸、完整設備順序、另一側細部、車底與動畫 |

## 來源與隱私

私庫 Taiwan catalog 的 E200 尺寸（Train Collection、Toshiba Review 79(5)）與 garage / blender manifest 的攝影來源連結；沒有取任何私有 mesh 或貼圖。
原始攝影文章：https://blair-train.blogspot.com/2010/02/e200.html 、https://blair-train.blogspot.com/2010/02/700t.html 。實際查看下載的每張檔案；含重複縮圖、E200兩側照、正面與700T側面／斜視／正面。照片只作視覺研究，不隨包散布、不送生成服務。Wikipedia/Commons請求403，沒有假裝讀到。高鐵官網安全六圖也看過，但均為內裝，不作外形依據。

## 重建

Swift6.4，原生公尺 +x前/+y左/+z上；builder x前/y上/z右，只在flat轉一次。軌面z=0。尾車為旋轉，不鏡射。12節中心x為139.7、114.3、88.9、63.5、38.1、12.7、−12.7、−38.1、−63.5、−88.9、−114.3、−139.7m；殼長25m，殼間0.4m，平移不另旋轉（尾單元已反向）。連結器／風琴可能跨過殼端，實際bounds見manifest。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DTrainShapeRefreshTests|Map3DModelFileTests|Map3DModelTests'
tools/train-shape-refresh/export.sh OUT
node tools/train-shape-refresh/review.mjs OUT
# 實際查看配色／白模／剪影，再做批次
node tools/train-shape-refresh/render.mjs OUT
node tools/train-shape-refresh/verify.mjs OUT
python3 tools/train-shape-refresh/wheel-audit.py OUT
blender --background --python tools/train-shape-refresh/glb-audit.py -- OUT
python3 tools/train-shape-refresh/verify-png.py OUT
node tools/train-shape-refresh/standalone.mjs OUT
node tools/train-shape-refresh/browser-check.mjs OUT
node tools/train-shape-refresh/browser-check.mjs OUT --standalone
python3 tools/train-shape-refresh/bundle.py OUT PRODUCER_COMMIT
```

公開只配方、工具、必要測試、文件與一張總覽。完整成品在私庫同名目錄；不用舊包覆寫。驗證結果以實際執行紀錄為準。Linux WebGL不等於Metal／效能／動畫驗證，也不代表作者認可。
