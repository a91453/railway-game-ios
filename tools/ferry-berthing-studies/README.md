# 碼頭靠泊接合組 producer

承接決策579的渡輪／浮台studies，不新增runtime註冊、不接營運。8款零件＋靜態繫纜與水位組裝例，各近遠景，共20 native／GLB、280張日夜七向RGBA。單檔≤15000三角。原創公尺制+x前/y左/z上，沿用本專案box／beam與station-kit的GLB／七向renderer，不加依賴。

```sh
PATH=/path/to/swift-6.4/usr/bin:$PATH tools/ferry-berthing-studies/rebuild.sh /path/to/railway-assets-private/game-art-previews/docs/art/ferry-berthing-2026-11
```

需要既有Swift6.4、Python/Pillow、Node/Playwright、Chromium。首次按`produce.py OUTPUT --part fender|bollard|ring|rope|pile|roller|plate|gangway|mooring-demo|assembly`逐件生成／七向自檢；完整rebuild供已自檢配方重建。輸出禁止在公開checkout內，每個近遠景一資料夾revision-1、14張日夜PNG，批次只留一viewer，無history／ZIP。

`posed()`為工具的非權威pose：translation／rotation／water三種scalar，有限值裁範圍、非有限回rest。water範圍±.30m，只平移浮台／滑套等部件，固定岸與導樁不動，跳板按輪底接觸式旋轉，過渡板按新端點旋轉平移；不是動力學或真潮汐。活動範圍以當前mesh的絕對triangle index記錄，不再次加assembly offset。Python fixtures由真正讀回的native float32頂點產生，viewer逐頂點核對，不只看slider有沒有動。

相容profile：浮台8×6m、甲板.65、水線0；岸hinge(-10,0,1.65)、跳板6.1×2.2m。新輪半徑.06、輪心局部下垂.18m，靜止坡角會調整以維持輪底接觸；**需替換舊跳板，不能直接加輪到舊版**。過渡板長.8厚.04，板底兩端分別落在跳板上表面及浮台面。所有尺寸／行程為studies設計推估，不是荷載／海事工程／無障礙保證，也未驗適用大型旗津渡輪。

防舷／繫纜環固定面x0、法線−x；地置繫纜柱面z0、法線−z。靜態繩索端距2m、弧垂.2m，端點裝配到專用繫纜設備，沒有打結／張力／真船。滑套deckMount在.57，對外裝配應用接點對位，不直接疊原點；組景為自洽的專用bracket版。GLB靜態、無動畫軌，viewer與manifest提供分件方式；本批沒有需要發光的電器。

8項幾何測試檢查封閉有向邊／正體積／LOD、缺面與反向故障、wall mount、固定件／剛體／clamp、輪底與過渡板接觸、舊坡度壓輪反例、繩端對專用柱。逐solid閉合不代表做過整體布林聯集或全面穿插證明。source profile與證據在私庫SOURCE／validation.log。舊版坡角加新輪的反例會使輪底進甲板超過.20m；測試也抓到assembly活動索引重複加offset，已修正。

`verify.mjs`重建GLB比bytes；真Swift loader逐頂點讀回；280PNG真正解碼／SHA／透明非空不裁邊；12份Python／JS pose全頂點對照、slider改像素、固定body不動、390px與四底色。受管Chromium封鎖file://時明寫UNVERIFIED，改驗同份自含HTML關網互動，不宣稱直接雙擊已驗。沒有fetch/CDN或額外下載，Metal／裝置／營運與作者外觀另驗。
