# The game's brand

This repository is public and names the game only as **railway game ios**
(owner, 2026-11-15). The released game's name, the save file extension
players' files already carry, the website and the mailbox are kept out of
it:

- the master copy is `branding/game-brand.json` in the private assets
  repository that takes new material (`docs/ASSET_REPOSITORIES.md`;
  `a91453/railway-assets-private` until the switch of decision 842, whose
  copy stays there unchanged);
- CI reads the same JSON from the repository secret `GAME_BRAND_JSON`
  (Settings → Secrets and variables → Actions → Repository secrets).

The committed files carry the neutral brand (`GameBrand.neutral` in
`Sources/GamePresentation/GameBrand.swift`): "Railway Game" / 「鐵道遊戲」,
save extension `railwaygame`, no website, no mailbox. A build with the
neutral brand, a fork's or a pull request's, has no website button and no
3D city preview, and its data credits offer the derived files from "the
developer".

## The file

```json
{
  "english" : "…",
  "chinese" : "…",
  "saveExtension" : "…",
  "website" : "www.….com",
  "contactEmail" : "…@….com"
}
```

`website` is a host name only (no `https://`, no path). Keep
`saveExtension` as it is: it is the extension of every save players have
shared, and changing it stops those files opening in the game.

## Where it is put in

`apply_brand.py` writes it into the working copy, never into a commit:
`RailwayGameApp/Resources/GameBrand.json` (what the app reads), the en and
zh-Hant `InfoPlist.strings` (the Home Screen name, the save type's name) and
`RailwayGameApp/Info.plist` (the save type's name and extension).
`GameBrandTests` fails if any of them is committed with a brand in it.

- `testflight.yml`: the preflight job checks the secret, the release job
  applies it before the archive. A release with no secret fails.
- `website-screenshots.yml`: applies it when the secret is set.
- `ios-build.yml`, the full lane and `release-archive.yml` build the
  neutral game; `SettingsUITests`' city preview test skips there.
- `tools/procedural-city/build_city_view.sh` puts the names into the built
  3D city page from the newest assets checkout beside this one
  (`../railway-assets-private-N/`, else `../railway-assets-private/`,
  `branding/game-brand.json`), or `GAME_BRAND_FILE`.

On the Mac, before building in Xcode with the released name:

```sh
python3 -I tools/brand/apply_brand.py ../railway-assets-private/branding/game-brand.json
# … build …
git checkout -- RailwayGameApp/Resources/GameBrand.json \
  RailwayGameApp/Resources/en.lproj/InfoPlist.strings \
  RailwayGameApp/Resources/zh-Hant.lproj/InfoPlist.strings RailwayGameApp/Info.plist
```

Each value is masked in the Actions logs (`--github-mask`). Git history from
before 2026-11-15 still has the name; it is not rewritten.
