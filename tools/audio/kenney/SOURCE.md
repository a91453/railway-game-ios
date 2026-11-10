# Kenney sounds (decision 675)

Made by Kenney (www.kenney.nl), **CC0 1.0** (public domain; credit is kind, not required).
The licence texts of both packs are kept here: `LICENSE-interface-sounds.txt`, `LICENSE-jingles.txt`.

| Pack | Version | Source | Fetched |
| --- | --- | --- | --- |
| Interface Sounds | 1.0 (2020-02-11) | https://kenney.nl/assets/interface-sounds, taken from the same pack on https://opengameart.org/content/interface-sounds (`kenney_interfaceSounds.zip`) | 2026-11-10 |
| Short jingles ("85 Short music jingles", Kenney's Jingles) | 2014-03-17 | https://opengameart.org/content/85-short-music-jingles (`jingleSounds_Kenney.zip`) | 2026-11-10 |

kenney.nl itself answers 403 from the build environment, so both zips came from OpenGameArt, where Kenney
is the uploader and the licence is CC0. Only the files below are in the app; `convert.sh` makes them
(OGG to 16-bit mono 44.1 kHz WAV, nothing else changed; levels are set in `GameAudio`).

| App file (`Resources/AudioKenney/`) | Original | Plays for |
| --- | --- | --- |
| `kenney-ui-tap.wav` | Interface Sounds `click_003.ogg` | `SoundCue.uiTap` |
| `kenney-ui-toggle.wav` | `toggle_001.ogg` | `.uiToggle` |
| `kenney-ui-confirm.wav` | `confirmation_001.ogg` | `.uiConfirm` |
| `kenney-ui-cancel.wav` | `back_002.ogg` | `.uiCancel` |
| `kenney-ui-open.wav` | `maximize_009.ogg` | `.uiOpen` |
| `kenney-ui-close.wav` | `minimize_009.ogg` | `.uiClose` |
| `kenney-jingle-goal.wav` | Jingles `jingles_PIZZA/jingles_PIZZA02.ogg` | `.goalMet` |

Other candidates heard of by measurement only (see the pull request): `click_005`, `toggle_004`,
`confirmation_004`, `back_004`, `maximize_007`/`minimize_007`, `jingles_PIZZA10`.
