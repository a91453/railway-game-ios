# E200／700T 原生素材，第九版：圓角風擋、圓鼻尖與下裙板

實際查看使用者新附IMG_4456.jpg正面模型圖，再對照700T實車正面近照／斜視，發現第八版仍有黑罩偏方、玻璃與燈區未分、白鼻尖太尖、輪架外露的差異。本輪修頭尾鼻部x≥3.7m，保留白車身、綠松主帶＋黑細線色票。原生曲面與色界先修，再補上玻璃、簡化雨刷與實體支點、收內燈位；下裙板與車殼封閉相連。兩次檢視再收薄深色區並修色界接點。

![第九版實際原生模型](overview.png)

[公開draft #1201](https://github.com/a91453/railway-game-ios/pull/1201)／[私有draft #70](https://github.com/a91453/railway-reference-private/pull/70)互鏈。[判讀、配方、來源與重建交接](../../../tools/train-shape-refresh/README.md)。最新producer與CI單獨記在[issue #1200](https://github.com/a91453/railway-game-ios/issues/1200)。

完整[第九版私有包](https://github.com/a91453/railway-reference-private/tree/codex/train-shape-refresh-2026-10-24/Railway/game-art-previews/docs/art/train-shape-refresh-2026-10-24/revision-9)包含原生、七向透明PNG、單元／完整12節、配色／白模／剪影四向、同尺度風格比較、同相機真正前後、GLB、viewer、來源／SHA、ZIP。前版f60f0d92原生／GLB／配方／來源留history/f60f0d92；完整revision-8及更早包保持。七向在views，局部正面對照windscreen-front-before-after.png與四向700t-nose-before-after.png在previews。

## 外觀自檢

| 判定 | 結論 |
|---|---|
| 已符合本輪目標 | 黑罩四角收圓、下側略窄，上玻璃／下燈區與兩支雨刷可區分；保留車頂白邊。白鼻尖從尖V收成圓底U，下裙板連續包覆鼻部，減少原先外露橫桿與輪架 |
| 維持 | 白車身、綠松＋黑色票、鼻長／外包bounds、門窗／輪架／編組；E200、中車、集電車、Codex比較車native及GLB逐bytes相同；中車無駕駛窗與頭燈，尾車向外 |
| 仍不符合完整復刻 | 玻璃／雨刷仍簡化，無透明反射與內裝；車底小設備、不同中車精確門窗／設備差異仍不足 |
| 資料不足 | 新圖模型來源／相機／尺寸、700T鼻部與風擋工程尺寸、完整設備順序與另一側細節；E200特定編號／年代設備差異 |

已親自查看最終原生模型側、正、俯、斜配色／白模／剪影及固定相機同公尺尺度前後。以上是自檢，**不代表作者認可、工程復刻或相似度評分**。新圖是模型正面參考，其他既有六圖中五張為模型、一張為實車，不能混稱工程照片。原圖、私庫來源mesh／貼圖不隨包散布或送外部生成服務。

## 技術與CI分開記錄

**VERIFIED，Linux本輪**：Swift6.4 warnings-as-errors build --build-tests及23相關測試；新測試在真正前版先失敗兩項，修後通過。原生讀回／既有註冊共存、封閉有向邊／正體積、缺面／反面拒收；完整編組JS與Swift逐bytes一致、移車1m拒收；玻璃背板射線與750mm浮空拒收；44輪胎連通件貼軌與輪頂淨空抽檢；前輪上緣40點正面射線由前版4點覆蓋改善至40點覆蓋。Blender4.3.2獨立匯入全部7GLB／三角數／bounds／頂點色／霧面；49七向及全部PNG完整解碼透明不裁邊；folder／離線HTML viewer載入旋轉縮放、單元／組裝／GLB／PNG／ZIP實際下載與390px版面；ZIP完整解壓CRC逐檔bytes、producer來源SHA一致。確切值見各verification.json。

六單元合法M3DM各≤15,000三角，完整12節用自含合法單元與placements的組裝JSON，不寫入超限單檔；未加入遊戲scene loader。展示單位公尺，+X前／+Y左／+Z上、軌面Z=0；尺寸除有來源E200車體長寬外仍比例推估。

**UNVERIFIED**：完整設備接觸圖／全表面穿模閃爍、真機Metal／效能／動畫／動態轉彎懸吊、工程完整性、OS雙擊file://。射線抽檢及Linux WebGL不代表完整碰撞或iOS驗證。**最新head實際CI另記issue，不能拿本機23測試代替。**

**本次是靜態素材；素材註冊未替換營運E200／高鐵，合併不會自動出現在遊戲中。** 後續整合需配置營運映射、LOD、單節長度與動態／真機驗證。GameCore／存檔／golden／replay與玩法未改；PR保持draft，不合併／auto-merge／TestFlight。
