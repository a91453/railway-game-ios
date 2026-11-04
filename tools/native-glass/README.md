# Native Metal glass verification

[設計與限制](../../docs/art/native-glass-2026-11/README.md)。Linux只驗GamePresentation與Swift解析，不假稱能執行Metal。

在Swift6.4、Xcode／Metal SDK的Mac上：先在本repository之外以真producer產生fixtures：

```sh
git fetch origin 5cfec2954bde648ad3a40f43f8ec18ff89d11bdf
git worktree add --detach /tmp/maokong-glass-recipe 5cfec2954bde648ad3a40f43f8ec18ff89d11bdf
python3 /tmp/maokong-glass-recipe/tools/maokong-cabin-refine/produce.py /tmp/glass-fixtures/maokong
git fetch origin 074b085c03329edcda9f212927783b5787857adc
git worktree add --detach /tmp/sunmoon-glass-recipe 074b085c03329edcda9f212927783b5787857adc
python3 /tmp/sunmoon-glass-recipe/tools/sunmoon-cabin-studies/produce.py /tmp/glass-fixtures/sunmoon --kind red
python3 /tmp/sunmoon-glass-recipe/tools/sunmoon-cabin-studies/produce.py /tmp/glass-fixtures/sunmoon --kind crystal
tools/native-glass/run-metal.sh /tmp/native-glass-proof /tmp/glass-fixtures
```

輸出metal-verification.json及GPU可用時的PNG。保留真Metal執行狀態，無裝置時明寫UNVERIFIED。工廠由App原檔標記區抽出，同步防止測試／App blend或depth設定各走各的。fixtures不commit，也不安裝新套件／引擎；不跑發版workflow。
