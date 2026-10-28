目前為C381照片修訂：C371第五輪外觀已接受、全部模型bytes保護。詳見 [本輪查證](../../docs/art/c371-c381-2026-10-27/C381_REFERENCE_RECHECK.md)。

`export.sh OUT PROTECTED_C371_SCENE` 必須傳入真正前包 `history/true-v9/models/c371-formation.m3dscene.json`，保留舊C371容器未引用的C381記錄；核引用單元／站位及Swift整列payload，沒有偷偷替換新C381。`c381-audit.py OLD OUT`核C371所有檔案bytes、C381屋頂／輪組位置、正面玻璃射線、V帶與實際支架接地板及故障反例。舊protected-payload.py只適用歷史C371輪次，本輪不用；front-visibility.py／underframe-contact.py仍核受保護C371。當前真前版是true-v9，下文v7／第五輪敘述為歷史。

C371／C381 靜態原生模型工具。先讀 docs/art/c371-c381-2026-10-27/README.md。
已合併 PR #1357 的 `tools/train-models/` 是單元原生匯出、日夜七向、FNV 鎖與遊戲光線的共用入口；本資料夾保留完整編組、GLB、真正前後、白模／剪影、故障注入及 ZIP/viewer 專用驗收。
`export.sh OUT` 以 Swift 6.4 輸出原生及 GLB；`render.mjs OUT` 實際從原生顯示七向；`clay.mjs OUT` 產生白模／剪影；`standalone.mjs OUT` 產生離線檢視器。
M3DAssembly 由每個獨立單元的最終原生 bytes 組成。 `scene.js` 只做組裝平移。

本輪修形加用 `front-visibility.py OUT`：從實際原生三角向 +X 射線，檢查黑罩／玻璃區域及埋入玻璃反例；僅抽樣正交正面，不代表全碰撞。`protected-payload.py OLD NEW` 比較 C381 全部模型及 C371 中間車逐 bytes，並檢查 C371 頭車差異範圍。`bundle.py OUT` 建立不含 history 的當前 ZIP，CRC、解壓及每件 bytes 比對；真前版另存 history/true-v7。

第五輪六車超過單一M3DM上限，沿既有M3DAssembly匯出；`export.swift`寫出Swift整列預期triangle payload至verification/*.bin（不是超限M3DM）。`package.mjs`逐bytes對照單元平移組裝結果，並拒收移位100mm的單元。`assembly-verification.json`記錄結果。M3DM上限保持15,000；GLB與viewer從同一組裝生成。

`underframe-contact.py OUT` 從實際原生連通三角辨識兩個實心箱形支座，核它們與底板／橫樑實際重疊；將真支座頂點降低50mm的反例須拒收。只核這幾件局部接觸，不是完整碰撞或結構工程驗收。
