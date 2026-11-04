#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
swift_version="$(swift --version 2>&1)"
printf '%s\n' "$swift_version"
[[ "$swift_version" =~ Swift\ version\ 6\.4([.[:space:]]|$) ]] || { echo 'Swift 6.4 required' >&2; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bin="$(swift build --show-bin-path)"
shopt -s nullglob
source "$root/tools/native-glass/build-inputs.sh"
native_glass_build_inputs "$root" "$bin"
swiftc -swift-version 6 -warnings-as-errors "${includes[@]}" tools/native-glass/check-cabins.swift "${objects[@]}" -o "$work/check"
"$work/check" "${1:?fixtures}" "${2:?report JSON}"
