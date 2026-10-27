C371／C381 靜態原生模型工具。先讀 docs/art/c371-c381-2026-10-27/README.md。
`export.sh OUT` 以 Swift 6.4 輸出原生及 GLB；`render.mjs OUT` 實際從原生顯示七向；`clay.mjs OUT` 產生白模／剪影；`standalone.mjs OUT` 產生離線檢視器。
M3DAssembly 由每個獨立單元的最終原生 bytes 組成。 `scene.js` 只做組裝平移。
