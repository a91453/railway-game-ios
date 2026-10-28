# 新對話車輛素材製作指令

適用沒有本對話紀錄的代理。列車先使用共用tools/train-models；原始來源資料與成品素材分庫。以下指令依2026-10-28規則整理，接手仍須讀最新main，不能用本頁覆蓋更新的AGENTS.md。

```text
請在 a91453/railway-game-ios 完成我指定的新車原生3D素材，實際查看來源、寫配方、匯出、驗證並推draft PR，不只列計畫。

先fetch最新main，讀AGENTS.md、CLAUDE.md、docs/HANDOFF.md、art-style與rolling-stock技能、docs/art/native-vehicle-modeling/{README,PROMPT,REVIEW_CHECKLIST}.md、tools/train-models/README.md，以及railway-assets-private的AGENTS.md。讀#1041工作登記並認領自己的精確檔案；前置PR逐張查merged與head，從main開自己的codex/分支／worktree，兩庫PR的base都是main。不另開平行子agent。

先親自開啟官方／製造商及其他可靠實車原圖，分類照片／效果圖／插畫／工程資料；記來源、作者、授權與日期。確認車型、尺寸、編組與朝向、頭尾／左右差異、門窗／設備／走行及集電方式。未知就標待查，照片推估不冒充工程尺寸。先查作者reference-private內可用資料；成品去assets-private，不能公開原始私有來源或送外部生成服務。

先大形比例、側正俯斜與車頭肩部，再白模／剪影、人眼修形，最後門窗、設備、塗裝、薄框與燈。學既有車風格／驗收，不把舊車換色當新車；依本車來源決定造型及設備。使用遊戲霧面頂點色、既有色票，不放真實商標或照片貼圖。列車兩側門與實際編組按來源確認，不套公車規則。

優先使用tools/train-models：匯出單元、--assembly-spec資料描述編組、package.mjs、audit.mjs、render.mjs、inspect.mjs與deliver.py；僅缺少的專用驗收才新開工具。展示資產放studies，不增加standard常駐負擔。近遠景／整列預算與M3DM單檔上限分開驗；完整編組由最終單元組成。保護其他車payload，不整份重寫hash鎖去消除既有差異。

用Swift6.4 warnings-as-errors及觸及測試；檢查最終原生／GLB、封閉／法線／有限值、玻璃貼合與可見、設備接觸、逐輪貼軌／淨空及編組。加入實際缺面／反面／玻璃埋入／輪子抬起／編組錯位反例；共用幾何通過不代表專用驗收已做。獨立GLB importer、PNG完整解碼、最終七向／白模／剪影人眼檢查、真viewer互動與下載SHA都要完成。

先提交影響輸出的配方與工具，再以真producer重建核bytes。修訂先記真正前版commit，固定相機／尺度比較；不複製history包。公開只放配方、工具、必要測試／文件及一張小總覽；大型輸出放railway-assets-private/game-art-previews/docs/art/<model>/<revision-N>/。整個模型每輪最多21張PNG、每張≤2MiB、單檔≤50MiB、PR新增≤200MiB。最多3候選、僅選中候選留重檔；只最新輪次留模型／viewer，被取代輪次同PR刪重檔、留PNG／README／來源。禁止新增ZIP、history/、old/、backup/。

README填producer、重建指令、來源及授權，依status-template.json分開記素材技術、明確producer的使用者外觀接受、營運接入、裝置驗證，未驗為UNVERIFIED。使用者同意合併或技術全綠都不能代替外觀／真機接受。

本輪預設是靜態展示，不動GameCore、存檔、golden／replay fixtures或營運玩法。完成asset_guard後推互鏈的公開／素材draft PR、更新#1041及HANDOFF，查最新head實際CI；PR附五方理由與VERIFIED／UNVERIFIED。不要推main、merge、auto-merge或啟動TestFlight。最後用繁體中文給本批實際預覽、PR、交接／重建連結及未驗事項。
```

開始前補上車種名稱、參考圖／網址、已接受部位、本輪是否另包含營運接入。三鶯線可直接用 [專用指令](native-vehicle-modeling/SANYING_PROMPT.md)。
