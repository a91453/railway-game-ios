#!/usr/bin/env bash
# Installs an official Swift toolchain for Linux from swift.org into DEST,
# verified against swift.org's signing keys. Used by the Claude Code cloud
# session hook (.claude/hooks/session-start.sh):
#
#   .github/scripts/install-swift-linux.sh 6.4.0 /opt/swift
#
# VERSION is the full release name with three numbers. swift.org names every
# release that way (swift-6.4.0-RELEASE), even a .0 one, so a URL built from
# "6.4" does not exist.
#
# Does nothing when DEST already holds that version. Supports the Ubuntu and
# Debian releases swift.org builds for, on x86_64 and aarch64; the system
# packages the toolchain needs (see swift.org's install guide) must already be
# there, as they are in the cloud session image and the swift: containers.
set -euo pipefail

usage="usage: install-swift-linux.sh VERSION DEST (VERSION like 6.4.0)"
version="${1:?$usage}"
dest="${2:?$usage}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: '$version' is not a full release version; swift.org releases have three numbers, such as 6.4.0" >&2
  exit 2
fi

# The toolchain's own --version drops a .0 (6.4.0 reports "swift-6.4-RELEASE"),
# so the installed release is recorded next to it instead.
marker="$dest/.swift-release"
if [[ -x "$dest/usr/bin/swift" && "$(cat "$marker" 2>/dev/null)" == "$version" ]]; then
  echo "Swift $version is already in $dest"
  exit 0
fi

# shellcheck source=/dev/null
. /etc/os-release
case "$(uname -m)" in
  x86_64) arch="" ;;
  aarch64 | arm64) arch="-aarch64" ;;
  *) echo "error: no swift.org toolchain for $(uname -m)" >&2; exit 1 ;;
esac
# ubuntu 24.04 → directory ubuntu2404, file suffix ubuntu24.04.
platform="${ID}${VERSION_ID//./}${arch}"
name="swift-${version}-RELEASE-${ID}${VERSION_ID}${arch}"
url="https://download.swift.org/swift-${version}-release/${platform}/swift-${version}-RELEASE/${name}.tar.gz"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "Downloading $url"
curl -fsSL --retry 4 --retry-delay 2 -o "$work/swift.tar.gz" "$url"
curl -fsSL --retry 4 --retry-delay 2 -o "$work/swift.tar.gz.sig" "$url.sig"
# swift.org sends the keys gzip-encoded (Content-Encoding: gzip) even when the
# request does not ask for it; without --compressed curl saves the gzip bytes
# and gpg finds no keys. Only the keys: the archive is gzip itself and must
# stay as it is.
curl -fsSL --compressed --retry 4 --retry-delay 2 -o "$work/keys.asc" https://www.swift.org/keys/all-keys.asc
mkdir -m 700 "$work/gnupg"
GNUPGHOME="$work/gnupg" gpg --batch --quiet --import "$work/keys.asc"
GNUPGHOME="$work/gnupg" gpg --batch --quiet --verify "$work/swift.tar.gz.sig" "$work/swift.tar.gz"

mkdir "$work/toolchain"
tar -xzf "$work/swift.tar.gz" -C "$work/toolchain" --strip-components=1
echo "$version" > "$work/toolchain/.swift-release"
rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$work/toolchain" "$dest"
"$dest/usr/bin/swift" --version
