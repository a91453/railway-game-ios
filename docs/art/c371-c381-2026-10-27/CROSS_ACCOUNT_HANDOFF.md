# C371／C381 續作交接（C381 照片修訂，2026-10-28）

公開 draft [#1342](https://github.com/a91453/railway-game-ios/pull/1342) ↔ 私有 draft [#103](https://github.com/a91453/railway-reference-private/pull/103)，同分支 `codex/c371-c381-native-2026-10-27`；工作#1341、登記#1041。最新producer／head／CI以兩PR及source-record為準。

使用者現已授權C381依相同流程製作；C371第五輪外觀已接受，鎖producer `d4ee39b5eaec951137af6158959e8d6ff2cc97de` 模型bytes。本輪不重做C371。C381外觀未驗收。這不授權合併、營運映射、TestFlight或真機工程驗收。

## 真前版與照片

真正完整前包（私庫 `fa7bf6f07ff23edc9b629a5c02b6539d3371280c`）及ZIP完整存於私庫 `Railway/game-art-previews/docs/art/c371-c381-2026-10-27/history/true-v9/`；ZIP SHA `be95b0a0ca240cd0f62462a3a2819eca87ee3fc44e3ce236bab833c8f2cb0651`。true-v1～v8保留；這是使用者明確保存要求的例外。

先讀 [C381本輪查證](C381_REFERENCE_RECHECK.md)：兩張TRSC原廠完整原圖、兩張Commons完整原圖均下載並親自打開，列URL、尺寸、SHA、授權與證據界線。歷史C371查證見[REFERENCE_RECHECK](REFERENCE_RECHECK.md)。不把搜尋縮圖或舊帳戶查看寫成本輪原圖查證。

C381修銀色側殼、拱形深灰前罩、雙軸曲面、寬中央逃生窗／細門框、側窗／雨刷、中央收尖V帶、燈罩內連續分色、薄防爬肋背板與分離前裙／支架／連結器。第一稿灰色燈腔切斷藍帶、細肋無明確背板，已拒收，只留review圖。比較以true-v9為真正前版，用同尺度相機。車頂、輪組站位保持，隱藏設備及精確曲率仍推估。

C381 DM/rear各6,252三角，六車19,744；C371 DM/rear各3,526、六車15,828。兩個六車均用既有M3DAssembly展示契約，單元不超過15,000；不改讀檔上限，不冒稱App完整編組接入。

## 重建與驗證

1. 查工作登記及雙庫遠端；不整合無關main、不動GameCore／存檔／Golden／Save／Replay／營運映射。Swift6.4 warnings-as-errors build-tests及相關測試。
2. `tools/c371-c381/export.sh OUT PRIVATE/history/true-v9/models/c371-formation.m3dscene.json`。必須傳受保護C371容器：舊容器內未引用C381記錄也要保持bytes；匯出核每個引用C371單元及站位，package再核實際展開與Swift完整payload。詳見本輪查證及source-record的輸入SHA。重新執行乾淨producer匯出並對22模型檔與兩個預期payload。
3. `render.mjs OUT`、`clay.mjs OUT`、`revision-compare.mjs OLD OUT`；親自查看C381正、左右、俯、斜、白模、剪影及尾／整列。`geometry-audit.py OUT`、`c381-audit.py OLD OUT`（鎖C371全部檔案、C381原屋頂／輪組位置、前窗射線、V帶收尖、支架／底板與破壞反例）、Blender `glb-audit.py`。C371舊front-visibility／underframe-contact也仍執行。
4. 共用#1357 `tools/train-models/run.sh`匯出八單元，`check.mjs`核預算／FNV，只有四個C381鎖值可變；C371四個FNV保持。日夜七向112張，專用七向77張。pack與裸配方應核位置相同，材質旗標／遮蔽色不保證相同。
5. source-record綁producer、保護輸入及真前版；viewer互動／390px手機寬度／下載驗證；bundle.py做ZIP CRC、解壓與全部bytes比對。history不收入當前ZIP。推私庫後從精確artifact commit下載ZIP、真前ZIP和代表檔，完整比對所有ZIP成員；遠端記錄置ZIP外。

## 驗收界線

C371外觀接受；C381待使用者外觀驗收。Linux／WebGL／Blender檢查不等於Simulator、真機Metal、效能、動畫或完整碰撞。直接file協定啟動仍UNVERIFIED，viewer透過本機loopback驗互動。兩PR保持draft；不推main、不合併、不開auto-merge、不啟動TestFlight。僅靜態單元註冊，合併重建不會自動替換營運列車。最新head CI另查；舊head綠燈不能當新head結果。
