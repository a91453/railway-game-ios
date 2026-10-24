# E200 / 700T 原生外形修訂（七版：白車身、綠松／黑細線）

獨立配方 `Map3DTrainShapeRefresh.swift`，本輪以實際已交付Codex producer `262bc3ef` 為真正前版；本輪白車身保持、只加黑細輔線；原殼面／硬體／編組保持，新增共面分色切分。依使用者新規則：Codex列車可沿用／拆件，非Codex模型只參考。沒有複製E201來源mesh／貼圖。入口仍只註冊五個靜態單元，**不替換營運E200／高鐵**。GameCore／存檔／golden／replay不動。

## 建模前判讀與本輪來源

| 特徵 | E200家族研究 | 700T研究 |
|---|---|---|
| 類別／編組 | 雙端電力機車、獨立單機；不自行指定牽引客車 | 外向頭尾＋十中車；第4、9車集電設備沿專案配置，非照片全數確認 |
| 側／前／俯輪廓 | 長直側板、收肩雙窗端面；平滑機器室側面、前後不同屋頂設備 | 寬扁圓鼻、飽滿肩線、駕駛艙分段起伏；中間車平端 |
| 頭尾／左右 | 雙端同型；左右未見細部鏡置是補全假設 | 尾車旋轉180°；中車無駕駛窗／燈；兩側門窗鏡置 |
| 門窗設備 | 圓角前窗、窄側門、寬駕駛側窗、圓燈；端部冷卻箱、單側設備罩／另一側高壓元件、踏階 | 圓角小客窗、薄貼身單門、25mm風擋緣、兩組各雙燈；單臂弓有底座絕緣支承 |
| 尺寸 | 車體17.049m／寬2.972m取私庫附來源catalog；屋頂／升弓等位置推估 | 中車殼25m，頭車殼25m（撤回上一輪多加的1.05m鼻長）／寬3.38m／頂3.65m／節距25.4m全為**比例推估**，非工程尺寸 |
| 走行 | 兩架三軸，12輪；補架框、軸箱／輪轂／懸吊，輪徑與位置推估 | 兩架兩軸，8輪，裙板遮輪上緣；車底、輪徑、懸吊為展示補全 |
| 缺口 | E201來源模型不是工程圖；不同編號／年代弓型與設備差異未核定，不能稱精確E201復刻 | 真實工程規格、全部設備次序、另一側門窗與車底不可見細部 |

1. 實際照片：https://blair-train.blogspot.com/2010/02/e200.html 、https://blair-train.blogspot.com/2010/02/700t.html 。前輪逐張查看，本輪重看700T正面／斜視與E200側面。原照片不隨包散布。
2. 使用者指定[PR #1203](https://github.com/a91453/railway-game-ios/pull/1203)，實際查看head `524058ef` 的總覽與交接。學習駕駛艙／肩線／鼻部曲面分段和圓角窗；**沒有把N700S殼直接當700T**，不改其分支。
3. 私庫 `Simulator/reference_snapshot/models/tra-e201/tra-e201.glb`：在本機Blender渲染並查看側、正、俯、斜四視角，只判讀屋頂不對稱、端冷卻箱、輪架與踏階。來源不是已確認Codex，所以不搬來源頂點／貼圖／商標，不把其17.97×3.25×5.335來源bounds當工程尺寸。SHA見私包reference-review.json。
4. E200長寬來源沿catalog的Train Collection／Toshiba Review 79(5)連結；原有Codex暖白綠松霧面保持。維基403沒有假裝讀到；官網安全六圖是內裝，不作外形證據。私有素材未送外部生成服務。

## 原生與組裝

原生公尺 +x前／+y左／+z上，builder x前／y上／z右，只在flat轉一次，軌面z=0。五新單元＋既有Codex風格比較各為合法M3DM v1（單件≤15,000三角）。全12節細節合計實際manifest所列三角，**不寫入超限的單一M3DM**；交付 `refresh-700t-formation.m3dscene.json`，自含合法單元base64與以下placements。這是本工具的組裝契約，遊戲既有Map3DModelFile只讀其中各M3DM單元，未新增遊戲scene載入器。

中心x：139.7、114.3、88.9、63.5、38.1、12.7、−12.7、−38.1、−63.5、−88.9、−114.3、−139.7m。頭／尾用cab／tail，其餘用middle，索引3、8用panto。tail已含180°旋轉，重建只平移，不另旋轉或鏡射。殼間0.4m，風琴跨過殼端。實際bounds與三角數以manifest為準。

`scene.js`依單元M3DM原始三角順序、Float32平移重建完整幾何；JS結果與Swift直接組裝的 `assembly-expected.bin` 逐bytes核對。該bin只是稽核資料，不是可載入遊戲的原生檔。完整GLB／viewer／七向／白模剪影皆取這份相同最終組裝，不使用較粗的替代編組。移開一節1m必須被拒收。

## 重建與驗證

OUT用公開庫外全新目錄。Swift6.4、Node/Playwright/Chromium、Python/Pillow/NumPy、Blender；沒有新增遊戲依賴。

```sh
export PATH=/workspace/swift/usr/bin:$PATH
swift build --build-tests -Xswiftc -warnings-as-errors -j 4
swift test --skip-build --filter 'Map3DTrainShapeRefreshTests|Map3DModelFileTests|Map3DModelTests'
tools/train-shape-refresh/export.sh OUT
node tools/train-shape-refresh/review.mjs OUT
# 查看配色／白模／剪影四向，修幾何須重新匯出與查看
node tools/train-shape-refresh/verify.mjs OUT
python3 tools/train-shape-refresh/colour-audit.py OUT PRIOR
python3 tools/train-shape-refresh/paint-audit.py OUT PRIOR
# nose-audit.py只用於先前僅改鼻殼的修訂；此輪四個HSR單元都換色，不跑該項。
python3 tools/train-shape-refresh/band-audit.py OUT PRIOR
# paint-audit在第七版逐新增三角檢查原面內與覆蓋面積；第六版殼形修訂不適用。
# 合併N700S參考GLB本機四向白模研究（來源檔不隨本包散布）
blender --background --python tools/train-shape-refresh/reference-study.py -- PRIVATE_N700S_GLB OUT/reference-study
python3 tools/train-shape-refresh/wheel-audit.py OUT
node tools/train-shape-refresh/render.mjs OUT
for part in cab nose e200 middle formation; do
  node tools/train-shape-refresh/feedback-compare.mjs OUT PRIOR "$part"
done
blender --background --python tools/train-shape-refresh/glb-audit.py -- OUT
python3 tools/train-shape-refresh/verify-png.py OUT
node tools/train-shape-refresh/standalone.mjs OUT
node tools/train-shape-refresh/browser-check.mjs OUT
node tools/train-shape-refresh/browser-check.mjs OUT --standalone
python3 tools/train-shape-refresh/bundle.py OUT ACTUAL_PRODUCER_COMMIT
# bundle後重測真ZIP下載、再bundle，最後確認現有ZIP每個member仍等於live bytes
```

本輪真前版模型與來源在history/262bc3ef，第二版完整包仍留私庫revision-2；早期交付在revision-2/history/d476304b，不是臨時重捏前版；四種比較同相機／公尺尺度。公開只有配方／工具／必要測試／文件／一張總覽，完整包留私庫原目錄新增 `revision-7/`，不覆蓋舊包。來源記實際producer，不用未提交版本冒充commit。Linux抽樣射線／WebGL不代表完整碰撞、真機Metal、動畫或效能驗證。

## 第七版：白車身、綠松主色帶＋黑細輔線

使用者更正「車身白色，線條什麼顏色搭黑色」，依此保留原暖白車身／鼻罩／門葉、玻璃與暖白燈，選綠松主色帶＋石墨黑細輔線。黑色沿綠松上緣，標稱高度55mm為本模型造型推估；前唇與車側連續，沒有外掛箱或貼片。先前黑車身只是未提交本機試稿，未作為交付。E200維持原色。

全部沿既有色票：暖白shopAwnings[3]、綠松shopAwnings[0]、黑色tankStand×0.42、玻璃glazing×0.5。未打光sRGB對比綠松／白3.45、黑／白11.48、黑／綠3.32、玻璃／白6.21，詳UI_THEME與colour-verification；不代表所有打光像素或真機已驗。

本輪IMG_4456.PNG已實際看，是12節立面插畫，署名K.Y.Chung／Nanyue Express、標示CC BY-NC-ND 4.0；僅視覺參考，無描摹、圖素貼圖取用、改作該圖或原圖散布。其各中車門窗／設備差異仍未完整重建；此輪只修線條配色，不宣稱工程編組完全符合。原圖SHA與用途留私包reference-review／source-record。

colour-audit逐bytes鎖住四HSR單元的綠松面與發光燈組，確認只移除原暖白三角、加入白或黑的子三角；E200／比較車native及GLB完整bytes不變。paint-audit獨立檢查每個新增三角都位於唯一原三角內，原面覆蓋面積一致；原車殼表面、bounds與編組placements不變，三角數因分色細分增加，依manifest實記，不能宣稱頂點／三角數完全相同。沒有用換色移動門窗或輪組。

真前版262bc3ef模型／GLB／manifest／來源／配方留history/262bc3ef，完整revision-6保持。前後同相機同尺度圖在blue-cab-before-after.png／700t-nose-before-after.png／700t-formation-before-after.png；700t-livery.png為白車身配綠松／黑線預覽。實際原生配色／白模／剪影四向、單元／完整編組與七向都重匯出並查看。

前輪已合併N700S GLB的四向研究沿用，沒有新搬來源頂點／貼圖。21既有相關測試繼續檢查同一原生外形，既有色彩選取調整為明確livery欄位；不為可逆換色加常數鏡像測試。原生／GLB／PNG／viewer／ZIP與實際producer重新驗證。外觀仍自檢，工程級還原／不同中車細節、真機Metal／效能／動畫／全碰撞仍UNVERIFIED；靜態素材合併不替換營運。
