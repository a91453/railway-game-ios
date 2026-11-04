#!/usr/bin/env bash
# Sourced by both standalone checkers. SwiftBuild can emit a .swiftmodule
# directory and does not promise a particular package's intermediate name.
native_glass_build_inputs() {
 local build_root="$1" bin_path="$2" component module target found
 includes=(); objects=()
 if [[ -d "$bin_path/GamePresentation.build" ]]; then
  includes=(-I "$bin_path/Modules")
  objects=("$bin_path"/GamePresentation.build/*.swift.o "$bin_path"/GameCore.build/*.swift.o)
 else
  for component in GameCore GamePresentation; do
   found=false
   while IFS= read -r -d '' module; do
    target="${module%/Modules/$component.swiftmodule}"
    if [[ -e "$module" ]]; then
     includes+=(-I "$target/Modules")
     objects+=("$target"/*.o "$target"/Modules/*.o)
     found=true; break
    fi
   done < <(find "$build_root/.build" -path "*/Objects-normal/*/Modules/$component.swiftmodule" -print0)
   "$found" || { echo "Missing $component build in $build_root/.build" >&2; find "$build_root/.build" -name "$component.swiftmodule" -print >&2; return 1; }
  done
 fi
 [[ ${#objects[@]} -gt 0 ]] || { echo 'Missing native object files' >&2; return 1; }
}
