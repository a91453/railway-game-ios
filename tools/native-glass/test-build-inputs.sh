#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/build-inputs.sh"
shopt -s nullglob
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
# Classic Linux SwiftPM layout.
bin="$fixture/classic/debug"
mkdir -p "$bin/Modules" "$bin/GameCore.build" "$bin/GamePresentation.build"
touch "$bin/GameCore.build/core.swift.o" "$bin/GamePresentation.build/presentation.swift.o"
native_glass_build_inputs "$fixture/classic" "$bin"
[[ ${#objects[@]} -eq 2 && ${#includes[@]} -eq 2 ]]
# SwiftBuild: module alongside objects (observed on macOS Swift 6.4), or
# inside Modules/, either file or directory, arbitrary package intermediate.
for layout in flat nested; do
 for kind in file directory; do
 root="$fixture/$layout-$kind"
 for component in GameCore GamePresentation; do
  target="$root/.build/out/Intermediates.noindex/OtherPackage.build/Debug/$component-arbitrary-id.build/Objects-normal/arm64"
  modules="$target"
  if [[ "$layout" == nested ]]; then modules="$target/Modules"; fi
  mkdir -p "$modules"
  if [[ "$kind" == file ]]; then touch "$modules/$component.swiftmodule"; else mkdir "$modules/$component.swiftmodule"; fi
  touch "$target/object.o"
  if [[ "$layout" == nested ]]; then touch "$modules/module.o"; fi
 done
 native_glass_build_inputs "$root" "$root/unused-bin"
 expected=2; if [[ "$layout" == nested ]]; then expected=4; fi
 [[ ${#objects[@]} -eq $expected && ${#includes[@]} -eq 4 ]]
 done
done
echo 'VERIFIED classic and SwiftBuild file/directory module discovery'
