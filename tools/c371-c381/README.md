C371／C381 專用組裝與驗收工具；先讀 [本輪main核對與造型](../../docs/art/c371-c381-2026-10-27/README.md)。

單元匯出／預算／FNV／日夜七向／總覽沿用`tools/train-models/`（#1357，讀standard＋studies），不另開新工具目錄。本資料夾只保留GLB、完整編組、幾何／前窗／支架／真前後與分車交付。

- `export.sh OUT`：Swift6.4 warnings-as-errors，8單元＋2編組＋EMU3000風格對照；M3DM讀回，GLB封裝。完整編組用既有M3DAssembly，各自僅引用四種最終單元，Swift expected.bin逐bytes與移位反例驗證。單元上限15,000保持。新輪兩車都從最終配方生成，不傳前輪凍結容器。
- `render.mjs OUT`、`clay.mjs OUT`、`revision-compare.mjs TRUE_PRIOR OUT`：從真原生頂點拍七向、白模／剪影、同相機真前後。完整暫存不全放私庫；每車上限21張。
- `geometry-audit.py OUT`：有限／非退化／封閉朝向／正體積／八輪貼軌；缺面、反面、抬輪反例。
- `front-visibility.py OUT`與`underframe-contact.py OUT`：C371正面玻璃／黑罩及真箱形支座與底板／橫樑正重疊，埋入玻璃／降低支架反例。只局部，不是全碰撞或工程驗收。
- `c381-audit.py TRUE_PRIOR OUT`：兩型T/M及比較模型原生／GLB bytes、兩型原屋頂與走行組位置保護，另核C381前窗射線／三窗比例／V尖、真支架接底板與破壞反例。`protected-payload.py`只適用歷史C371單車輪次，現在不用。
- Blender `glb-audit.py OUT`、`verify-png.py OUT`：獨立GLB import／法線／bounds與PNG。
- `delivery.py OUT TRUE_PRIOR DELIVERY_ROOT`：依新railway-assets-private AGENTS分成c371-2026-10-28/revision-1、c381-2026-10-28/revision-1，各10模型檔、19PNG、source／README與驗證。執行前須完成producer重建及共用payload／驗證summary報告，見交接。
- 各交付根執行`standalone.mjs`、`browser-check.mjs`、`offline-check.mjs`：五模型／七方向／orbit／zoom／native／GLB／PNG下載與390px／無外連。單檔viewer用loopback驗內容，直接file協定未驗。不提供ZIP連結；舊bundle.py只重建歷史封包，不用於新私庫交付。

最新main8be22423：展示車型在`Map3DModelPack.studies`；standard529模型／3,127,704頂點保持。新素材庫不新增ZIP／history，真前完整包固定在reference-private的63b44693／素材e791fdb7，原producer cf8d79ba。歷史檔案未刪，不再複製它們。素材guard提交前／後皆跑，並人工工具核PNG上限與尺寸；來源原圖不重發。

兩型外觀均待驗收；不改營運映射／GameCore／存檔／fixtures，不合併PR／auto-merge／TestFlight。最新producer、來源SHA、CI依交付source-record／PR。
