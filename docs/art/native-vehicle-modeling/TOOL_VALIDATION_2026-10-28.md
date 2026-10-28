# 列車模組更新驗證（2026-10-28，Linux）

工具 producer：`a1164a71ade7e55024e83c39f3523e7bfc48334c`；base：`95c046e3fb10e74ae7d63dd3b940f600f9779d11`。後續純文件提交不影響此producer的工具／模型。沒有製作三鶯線，沒有修改任何 Sources、Swift測試、hashes.lock、GameCore、fixtures或營運映射。共用scene.js與GLB writer直接引用現有版本，未複製新一套；私有參考庫的預覽入口確認舊輪次／ZIP政策，最新素材AGENTS決定限制，不引入外部程式或新遊戲依賴。

## 已執行

| 檢查 | 結果與範圍 |
|---|---|
| Swift 6.4 `swift build --build-tests -Xswiftc -warnings-as-errors -j 4` | VERIFIED；獨立worktree乾淨建置，356.71s |
| `swift test --skip-build --filter 'Map3DModelFileTests\|TrainNightLightsReadBackTests\|Map3DModelPackSizeTests\|Map3DC371C381Tests'` | VERIFIED；14項、0失敗，實際Selected tests suite通過；空的第二runner不作證據 |
| `node --test tools/train-models/test.mjs` | VERIFIED；5項契約測試：單元上限／非法幾何、組裝位移與180度旋轉／flags／色彩、錯誤定義拒收、真缺面／反面、GLB改byte拒收、保留單元FNV保護並排除無FNV的編組場景 |
| `python3 -m unittest discover -s tools/train-models -p 'test_*.py'` | VERIFIED；6項：選圖／SHA／防覆寫、22張／重複拒收、裁邊／截斷拒收、越界路徑／ZIP／超限檔案拒收、producer／接受版本拒收、未提交來源／>2MiB PNG拒收 |
| 實際共用匯出 | VERIFIED；c371-dm、c381-dm、taipei610-a／b，JSON再組一個雙單元測試場景；不是新增實車編組 |
| 共用check／audit | VERIFIED；5個記錄、4個pack FNV符合既有鎖，編組單獨檢查；全部合法單元、GLB writer重建、封閉方向／正體積、缺面／反面及編組錯位反例通過。沒有聲稱全模型鎖都已重驗 |
| 原模型保護 | VERIFIED；git diff無Sources／hash鎖變動；兩個C371／C381頭車pack-native與先前交付逐bytes相同 |
| 獨立Blender 4.3.2匯入 | VERIFIED；兩個頭車＋雙單元場景共3個GLB，三角數、原生軸bounds、色彩／霧面材質；沿用emu900-native/glb-audit.py |
| PNG | VERIFIED；3模型×7向×日夜＝42張，Pillow完整解碼、RGBA／透明、非空且不裁邊 |
| 最後自含inspector | VERIFIED（localhost）；3模型、每件7向及日夜，native／GLB真下載bytes相等、PNG真下載，旋轉／縮放改畫面、390px無橫向溢出、無JS錯誤或外部請求；親自開啟手機截圖 |
| 限量交付 | VERIFIED；只選2張PNG，16檔約7.8MiB；真producer、來源／四狀態／README／SHA；最後inspector和所有下載模型bytes與實測版本一致 |
| 素材庫asset_guard | VERIFIED；暫存git repo的新輪次staged tree，16新增檔、7.8MB、沒有違規。沒有推送測試用模型到素材庫 |
| 文件 | VERIFIED；本輪文件連結無缺檔、git diff --check通過、doc_numbers差異0 |

## 未驗與限制

- `file://`：UNVERIFIED；本環境Chromium回報ERR_BLOCKED_BY_ADMINISTRATOR。檢查器記錄此精確限制，其他檔案／JS錯誤仍使檢查失敗。
- 新車專用玻璃可見性／設備支承／逐輪貼軌及淨空未由共用audit自動證明；三鶯線仍須按實車來源設計與跑故障反例。
- 不把JS自己展開的assembly_payload稱為獨立Swift證據；有Swift直接編組時仍須逐payload比較。
- 不證明工程精度、所有自交／碰撞、使用者外觀接受、營運接入、Metal／真機效能或動畫。
- 遠端CI以本PR最新head檢查為準，這份本機紀錄不預先宣布遠端通過。

本次暫存輸出位於`/workspace/train-kit-check`、`train-kit-browser`及`train-kit-delivery-final`；不依賴這些目錄作下一位的交接。請從[工具README](../../../tools/train-models/README.md)重建／驗證；[三鶯線prompt](SANYING_PROMPT.md)可直接貼給下一個對話。
