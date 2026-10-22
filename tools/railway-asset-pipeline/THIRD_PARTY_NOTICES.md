# Railway asset pipeline — third-party notices

The source files in this folder contain **no commercial railway model data**.
The names below credit technical implementations consulted while studying the
container formats. They are not sources of model/texture redistribution rights.

| Component | Usage in this folder | Attribution / license |
| --- | --- | --- |
| [Dasug/a9tools](https://github.com/Dasug/a9tools) | Fixed-key transform and LZ-style archive decoder adapted in decode_unpack.cpp | MIT, copyright (c) 2022 Marius Kaufmann. Full text: [MIT](licenses/MIT.txt). |
| [pawstas80/Unpacker](https://github.com/pawstas80/Unpacker) | Studied ISSetupStream envelope, PE overlay and encrypted entry handling for the independent Python port | Apache-2.0. Full text: [Apache-2.0](licenses/Apache-2.0.txt). |
| [lifenjoiner/ISx](https://github.com/lifenjoiner/ISx) and original ISSetupStream extractor | Technical predecessor for InstallShield stream decoding: original extraction credits to lifenjoiner (2017) and Mantas Mikulenas (2019) | MIT; retain upstream acknowledgement. |
| [libarchive](https://www.libarchive.org/) | System library linked by the optional CAB extraction helper | BSD-style license in the installed libarchive distribution; no libarchive source is vendored. |
| [openOMSI/openOMSI](https://github.com/openOMSI-org/openOMSI) | DirectX X token and glTF coordinate-system reference, not copied code | Technical format research only. |
| Python, NumPy, trimesh, Pillow | Only the optional local model-preview stage imports NumPy / trimesh / Pillow | No vendored dependency or pinned runtime change in this PR; respect each dependency's installed license. |

## Railway input assets

The repository owner supplied the railway source archive under an existing
purchase/use authorization. This workflow is intended to work with **the
owner's authorized local files**: unpacking, decoding, conversion, preview,
prototype evaluation and performance research may proceed under that license.

The source files and preview exports are intentionally kept in a **private
workspace outside the public repository**. Whether any particular original
mesh/texture or derived file may be shipped or sublicensed in a public game
depends on the owner's actual grant, which can be assessed at release time.
No broad ban on local development or hypothetical restriction is asserted here.

The converter's grey placeholder material is newly generated demonstration
content; it must not be described as an authentic recovered skin.
