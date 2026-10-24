# E200 / 700T 原生外形修訂（九版：圓角風擋、圓鼻尖與連續下裙板）

獨立配方 `Map3DTrainShapeRefresh.swift`；本輪以真正交付producer `f60f0d92`（完整revision-8保留）作前版。實際查看使用者新附IMG_4456.jpg正面模型圖，以及700T實車正面近照與斜視，修頭尾x≥3.7m的罩體／玻璃與雨刷／燈橫向位置／白鼻尖色帶界線／下裙板。白車身、綠松主帶＋黑細線色票、鼻長與外包bounds、門窗／輪架／編組保持；其他四個單元native與GLB逐bytes相同。Codex列車可沿用，非Codex只參考，無來源mesh／貼圖搬用。入口仍只註冊五個靜態單元，**不替換營運E200／高鐵；合併不會出現在遊戲中**。GameCore／存檔／golden／replay不動。

## 第九版特徵與外觀自檢

新附圖是模型正面渲染，來源作者／尺寸／相機未知，不稱實車工程圖。實際照片再核對700t-2正面、700t-1斜視：罩體四角收圓、下側收窄，上部玻璃與下部雙燈區分開；白鼻尖為較寬的圓底U形；深色下裙板沿鼻面連續包覆。先修整體閉合曲面與白鼻尖輪廓，再補罩／玻璃／兩支簡化雨刷與燈位，最後調裙板色界。本輪模型與圖中橘色不共用塗裝，保留使用者指定白車身與綠松黑線。

| 判定 | 觀察與修正 |
|---|---|
| 已符合本輪自檢 | 避免整片寬方黑板：罩寬收窄、四角收圓、下緣收窄，保留白車頂邊；補貼合罩面的上玻璃／細框與兩雨刷；燈組略往內收 |
| 已符合本輪自檢 | 白鼻尖從尖V改為圓底U；沿原殼面分色，黑細線與主帶連續銜接；鼻長／外包bounds保持 |
| 已符合本輪自檢 | 鼻部下殼連續向下包覆並封閉，深色裙板上緣隨鼻面彎曲；二次檢視後收薄深色區，減少輪架露出；未直接加外掛箱遮醜 |
| 維持 | 白車身／綠松＋黑色票、原門窗與輪架、E200／中車／集電車／比較車及編組；真前版可重現 |
| 仍不符合完整復刻 | 雨刷與玻璃只有簡化實體，無駕駛室內裝／透明反射；小管線、各中車精確差異與所有細節仍不足 |
| 資料不足 | 新圖來源模型與相機，700T風擋／鼻部工程尺寸、完整底部與另一側設備細節；展示尺寸仍比例推估 |

最終原生模型的側、正、俯、斜配色／白模／剪影與同相機同公尺前後均重新輸出並親自查看。技術通過不當外觀合格，也不代表作者已認可。不散布新附圖／原照片／來源GLB，不描摹或送外部生成服務。來源SHA與逐張查看紀錄在私包reference-review.json。

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
python3 tools/train-shape-refresh/front-audit.py OUT PRIOR
# colour-audit / paint-audit適用歷史第七版細線；本輪確實改動鼻部幾何／風擋／色界，不跑這兩項。
python3 tools/train-shape-refresh/band-audit.py OUT PRIOR
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

本輪真前版模型與來源在history/f60f0d92，第二版完整包仍留私庫revision-2；早期交付在revision-2/history/d476304b，不是臨時重捏前版；四種比較同相機／公尺尺度。公開只有配方／工具／必要測試／文件／一張總覽，完整包留私庫原目錄新增 `revision-9/`，不覆蓋舊包。來源記實際producer，不用未提交版本冒充commit。Linux抽樣射線／WebGL不代表完整碰撞、真機Metal、動畫或效能驗證。

## 歷史第八版：比對照片後收低風擋罩上緣（第九版前稿）

使用者指出車頭黑色方框太高，已重新實際查看四張既有700T實車照片，尤其700t-2正面近照、700t-1前斜視，並對照前輪六圖及IMG4456立面。實車罩體上方有明顯白車身留邊；前版模型黑罩幾乎碰到車頂，且縱向範圍過長。這是形狀與位置問題，不能只換色。

本輪只修頭尾的風擋罩和25mm細緣：上緣沿原鼻面往前下收，罩體縮短、略收寬，前後角用圓弧映射；下端燈組保持原位。罩體仍貼合原鼻殼、有實體背板，不直接下移穿入車身。中央鼻罩／肩部／前唇、原白車身／綠松主色帶／55mm黑細輔線、門窗／輪架／燈及編組保持。

獨立windscreen-audit量真正前版與最終原生頂點：罩體頂由3.625降到3.326m、垂直高度1.239→0.974m、寬高比2.04→2.41；距本模型3.65m車頂的白色留邊0.025→0.324m。這些是**模型展示座標**，不是從照片像素推得的實車工程尺寸。新測試先在真前版四項失敗，修後22相關測試通過。

windscreen-audit逐三角bytes證明頭尾各只有1296個風擋／細緣三角改動，各7012個其餘三角完全相同；所有變更都在各自x>7／x<−7且色彩只限玻璃／細緣。E200／中車／集電車／Codex比較車native及GLB全bytes相同，編組placements不變。白車身綠松黑線、車殼、燈組等沒有順手改。外形與三角數／bounds記manifest。

真前版2b7eb826模型／GLB／manifest／來源／配方留history/2b7eb826，完整revision-7保留；固定相機同公尺尺度四向比較在blue-cab-before-after.png／700t-nose-before-after.png／700t-formation-before-after.png，另有windscreen-front-before-after.png的聚焦正面對照。最終原生配色／白模／剪影側正俯斜及鼻部局部都重匯出並查看。

本輪外觀自檢改善黑罩過高與留白不足；罩內玻璃分層、雨刷、駕駛室／中車細部仍簡化，不稱工程復刻或作者認可。既有六圖（五模型、一實車）、合併N700S GLB四向研究與IMG4456只視覺參考的來源脈絡保持，原始照片／mesh不上公開庫或外部生成服務。仍為靜態素材，合併不替換營運；真機Metal／效能／動畫／全碰撞等保持UNVERIFIED。

## 第九版原生量測與範圍稽核

front-audit直接讀最終M3DM：罩寬2.349→2.209m，白車頂留邊0.324m保持；x=11.9m白鼻尖寬0.512→1.094m；鼻下殼最低0.780→0.240m。40個實際前輪上緣頂點的正面射線，前殼覆蓋4→40，原輪頂淨空保持。每端5425個其餘三角bytes相同，全部修改在x≥3.7／尾端x≤−3.7；其他四單元native／GLB與全部placements完全相同。這是展示幾何／取樣證據，不是實車工程尺寸或全碰撞證明。23相關測試及各項資產驗證明細見私包；歷史windscreen-audit僅適用第八版，不用它宣稱本輪只動罩體。
