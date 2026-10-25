# E200／700T 原生素材，第十版：收薄車頭綠色

> 跨 AI 的完整方法、製作指令、獨立驗收與這次實例，見 [原生車輛製作手冊](../native-vehicle-modeling/README.md)。
>
> 本頁記錄 producer `04b051b0` 的素材交付階段；原素材 PR 已合併，後續 Claude 的 [#1217](https://github.com/a91453/railway-game-ios/pull/1217) 已接入營運，見 [決策 408](../../decisions/408.md)。下文歷史「靜態素材」不代表最新遊戲仍未接入；本文件沒有新增裝置／效能驗證。

再次實際查看使用者附的IMG_4456.jpg正面模型圖，並重看700T實車正面近照。前稿鼻尖綠色過厚，本輪讓白鼻罩向下延伸、收薄車頭綠色，較寬色塊留在兩側肩部，接回原車側主帶。只調頭尾鼻部原生分色，車殼曲面／bounds／鼻長、風擋／燈／雨刷、輪架／門窗／設備與編組保持；白車身、綠松與黑細線色票不變。

![第十版實際原生模型](overview.png)

[公開素材 PR #1201](https://github.com/a91453/railway-game-ios/pull/1201)／[私有素材 PR #70](https://github.com/a91453/railway-reference-private/pull/70)互鏈，均已合併。[判讀、來源與重建交接](../../../tools/train-shape-refresh/README.md)。素材 producer 與交付當時 CI 記錄在 [issue #1200](https://github.com/a91453/railway-game-ios/issues/1200)；遊戲目前狀態另查後續接入。

[第十版完整私有包](https://github.com/a91453/railway-reference-private/tree/codex/train-shape-refresh-2026-10-24/Railway/game-art-previews/docs/art/train-shape-refresh-2026-10-24/revision-10)有6合法M3DM、1自含單元完整12節組裝JSON、7GLB、49七向透明PNG、單元／編組、白模／剪影四向、同尺度E200／700T／既有Codex metro比較、真正前後、viewer、來源／SHA與ZIP。真前版為已交付0ef6c1c8，原生／GLB／來源／配方留history/0ef6c1c8，完整revision-9和更早包保持。

## 外觀自檢

| 判定 | 結論 |
|---|---|
| 已符合本輪目標 | 鼻尖綠色收薄、白鼻罩向下延伸，肩部綠色接回原車側主帶；仍保留窄綠邊與黑細線；鼻尖中央避免原先突點 |
| 維持 | 原殼面、風擋／燈／雨刷、輪架／門窗／設備、鼻長／全部bounds／placements；E200、中車、集電車、Codex比較單元native及GLB逐bytes相同 |
| 仍不符合完整復刻 | 玻璃反射／透明內裝、精確雨刷機構、各中車門窗／設備差異與車底小設備仍簡化 |
| 資料不足 | 新圖模型來源／相機／真實尺寸、700T鼻／罩工程規格、完整底部及另一側設備細節 |

最終實際原生配色／白模／剪影側、正、俯、斜和固定相機同公尺前後重新匯出並親自查看。新圖是模型正面，實車近照作交叉參考；不把透視像素當工程尺寸，不捏造相似度分數，不稱作者已認可。原始參考圖片／mesh／貼圖未散布或送外部生成服務。

## 技術與CI分開記錄

**VERIFIED，本輪Linux**：Swift6.4 warnings-as-errors build --build-tests及24相關測試，新回歸在真前版先失敗。原生讀回／共存、封閉有向邊／正體積、缺面反面拒收、JS完整組裝與Swift逐bytes一致及移位1m拒收；玻璃背板與750mm浮空拒收、44輪胎連通件貼軌與輪頂淨空。livery-audit讀實際原生，核對鼻部白／綠／黑三角範圍、其他單元native／GLB bytes、全部bounds／placements，對新舊殼三角做雙向共面交疊面積核對並拒收5mm移面故障，證明只改同殼面分色與細分；量測實際模型正面綠色投影面積減少，並非圖片相似度。

Blender4.3.2獨立7GLB匯入／bounds／三角／頂點色／霧面；49七向與全部PNG完整解碼透明不裁邊；folder與離線HTML viewer載入、旋轉、縮放、真native／GLB／PNG及folderZIP下載、390px；ZIP完整解壓CRC逐檔bytes與實際producer／來源SHA同版。確切三角數、bounds、投影面積、SHA和稽核證據在manifest及verification檔。

**UNVERIFIED**：完整設備接觸圖／全表面穿模閃爍、真機Metal／效能／動畫／動態轉彎懸吊、工程完整性、OS雙擊file://（Chromium離線setContent已驗）。射線取樣／Linux WebGL不代表完整碰撞或iOS／真機。最新head實際CI單獨記issue，不能用本機24測試代替。

**本次仍為靜態素材註冊，未替換營運E200／高鐵；合併不會自動出現在遊戲中。**（2026-10-25：決策 408 把第十版的 E200 與 700T 接進營運，單節長度與 500 m 外的遠景模型見 `docs/decisions/408.md`。） 完整編組JSON僅為工具重建契約，沒有遊戲scene loader；後續需營運映射／LOD／單節長度與動態真機驗證。GameCore／存檔／golden／replay和玩法不動，兩PR保持draft，不推main、不合併／auto-merge／TestFlight。
