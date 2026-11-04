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
# SwiftBuild: either file or directory modules, arbitrary package intermediate.
for kind in file directory; do
 root="$fixture/$kind"
 for component in GameCore GamePresentation; do
  target="$root/.build/out/Intermediates.noindex/OtherPackage.build/Debug/$component-arbitrary-id.build/Objects-normal/arm64"
  mkdir -p "$target/Modules"
  if [[ "$kind" == file ]]; then touch "$target/Modules/$component.swiftmodule"; else mkdir "$target/Modules/$component.swiftmodule"; fi
  touch "$target/$component.o" "$target/Modules/$component.o"
 done
 native_glass_build_inputs "$root" "$root/unused-bin"
 [[ ${#objects[@]} -eq 4 && ${#includes[@]} -eq 4 ]]
done
echo 'VERIFIED classic and SwiftBuild file/directory module discovery'
