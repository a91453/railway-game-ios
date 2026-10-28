# C371／C381 續作交接（第五輪，2026-10-28）

公開 draft [#1342](https://github.com/a91453/railway-game-ios/pull/1342) ↔ 私有 draft [#103](https://github.com/a91453/railway-reference-private/pull/103)，同分支 `codex/c371-c381-native-2026-10-27`；工作 #1341、登記 #1041。producer 與最新 head CI 見兩 PR；不能沿用舊 head 的綠燈。

## 真前版與本輪

真正接手的第四輪私包（私庫1a94ea1d）完整保存在 `Railway/game-art-previews/docs/art/c371-c381-2026-10-27/history/true-v8/`，含原生、GLB、預覽、viewer、來源／驗證與原ZIP。ZIP SHA-256：`be655c5541042d89f72aef55711d0c6a874ff46464106988d05d2dda2453dee3`。更早true-v1～v7保留。使用者要求完整保存真前版，優先於一般素材清理規則。

本輪重新查看已下載的TRSC完整實車原圖（同一原檔SHA，見REFERENCE_RECHECK），修三處：連續弧形銀色端面／黑罩與多段橫向弧面；略斜前窗及細中央門框；薄下裙橫樑、分離支座、中央連結器及四根台車軸桿。第一稿整片厚橫樑從正面像厚板，已拒收；其PNG在review，不能稱真前版。比較圖使用true-v8及最終模型、同公尺尺度／相機／光線。

C371 DM/rear各3,526三角，六車15,828三角。每個原生單元仍不超過15,000；完整六車使用既有工具M3DAssembly展示契約，沒有輸出超限M3DM或修改遊戲讀檔上限。Swift整列預期payload存為verification/*.bin，展開單元平移後逐bytes相同，移位100mm反例會被拒收。GLB和viewer從同一組裝來；這不是App整列接入驗收。

C381本輪不改，10件專用原生／GLB與true-v8 bytes相同，外觀未驗收。C371 T/M及EMU3000比較模型同樣bytes不變。頭車新增軸桿，原有輪胎、輪轂與車頂三角不改；本輪主車殼站位不改，重新分片的是端罩／前面板；車頭末段0.42m以外只新增四根軸桿，既有三角逐bytes保持。檢查見protected-payload-verification.json。

## 驗收界線

已自檢改善眉線／肩部、窗框及厚橫樑；輪徑和貼軌位置保持，輪組投影仍會在正交前視看到。精確弧度、支座尺寸與隱藏設備仍為比例推估，不冒稱工程還原。C371仍待使用者外觀驗收；C381外觀未驗收。原生前、左右、俯、斜、白模、剪影均需親自查看。僅靜態單元註冊，不改營運映射；合併重建App不會自動換營運列車。真機Metal／效能／動畫／完整碰撞、本輪Simulator畫面及直接file://啟動仍UNVERIFIED。

## 重建

1. 先查工作登記、雙庫遠端head與適用規則；本輪已整合main cdb5bba0的衝突，保留其夜間燈光、淡色與乘客效能修改，只對註冊／計數做必要衝突整合。沒有新增GameCore／存檔／Golden／Save／Replay／玩法變更。主庫不放完整素材或照片。
2. Swift6.4 warnings-as-errors：build-tests與相關測試。`tools/c371-c381/export.sh OUT`，接續render.mjs、clay.mjs、revision-compare.mjs OLD NEW。
3. `geometry-audit.py`、`front-visibility.py`（目前正面黑罩114點／玻璃18點及埋入玻璃反例）、`protected-payload.py OLD NEW`、Blender glb-audit.py、verify-png.py。package.mjs額外核assembly預期payload與移位反例。
4. 已合併#1357的共用train-models工具匯出八單元、FNV與日夜七向；本輪只應改C371頭尾鎖值。pack的材質旗標與遮蔽顏色不同於裸配方，應核座標，不能宣稱整份payload一致。
5. 用真producer提交重建22件原生／GLB bytes，綁source-record，更新viewer後驗互動／手機寬度／下載，bundle.py做CRC／完整解壓逐bytes。history另存，不收入當前ZIP。私庫推送後重新下載ZIP、真前ZIP及代表檔核對；遠端驗證記錄置ZIP外。

上一輪44b3d270的Linux build、五分片、gate與Xcode Simulator build已通過；UI/iPad skipped。本輪新head另查，不把舊結果當新結果。

兩PR保持draft；不推main、不合併PR、不開auto-merge、不啟動TestFlight。
