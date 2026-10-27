# 莒光號營運編組的近景（決策 430）

`overview.png`：E500 拉三節莒光自動門客車（#1306 的 `standard`），最後一節的端牆亮兩顆紅色尾燈。上排是整列從左後方看；下排左是尾端近景，下排右是從正後方看。

這是用遊戲模型包的實際頂點（`set-E500CK-head`、兩個 `set-E500CK-car`、`set-E500CK-tail`，依 `Map3DModelPack.layout` 的長度接起來）做的**軟體算圖**：正交、平面著色、發光的面加一點光暈。它不是 Metal 的畫面，沒有雨、夜、霧與陰影，只用來看形狀、顏色與尾燈的位置。真機畫面、幀數是 UNVERIFIED。

重做：寫一個暫時的測試，把四個模型的頂點（`x + 位移, y, z, nx, ny, nz, color, glows`）依序存成 JSON，再 `python3 -I render.py <放 set.json 的資料夾>`（需要 NumPy 與 Pillow）。測試與 JSON 不進 repository。
