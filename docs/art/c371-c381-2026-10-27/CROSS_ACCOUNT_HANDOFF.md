# C371／C381 跨帳戶續作交接

2026-10-27 本帳戶已依原交接順序先讀本文件，再讀私有 PR #103，親自開啟 TRSC 完整原廠照片、Kirk 淡水線原圖及 Howard61313 中正紀念堂原圖，另查網路圖片與本輪五張內嵌實車照。逐張來源、SHA、觀察與限制見 [本帳戶複查](REFERENCE_RECHECK.md)及私包 source-record.json。

## 本輪入口

- 公開 `a91453/railway-game-ios` draft [#1342](https://github.com/a91453/railway-game-ios/pull/1342)，私有 `a91453/railway-reference-private` draft [#103](https://github.com/a91453/railway-reference-private/pull/103)。同名分支 `codex/c371-c381-native-2026-10-27`；工作 [#1341](https://github.com/a91453/railway-game-ios/issues/1341)、登記 [#1041](https://github.com/a91453/railway-game-ios/issues/1041)。producer 及最新 head CI 見兩 PR，不沿用舊 head 綠燈。
- 私包根目錄：`Railway/game-art-previews/docs/art/c371-c381-2026-10-27/`。本輪接手時完整交付（私庫 8c51ce58）已保存於 **history/true-v7/**，含模型、圖、viewer、來源、驗證及原 ZIP，ZIP SHA-256 `8b5f81f78713034c468badbdec0659d7068cfdc96d37c7be1fda32a5b5dff140`。true-v1 至 true-v6 均保留。此為使用者明確要求完整真前版保存，優先於一般素材清理規則。
- `comparison/c371-before-after.png` 使用真正 true-v7 與本輪模型、固定相機／公尺尺度／光線。`review/` 的 A 方案與露底試稿為試驗證據，不能稱為真正交付前版。

## 修改與外觀界線

本輪只改 `Map3DMetroStudyGeometry.swift` 中 C371 駕駛端：拱形眉線、最後 0.32 m 端殼過渡、淺橫向弧面、前窗下緣降低、薄圓角燈腔；雨刷／燈片貼合最終面。先前非平面扇形三角讓銀底穿過黑罩，已改用共面分片並用真正試稿驗證射線檢查會拒收。C371 六車 14,876 三角，未超 15,000。降低小顯示面與中央門框細節分段，將預算用於輪廓；沒有借 C341 幾何。

**C381 本輪不改，10 件原生／GLB 與 true-v7 bytes 相同，外觀未驗收。** C371 中間 T/M 車及 EMU3000 風格比較模型同樣 bytes 不變。C371 主殼新增站位會重切跨車身長面；不能宣稱所有車頭以外的主殼三角 bytes 不變。配件保護與實際差異見 protected-payload-verification.json。

本輪自檢改善眉線方框、前窗下方留白及厚燈座；精確半徑、另一側設備與隱藏底盤仍是比例推估。**C371 仍待使用者外觀驗收，C381 未驗收；兩者皆不可寫成已接受。** 此為靜態素材註冊，沒有營運映射；合併重建 App 不會自動替換營運列車。真機 Metal、效能、動畫、全碰撞與本輪 Simulator 實際畫面仍 UNVERIFIED。

## 重建與檢查

Swift 6.4 warnings-as-errors 建置相關測試。使用已合併 #1357 的 `tools/train-models/` 匯出八單元、FNV 鎖與日夜七向；接手時鎖未同步後來的 pack 材質／遮蔽處理；用原配方與新配方在同 pipeline 重建，確認只有 C371 DM/rear 改變，再校正本批八個鎖項。原生 C381 幾何與交付 bytes 不變，詳見私包 lock-reconciliation.json。完整六車／GLB 仍用 `tools/c371-c381/export.sh OUT`，接續 `render.mjs`、`clay.mjs`、`revision-compare.mjs OLD NEW`。每次修改都重看前、左右、俯、斜、白模與剪影。

跑 `geometry-audit.py`、`front-visibility.py`、`protected-payload.py OLD NEW`、Blender `glb-audit.py`、`verify-png.py`。source-record 綁真 producer commit 後重建 22 件模型逐 bytes；再更新 viewer、跑互動／下載／手機寬度驗收，`bundle.py` 完整 CRC／解壓逐檔比對。history 不收入當前 ZIP，仍完整保存在私庫。推送後從遠端下載 ZIP 與代表檔重新核 SHA。

先讀雙庫適用 AGENTS／CLAUDE／HANDOFF、rolling-stock、art-style 與建模手冊，查工作登記與遠端最新 head，保護他人增量。私庫無根 AGENTS／CLAUDE／docs/HANDOFF；公開庫規則與本輪使用者授權適用本工作。不改 GameCore、存檔、Golden／Save／Replay fixtures、玩法或營運映射。

兩 PR 保持 draft；不推 main、不合併、不開 auto-merge、不啟動 TestFlight。
