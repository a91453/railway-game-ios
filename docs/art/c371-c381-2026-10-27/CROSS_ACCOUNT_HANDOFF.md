# C371 外觀續作：另一個帳戶的 Codex 接手

更新日：2026-10-27。這份文件是可跨對話讀取的工作狀態，**不是外觀驗收**。使用者要求先修 C371，C381 留待獨立修形。兩車現有素材都不能說已獲使用者接受。

## 從哪裡接

| 項目 | 目前位置 |
|---|---|
| 公開 repo／draft PR | `a91453/railway-game-ios`，[#1342](https://github.com/a91453/railway-game-ios/pull/1342)，分支 `codex/c371-c381-native-2026-10-27`；本交接前 head `6104041a009699449294de91f60861b7aa097260` |
| 私有 repo／draft PR | `a91453/railway-reference-private`，[#103](https://github.com/a91453/railway-reference-private/pull/103)，同名分支；head `8c51ce58c4374f43dc8eda3d9926513c64140fe5` |
| 工作 issue／登記 | 公開 [#1341](https://github.com/a91453/railway-game-ios/issues/1341)、[#1041](https://github.com/a91453/railway-game-ios/issues/1041) |
| 公開配方 producer | `6021887799cd136e267e3da0dc527048a84a084a`；其後 `6104041a` 只整合新版 main 與 610 車型的索引／測試衝突 |
| 私有素材目錄 | `Railway/game-art-previews/docs/art/c371-c381-2026-10-27/`，當前 `asset-package.zip` SHA-256 `8b5f81f78713034c468badbdec0659d7068cfdc96d37c7be1fda32a5b5dff140` |
| 真正上一交付 | 私庫 `history/true-v6/`，含原生、GLB、預覽、viewer、來源及完整 ZIP；其 ZIP SHA-256 `8a3fd5d7f3f6de129cdd7bc8c3bcd1a0867deb541a0b5a4149ee2e7de4a6d80a` |

另一個 GitHub 帳戶須能讀**私有 repo**，並對兩 repo 的 PR 分支有寫入權，才能直接續改原 PR。若只有公開 repo 權限，仍可查來源與做公開配方，但不能讀前版私包或更新私有 PR；不要假稱已驗過私包，也不要傳遞憑證。兩個 PR 都保持 draft，不推 main、不合併、不開 auto-merge、不啟動 TestFlight。

## 照片如何接續

使用者在原對話內嵌三張 C371 實車圖：一張前側近景、一張高位前側連車頂、一張高位正面連六車車頂。它們沒有可供另一個帳戶讀取的原檔路徑、作者、授權或 SHA，**不能說新帳戶已查看這三張圖**，也不能從本 repo 找到原圖。原對話中可辨：C371 近直立、幾乎全車寬的銀色前端；黑色罩面與兩片駕駛窗；連續單條藍腰帶；燈座位於腰帶內；低矮連續肋條車頂。透視照片不是工程尺寸，型號與版本仍須以可靠來源交叉確認。

接手者先親自開啟以下**原圖頁及原圖**，再自行搜尋更多正面、左右側、車頂、底部與台車圖；記錄作者、授權、可支持和不能支持的判斷。原圖不可直接搬進公開 repo、預覽或貼圖，沒有授權時也不要存入私庫。

- [台灣車輛 C371 原廠規格](https://www.trsc.com.tw/train/tran-58ace453a7ad8)：正式六車編組、車體及台車尺度；官網圖片前次下載超時，**未查看原圖**。
- [C371 on Tamsui Line](https://commons.wikimedia.org/wiki/File:C371_on_Tamsui_Line_20090221.jpg)：Kirk，CC BY-SA 3.0；前上斜視與車頂。上一位 Codex 已開 960px 原圖；新帳戶須自己重新開圖。
- [C371 approaching Platform 2, CKS Meml Hall](https://commons.wikimedia.org/wiki/File:C371_approaching_Platform_2,_CKS_Meml_Hall_20110225.jpg)：Howard61313，頁面標 public domain；前斜視。前次已開 640px 原圖；新帳戶須自己重新開圖。
- [C371 英文條目](https://en.wikipedia.org/wiki/Taipei_Metro_C371)：只用於型號版本脈絡及找原始來源，不能以條目照片混認 C321／C341 或不同批次。

兩張最初的使用者附件是**插畫**，並非實車工程圖；在 [製作紀錄](README.md) 有逐圖限制。其他可開啟來源與支援範圍也在該文件。不要用模型圖的節數或曲線證明實車編組／尺寸。

## 目前哪裡不合格

從[真正當前正面](https://github.com/a91453/railway-reference-private/blob/codex/c371-c381-native-2026-10-27/Railway/game-art-previews/docs/art/c371-c381-2026-10-27/views/c371-dm/front.png)及私庫 `comparison/c371-before-after.png` 自檢：C371 的銀色端緣雖比 true-v6 圓，但**黑色面罩偏高、前窗下緣與藍帶距離偏大、方形燈座顯厚、端面三維弧度偏平**；同尺度前後圖的差異仍小。這些是下一輪優先修的可見缺陷，不應只調小圓角數值或只增加配件。與實車的正面寬高分區、肩部、窗比例、腰帶、燈腔及側門窗節奏依序比對；不符合就改原生幾何／分色並重渲。未核查的設備站位仍標「比例推估」。C371 全六車目前 14,936 三角，距 M3DM 單檔 15,000 上限只剩 64；增加幾何前先分配／節省三角。

C381 的配方與 10 個交付原生／GLB 檔案在上輪 **byte 相同**，沒有因 C371 修形而改善。另查 C381 實車與差異，之後再做其獨立版本；不可將 C371 改名、縮放或換色冒充。C341 可看完成度、色票、燈光與密度，不能取用其車體、車頭、門窗、底盤或編組。

## 修改與驗證順序

1. 讀兩 repo 的 `AGENTS.md`、`CLAUDE.md`、`docs/HANDOFF.md`，公開 `.claude/skills/rolling-stock/SKILL.md`、`.claude/skills/art-style/SKILL.md`、`docs/art/native-vehicle-modeling/README.md`、`tools/train-models/README.md`。查兩 repo 最新 main、現有 branch、兩 PR／issue 和工作登記；從既有 PR head 繼續，保護別人增量。
2. **改模型前**先把當前私包完整複製成新 `history/true-v7/`，含當前 ZIP、原生／GLB、七向、viewer、來源／SHA。現有 `true-v1` 至 `true-v6` 均須保留。現行 ZIP 未內包 history，是為避開單檔大小限制；history 在 repo 各自保存。
3. 只修改 C371 專用配方 `Sources/GamePresentation/Map3DC371.swift` 與 `Sources/GamePresentation/Map3DMetroStudyGeometry.swift` 的 C371 分支；中央入口只做必要註冊。避免影響 C381 與其他車型。C371 前版／新版以同公尺尺度、同相機、光線及材質做真正前後比較；逐頂點／三角 payload 比較未預期變更範圍。
4. 用 Swift 6.4 warnings-as-errors 匯出與測試（`tools/c371-c381/export.sh OUT`；後續 `render.mjs`、`clay.mjs`、`standalone.mjs`；細節見 `tools/c371-c381/README.md`）。用已合併 main 的 PR #1357 共用 `tools/train-models/` 做單元、FNV 鎖、日夜七向與遊戲光線；C371/C381 特殊完整編組、GLB、故障反例與 ZIP 驗收仍用專用工具。每次新模型都實際查看前、左、右、俯、斜、白模及剪影。
5. 獨立檢查原生逐頂點讀回、三角預算、閉合／法線／輪底／支承、編組真單元平移、Blender GLB importer、所有 PNG 解碼與不裁邊、viewer 手機寬度／旋轉／縮放／下載、ZIP CRC／全解壓／逐檔 bytes。用新 producer commit **重建模型 bytes**。私庫推送後，再從遠端下載 ZIP、代表性原生／GLB／PNG／viewer 與 SHA 核對。
6. 公開庫只放獨立配方、必要工具／測試、文件與一張最新總覽；私庫放完整素材與真前版。更新互鏈的公開 #1342、私有 #103、issue #1341 與登記 #1041。把外觀「已符合／仍不符合／資料不足」、本地 VERIFIED、最新 head CI、Simulator／真機狀態分開寫。若新 head CI 失敗先修；pending、skipping、未觸發不可寫通過。

現有 `metroC381` 是多路線／性能共用營運接點，不是兩款車的專用映射。現有 PR 只有**靜態素材註冊**；合併並重建 App 不會自動替換營運車。不得改 GameCore、存檔、GoldenScenarios、SaveFixtures、ReplayFixtures 或玩法。
