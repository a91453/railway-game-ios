# E200 / 700T 暖白綠松：第七版白車身、綠松／黑細線修訂

依使用者回饋，沿用前版Codex配方，參考[PR #1203](https://github.com/a91453/railway-game-ios/pull/1203)的駕駛艙／肩線與圓角窗，以及私庫E201四向渲染的輪架／屋頂布局。E201只作參考，未搬來源mesh、貼圖、商標或來源尺寸。[判讀、來源、重建與組裝](../../../tools/train-shape-refresh/README.md)。

![第七版實際原生模型](overview.png)

[公開draft #1201](https://github.com/a91453/railway-game-ios/pull/1201)／[私有draft #70](https://github.com/a91453/railway-reference-private/pull/70)互鏈。最新producer與CI見[issue #1200](https://github.com/a91453/railway-game-ios/issues/1200)。完整新包在私庫原目錄的[revision-7](https://github.com/a91453/railway-reference-private/tree/codex/train-shape-refresh-2026-10-24/Railway/game-art-previews/docs/art/train-shape-refresh-2026-10-24/revision-7)，原交付保留。

交付6合法M3DM（5新單元＋1Codex風格對照）、1自含單元的原生組裝JSON、7 GLB、49七向透明PNG、白模／剪影四向、同尺度風格比較、完整12節、viewer、來源／SHA與ZIP。完整編組三角數依最終manifest（分色細分新增），以相同最終單元重建，不強塞進15,000上限的單檔。組裝JSON是工具契約，未加入遊戲scene loader。

## 外觀結論

| 判定 | 本輪結論 |
|---|---|
| 已符合本輪目標 | 鼻部與肩部重新分段、風擋下移收窄與25mm細緣、雙燈罩各雙暖白燈、圓角客窗、薄門葉／窄門窗；E200圓角前窗／圓燈、12面輪胎、輪架軸箱輪轂／懸吊、踏階；移除虛構車側通風格，補前後不同屋頂設備 |
| 維持 | 暖白綠松無紅色、霧面無照片貼圖；車殼長寬／編組節距／門數／基本窗位；中車無駕駛窗或頭燈，尾車旋轉向外 |
| 仍簡化 | 雨刷、駕駛室內裝、車底管線、設備銘牌與小型緊固件；玻璃以不透明霧面色呈現，沒有玻璃反射或透視內裝 |
| 資料不足 | 700T工程尺寸與完整設備序、E200各車號／年代弓型與屋頂差異、另一側精確細部；本模型不是經工程確認的E201或特定編號復刻 |

以上是本次自檢，**不代表作者已認可或工程級復刻**。本輪真正前版為已交付producer `262bc3ef`，保留完整原生檔；`previews/blue-cab-before-after.png`、`700t-formation-before-after.png`均是固定相機、共同bounds與同公尺尺度。舊稿未被改造後冒充前版。

## 技術與CI分開記錄

**VERIFIED，本輪Linux**：Swift6.4 warnings-as-errors build --build-tests及21相關測試（新增實際圓角玻璃檢查）；六單元原生讀回／normal；完整組裝JS與Swift預期三角payload逐bytes相同，偏移1m故障拒收；封閉有向邊／正體積、缺面與反面拒收；玻璃承板射線與750mm浮空拒收；44輪胎實際連通件貼軌、輪頂外緣向上射線淨空；Blender4.3.2獨立GLB匯入／bounds／三角數／頂點色／霧面；PNG完整解碼透明與邊界；folder及offline viewer旋轉縮放、單元／組裝／GLB／PNG／ZIP真下載與390px版面；ZIP解壓CRC逐檔bytes、producer SHA核對。確切數量與距離見新包verification檔。

**UNVERIFIED**：完整設備接觸圖、全表面穿模／閃爍、動態輪組／轉彎／懸吊、真機Metal／效能／動畫、OS雙擊HTML與完整工程規格。射線抽檢不等於完整碰撞證明。最新head CI單獨更新issue，不能拿本機21測試或WebGL當Xcode／真機全綠。

**仍是靜態素材註冊，未替換營運映射；合併也不會自動把遊戲E200／高鐵換成此版。** 不改GameCore、存檔、golden／replay或玩法；不合併／auto-merge／TestFlight。下一位整合需依每節原生長度與組裝表、做LOD及真機檢查。

## 第七版：車身白色，線條用綠松＋黑色

依使用者明確更正，車身／鼻罩／門葉、原玻璃與燈保持，採綠松主色帶＋沿上緣的55mm石墨黑細輔線；E200原色不動。先前黑車身只在本機試稿，未交付。全部沿既有色票，對比詳UI_THEME與colour-verification。

IMG_4456已實際看，為署名CC BY-NC-ND的12節立面插畫；只視覺參考，未描摹／取圖素貼圖／散布原圖；各中車差異仍未完整重建。真正前版262bc3ef及完整revision-6保留。

colour-audit鎖定綠松面／燈組完整bytes，只有原暖白面內新增白／黑分色；paint-audit逐新增三角確認在唯一原三角內、覆蓋面積相同。實際車殼表面、bounds、門窗／輪架與編組不變，三角數因共面分色細分增加，不能稱所有頂點bytes不變。E200／比較車native及GLB保持完整bytes。21既有測試、原生／獨立GLB／PNG／viewer／ZIP均重新驗證，實際配色／白模／剪影與同尺度前後已看。

外觀自檢符合本輪白車身＋綠松黑線目標，仍非作者認可／工程完整性。歷史N700S GLB研究、工程與中車細節缺口、真機Metal／效能／動畫／全碰撞限制同上。**仍靜態素材，合併不替換營運。**
