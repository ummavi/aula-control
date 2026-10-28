#!/bin/zsh
# Produce a ZIP for this Mac's architecture. This does not publish a release.
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
./scripts/build.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
architecture="$(uname -m)"
archive="build/AULA-Control-${version}-macOS-${architecture}.zip"
ditto -c -k --keepParent --norsrc --noextattr 'build/AULA Control.app' "$archive"
shasum -a 256 "$archive" > "${archive}.sha256"
printf 'Packaged %s\n' "$archive"
