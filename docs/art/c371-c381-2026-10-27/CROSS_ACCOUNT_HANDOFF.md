# C371／C381 接手：雙車修訂＋main資產格式（2026-10-28）

使用者要求同修兩車並核對最新main格式。**C371與C381均待外觀驗收**，先前把「可以」記為接受已撤回。公開draft #1342、工作#1341；舊reference-private #103為前版／交接，新成品在railway-assets-private各車獨立目錄的draft。最新producer／素材提交／CI見各車source-record和公開PR。

先讀[README與main核對表](README.md)、[C371查證](REFERENCE_RECHECK.md)、[C381原圖](C381_REFERENCE_RECHECK.md)。原圖需親自打開，不把前人或縮圖說成本人查看。照片／精確曲率／隱藏設備界線保留；不用其他車幾何冒充。

真正完整前版：公開cf8d79ba、reference-private私庫63b44693／素材e791fdb7，路徑Railway/game-art-previews/docs/art/c371-c381-2026-10-27；固定git提交中原生、GLB、PNG、viewer、原ZIP完整。不要讀其已清掉遷移素材的main，不把更早版本當真前版。依新素材庫AGENTS，不再新增history／ZIP。新格式：c371-2026-10-28/revision-1、c381-2026-10-28/revision-1，各19PNG、僅最新重檔、每輪README／SOURCE／source-record記producer與重建。

## 必要整合與工作範圍

已整合main8be22423的#1403：八個展示單元放Map3DModelPack.studies，standard仍529模型／3,127,704頂點；route bus索引約定保留。只加兩個展示鋼材質key c371／c381，不改metroC381營運映射／GameCore／存檔／fixtures／玩法。沒有新App檔案，不手改Xcode專案。共用工具沿#1357，僅本批八個FNV可更新。其他既有車／standard FNV應不變。

C371修肩部過渡、密一些的橫向曲面、圓角燈腔／分層燈圈、薄有背板防爬肋、窄支座／連結器，保留兩個實車圓件但縮小／壓暗並接細支座。C381細化曲面／肩部、收薄燈罩、降低分離前裙、縮窄硬體。T/M裸原生及GLB保持，屋頂／走行組站位保持，兩組完整編組由最終四單元組成。正交前視輪組會疊影，不能為了藏它而改輪距／輪徑。

## 重建與獨立驗證

1. 讀最新main／雙庫AGENTS、工作登記，Swift6.4 warnings-as-errors build-tests與相關測試；包含Map3DModelPackSizeTests及材質／原模型／bus／燈光。記憶體報告用MOTION_BUDGET_REPORT=1執行對應單測，保留其他已配置skip。
2. `tools/c371-c381/export.sh OUT`；兩車都從最終配方匯出，不再傳凍結C371容器。每個assembly只嵌四種引用單元，展開payload逐bytes等於Swift整列；移位100mm反例拒收。單元M3DM仍<=15,000，不改loader；raw expected.bin只是驗證資料。
3. `render.mjs OUT`、`clay.mjs OUT`、`revision-compare.mjs TRUE_PRIOR OUT`。親自看兩型前／左右／俯／斜、白模／剪影／尾及整列；完整暫存七向不全部提交，遵守每車21PNG上限。
4. `geometry-audit.py OUT`（8單元封閉／方向／體積／貼軌及缺面／反面／抬輪反例）；`front-visibility.py OUT`（C371）；`underframe-contact.py OUT`（C371真支架與底板／橫樑及降低反例）；`c381-audit.py TRUE_PRIOR OUT`現在也核兩型T/M bytes與原屋頂／輪組位置，另核C381射線／三窗／V尖／支架與故障反例。舊protected-payload.py只屬歷史輪次，不在本輪使用。
5. Blender4.3.2 `glb-audit.py`獨立匯11GLB；verify-png.py；共用train-models/run.sh匯八單元、check.mjs預算／FNV、render.mjs日夜、overview.py一張公開總覽。pack與裸配方應核位置相同，不宣稱材質／遮蔽色整份payload相同。
6. 實際提交producer後重建22模型＋2expected，全部bytes一致，再做分車交付。`delivery.py OUT TRUE_PRIOR DELIVERY_ROOT`每車10模型／19PNG；各車執行standalone.mjs、browser-check.mjs、offline-check.mjs，核五模型七向互動、下載、390px／無外連。無ZIP下載控制項。
7. 交付前`python3 tools/asset_guard.py --base origin/main --head TREE`（TREE可為git write-tree結果），提交後再以HEAD核。另核PNG<=21、單張<=2MiB、單檔<=50MiB、新增<=200MiB、無history／old／backup／ZIP、每款一個最新重檔輪次。
8. 推新素材庫draft後從精確提交下載代表native／GLB／assembly／expected／viewer／PNG／SHA／source-record核bytes；報告綁素材commit。舊#103只改交接描述，不再往舊庫添加重檔。更新原#1342／#1341及工作登記，檢查最新head CI與draft狀態，不以舊綠燈替代。

## 未驗收

兩型使用者外觀接受、當輪Simulator畫面、真機Metal／效能／動畫／完整碰撞或工程強度、隱藏設備精確站位、直接file協定啟動。已有Linux／WebGL／Blender證據不能替代以上項目。公開及素材PR保持draft；不合併、不開auto-merge、不啟動TestFlight。合併重建不自動換營運列車。
