# MAP-PACK-COPY：讓地圖包在換新版後也讀得到（接 DEBUG-150）

雲端工作串「讓地圖包能正常下載更新」，分支 `claude/project-thread-s9j6xa`。存檔版本、決策、golden schema 不動。

## 進度

- 做到：#2771 合進 main（48e293b），TestFlight 152（run 45876417790，`carry_map_packs: yes`）11-27 03:20 上架；拆成三段的 testflight.yml 第一次真的跑，三段都成功。
- 已驗證（作者 iPhone，iOS 27.3，從 150、151 升上來）：設定三列都「已下載」；回報「地圖包：」是 `mappack-hongkong used (copied out: 17 files, 17 new); mappack-rovaniemi used (copied out: 16 files, 16 new); mappack-fukuoka used (copied out: 24 files, 24 new)`。也就是 `url(for:)` 還是壞的，`descriptor(for:)` 讀得到，三座城 57 個檔全靠複製讀到；沒有走到「刪掉重抓」。
- 下一步：從 main 發 `carry_map_packs: no` 的 TestFlight，作者看三列都「已下載」、三座城開得起來（從內建版升級）；有沒裝過的裝置就順便驗全新安裝。過了，上架版就用 `no` 發，送審時「素材包」附上六包現行版本（DEBUG-150）。

## 為什麼

DEBUG-150：150、151 在作者 iPhone 上，`AssetPackManager.url(for:)` 對每個檔和資料夾都回
`NSCocoaErrorDomain 513`「沒有權限在 <UUID> 儲存 Staged Subpaths.plist」。那是手機第一次把已下載的包換成新版本。

Apple 論壇有一樣的情形（UNVERIFIED，是別人的回報，不是 Apple 的答覆）：

- thread 859906：包換新版後 `contents(at:)` 回 Operation not permitted，重開 App 有時會好。
- thread 845723：`ensureLocalAvailability` 成功，但 178 台裝置讀不到檔，刪掉 App 重裝就好。
- Apple 文件：`url(for:)` 要先「stage」檔案，比較慢；`descriptor(for:searchingInAssetPackWithID:)` 和 `contents(at:searchingInAssetPackWithID:options:)` 直接開檔，不用 stage。

所以壞掉的是 stage 那一步，不是檔案本身。

## 改了什麼

1. `take` 加第四個找法（`MapPackDownloader.Copier`）：前三個都找不到時，用 `descriptor(for:)` 開檔（打不開就改用 `contents(at:)`），
   把檔案複製到 App 自己的 `Application Support/MapPackCopies/MapPacks/<城市>/`（不備份到 iCloud），再從那裡讀。
   `pack.json` 每次都重抓來比：和上次複製的不一樣，就整包重新複製。之後又能照原本的方式讀時，複製的檔會刪掉。玩家在設定按「移除」也一起刪掉。
2. 系統說包在手機上卻一個檔都找不到（`noManifest`）時刪掉重抓：原本只在不內建的版本做，現在內建的版本也做，**每個 build 一次**（`mapPacks.refetchedInBuild.<城市>`）。
   內建的版本在重抓期間照樣讀內建的，玩家不受影響，又能從回報看出重抓有沒有用。
3. 回報問題的「地圖包：」：
   - 讀到時，不是用原本方式讀到的會寫在括號裡：`mappack-hongkong used (copied out: 16 files, 16 new)`、`(fetched again)`、`(fetched again, copied out: …)`。
   - 讀不到時，括號裡多寫複製時系統回的錯：`copy said …`。
4. `testflight.yml` 多一個選項 `carry_map_packs`（預設 `yes`）：選 `no` 就只帶 `pack.json`，App 約小 140 MB（`project.yml` 的 `CARRY_MAP_PACKS=NO`）。

## 接下來（實機）

- 先發一版**內建的**（`carry_map_packs: yes`）到 TestFlight，裝在作者那支從 150、151 升上來的 iPhone 上。
  打開 App 等幾分鐘，到「設定」看香港、羅瓦涅米、福岡三列：
  - 寫「已下載」：下載讀得到了。再送一份「回報問題」，括號裡說是用哪條路讀到的。
  - 還是「使用內建資料」：送「回報問題」，看 `copy said …` 和 `fetched again`，再決定下一步。
- 三座城都「已下載」以後，才用 `carry_map_packs: no` 發一版，確認不內建也能玩（這時候就是從內建版升級的情形）。
  全新安裝要用另一台沒裝過的裝置，或刪掉 App 重裝（存檔沒放 iCloud 的話會不見）。147 那次第一次下載是正常的。
- 送 App Store 審核前沒有證明可以，就照 DEBUG-150 帶著內建送審。

## 還沒做

- 複製一份會多占手機空間（三座城約 140 MB，系統那份也還在）。`url(for:)` 好了以後會自動刪掉複製。要省空間，可以在複製完後改成只留一份，但系統那份不能刪（刪了就會重抓），先不動。
- 如果 `descriptor(for:)` 也回 513，下一步是讓每次資料更新都換一個新的包 ID（`mappack-hongkong-2`），而且路徑也要換（Apple：包的 ID 不算在路徑裡，兩包同路徑會撞，thread 804019），讓手機每次都是「第一次下載」，不會走到換新版那一步。
